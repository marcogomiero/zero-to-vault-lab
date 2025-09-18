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
        log INFO "Loaded backend type from config: $BACKEND_TYPE"
        [ -n "$CLUSTER_MODE" ] && log INFO "Loaded cluster mode from config: $CLUSTER_MODE"
        [ -n "$ENABLE_TLS" ] && log INFO "Loaded TLS mode from config: $ENABLE_TLS"

        # Aggiorna VAULT_ADDR e CONSUL_ADDR se TLS è abilitato
        if [ "$ENABLE_TLS" = true ]; then
            VAULT_ADDR="https://127.0.0.1:8200"
            CONSUL_ADDR="https://127.0.0.1:8500"
        fi
    fi
}

stop_lab_environment() {
    log INFO "STOPPING VAULT LAB ENVIRONMENT (Backend: $BACKEND_TYPE)"
    stop_vault
    if [ "$BACKEND_TYPE" == "consul" ]; then
        stop_consul
    fi
    log INFO "Vault lab environment stopped. 👋"
}

cleanup_previous_environment() {
    log INFO "FULL CLEANUP OF PREVIOUS LAB ENVIRONMENT"
    stop_lab_environment
    rm -f "$LAB_CONFIG_FILE"
    log INFO "Deleting previous working directories..."
    rm -rf "$VAULT_DIR" "$CONSUL_DIR"
    mkdir -p "$VAULT_DIR" "$CONSUL_DIR"
    log INFO "Cleanup completed. ✅"
}

check_lab_status() {
    log INFO "CHECKING VAULT LAB STATUS (Backend: $BACKEND_TYPE)"
    local vault_running=false
    if [ -f "$LAB_VAULT_PID_FILE" ] && ps -p "$(cat "$LAB_VAULT_PID_FILE")" > /dev/null; then
        vault_running=true
    fi

    if [ "$vault_running" = true ]; then
        log INFO "Vault process is RUNNING. PID: $(cat "$LAB_VAULT_PID_FILE")"

        # Imposta le variabili necessarie per il controllo dello stato
        if [ "$ENABLE_TLS" = true ]; then
            export VAULT_CACERT="$CA_CERT"
        fi
        export VAULT_ADDR="$VAULT_ADDR"

        local status_json=$(get_vault_status)
        if [ "$(echo "$status_json" | jq -r '.sealed')" == "false" ]; then
            log INFO "Vault is UNSEALED and READY. 🎉"
        else
            log WARN "Vault is SEALED. 🔒 Run 'restart' to unseal."
        fi
    else
        log INFO "Vault server is NOT RUNNING. 🛑"
    fi

    if [ "$BACKEND_TYPE" == "consul" ]; then
        if [ -f "$LAB_CONSUL_PID_FILE" ] && ps -p "$(cat "$LAB_CONSUL_PID_FILE")" > /dev/null; then
            log INFO "Consul process is RUNNING. PID: $(cat "$LAB_CONSUL_PID_FILE")"
        else
            log INFO "Consul server is NOT RUNNING. 🛑"
        fi
    fi

    if [ "$ENABLE_TLS" = true ]; then
        log INFO "TLS encryption is ENABLED. 🔒"
    else
        log INFO "TLS encryption is DISABLED. 🔓"
    fi
}

display_final_info() {
    log INFO "LAB VAULT IS READY TO USE!"
    local vault_root_token=$(cat "$VAULT_DIR/root_token.txt" 2>/dev/null)
    local approle_role_id=$(cat "$VAULT_DIR/approle_role_id.txt" 2>/dev/null)
    local approle_secret_id=$(cat "$VAULT_DIR/approle_secret_id.txt" 2>/dev/null)
    local consul_token=$(cat "$CONSUL_DIR/acl_master_token.txt" 2>/dev/null)

    # Determina gli IP corretti in base all'ambiente
    local vault_ip="127.0.0.1"  # Vault sempre su localhost
    local consul_ip="127.0.0.1" # Default per Consul

    # Su WSL, usa l'IP della VM per Consul per accessibilità esterna
    if grep -q "microsoft" /proc/version &>/dev/null; then
        local wsl_ip=$(ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
        if [ -n "$wsl_ip" ]; then
            consul_ip="$wsl_ip"
        fi
    fi

    local protocol="http"
    local tls_note=""
    if [ "$ENABLE_TLS" = true ]; then
        protocol="https"
        tls_note=" (🔒 TLS enabled)"
    fi

    echo -e "\n${YELLOW}--- ACCESS DETAILS ---${NC}"
    echo -e "  🔗 Vault UI: ${GREEN}${protocol}://${vault_ip}:8200${NC}${tls_note}"
    echo -e "  🔑 Vault Root Token: ${GREEN}$vault_root_token${NC}"

    if [ "$BACKEND_TYPE" == "consul" ]; then
        echo -e "  ---"
        echo -e "  🔗 Consul UI: ${GREEN}${protocol}://${consul_ip}:8500${NC}${tls_note}"
        echo -e "  🔑 Consul ACL Token: ${GREEN}$consul_token${NC}"
    fi

    if [ "$CLUSTER_MODE" = "multi" ]; then
        echo -e "\n${YELLOW}Vault cluster nodes:${NC}"
        echo "  ${protocol}://${vault_ip}:8200"
        echo "  ${protocol}://${vault_ip}:8201"
        echo "  ${protocol}://${vault_ip}:8202"
    fi

    if [ "$ENABLE_TLS" = true ]; then
        echo -e "\n${YELLOW}--- TLS CERTIFICATE INFO ---${NC}"
        echo -e "  📜 CA Certificate: ${GREEN}$CA_CERT${NC}"
        echo -e "  📁 Certificates Directory: ${GREEN}$CERTS_DIR${NC}"
        echo -e "\n  To trust the CA certificate:"
        echo -e "  ${CYAN}Linux:${NC} sudo cp $CA_CERT /usr/local/share/ca-certificates/vault-lab-ca.crt && sudo update-ca-certificates"
        echo -e "  ${CYAN}macOS:${NC} sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain $CA_CERT"
        echo -e "  ${CYAN}Windows:${NC} Import CA cert via certmgr.msc into Trusted Root Certification Authorities"

        if grep -q "microsoft" /proc/version &>/dev/null; then
            echo -e "\n  ${YELLOW}WSL Note:${NC} Vault uses localhost (127.0.0.1) for local access"
            echo -e "  Consul uses VM IP ($consul_ip) for Windows host access"
        fi
    fi
}

start_lab_environment_core() {
    log INFO "Validating environment..."
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
    log INFO "RESTARTING VAULT LAB ENVIRONMENT (Backend: $BACKEND_TYPE)"
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
    log INFO "Vault lab environment restarted and unsealed. 🔄"
    display_final_info
}

reset_lab_environment() {
    log INFO "RESETTING VAULT LAB ENVIRONMENT"
    cleanup_previous_environment
    start_lab_environment_core
}

parse_args() {
    # reset variabili globali
    FORCE_CLEANUP_ON_START=false
    VERBOSE_OUTPUT=false
    COLORS_ENABLED=true
    TLS_ENABLED_FROM_ARG=false
    BACKEND_TYPE_SET_VIA_ARG=false
    COMMAND=""
    REMAINING_ARGS=()

    # parse con getopts (gestione di opzioni lunghe con '-:')
    while getopts ":chv-:" opt; do
        case $opt in
            c) FORCE_CLEANUP_ON_START=true ;;
            h) display_help ;;
            v) VERBOSE_OUTPUT=true ;;
            -)
                case "${OPTARG}" in
                    no-color) COLORS_ENABLED=false ;;
                    backend)  BACKEND_TYPE="$2"; BACKEND_TYPE_SET_VIA_ARG=true; shift ;;
                    cluster)  CLUSTER_MODE="$2"; shift ;;
                    tls)      ENABLE_TLS=true; TLS_ENABLED_FROM_ARG=true ;;
                    help)     display_help ;;
                    *) log ERROR "Unknown option --${OPTARG}" ;;
                esac
                ;;
            \?) log ERROR "Unknown option -$OPTARG" ;;
        esac
    done
    shift $((OPTIND-1))

    # primo argomento dopo le opzioni è il comando
    COMMAND="${1:-start}"
    shift || true
    REMAINING_ARGS=("$@")
}

main() {
    apply_color_settings
    parse_args "$@"

    # carica backend da file se serve
    case "$COMMAND" in
        start|reset|backup|list-backups|delete-backup|export-backup|import-backup) ;;
        *) load_backend_type_from_config ;;
    esac

    # prompt interattivi (cluster/backend/tls) solo per start/reset
    if [[ "$COMMAND" =~ ^(start|reset)$ ]]; then
        if [[ ! "$CLUSTER_MODE" =~ ^(single|multi)$ ]]; then
            echo -e "\n${YELLOW}Cluster mode (single/multi) [single]:${NC}"
            read -r cchoice
            CLUSTER_MODE=${cchoice:-single}
        fi
        echo -e "Using cluster mode: ${GREEN}$CLUSTER_MODE${NC}"

        if [ "$BACKEND_TYPE_SET_VIA_ARG" = false ]; then
            if [ "$CLUSTER_MODE" = "multi" ]; then
                BACKEND_TYPE="consul"
                echo -e "Cluster mode is multi: forcing backend to ${GREEN}consul${NC}"
            else
                echo -e "\n${YELLOW}Choose storage backend (file/consul) [file]:${NC}"
                read -r choice
                BACKEND_TYPE=${choice:-file}
            fi
        fi
        echo -e "Using backend: ${GREEN}$BACKEND_TYPE${NC}"

        if [ "$TLS_ENABLED_FROM_ARG" = false ]; then
            echo -e "\n${YELLOW}Enable TLS/SSL encryption? (y/N):${NC}"
            read -r tls_choice
            [[ "$tls_choice" =~ ^[Yy] ]] && ENABLE_TLS=true
        fi
        echo -e "TLS encryption: ${GREEN}$([ "$ENABLE_TLS" = true ] && echo enabled || echo disabled)${NC}"

        [ "$ENABLE_TLS" = true ] && {
            VAULT_ADDR="https://127.0.0.1:8200"
            CONSUL_ADDR="https://127.0.0.1:8500"
        }
    fi

    # esecuzione comando
    case "$COMMAND" in
        start)   $FORCE_CLEANUP_ON_START && cleanup_previous_environment; start_lab_environment_core ;;
        stop)    stop_lab_environment ;;
        restart) restart_lab_environment ;;
        reset)   reset_lab_environment ;;
        status)  check_lab_status ;;
        cleanup) cleanup_previous_environment ;;
        shell)
            [ "$ENABLE_TLS" = true ] && export VAULT_CACERT="$CA_CERT"
            export VAULT_ADDR PATH="$BIN_DIR:$PATH"
            [ -f "$VAULT_DIR/root_token.txt" ] && export VAULT_TOKEN="$(cat "$VAULT_DIR/root_token.txt")"
            echo "🔓 Lab shell active. Type 'exit' to leave."
            exec "${SHELL:-bash}" -i
            ;;
        backup)         create_backup "${REMAINING_ARGS[0]}" "${REMAINING_ARGS[1]}" ;;
        restore)        restore_backup "${REMAINING_ARGS[0]}" "${REMAINING_ARGS[1]}" ;;
        list-backups)   list_backups ;;
        delete-backup)  delete_backup "${REMAINING_ARGS[0]}" "${REMAINING_ARGS[1]}" ;;
        export-backup)  export_backup "${REMAINING_ARGS[0]}" "${REMAINING_ARGS[1]}" ;;
        import-backup)  import_backup "${REMAINING_ARGS[0]}" "${REMAINING_ARGS[1]}" ;;
        *) log ERROR "Invalid command '$COMMAND'." ;;
    esac
}