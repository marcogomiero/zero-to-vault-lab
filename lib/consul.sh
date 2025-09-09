#!/bin/bash
# lib/consul.sh
# Funzioni per la gestione di Consul come backend di Vault.

get_consul_exe() { get_exe "consul"; }

wait_for_consul_up() {
  local addr=$1; local timeout=${2:-30}; local elapsed=0
  log_info "In attesa che Consul sia raggiungibile su $addr (timeout: ${timeout}s)..."
  while [[ $elapsed -lt $timeout ]]; do
    if curl -s -o /dev/null -w "%{http_code}" "$addr/v1/status/leader" | grep -q "200"; then
      log_info "Consul raggiungibile dopo ${elapsed}s ✅"; return 0
    fi
    sleep 1; echo -n "."; elapsed=$((elapsed + 1))
  done
  log_error "\nTimeout: Consul non raggiungibile. Controlla i log: tail -f $CONSUL_DIR/consul.log"
}

stop_consul() {
  local consul_port=$(echo "$CONSUL_ADDR" | cut -d':' -f3)
  stop_service "Consul" "$LAB_CONSUL_PID_FILE" "consul agent" "$consul_port"
}

get_consul_status() {
    local consul_exe=$(get_consul_exe)
    CONSUL_ADDR="$CONSUL_ADDR" "$consul_exe" members -format=json 2>/dev/null
}

configure_and_start_consul() {
    log_info "CONFIGURING AND STARTING CONSUL (SINGLE NODE SERVER)"
    mkdir -p "$CONSUL_DIR/data" || log_error "Failed to create Consul directories."
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

    log_info "Starting Consul server in background..."
    local consul_exe=$(get_consul_exe)
    "$consul_exe" agent -config-dir="$CONSUL_DIR" > "$CONSUL_DIR/consul.log" 2>&1 &
    echo $! > "$LAB_CONSUL_PID_FILE"
    log_info "Consul PID saved to $LAB_CONSUL_PID_FILE"

    wait_for_consul_up "$CONSUL_ADDR"
    sleep 5 # Wait for stabilization

    log_info "Bootstrapping Consul ACL Master Token..."
    local token_file="$CONSUL_DIR/acl_master_token.txt"
    if [ -f "$token_file" ]; then
        log_info "Re-using existing Consul ACL Master Token."
        export CONSUL_HTTP_TOKEN=$(cat "$token_file")
    else
        local bootstrap_output
        bootstrap_output=$("$consul_exe" acl bootstrap -format=json)
        local root_token=$(echo "$bootstrap_output" | jq -r '.SecretID')
        if [ -z "$root_token" ] || [ "$root_token" == "null" ]; then
            log_error "Failed to extract Consul ACL Master Token."
        fi
        echo "$root_token" > "$token_file"
        log_info "Consul ACL Master Token saved to $token_file. 🔑"
        export CONSUL_HTTP_TOKEN="$root_token"
    fi
}