#!/bin/bash
# lib/vault.sh
# Funzioni per la configurazione e gestione di Vault.

get_vault_exe() { get_exe "vault"; }

wait_for_vault_up() {
  local addr=$1; local timeout=${2:-30}; local elapsed=0
  log_info "In attesa che Vault sia raggiungibile su $addr (timeout: ${timeout}s)..."
  while [[ $elapsed -lt $timeout ]]; do
    if curl -s -o /dev/null -w "%{http_code}" "$addr/v1/sys/seal-status" | grep -q "200"; then
      log_info "Vault raggiungibile dopo ${elapsed}s ✅"; return 0
    fi
    sleep 1; echo -n "."; elapsed=$((elapsed + 1))
  done
  log_error "\nTimeout: Vault non raggiungibile. Controlla i log: tail -f $VAULT_DIR/vault.log"
}

wait_for_unseal_ready() {
  local addr=$1; local timeout=30; local elapsed=0
  log_info "Waiting for Vault to be fully unsealed..."
  while [[ $elapsed -lt $timeout ]]; do
    local status_json=$(get_vault_status)
    if echo "$status_json" | jq -e '.initialized == true and .sealed == false' &>/dev/null; then
      log_info "Vault is unsealed and operational. ✅"; return 0
    fi
    sleep 1; echo -n "."; ((elapsed++))
  done
  log_error "\nVault did not become operational after $timeout seconds."
}

stop_vault() {
    # --- CLUSTER ---
    if [ -f "$VAULT_DIR/vault_pids" ]; then
        while read -r pid; do
            kill "$pid" 2>/dev/null || true
        done < "$VAULT_DIR/vault_pids"
        rm -f "$VAULT_DIR/vault_pids"
        log_info "All Vault nodes stopped. ✅"
        return
    fi
    local vault_port=$(echo "$VAULT_ADDR" | cut -d':' -f3)
    stop_service "Vault" "$LAB_VAULT_PID_FILE" "vault server" "$vault_port"
}

get_vault_status() {
    local vault_exe=$(get_vault_exe)
    VAULT_ADDR="$VAULT_ADDR" "$vault_exe" status -format=json 2>/dev/null
}

configure_and_start_vault() {
    log_info "CONFIGURING AND STARTING VAULT"
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

    log_info "Starting Vault server in background..."
    local vault_exe=$(get_vault_exe)
    "$vault_exe" server -config="$VAULT_DIR/config.hcl" > "$VAULT_DIR/vault.log" 2>&1 &
    echo $! > "$LAB_VAULT_PID_FILE"
    log_info "Vault PID saved to $LAB_VAULT_PID_FILE"
    wait_for_vault_up "$VAULT_ADDR"
}

# --- CLUSTER ---
start_vault_nodes() {
    log_info "CONFIGURING AND STARTING 3-NODE VAULT CLUSTER (Consul backend)"
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
        log_info "Vault node $i started on port $port"
        wait_for_vault_up "http://127.0.0.1:$port"
    done
}

initialize_and_unseal_vault() {
    log_info "INITIALIZING AND UNSEALING VAULT"
    export VAULT_ADDR="$VAULT_ADDR"
    local vault_exe=$(get_vault_exe)
    local status_json=$(get_vault_status)

    if [ "$(echo "$status_json" | jq -r '.initialized')" == "true" ]; then
        log_info "Vault is already initialized."
    else
        log_info "Initializing Vault..."
        local init_output=$("$vault_exe" operator init -key-shares=1 -key-threshold=1 -format=json)
        local root_token=$(echo "$init_output" | jq -r '.root_token')
        local unseal_key=$(echo "$init_output" | jq -r '.unseal_keys_b64[0]')
        echo "$root_token" > "$VAULT_DIR/root_token.txt"
        echo "$unseal_key" > "$VAULT_DIR/unseal_key.txt"
        log_info "Vault initialized. Root Token and Unseal Key saved. 🔑"
        log_warn "INSECURE: Credentials are saved in plain text in $VAULT_DIR."
    fi

    status_json=$(get_vault_status)
    if [ "$(echo "$status_json" | jq -r '.sealed')" == "true" ]; then
        log_info "Vault is sealed. Unsealing..."
        local unseal_key=$(cat "$VAULT_DIR/unseal_key.txt")
        # --- CLUSTER ---
        if [ "$CLUSTER_MODE" = "multi" ]; then
            for port in 8200 8201 8202; do
                VAULT_ADDR="http://127.0.0.1:$port" "$vault_exe" operator unseal "$unseal_key" >/dev/null
                log_info "Node on port $port unsealed."
            done
        else
            "$vault_exe" operator unseal "$unseal_key" >/dev/null
            log_info "Vault unsealed successfully. ✅"
        fi
    else
        log_info "Vault is already unsealed."
    fi

    wait_for_unseal_ready "$VAULT_ADDR"
    export VAULT_TOKEN=$(cat "$VAULT_DIR/root_token.txt")
}

configure_vault_features() {
    log_info "CONFIGURING COMMON VAULT FEATURES"
    local vault_exe=$(get_vault_exe)
    log_info " - Enabling KV v2 secrets engine at 'secret/'"
    "$vault_exe" secrets enable -path=secret kv-v2 &>/dev/null
    log_info " - Enabling PKI secrets engine at 'pki/'"
    "$vault_exe" secrets enable pki &>/dev/null
    "$vault_exe" secrets tune -max-lease-ttl=87600h pki &>/dev/null
    log_info " - Creating 'dev-policy' for test users..."
    echo 'path "secret/*" {
  capabilities = ["list"]
}
path "secret/data/*" {
  capabilities = ["create","read","update","delete","list","patch","sudo"]
}
path "secret/metadata/*" {
  capabilities = ["create","read","update","delete","list","patch","sudo"]
}' | "$vault_exe" policy write dev-policy -
    log_info " - Enabling Userpass authentication..."
    "$vault_exe" auth enable userpass &>/dev/null
    "$vault_exe" write auth/userpass/users/devuser password=devpass policies="default,dev-policy" &>/dev/null
    log_info " - Enabling and configuring AppRole Auth Method..."
    "$vault_exe" auth enable approle &>/dev/null
    echo 'path "secret/*" {
  capabilities = ["list"]
}
path "secret/data/my-app/*" {
  capabilities = ["create","read","update","delete","list","patch","sudo"]
}
path "secret/metadata/my-app/*" {
  capabilities = ["create","read","update","delete","list","patch","sudo"]
}' | "$vault_exe" policy write my-app-policy -
    "$vault_exe" write auth/approle/role/web-application token_policies="default,my-app-policy"
    local role_id=$("$vault_exe" read -field=role_id auth/approle/role/web-application/role-id)
    local secret_id=$("$vault_exe" write -f -field=secret_id auth/approle/role/web-application/secret-id)
    echo "$role_id" > "$VAULT_DIR/approle_role_id.txt"
    echo "$secret_id" > "$VAULT_DIR/approle_secret_id.txt"
    log_info " - Enabling file audit device to $AUDIT_LOG_PATH"
    "$vault_exe" audit enable file file_path="$AUDIT_LOG_PATH" &>/dev/null
    log_info " - Writing test secret to secret/test-secret"
    "$vault_exe" kv put secret/test-secret message="Hello from Vault!" username="testuser" &>/dev/null
}
