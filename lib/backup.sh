#!/bin/bash
# lib/backup.sh
# Funzioni per backup e restore delle configurazioni del lab

# --- Configuration ---
BACKUP_DIR="$BASE_DIR/backups"
BACKUP_METADATA_FILE="backup_metadata.json"

# --- Backup Management Functions ---

list_backups() {
    log_info "LISTING AVAILABLE BACKUPS"

    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        log_warn "No backups found in $BACKUP_DIR"
        return 1
    fi

    echo -e "\n${YELLOW}Available backups:${NC}"
    echo "----------------------------------------"
    printf "%-25s %-15s %-8s %-12s %s\n" "NAME" "BACKEND" "TLS" "SIZE" "DATE"
    echo "----------------------------------------"

    for backup_path in "$BACKUP_DIR"/*; do
        if [ -d "$backup_path" ]; then
            local backup_name=$(basename "$backup_path")
            local metadata_file="$backup_path/$BACKUP_METADATA_FILE"

            if [ -f "$metadata_file" ]; then
                local backend_type=$(jq -r '.backend_type // "unknown"' "$metadata_file" 2>/dev/null)
                local tls_enabled=$(jq -r '.tls_enabled // false' "$metadata_file" 2>/dev/null)
                local created_date=$(jq -r '.created_date // "unknown"' "$metadata_file" 2>/dev/null)
                local size=$(du -sh "$backup_path" 2>/dev/null | cut -f1)
                local tls_status=$([ "$tls_enabled" = "true" ] && echo "YES" || echo "NO")

                printf "%-25s %-15s %-8s %-12s %s\n" "$backup_name" "$backend_type" "$tls_status" "$size" "$created_date"
            else
                printf "%-25s %-15s %-8s %-12s %s\n" "$backup_name" "unknown" "?" "?" "No metadata"
            fi
        fi
    done
    echo "----------------------------------------"
}

create_backup() {
    local backup_name="$1"
    local backup_description="$2"

    # Se non viene fornito un nome, genera uno automatico
    if [ -z "$backup_name" ]; then
        backup_name="backup_$(date +%Y%m%d_%H%M%S)"
    fi

    # Valida il nome del backup
    if [[ ! "$backup_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Backup name must contain only letters, numbers, hyphens, and underscores."
    fi

    local backup_path="$BACKUP_DIR/$backup_name"

    if [ -d "$backup_path" ]; then
        log_error "Backup '$backup_name' already exists. Choose a different name or delete the existing backup."
    fi

    log_info "CREATING BACKUP: $backup_name"
    log_info "Description: ${backup_description:-"No description provided"}"

    # Controlla se il lab è attivo
    local lab_running=false
    if [ -f "$LAB_VAULT_PID_FILE" ] && ps -p "$(cat "$LAB_VAULT_PID_FILE")" > /dev/null 2>&1; then
        lab_running=true
        log_info "Lab is currently running. Creating hot backup..."
    else
        log_info "Lab is stopped. Creating cold backup..."
    fi

    # Crea la directory di backup
    mkdir -p "$backup_path" || log_error "Failed to create backup directory: $backup_path"

    # Backup dei dati Vault
    if [ -d "$VAULT_DIR" ]; then
        log_info "Backing up Vault data..."
        cp -r "$VAULT_DIR" "$backup_path/vault-data" || log_error "Failed to backup Vault data"

        # Se il lab è in esecuzione, esporta anche i dati via API
        if [ "$lab_running" = true ] && [ -f "$VAULT_DIR/root_token.txt" ]; then
            log_info "Exporting Vault configuration via API..."
            export VAULT_ADDR="$VAULT_ADDR"

            # Imposta VAULT_CACERT se TLS è abilitato
            if [ "$ENABLE_TLS" = true ] && [ -f "$CA_CERT" ]; then
                export VAULT_CACERT="$CA_CERT"
            fi

            export VAULT_TOKEN=$(cat "$VAULT_DIR/root_token.txt")
            local vault_exe=$(get_vault_exe)

            # Esporta policies
            mkdir -p "$backup_path/api_export"
            "$vault_exe" policy list -format=json > "$backup_path/api_export/policies_list.json" 2>/dev/null || true

            # Esporta auth methods
            "$vault_exe" auth list -format=json > "$backup_path/api_export/auth_methods.json" 2>/dev/null || true

            # Esporta secrets engines
            "$vault_exe" secrets list -format=json > "$backup_path/api_export/secrets_engines.json" 2>/dev/null || true

            # Esporta alcune configurazioni specifiche (se esistono)
            "$vault_exe" read -format=json auth/approle/role/web-application > "$backup_path/api_export/approle_config.json" 2>/dev/null || true
        fi
    fi

    # Backup dei dati Consul (se presente)
    if [ -d "$CONSUL_DIR" ] && [ "$BACKEND_TYPE" == "consul" ]; then
        log_info "Backing up Consul data..."
        cp -r "$CONSUL_DIR" "$backup_path/consul-data" || log_error "Failed to backup Consul data"

        # Se Consul è in esecuzione, esporta anche il KV store
        if [ "$lab_running" = true ] && [ -f "$CONSUL_DIR/acl_master_token.txt" ]; then
            log_info "Exporting Consul KV store..."
            export CONSUL_HTTP_TOKEN=$(cat "$CONSUL_DIR/acl_master_token.txt")

            # Imposta CONSUL_CACERT se TLS è abilitato
            if [ "$ENABLE_TLS" = true ] && [ -f "$CA_CERT" ]; then
                export CONSUL_CACERT="$CA_CERT"
            fi

            local consul_exe=$(get_consul_exe)

            mkdir -p "$backup_path/consul_export"
            "$consul_exe" kv export > "$backup_path/consul_export/kv_export.json" 2>/dev/null || true
        fi
    fi

    # Backup dei certificati TLS (se presente)
    if [ "$ENABLE_TLS" = true ] && [ -d "$TLS_DIR" ]; then
        log_info "Backing up TLS certificates..."
        cp -r "$TLS_DIR" "$backup_path/tls-data" || log_error "Failed to backup TLS data"
    fi

    # Backup della configurazione del lab
    if [ -f "$LAB_CONFIG_FILE" ]; then
        log_info "Backing up lab configuration..."
        cp "$LAB_CONFIG_FILE" "$backup_path/" || log_error "Failed to backup lab configuration"
    fi

    # Crea i metadati del backup
    local metadata="{
        \"backup_name\": \"$backup_name\",
        \"description\": \"${backup_description:-""}\",
        \"created_date\": \"$(date -Iseconds)\",
        \"backend_type\": \"$BACKEND_TYPE\",
        \"tls_enabled\": $ENABLE_TLS,
        \"cluster_mode\": \"$CLUSTER_MODE\",
        \"lab_was_running\": $lab_running,
        \"vault_version\": \"$(get_vault_exe --version 2>/dev/null | head -n1 | awk '{print $2}' || echo "unknown")\",
        \"consul_version\": \"$([ "$BACKEND_TYPE" == "consul" ] && get_consul_exe --version 2>/dev/null | head -n1 | awk '{print $2}' || echo "n/a")\",
        \"script_version\": \"$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")\",
        \"hostname\": \"$(hostname)\",
        \"user\": \"$(whoami)\"
    }"

    echo "$metadata" | jq '.' > "$backup_path/$BACKUP_METADATA_FILE" 2>/dev/null || {
        echo "$metadata" > "$backup_path/$BACKUP_METADATA_FILE"
    }

    # Calcola checksum per verifica integrità
    log_info "Calculating backup integrity checksum..."
    find "$backup_path" -type f -exec sha256sum {} \; | sort > "$backup_path/checksums.sha256"

    local backup_size=$(du -sh "$backup_path" | cut -f1)
    log_info "Backup '$backup_name' completed successfully! Size: $backup_size"
    log_info "Backup location: $backup_path"
}

restore_backup() {
    local backup_name="$1"
    local force_restore="$2"

    if [ -z "$backup_name" ]; then
        log_error "Backup name is required for restore operation."
    fi

    local backup_path="$BACKUP_DIR/$backup_name"

    if [ ! -d "$backup_path" ]; then
        log_error "Backup '$backup_name' not found in $BACKUP_DIR"
    fi

    local metadata_file="$backup_path/$BACKUP_METADATA_FILE"
    if [ ! -f "$metadata_file" ]; then
        log_error "Backup metadata not found. This might be a corrupted backup."
    fi

    # Verifica integrità del backup
    log_info "VERIFYING BACKUP INTEGRITY"
    if [ -f "$backup_path/checksums.sha256" ]; then
        if ! (cd "$backup_path" && sha256sum -c checksums.sha256 --quiet); then
            log_error "Backup integrity check failed! The backup might be corrupted."
        fi
        log_info "Backup integrity verified"
    else
        log_warn "No integrity checksums found. Proceeding without verification."
    fi

    # Leggi i metadati
    local backup_backend=$(jq -r '.backend_type // "unknown"' "$metadata_file" 2>/dev/null)
    local backup_tls=$(jq -r '.tls_enabled // false' "$metadata_file" 2>/dev/null)
    local backup_cluster=$(jq -r '.cluster_mode // "single"' "$metadata_file" 2>/dev/null)
    local backup_date=$(jq -r '.created_date // "unknown"' "$metadata_file" 2>/dev/null)
    local backup_desc=$(jq -r '.description // ""' "$metadata_file" 2>/dev/null)

    log_info "RESTORING BACKUP: $backup_name"
    log_info "Created: $backup_date"
    log_info "Backend: $backup_backend"
    log_info "TLS: $([ "$backup_tls" = "true" ] && echo "enabled" || echo "disabled")"
    log_info "Cluster: $backup_cluster"
    [ -n "$backup_desc" ] && log_info "Description: $backup_desc"

    # Controllo di sicurezza
    if [ "$force_restore" != "--force" ]; then
        echo -e "\n${YELLOW}WARNING: This will completely replace your current lab environment!${NC}"
        echo -e "Current data will be ${RED}permanently lost${NC}."
        read -p "Are you sure you want to continue? (yes/NO): " confirmation
        if [[ ! "$confirmation" =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Restore cancelled by user."
            return 0
        fi
    fi

    # Ferma il lab se è in esecuzione
    log_info "Stopping current lab environment..."
    stop_lab_environment 2>/dev/null || true

    # Pulisci l'ambiente corrente
    log_info "Cleaning current environment..."
    rm -rf "$VAULT_DIR" "$CONSUL_DIR" "$TLS_DIR" "$LAB_CONFIG_FILE" 2>/dev/null || true

    # Ripristina i dati
    if [ -d "$backup_path/vault-data" ]; then
        log_info "Restoring Vault data..."
        cp -r "$backup_path/vault-data" "$VAULT_DIR" || log_error "Failed to restore Vault data"
    fi

    if [ -d "$backup_path/consul-data" ]; then
        log_info "Restoring Consul data..."
        cp -r "$backup_path/consul-data" "$CONSUL_DIR" || log_error "Failed to restore Consul data"
    fi

    if [ -d "$backup_path/tls-data" ]; then
        log_info "Restoring TLS certificates..."
        cp -r "$backup_path/tls-data" "$TLS_DIR" || log_error "Failed to restore TLS data"
    fi

    if [ -f "$backup_path/$(basename "$LAB_CONFIG_FILE")" ]; then
        log_info "Restoring lab configuration..."
        cp "$backup_path/$(basename "$LAB_CONFIG_FILE")" "$LAB_CONFIG_FILE" || log_error "Failed to restore lab configuration"
    fi

    # Aggiorna le variabili dalle configurazioni ripristinate
    load_backend_type_from_config
    [ -n "$ENABLE_TLS" ] && log_info "Restored TLS setting: $ENABLE_TLS"

    log_info "Backup '$backup_name' restored successfully!"
    log_info "You can now start the lab with: $0 start"
}

delete_backup() {
    local backup_name="$1"
    local force_delete="$2"

    if [ -z "$backup_name" ]; then
        log_error "Backup name is required for delete operation."
    fi

    local backup_path="$BACKUP_DIR/$backup_name"

    if [ ! -d "$backup_path" ]; then
        log_error "Backup '$backup_name' not found in $BACKUP_DIR"
    fi

    # Mostra info del backup prima di eliminarlo
    local metadata_file="$backup_path/$BACKUP_METADATA_FILE"
    if [ -f "$metadata_file" ]; then
        local backup_date=$(jq -r '.created_date // "unknown"' "$metadata_file" 2>/dev/null)
        local backup_backend=$(jq -r '.backend_type // "unknown"' "$metadata_file" 2>/dev/null)
        local backup_tls=$(jq -r '.tls_enabled // false' "$metadata_file" 2>/dev/null)
        log_info "Backup details - Date: $backup_date, Backend: $backup_backend, TLS: $backup_tls"
    fi

    # Controllo di sicurezza
    if [ "$force_delete" != "--force" ]; then
        echo -e "\n${YELLOW}WARNING: This will permanently delete backup '$backup_name'!${NC}"
        read -p "Are you sure you want to continue? (yes/NO): " confirmation
        if [[ ! "$confirmation" =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Delete cancelled by user."
            return 0
        fi
    fi

    log_info "Deleting backup '$backup_name'..."
    rm -rf "$backup_path" || log_error "Failed to delete backup"
    log_info "Backup '$backup_name' deleted successfully!"
}

export_backup() {
    local backup_name="$1"
    local export_path="$2"

    if [ -z "$backup_name" ]; then
        log_error "Backup name is required for export operation."
    fi

    local backup_path="$BACKUP_DIR/$backup_name"

    if [ ! -d "$backup_path" ]; then
        log_error "Backup '$backup_name' not found in $BACKUP_DIR"
    fi

    # Se non specificato, usa la directory corrente
    if [ -z "$export_path" ]; then
        export_path="./$(basename "$backup_name").tar.gz"
    fi

    log_info "Exporting backup '$backup_name' to '$export_path'..."

    # Crea un archivio compresso
    tar -czf "$export_path" -C "$BACKUP_DIR" "$backup_name" || log_error "Failed to create export archive"

    local export_size=$(du -sh "$export_path" | cut -f1)
    log_info "Backup exported successfully! Size: $export_size"
    log_info "Export location: $export_path"
}

import_backup() {
    local import_path="$1"
    local backup_name="$2"

    if [ -z "$import_path" ]; then
        log_error "Import file path is required."
    fi

    if [ ! -f "$import_path" ]; then
        log_error "Import file '$import_path' not found."
    fi

    # Se non specificato, estrai il nome dal file
    if [ -z "$backup_name" ]; then
        backup_name=$(basename "$import_path" .tar.gz)
    fi

    local backup_path="$BACKUP_DIR/$backup_name"

    if [ -d "$backup_path" ]; then
        log_error "Backup '$backup_name' already exists. Delete it first or choose a different name."
    fi

    log_info "Importing backup from '$import_path' as '$backup_name'..."

    # Crea la directory di backup se non esiste
    mkdir -p "$BACKUP_DIR" || log_error "Failed to create backup directory"

    # Estrai l'archivio
    tar -xzf "$import_path" -C "$BACKUP_DIR" || log_error "Failed to extract import archive"

    # Se necessario, rinomina la directory estratta
    local extracted_name=$(tar -tzf "$import_path" | head -1 | cut -d/ -f1)
    if [ "$extracted_name" != "$backup_name" ]; then
        mv "$BACKUP_DIR/$extracted_name" "$backup_path" || log_error "Failed to rename imported backup"
    fi

    log_info "Backup imported successfully!"
    log_info "You can now restore it with: $0 restore $backup_name"
}