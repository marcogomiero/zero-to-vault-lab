#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration Variables ---
# Use current directory for data and config files for portability
BASE_DIR="$(pwd)/zero-to-vault-lab_data"
VAULT_CONFIG_DIR="$BASE_DIR/vault_config"
CONSUL_CONFIG_DIR="$BASE_DIR/consul_config"
VAULT_DATA_DIR="$BASE_DIR/vault_data"
CONSUL_DATA_DIR="$BASE_DIR/consul_data"
LOG_FILE="$BASE_DIR/setup-vault-consul.log"

# Ensure log file and base directory exist
mkdir -p "$BASE_DIR"
touch "$LOG_FILE"

# --- Helper Functions ---

# Function to log messages to stdout and a log file
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to check if a command exists in the PATH
check_command() {
  command -v "$1" >/dev/null 2>&1 || { log "Error: $1 CLI not found. Please install it and try again."; exit 1; }
}

# Function to wait for Consul to elect a leader
wait_for_consul_leader() {
  log "---"
  log "Waiting for Consul to become leader..."
  until curl -s http://127.0.0.1:8500/v1/status/leader | grep -q '.*'; do
    log "Consul not yet leader. Waiting 1 second..."
    sleep 1
  done
  log "Consul is ready and leader!"
  log "---"
}

# Function to wait for Vault to be reachable and responsive
wait_for_vault_ready() {
  log "---"
  log "Waiting for Vault to be available..."
  # 'vault status' command returns 0 if Vault is reachable and responsive
  until VAULT_ADDR="http://127.0.0.1:8200" vault status >/dev/null 2>&1; do
    log "Vault not yet available. Waiting 1 second..."
    sleep 1
  done
  log "Vault is available!"
  log "---"
}

# Function to start Consul service in background
start_consul_background() {
  log "Starting Consul in background..."
  mkdir -p "$CONSUL_DATA_DIR" "$CONSUL_CONFIG_DIR"

  cat <<EOF > "$CONSUL_CONFIG_DIR/consul.hcl"
datacenter = "dc1"
data_dir = "$CONSUL_DATA_DIR"
server = true
bootstrap_expect = 1
client_addr = "0.0.0.0"
ui = true
bind_addr = "0.0.0.0" # Bind to all interfaces for lab simplicity
EOF

  # Start Consul in the background, redirecting output to a file
  consul agent -config-dir="$CONSUL_CONFIG_DIR" -dev -ui > "$BASE_DIR/consul.log" 2>&1 &
  CONSUL_PID=$!
  echo "$CONSUL_PID" > "$BASE_DIR/consul.pid"
  log "Consul started with PID: $CONSUL_PID"
  wait_for_consul_leader # Call the wait function after starting
}

# Function to start Vault service in background
start_vault_background() {
  log "Starting Vault in background..."
  mkdir -p "$VAULT_DATA_DIR" "$VAULT_CONFIG_DIR"

  cat <<EOF > "$VAULT_CONFIG_DIR/vault.hcl"
storage "consul" {
  address = "127.0.0.1:8500"
  path    = "vault"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = "true" # For lab purposes, disable TLS
}

ui = true
EOF

  # Start Vault in the background, redirecting output to a file
  # Set VAULT_ADDR for the Vault process
  VAULT_ADDR="http://127.0.0.1:8200" vault server -config="$VAULT_CONFIG_DIR/vault.hcl" > "$BASE_DIR/vault.log" 2>&1 &
  VAULT_PID=$!
  echo "$VAULT_PID" > "$BASE_DIR/vault.pid"
  log "Vault started with PID: $VAULT_PID"
  wait_for_vault_ready # Call the wait function after starting
}

# Function to initialize and unseal Vault
initialize_and_unseal_vault() {
  log "Initializing Vault..."
  # Ensure VAULT_ADDR is set for the CLI commands
  export VAULT_ADDR="http://127.0.0.1:8200"

  VAULT_INIT_OUTPUT=$(vault operator init -key-shares=3 -key-threshold=3)
  log "Vault initialization output:"
  echo "$VAULT_INIT_OUTPUT" | tee -a "$LOG_FILE"

  # Extract unseal keys and root token
  UNSEAL_KEY1=$(echo "$VAULT_INIT_OUTPUT" | grep "Unseal Key 1:" | awk '{print $NF}')
  UNSEAL_KEY2=$(echo "$VAULT_INIT_OUTPUT" | grep "Unseal Key 2:" | awk '{print $NF}')
  UNSEAL_KEY3=$(echo "$VAULT_INIT_OUTPUT" | grep "Unseal Key 3:" | awk '{print $NF}')
  ROOT_TOKEN=$(echo "$VAULT_INIT_OUTPUT" | grep "Root Token:" | awk '{print $NF}')

  if [ -z "$UNSEAL_KEY1" ] || [ -z "$ROOT_TOKEN" ]; then
    log "Error: Failed to extract unseal keys or root token. Vault initialization might have failed."
    exit 1
  fi

  log "Attempting to unseal Vault..."
  vault operator unseal "$UNSEAL_KEY1"
  vault operator unseal "$UNSEAL_KEY2"
  vault operator unseal "$UNSEAL_KEY3"
  log "Vault unsealed."

  log "Logging into Vault with the Root Token..."
  vault login "$ROOT_TOKEN"
  log "Vault login complete. Root Token saved to VAULT_TOKEN environment variable."

  # Export the root token for the current shell session
  export VAULT_TOKEN="$ROOT_TOKEN"

  log "Vault initialized and unsealed successfully."
  log "Unseal Keys:"
  log "  Key 1: $UNSEAL_KEY1"
  log "  Key 2: $UNSEAL_KEY2"
  log "  Key 3: $UNSEAL_KEY3"
  log "Root Token: $ROOT_TOKEN"
  log "THESE KEYS ARE ESSENTIAL TO UNSEAL YOUR VAULT. SAVE THEM IN A SECURE LOCATION!"
}

# Function to clean up background processes and data
cleanup() {
  log "---"
  log "Cleaning up background processes and data..."

  if [ -f "$BASE_DIR/vault.pid" ]; then
    VAULT_PID=$(cat "$BASE_DIR/vault.pid")
    if ps -p "$VAULT_PID" > /dev/null; then
      log "Stopping Vault (PID: $VAULT_PID)..."
      kill "$VAULT_PID"
      wait "$VAULT_PID" 2>/dev/null || true # Wait for process to terminate, ignore "no such process" error
    fi
    rm -f "$BASE_DIR/vault.pid"
  fi

  if [ -f "$BASE_DIR/consul.pid" ]; then
    CONSUL_PID=$(cat "$BASE_DIR/consul.pid")
    if ps -p "$CONSUL_PID" > /dev/null; then
      log "Stopping Consul (PID: $CONSUL_PID)..."
      kill "$CONSUL_PID"
      wait "$CONSUL_PID" 2>/dev/null || true # Wait for process to terminate, ignore "no such process" error
    fi
    rm -f "$BASE_DIR/consul.pid"
  fi

  # Remove data directories, but add a confirmation if not running in CI/CD
  if [ -z "$CI" ]; then # Check if not running in a CI environment
    read -p "Do you want to remove all generated data (config and data directories)? (y/N): " -n 1 -r
    echo # (optional) move to a new line
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      log "Removing data directories: $BASE_DIR"
      rm -rf "$BASE_DIR"
    else
      log "Data directories retained."
    fi
  else
    log "Running in CI environment, removing data directories: $BASE_DIR"
    rm -rf "$BASE_DIR"
  fi

  log "Cleanup complete."
  log "---"
}

# --- Main Execution ---

# Set up trap to call cleanup function on script exit (even on errors)
trap cleanup EXIT

log "Starting Vault with Consul setup script (monoshell version)."

# Check for necessary commands
check_command "vault"
check_command "consul"
check_command "curl"
check_command "jq" # Used implicitly by vault and for parsing

# Start Consul in background and wait for it to be ready
start_consul_background

# Start Vault in background and wait for it to be ready
start_vault_background

# Initialize and unseal Vault
initialize_and_unseal_vault

log "Vault with Consul setup completed successfully."
log "You can now interact with Vault:"
log "  Export VAULT_ADDR=http://127.0.0.1:8200"
log "  Export VAULT_TOKEN=$VAULT_TOKEN (already set in this shell)"
log "  vault status"
log "  vault secrets enable -path=secret/ kv-v2"
log "  vault kv put secret/my-secret value=my-value"
log "  vault kv get secret/my-secret"
log "---"
log "To stop and clean up, simply exit this shell or run 'kill $(cat $BASE_DIR/consul.pid) $(cat $BASE_DIR/vault.pid)' and then 'rm -rf $BASE_DIR'"
