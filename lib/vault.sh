#!/bin/bash
# lib/vault.sh
# Funzioni per la configurazione e gestione di Vault.

get_vault_exe() { get_exe "vault"; }

wait_for_vault_up() {
    wait_for_http_up "$1/v1/sys/seal-status" "${2:-30}" "Vault"
}

wait_for_unseal_ready() {
  local addr=$1; local timeout=30; local elapsed=0
  log INFO "Waiting for Vault to be fully unsealed..."
  while [[ $elapsed -lt $timeout ]]; do
    local status_json=$(get_vault_status)
    if echo "$status_json" | jq -e '.initialized == true and .sealed == false' &>/dev/null; then
      log INFO "Vault is unsealed and operational."; return 0
    fi
    sleep 1; echo -n "."; ((elapsed++))
  done
  log ERROR "\nVault did not become operational after $timeout seconds."
}

wait_for_vault_ready() {
    local max_attempts=15
    local attempt=1

    log INFO "Waiting for Vault to be fully ready..."

    while [ $attempt -le $max_attempts ]; do
        # Prova una chiamata API semplice invece del status JSON
        if [ "$ENABLE_TLS" = true ]; then
            local response=$(curl -s -w "%{http_code}" -o /dev/null --cacert "$CA_CERT" -H "X-Vault-Token: $(cat "$VAULT_DIR/root_token.txt")" "$VAULT_ADDR/v1/sys/health" 2>/dev/null || echo "000")
        else
            local response=$(curl -s -w "%{http_code}" -o /dev/null -H "X-Vault-Token: $(cat "$VAULT_DIR/root_token.txt")" "$VAULT_ADDR/v1/sys/health" 2>/dev/null || echo "000")
        fi

        # Vault health check restituisce 200 se unsealed e ready
        if [ "$response" = "200" ]; then
            log INFO "Vault is ready after $attempt attempts."
            return 0
        fi

        log DEBUG "Attempt $attempt: HTTP response code: $response"
        sleep 3
        ((attempt++))
    done

    log WARN "Vault readiness check timed out after $max_attempts attempts, proceeding anyway..."
    return 0  # Non blocchiamo il processo, procediamo comunque
}

stop_vault() {
    # --- CLUSTER ---
    if [ -f "$VAULT_DIR/vault_pids" ]; then
        while read -r pid; do
            kill "$pid" 2>/dev/null || true
        done < "$VAULT_DIR/vault_pids"
        rm -f "$VAULT_DIR/vault_pids"
        log INFO "All Vault nodes stopped."
        return
    fi
    local vault_port=$(echo "$VAULT_ADDR" | cut -d':' -f3)
    stop_service "Vault" "$LAB_VAULT_PID_FILE" "vault server" "$vault_port"
}

get_vault_status() {
    local vault_exe=$(get_vault_exe)
    # Assicurati che le variabili ambiente siano impostate correttamente
    if [ "$ENABLE_TLS" = true ]; then
        VAULT_ADDR="$VAULT_ADDR" VAULT_CACERT="$CA_CERT" "$vault_exe" status -format=json 2>/dev/null
    else
        VAULT_ADDR="$VAULT_ADDR" "$vault_exe" status -format=json 2>/dev/null
    fi
}

configure_and_start_vault() {
    log INFO "CONFIGURING AND STARTING VAULT"
    stop_vault

    local storage_config=""
    if [ "$BACKEND_TYPE" == "file" ]; then
        mkdir -p "$VAULT_DIR/storage"
        storage_config="storage \"file\" { path = \"$VAULT_DIR/storage\" }"
    elif [ "$BACKEND_TYPE" == "consul" ]; then
        local consul_token=$(cat "$CONSUL_DIR/acl_master_token.txt")
        storage_config="storage \"consul\" { address = \"$CONSUL_ADDR\" path = \"vault/\" token = \"$consul_token\" }"
    fi

    cat > "$VAULT_DIR/config.hcl" <<EOF
$storage_config
listener "tcp" {
  address     = "127.0.0.1:8200"
  tls_disable = 1
}
api_addr = "$VAULT_ADDR"
cluster_addr = "http://127.0.0.1:8201"
ui = true
EOF

    log INFO "Starting Vault server in background..."
    local vault_exe=$(get_vault_exe)
    "$vault_exe" server -config="$VAULT_DIR/config.hcl" > "$VAULT_DIR/vault.log" 2>&1 &
    echo $! > "$LAB_VAULT_PID_FILE"
    log INFO "Vault PID saved to $LAB_VAULT_PID_FILE"
    wait_for_vault_up "$VAULT_ADDR"
}

start_vault_with_tls() {
    log INFO "Starting Vault server with TLS in background..."
    local vault_exe=$(get_vault_exe)

    # Imposta le variabili ambiente per TLS
    export VAULT_CACERT="$CA_CERT"

    "$vault_exe" server -config="$VAULT_DIR/config.hcl" > "$VAULT_DIR/vault.log" 2>&1 &
    echo $! > "$LAB_VAULT_PID_FILE"
    log INFO "Vault PID saved to $LAB_VAULT_PID_FILE"
    wait_for_vault_up "$VAULT_ADDR"
}

# --- CLUSTER ---
start_vault_nodes() {
    log INFO "CONFIGURING AND STARTING 3-NODE VAULT CLUSTER (Consul backend)"
    stop_vault
    local consul_token=$(cat "$CONSUL_DIR/acl_master_token.txt")
    rm -f "$VAULT_DIR/vault_pids"
    for i in 1 2 3; do
        local port=$((8200 + i - 1))
        local cluster_port=$((8300 + i - 1))
        local node_dir="$VAULT_DIR/node_$i"
        mkdir -p "$node_dir"
        cat > "$node_dir/config.hcl" <<EOF
storage "consul" { address = "$CONSUL_ADDR" path = "vault/" token = "$consul_token" }
listener "tcp" { address = "127.0.0.1:$port" tls_disable = 1 }
api_addr = "http://127.0.0.1:$port"
cluster_addr = "http://127.0.0.1:$cluster_port"
ui = true
EOF
        local vault_exe=$(get_vault_exe)
        "$vault_exe" server -config="$node_dir/config.hcl" > "$node_dir/vault.log" 2>&1 &
        echo $! >> "$VAULT_DIR/vault_pids"
        log INFO "Vault node $i started on port $port"
        wait_for_vault_up "http://127.0.0.1:$port"
    done
}

start_vault_nodes_with_tls() {
    log INFO "CONFIGURING AND STARTING 3-NODE VAULT CLUSTER WITH TLS (Consul backend)"
    stop_vault
    local consul_token=$(cat "$CONSUL_DIR/acl_master_token.txt")
    rm -f "$VAULT_DIR/vault_pids"

    for i in 1 2 3; do
        local port=$((8200 + i - 1))
        local cluster_port=$((8300 + i - 1))
        local node_dir="$VAULT_DIR/node_$i"
        mkdir -p "$node_dir"

        # Genera certificato per questo nodo
        generate_vault_certificate "vault-node$i" "127.0.0.1"

        cat > "$node_dir/config.hcl" <<EOF
storage "consul" {
    address = "127.0.0.1:8500"
    path = "vault/"
    token = "$consul_token"
    scheme = "https"
    tls_ca_file = "$CA_CERT"
}
listener "tcp" {
    address = "127.0.0.1:$port"
    tls_cert_file = "$CERTS_DIR/vault-node$i.pem"
    tls_key_file = "$CERTS_DIR/vault-node$i-key.pem"
    tls_ca_file = "$CA_CERT"
}
api_addr = "https://127.0.0.1:$port"
cluster_addr = "https://127.0.0.1:$cluster_port"
ui = true
EOF

        local vault_exe=$(get_vault_exe)
        VAULT_CACERT="$CA_CERT" "$vault_exe" server -config="$node_dir/config.hcl" > "$node_dir/vault.log" 2>&1 &
        echo $! >> "$VAULT_DIR/vault_pids"
        log INFO "Vault node $i started on port $port with TLS"

        # Wait for this node to start
        export VAULT_CACERT="$CA_CERT"
        wait_for_vault_up "https://127.0.0.1:$port"
    done

    # Aggiorna VAULT_ADDR per il primo nodo
    VAULT_ADDR="https://127.0.0.1:8200"
    export VAULT_CACERT="$CA_CERT"
    export VAULT_ADDR="$VAULT_ADDR"
}

initialize_and_unseal_vault() {
    log INFO "INITIALIZING AND UNSEALING VAULT"

    # Imposta le variabili ambiente per TLS se abilitato
    if [ "$ENABLE_TLS" = true ]; then
        export VAULT_CACERT="$CA_CERT"
    fi
    export VAULT_ADDR="$VAULT_ADDR"

    local vault_exe=$(get_vault_exe)
    local status_json=$(get_vault_status)

    if [ "$(echo "$status_json" | jq -r '.initialized')" == "true" ]; then
        log INFO "Vault is already initialized."
    else
        log INFO "Initializing Vault..."
        local init_output=$("$vault_exe" operator init -key-shares=1 -key-threshold=1 -format=json)
        local root_token=$(echo "$init_output" | jq -r '.root_token')
        local unseal_key=$(echo "$init_output" | jq -r '.unseal_keys_b64[0]')
        echo "$root_token" > "$VAULT_DIR/root_token.txt"
        echo "$unseal_key" > "$VAULT_DIR/unseal_key.txt"
        log INFO "Vault initialized. Root Token and Unseal Key saved."
        log WARN "INSECURE: Credentials are saved in plain text in $VAULT_DIR."
    fi

    # Ricontrolla lo status dopo l'inizializzazione
    status_json=$(get_vault_status)
    if [ "$(echo "$status_json" | jq -r '.sealed')" == "true" ]; then
        log INFO "Vault is sealed. Unsealing..."
        local unseal_key=$(cat "$VAULT_DIR/unseal_key.txt")

        if [ "$CLUSTER_MODE" = "multi" ]; then
            for port in 8200 8201 8202; do
                local node_addr="$(echo "$VAULT_ADDR" | sed 's/8200/'$port'/')"
                if [ "$ENABLE_TLS" = true ]; then
                    VAULT_ADDR="$node_addr" VAULT_CACERT="$CA_CERT" "$vault_exe" operator unseal "$unseal_key" >/dev/null
                else
                    VAULT_ADDR="$node_addr" "$vault_exe" operator unseal "$unseal_key" >/dev/null
                fi
                log INFO "Node on port $port unsealed."
            done
        else
            "$vault_exe" operator unseal "$unseal_key" >/dev/null
            log INFO "Vault unsealed successfully."
        fi

        # Aspetta un momento per stabilizzazione
        sleep 5

        # Verifica di nuovo lo status
        status_json=$(get_vault_status)
        if [ "$(echo "$status_json" | jq -r '.sealed')" == "true" ]; then
            log ERROR "Vault is still sealed after unseal operation. Check logs."
        fi
    else
        log INFO "Vault is already unsealed."
    fi

    wait_for_unseal_ready "$VAULT_ADDR"
    export VAULT_TOKEN=$(cat "$VAULT_DIR/root_token.txt")

    # Attendi che Vault sia completamente pronto
    wait_for_vault_ready

    # Debug: mostra status finale
    local final_status=$(get_vault_status)
    log DEBUG "Final Vault status: sealed=$(echo "$final_status" | jq -r '.sealed'), initialized=$(echo "$final_status" | jq -r '.initialized')"
}

configure_vault_features() {
    log INFO "CONFIGURING COMMON VAULT FEATURES"

    # Verifica che Vault sia unsealed prima di procedere
    local status_json=$(get_vault_status)
    if [ "$(echo "$status_json" | jq -r '.sealed')" == "true" ]; then
        log ERROR "Cannot configure Vault features: Vault is sealed!"
        return 1
    fi

    # Assicurati che le variabili ambiente siano impostate
    if [ "$ENABLE_TLS" = true ]; then
        export VAULT_CACERT="$CA_CERT"
    fi
    export VAULT_ADDR="$VAULT_ADDR"
    export VAULT_TOKEN=$(cat "$VAULT_DIR/root_token.txt")

    local vault_exe=$(get_vault_exe)

    # --- KV v2 ---
    log INFO " - Enabling KV v2 secrets engine at 'secret/'"
    "$vault_exe" secrets enable -path=secret kv-v2 &>/dev/null || log WARN "Failed to enable KV v2 engine"

    # --- PKI ---
    log INFO " - Enabling PKI secrets engine at 'pki/'"
    "$vault_exe" secrets enable pki &>/dev/null || log WARN "Failed to enable PKI engine"
    "$vault_exe" secrets tune -max-lease-ttl=87600h pki &>/dev/null || log WARN "Failed to tune PKI engine"

    # --- Policies and Auth ---
    log INFO " - Creating 'dev-policy' for test users..."
    echo 'path "secret/*" {
      capabilities = ["list"]
    }
    path "secret/data/*" {
      capabilities = ["create","read","update","delete","list","patch","sudo"]
    }
    path "secret/metadata/*" {
      capabilities = ["create","read","update","delete","list","patch","sudo"]
    }' | "$vault_exe" policy write dev-policy - || log WARN "Failed to create dev-policy"

    log INFO " - Enabling Userpass authentication..."
    "$vault_exe" auth enable userpass &>/dev/null || log WARN "Failed to enable userpass auth"
    "$vault_exe" write auth/userpass/users/devuser password=devpass policies="default,dev-policy" &>/dev/null || log WARN "Failed to create devuser"

    log INFO " - Enabling and configuring AppRole Auth Method..."
    "$vault_exe" auth enable approle &>/dev/null || log WARN "Failed to enable approle auth"
    echo 'path "secret/*" {
      capabilities = ["list"]
    }
    path "secret/data/my-app/*" {
      capabilities = ["create","read","update","delete","list","patch","sudo"]
    }
    path "secret/metadata/my-app/*" {
      capabilities = ["create","read","update","delete","list","patch","sudo"]
    }' | "$vault_exe" policy write my-app-policy - || log WARN "Failed to create my-app-policy"

    "$vault_exe" write auth/approle/role/web-application token_policies="default,my-app-policy" || log WARN "Failed to create approle role"
    local role_id=$("$vault_exe" read -field=role_id auth/approle/role/web-application/role-id 2>/dev/null || echo "")
    local secret_id=$("$vault_exe" write -f -field=secret_id auth/approle/role/web-application/secret-id 2>/dev/null || echo "")

    if [ -n "$role_id" ]; then
        echo "$role_id" > "$VAULT_DIR/approle_role_id.txt"
    fi
    if [ -n "$secret_id" ]; then
        echo "$secret_id" > "$VAULT_DIR/approle_secret_id.txt"
    fi

    log INFO " - Enabling file audit device to $AUDIT_LOG_PATH"
    "$vault_exe" audit enable file file_path="$AUDIT_LOG_PATH" &>/dev/null || log WARN "Failed to enable audit device"

    log INFO " - Writing test secret to secret/test-secret"
    "$vault_exe" kv put secret/test-secret message="Hello from Vault!" username="testuser" &>/dev/null || log WARN "Failed to write test secret"

    # ------------------------------------------------------------------
    # --- NEW DEMO ENGINES ---------------------------------------------
    # ------------------------------------------------------------------

    # --- Transit engine demo ---
    log INFO " - Enabling Transit secrets engine for encryption-as-a-service"
    "$vault_exe" secrets enable transit &>/dev/null || log WARN "Failed to enable transit engine"
    "$vault_exe" write -f transit/keys/lab-key &>/dev/null || log WARN "Failed to create transit key"
    log INFO "   Transit key 'lab-key' ready. Example: vault write transit/encrypt/lab-key plaintext=$(base64 <<< 'hello')"

    # --- Database secrets engine (mock/demo only) ---
    log INFO " - Enabling Database secrets engine (no backend configured)"
    "$vault_exe" secrets enable database &>/dev/null \
    || log WARN "Could not enable database engine"
    log INFO "   Database engine configured"
}