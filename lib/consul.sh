#!/bin/bash
# lib/consul.sh
# Funzioni per la gestione di Consul come backend di Vault.

get_consul_exe() { get_exe "consul"; }

wait_for_consul_up() {
    wait_for_http_up "$1/v1/status/leader" "${2:-30}" "Consul"
}

stop_consul() {
  local consul_port=$(echo "$CONSUL_ADDR" | cut -d':' -f3)
  stop_service "Consul" "$LAB_CONSUL_PID_FILE" "consul agent" "$consul_port"
}

get_consul_status() {
    local consul_exe=$(get_consul_exe)
    CONSUL_ADDR="$CONSUL_ADDR" ${CONSUL_CACERT:+CONSUL_CACERT="$CONSUL_CACERT"} "$consul_exe" members -format=json 2>/dev/null
}

configure_and_start_consul() {
    log INFO "CONFIGURING AND STARTING CONSUL (SINGLE NODE SERVER)"
    mkdir -p "$CONSUL_DIR/data" || log ERROR "Failed to create Consul directories."
    stop_consul

    cat > "$CONSUL_DIR/consul_config.hcl" <<EOF
datacenter = "dc1"
data_dir = "$CONSUL_DIR/data"
server = true
bootstrap_expect = 1
client_addr = "0.0.0.0"
ui = true
ports { http = 8500 }
acl = {
  enabled = true
  default_policy = "deny"
  enable_token_persistence = true
}
EOF

    log INFO "Starting Consul server in background..."
    local consul_exe=$(get_consul_exe)
    "$consul_exe" agent -config-dir="$CONSUL_DIR" > "$CONSUL_DIR/consul.log" 2>&1 &
    echo $! > "$LAB_CONSUL_PID_FILE"
    log INFO "Consul PID saved to $LAB_CONSUL_PID_FILE"

    wait_for_consul_up "$CONSUL_ADDR"
    sleep 5 # Wait for stabilization

    log INFO "Bootstrapping Consul ACL Master Token..."
    local token_file="$CONSUL_DIR/acl_master_token.txt"
    if [ -f "$token_file" ]; then
        log INFO "Re-using existing Consul ACL Master Token."
        export CONSUL_HTTP_TOKEN=$(cat "$token_file")
    else
        local bootstrap_output
        bootstrap_output=$("$consul_exe" acl bootstrap -format=json)
        local root_token=$(echo "$bootstrap_output" | jq -r '.SecretID')
        if [ -z "$root_token" ] || [ "$root_token" == "null" ]; then
            log ERROR "Failed to extract Consul ACL Master Token."
        fi
        echo "$root_token" > "$token_file"
        log INFO "Consul ACL Master Token saved to $token_file."
        export CONSUL_HTTP_TOKEN="$root_token"
    fi
}

start_consul_with_tls() {
    log INFO "Starting Consul server with TLS in background..."
    local consul_exe=$(get_consul_exe)

    # Imposta le variabili ambiente per TLS
    export CONSUL_CACERT="$CA_CERT"

    "$consul_exe" agent -config-dir="$CONSUL_DIR" > "$CONSUL_DIR/consul.log" 2>&1 &
    echo $! > "$LAB_CONSUL_PID_FILE"
    log INFO "Consul PID saved to $LAB_CONSUL_PID_FILE"

    # Aggiorna CONSUL_ADDR per HTTPS
    CONSUL_ADDR="https://127.0.0.1:8500"
    export CONSUL_CACERT="$CA_CERT"
    export CONSUL_HTTP_ADDR="$CONSUL_ADDR"  # Variabile specifica per il client CLI
    export CONSUL_HTTP_SSL=true             # Abilita SSL per il client CLI

    wait_for_consul_up "$CONSUL_ADDR"
    sleep 5

    log INFO "Bootstrapping Consul ACL Master Token..."
    local token_file="$CONSUL_DIR/acl_master_token.txt"
    if [ -f "$token_file" ]; then
        log INFO "Re-using existing Consul ACL Master Token."
        export CONSUL_HTTP_TOKEN=$(cat "$token_file")
    else
        # Usa le variabili ambiente corrette per HTTPS
        local bootstrap_output
        bootstrap_output=$(CONSUL_HTTP_ADDR="$CONSUL_ADDR" CONSUL_CACERT="$CA_CERT" CONSUL_HTTP_SSL=true "$consul_exe" acl bootstrap -format=json 2>&1)

        if [ $? -ne 0 ]; then
            log ERROR "ACL bootstrap failed: $bootstrap_output"
        fi

        local root_token=$(echo "$bootstrap_output" | jq -r '.SecretID' 2>/dev/null)
        if [ -z "$root_token" ] || [ "$root_token" == "null" ]; then
            log ERROR "Failed to extract Consul ACL Master Token from: $bootstrap_output"
        fi
        echo "$root_token" > "$token_file"
        log INFO "Consul ACL Master Token saved to $token_file."
        export CONSUL_HTTP_TOKEN="$root_token"
    fi
}

# ALTERNATIVA SEMPLICE: Se continua a dare problemi, puoi usare questa versione
# che bypassa temporaneamente il bootstrap ACL per il lab:

start_consul_with_tls_no_acl() {
    log INFO "Starting Consul server with TLS in background..."
    local consul_exe=$(get_consul_exe)

    # Modifica temporaneamente la configurazione per disabilitare ACL
    sed -i 's/enabled = true/enabled = false/' "$CONSUL_DIR/consul_config.hcl"

    export CONSUL_CACERT="$CA_CERT"
    "$consul_exe" agent -config-dir="$CONSUL_DIR" > "$CONSUL_DIR/consul.log" 2>&1 &
    echo $! > "$LAB_CONSUL_PID_FILE"
    log INFO "Consul PID saved to $LAB_CONSUL_PID_FILE"

    CONSUL_ADDR="https://127.0.0.1:8500"
    export CONSUL_CACERT="$CA_CERT"
    export CONSUL_HTTP_ADDR="$CONSUL_ADDR"
    export CONSUL_HTTP_SSL=true

    wait_for_consul_up "$CONSUL_ADDR"
    log INFO "Consul started with TLS but ACL disabled for lab simplicity."
}
