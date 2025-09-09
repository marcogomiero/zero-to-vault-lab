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
    echo ""
    echo "Commands:"
    echo "  start, stop, restart, reset, status, cleanup, shell"
    exit 0
}

save_backend_type_to_config() {
    mkdir -p "$VAULT_DIR"
    echo "BACKEND_TYPE=\"$BACKEND_TYPE\"" > "$LAB_CONFIG_FILE"
}

load_backend_type_from_config() {
    if [ -f "$LAB_CONFIG_FILE" ]; then
        source "$LAB_CONFIG_FILE"
        log_info "Loaded backend type from config: $BACKEND_TYPE"
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
}

# Sostituisci l'intera funzione in lib/lifecycle.sh

display_final_info() {
    log_info "LAB VAULT IS READY TO USE!"
    # --- Raccogli tutte le informazioni ---
    local vault_root_token=$(cat "$VAULT_DIR/root_token.txt" 2>/dev/null)
    local host_ip=$(get_host_accessible_ip)
    local approle_role_id=$(cat "$VAULT_DIR/approle_role_id.txt" 2>/dev/null)
    local approle_secret_id=$(cat "$VAULT_DIR/approle_secret_id.txt" 2>/dev/null)
    local consul_token=$(cat "$CONSUL_DIR/acl_master_token.txt" 2>/dev/null) # <-- NUOVO

    # --- Stampa il riepilogo ---
    echo -e "\n${YELLOW}--- ACCESS DETAILS ---${NC}"
    echo -e "  🔗 Vault UI: ${GREEN}$VAULT_ADDR${NC} (Accessibile da WSL)"
    echo -e "  🔑 Vault Root Token: ${GREEN}$vault_root_token${NC}"

    if [ "$BACKEND_TYPE" == "consul" ]; then
        echo -e "  ---"
        echo -e "  🔗 Consul UI: ${GREEN}http://${host_ip}:8500${NC} (Accessibile dal browser di Windows)"
        echo -e "  🔑 Consul ACL Token: ${GREEN}$consul_token${NC} (Usalo per il login nella UI)" # <-- NUOVO
    fi

    echo -e "\n${YELLOW}--- EXAMPLE USAGE ---${NC}"
    echo -e "  ${CYAN}Run the built-in shell for a pre-configured environment:${NC}"
    echo -e "    ${GREEN}$0 shell${NC}"
    echo ""
    echo -e "  ${CYAN}Test User (userpass):${NC}"
    echo -e "    Username: ${GREEN}devuser${NC}"
    echo -e "    Password: ${GREEN}devpass${NC}"
    echo ""
    echo -e "  ${CYAN}AppRole Credentials (for 'web-application' role):${NC}"
    echo -e "    Role ID:   ${GREEN}$approle_role_id${NC}"
    echo -e "    Secret ID: ${GREEN}$approle_secret_id${NC}"
    echo ""
    echo -e "  ${CYAN}Example CLI Commands (run inside the lab shell):${NC}"
    echo -e "    # Read the example secret"
    echo -e "    ${GREEN}vault kv get secret/test-secret${NC}"
    if [ "$BACKEND_TYPE" == "consul" ]; then
        echo ""
        echo -e "    # To use the consul CLI, export the token:"
        echo -e "    ${GREEN}export CONSUL_HTTP_TOKEN=\"$consul_token\"${NC}" # <-- NUOVO
        echo -e "    ${GREEN}consul members${NC}"
    fi

    log_info "\nEnjoy your Vault!"
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
        configure_and_start_consul
    fi

    configure_and_start_vault
    initialize_and_unseal_vault
    configure_vault_features
    save_backend_type_to_config
    display_final_info
}

# Sostituisci l'intera funzione in lib/lifecycle.sh

restart_lab_environment() {
    log_info "RESTARTING VAULT LAB ENVIRONMENT (Backend: $BACKEND_TYPE)"

    # AGGIUNTA: Assicurati che i binari esistano prima di procedere
    mkdir -p "$BIN_DIR"
    download_latest_vault_binary "$BIN_DIR"
    if [ "$BACKEND_TYPE" == "consul" ]; then
        download_latest_consul_binary "$BIN_DIR"
    fi

    stop_lab_environment
    sleep 3

    if [ "$BACKEND_TYPE" == "consul" ]; then
        configure_and_start_consul
    fi

    configure_and_start_vault
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
    local original_args=("$@") # Salva gli argomenti originali

    # Parsing degli argomenti
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help) display_help ;;
            -c|--clean) FORCE_CLEANUP_ON_START=true; shift ;;
            -v|--verbose) VERBOSE_OUTPUT=true; shift ;;
            --no-color) COLORS_ENABLED=false; shift ;;
            --backend) BACKEND_TYPE="$2"; BACKEND_TYPE_SET_VIA_ARG=true; shift 2 ;;
            start|stop|restart|reset|status|cleanup|shell) command="$1"; shift ;;
            *) log_error "Invalid argument: $1";;
        esac
    done

    # Handle shell command early
    if [[ "$command" == "shell" ]]; then
        export VAULT_ADDR="$VAULT_ADDR"
        [ -f "$VAULT_DIR/root_token.txt" ] && export VAULT_TOKEN="$(cat "$VAULT_DIR/root_token.txt")"
        export PATH="$BIN_DIR:$PATH"
        echo "🔒 Lab shell active. Type 'exit' to leave."
        exec "${SHELL:-bash}" -i
        return 0
    fi

    # Carica il tipo di backend dal file di config per i comandi che non sono 'start' o 'reset'
    if [[ "$command" != "start" && "$command" != "reset" ]]; then
        load_backend_type_from_config
    fi

    # *** BLOCCO RIPRISTINATO: Chiedi il backend se necessario ***
    if [ "$BACKEND_TYPE_SET_VIA_ARG" = false ] && [[ "$command" == "start" || "$command" == "reset" ]]; then
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

    case "$command" in
        start)
            if [ "$FORCE_CLEANUP_ON_START" = true ]; then
                cleanup_previous_environment
            fi
            start_lab_environment_core
            ;;
        stop) stop_lab_environment ;;
        restart) restart_lab_environment ;;
        reset) reset_lab_environment ;;
        status) check_lab_status ;;
        cleanup) cleanup_previous_environment ;;
        *) log_error "Invalid command '$command'." ;;
    esac
}