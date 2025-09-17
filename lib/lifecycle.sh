#!/bin/bash
# lib/lifecycle.sh
# Funzioni per la gestione del ciclo di vita del lab e funzione main.

display_help() {
    echo "Usage: $0 [OPTIONS] [COMMAND]"
    echo "This script deploys a HashiCorp Vault lab environment."
    echo ""
    echo "Options:"
    echo "  -c, --clean                    Force clean setup before start."
    echo "  -h, --help                     Show this help and exit."
    echo "  -v, --verbose                  Verbose output."
    echo "      --no-color                 Disable colored output."
    echo "      --backend <file|consul>    Select storage backend."
    echo "      --cluster <single|multi>   Start single node or 3-node cluster"
    echo "      --tls                      Enable TLS/SSL encryption"
    echo ""
    echo "Commands:"
    echo "  start, stop, restart, reset, status, cleanup, shell"
    echo ""
    echo "Backup/Restore Commands:"
    echo "  backup [name] [description]    Create a backup of current lab state"
    echo "  restore <name> [--force]       Restore from a backup"
    echo "  list-backups                   List all available backups"
    echo "  delete-backup <name> [--force] Delete a specific backup"
    echo "  export-backup <name> [path]    Export backup to tar.gz file"
    echo "  import-backup <path> [name]    Import backup from tar.gz file"
    echo ""
    echo "Examples:"
    echo "  $0 --tls start                       # Start with TLS encryption"
    echo "  $0 --cluster multi --backend consul start"
    echo "  $0 backup my-config \"Working KV setup\""
    echo "  $0 restore my-config"
    echo "  $0 list-backups"
    echo "  $0 export-backup my-config ./my-backup.tar.gz"
    exit 0
}

save_backend_type_to_config() {
    mkdir -p "$VAULT_DIR"
    echo "BACKEND_TYPE=\"$BACKEND_TYPE\"" > "$LAB_CONFIG_FILE"
    echo "CLUSTER_MODE=\"$CLUSTER_MODE\"" >> "$LAB_CONFIG_FILE"
    echo "ENABLE_TLS=\"$ENABLE_TLS\"" >> "$LAB_CONFIG_FILE"
}

load_backend_type_from_config() {
    if [ -f "$LAB_CONFIG_FILE" ]; then
        source "$LAB_CONFIG_FILE"
        log_info "Loaded backend type from config: $BACKEND_TYPE"
        [ -n "$CLUSTER_MODE" ] && log_info "Loaded cluster mode from config: $CLUSTER_MODE"
        [ -n "$ENABLE_TLS" ] && log_info "Loaded TLS mode from config: $ENABLE_TLS"

        # Aggiorna VAULT_ADDR e CONSUL_ADDR se TLS è abilitato
        if [ "$ENABLE_TLS" = true ]; then
            VAULT_ADDR="https://127.0.0.1:8200"
            CONSUL_ADDR="https://127.0.0.1:8500"
        fi
    fi
}

stop_lab_environment() {
    log_info "STOPPING VAULT LAB ENVIRONMENT (Backend: $BACKEND_TYPE)"
    stop_vault
    if [ "$BACKEND_TYPE" == "consul" ]; then
        stop_consul
    fi
    log_info "Vault lab environment stopped. 👋"
}

cleanup_previous_environment() {
    log_info "FULL CLEANUP OF PREVIOUS LAB ENVIRONMENT"
    stop_lab_environment
    rm -f "$LAB_CONFIG_FILE"
    log_info "Deleting previous working directories..."
    rm -rf "$VAULT_DIR" "$CONSUL_DIR"
    mkdir -p "$VAULT_DIR" "$CONSUL_DIR"
    log_info "Cleanup completed. ✅"
}

check_lab_status() {
    log_info "CHECKING VAULT LAB STATUS (Backend: $BACKEND_TYPE)"
    local vault_running=false
    if [ -f "$LAB_VAULT_PID_FILE" ] && ps -p "$(cat "$LAB_VAULT_PID_FILE")" > /dev/null; then
        vault_running=true
    fi

    if [ "$vault_running" = true ]; then
        log_info "Vault process is RUNNING. PID: $(cat "$LAB_VAULT_PID_FILE")"

        # Imposta le variabili necessarie per il controllo dello stato
        if [ "$ENABLE_TLS" = true ]; then
            export VAULT_CACERT="$CA_CERT"
        fi
        export VAULT_ADDR="$VAULT_ADDR"

        local status_json=$(get_vault_status)
        if [ "$(echo "$status_json" | jq -r '.sealed')" == "false" ]; then
            log_info "Vault is UNSEALED and READY. 🎉"
        else
            log_warn "Vault is SEALED. 🔒 Run 'restart' to unseal."
        fi
    else
        log_info "Vault server is NOT RUNNING. 🛑"
    fi

    if [ "$BACKEND_TYPE" == "consul" ]; then
        if [ -f "$LAB_CONSUL_PID_FILE" ] && ps -p "$(cat "$LAB_CONSUL_PID_FILE")" > /dev/null; then
            log_info "Consul process is RUNNING. PID: $(cat "$LAB_CONSUL_PID_FILE")"
        else
            log_info "Consul server is NOT RUNNING. 🛑"
        fi
    fi

    if [ "$ENABLE_TLS" = true ]; then
        log_info "TLS encryption is ENABLED. 🔒"
    else
        log_info "TLS encryption is DISABLED. 🔓"
    fi
}

display_final_info() {
    log_info "LAB VAULT IS READY TO USE!"
    local vault_root_token=$(cat "$VAULT_DIR/root_token.txt" 2>/dev/null)
    local host_ip=$(get_host_accessible_ip)
    local approle_role_id=$(cat "$VAULT_DIR/approle_role_id.txt" 2>/dev/null)
    local approle_secret_id=$(cat "$VAULT_DIR/approle_secret_id.txt" 2>/dev/null)
    local consul_token=$(cat "$CONSUL_DIR/acl_master_token.txt" 2>/dev/null)

    local protocol="http"
    local tls_note=""
    if [ "$ENABLE_TLS" = true ]; then
        protocol="https"
        tls_note=" (🔒 TLS enabled)"
    fi

    echo -e "\n${YELLOW}--- ACCESS DETAILS ---${NC}"
    echo -e "  🔗 Vault UI: ${GREEN}${protocol}://${host_ip}:8200${NC}${tls_note}"
    echo -e "  🔑 Vault Root Token: ${GREEN}$vault_root_token${NC}"

    if [ "$BACKEND_TYPE" == "consul" ]; then
        echo -e "  ---"
        echo -e "  🔗 Consul UI: ${GREEN}${protocol}://${host_ip}:8500${NC}${tls_note}"
        echo -e "  🔑 Consul ACL Token: ${GREEN}$consul_token${NC}"
    fi

    if [ "$CLUSTER_MODE" = "multi" ]; then
        echo -e "\n${YELLOW}Vault cluster nodes:${NC}"
        echo "  ${protocol}://127.0.0.1:8200"
        echo "  ${protocol}://127.0.0.1:8201"
        echo "  ${protocol}://127.0.0.1:8202"
    fi

    if [ "$ENABLE_TLS" = true ]; then
        echo -e "\n${YELLOW}--- TLS CERTIFICATE INFO ---${NC}"
        echo -e "  📜 CA Certificate: ${GREEN}$CA_CERT${NC}"
        echo -e "  📁 Certificates Directory: ${GREEN}$CERTS_DIR${NC}"
        echo -e "\n  To trust the CA certificate:"
        echo -e "  ${CYAN}Linux:${NC} sudo cp $CA_CERT /usr/local/share/ca-certificates/vault-lab-ca.crt && sudo update-ca-certificates"
        echo -e "  ${CYAN}macOS:${NC} sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain $CA_CERT"
        echo -e "  ${CYAN}Windows:${NC} Import CA cert via certmgr.msc into Trusted Root Certification Authorities"
    fi
}

start_lab_environment_core() {
    log_info "Validating environment..."
    validate_directories
    validate_ports_available
    mkdir -p "$BIN_DIR"

    check_and_install_prerequisites
    download_latest_vault_binary "$BIN_DIR"

    if [ "$BACKEND_TYPE" == "consul" ]; then
        download_latest_consul_binary "$BIN_DIR"
        if [ "$ENABLE_TLS" = true ]; then
            configure_consul_with_tls
            start_consul_with_tls
        else
            configure_and_start_consul
        fi
    fi

    if [ "$CLUSTER_MODE" = "multi" ]; then
        if [ "$ENABLE_TLS" = true ]; then
            start_vault_nodes_with_tls
        else
            start_vault_nodes
        fi
    else
        if [ "$ENABLE_TLS" = true ]; then
            configure_vault_with_tls
            start_vault_with_tls
        else
            configure_and_start_vault
        fi
    fi

    initialize_and_unseal_vault
    configure_vault_features
    save_backend_type_to_config
    display_final_info
}

restart_lab_environment() {
    log_info "RESTARTING VAULT LAB ENVIRONMENT (Backend: $BACKEND_TYPE)"
    mkdir -p "$BIN_DIR"
    download_latest_vault_binary "$BIN_DIR"
    if [ "$BACKEND_TYPE" == "consul" ]; then
        download_latest_consul_binary "$BIN_DIR"
    fi
    stop_lab_environment
    sleep 3

    if [ "$BACKEND_TYPE" == "consul" ]; then
        if [ "$ENABLE_TLS" = true ]; then
            configure_consul_with_tls
            start_consul_with_tls
        else
            configure_and_start_consul
        fi
    fi

    if [ "$CLUSTER_MODE" = "multi" ]; then
        if [ "$ENABLE_TLS" = true ]; then
            start_vault_nodes_with_tls
        else
            start_vault_nodes
        fi
    else
        if [ "$ENABLE_TLS" = true ]; then
            configure_vault_with_tls
            start_vault_with_tls
        else
            configure_and_start_vault
        fi
    fi

    initialize_and_unseal_vault
    log_info "Vault lab environment restarted and unsealed. 🔄"
    display_final_info
}

reset_lab_environment() {
    log_info "RESETTING VAULT LAB ENVIRONMENT"
    cleanup_previous_environment
    start_lab_environment_core
}

main() {
    apply_color_settings
    local command="start"
    local original_args=("$@")
    local backup_name="" backup_desc="" backup_force="" export_path="" import_path=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help) display_help ;;
            -c|--clean) FORCE_CLEANUP_ON_START=true; shift ;;
            -v|--verbose) VERBOSE_OUTPUT=true; shift ;;
            --no-color) COLORS_ENABLED=false; shift ;;
            --backend) BACKEND_TYPE="$2"; BACKEND_TYPE_SET_VIA_ARG=true; shift 2 ;;
            --cluster) CLUSTER_MODE="$2"; shift 2 ;;
            --tls) ENABLE_TLS=true; TLS_ENABLED_FROM_ARG=true; shift ;;
            start|stop|restart|reset|status|cleanup|shell) command="$1"; shift ;;
            backup) command="backup"; backup_name="$2"; backup_desc="$3"; shift; [ -n "$2" ] && shift; [ -n "$2" ] && shift ;;
            restore) command="restore"; backup_name="$2"; backup_force="$3"; shift 2; [ -n "$2" ] && shift ;;
            list-backups) command="list-backups"; shift ;;
            delete-backup) command="delete-backup"; backup_name="$2"; backup_force="$3"; shift 2; [ -n "$2" ] && shift ;;
            export-backup) command="export-backup"; backup_name="$2"; export_path="$3"; shift 2; [ -n "$2" ] && shift ;;
            import-backup) command="import-backup"; import_path="$2"; backup_name="$3"; shift 2; [ -n "$2" ] && shift ;;
            *) log_error "Invalid argument: $1";;
        esac
    done

    if [[ "$command" == "shell" ]]; then
        if [ "$ENABLE_TLS" = true ]; then
            export VAULT_CACERT="$CA_CERT"
        fi
        export VAULT_ADDR="$VAULT_ADDR"
        [ -f "$VAULT_DIR/root_token.txt" ] && export VAULT_TOKEN="$(cat "$VAULT_DIR/root_token.txt")"
        export PATH="$BIN_DIR:$PATH"
        echo "🔓 Lab shell active. Type 'exit' to leave."
        if [ "$ENABLE_TLS" = true ]; then
            echo "🔒 TLS is enabled - CA certificate: $VAULT_CACERT"
        fi
        exec "${SHELL:-bash}" -i
        return 0
    fi

    if [[ "$command" != "start" && "$command" != "reset" && "$command" != "backup" && "$command" != "list-backups" && "$command" != "delete-backup" && "$command" != "export-backup" && "$command" != "import-backup" ]]; then
        load_backend_type_from_config
    fi

    if [[ "$command" == "backup" || "$command" == "restore" ]]; then
        load_backend_type_from_config 2>/dev/null || true
    fi

    # Chiedi cluster mode prima se necessario
    if [[ "$command" == "start" || "$command" == "reset" ]]; then
        if [[ ! "$CLUSTER_MODE" =~ ^(single|multi)$ ]]; then
            echo -e "\n${YELLOW}Cluster mode (single/multi) [single]:${NC}"
            read -r cchoice
            case "${cchoice:-single}" in
                multi|Multi|MULTI) CLUSTER_MODE="multi" ;;
                *) CLUSTER_MODE="single" ;;
            esac
        fi
        echo -e "Using cluster mode: ${GREEN}$CLUSTER_MODE${NC}"
    fi

    # Backend prompt solo se serve e non forzato
    if [ "$BACKEND_TYPE_SET_VIA_ARG" = false ] && [[ "$command" == "start" || "$command" == "reset" ]]; then
        if [ "$CLUSTER_MODE" = "multi" ]; then
            BACKEND_TYPE="consul"
            echo -e "Cluster mode is multi: forcing backend to ${GREEN}consul${NC}"
        else
            echo -e "\n${YELLOW}Please choose a storage backend for Vault (file or consul, default: file):${NC}"
            read -p "> " choice
            choice=${choice:-file}
            case "$choice" in
                file|File|FILE) BACKEND_TYPE="file" ;;
                consul|Consul|CONSUL) BACKEND_TYPE="consul" ;;
                *) log_warn "Invalid choice. Defaulting to 'file'." ; BACKEND_TYPE="file" ;;
            esac
            echo -e "Using backend: ${GREEN}$BACKEND_TYPE${NC}"
        fi
    fi

    # TLS prompt se non specificato via argomento
    if [[ "$command" == "start" || "$command" == "reset" ]]; then
        if [ "$TLS_ENABLED_FROM_ARG" = false ]; then
            echo -e "\n${YELLOW}Enable TLS/SSL encryption? (y/N):${NC}"
            read -r tls_choice
            case "${tls_choice:-n}" in
                y|Y|yes|Yes|YES) ENABLE_TLS=true ;;
                *) ENABLE_TLS=false ;;
            esac
        fi
        echo -e "TLS encryption: ${GREEN}$([ "$ENABLE_TLS" = true ] && echo "enabled" || echo "disabled")${NC}"

        # Aggiorna gli indirizzi se TLS è abilitato
        if [ "$ENABLE_TLS" = true ]; then
            VAULT_ADDR="https://127.0.0.1:8200"
            CONSUL_ADDR="https://127.0.0.1:8500"
        fi
    fi

    case "$command" in
        start)   [ "$FORCE_CLEANUP_ON_START" = true ] && cleanup_previous_environment; start_lab_environment_core ;;
        stop)    stop_lab_environment ;;
        restart) restart_lab_environment ;;
        reset)   reset_lab_environment ;;
        status)  check_lab_status ;;
        cleanup) cleanup_previous_environment ;;
        backup)  create_backup "$backup_name" "$backup_desc" ;;
        restore) restore_backup "$backup_name" "$backup_force" ;;
        list-backups) list_backups ;;
        delete-backup) delete_backup "$backup_name" "$backup_force" ;;
        export-backup) export_backup "$backup_name" "$export_path" ;;
        import-backup) import_backup "$import_path" "$backup_name" ;;
        *) log_error "Invalid command '$command'." ;;
    esac
}