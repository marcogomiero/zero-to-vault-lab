#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration Variables ---
# Use current directory for data and config files for portability
BASE_DIR="$(pwd)/zero-to-vault-lab_data"
VAULT_CONFIG_DIR="$BASE_DIR/vault_config"
CONSUL_CONFIG_DIR="$BASE_DIR/consul_config"
VAULT_DATA_DIR="$BASE_DIR/vault_data"
CONSUL_DATA_DIR="$BASE_DIR/consul_data"
BIN_DIR="$BASE_DIR/bin" # Directory for downloaded binaries
LOG_FILE="$BASE_DIR/setup-vault-consul.log"

# HashiCorp product versions - update as needed
VAULT_VERSION="1.17.0"
CONSUL_VERSION="1.18.1"

# Ensure base directory exists and log file is ready
mkdir -p "$BASE_DIR"
touch "$LOG_FILE"

# --- Helper Functions ---

# Function to log messages to stdout and a log file
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to check if a command exists in the PATH,
# or if it's already in our BIN_DIR.
check_command() {
  if [ -x "$BIN_DIR/$1" ]; then
    return 0 # Command found in our bin directory
  fi
  command -v "$1" >/dev/null 2>&1 || { log "Error: $1 CLI not found. Please install it or ensure it's in PATH. Exiting."; exit 1; }
}

# Function to download and install HashiCorp binaries
download_and_install_binaries() {
  log "Ensuring HashiCorp binaries are available..."
  mkdir -p "$BIN_DIR"

  # Determine OS and Architecture
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *) log "Error: Unsupported architecture $ARCH. Exiting."; exit 1 ;;
  esac

  # --- Download and install Vault ---
  if ! [ -x "$BIN_DIR/vault" ]; then
    log "Downloading Vault v${VAULT_VERSION} for ${OS}_${ARCH}..."
    VAULT_URL="https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_${OS}_${ARCH}.zip"
    curl -sSf -o "$BIN_DIR/vault.zip" "$VAULT_URL" || { log "Error: Failed to download Vault from $VAULT_URL. Exiting."; exit 1; }
    unzip -o "$BIN_DIR/vault.zip" -d "$BIN_DIR"
    rm "$BIN_DIR/vault.zip"
    chmod +x "$BIN_DIR/vault"
    log "Vault binary installed to $BIN_DIR/vault"
  else
    log "Vault binary already exists at $BIN_DIR/vault. Skipping download."
  fi

  # --- Download and install Consul ---
  if ! [ -x "$BIN_DIR/consul" ]; then
    log "Downloading Consul v${CONSUL_VERSION} for ${OS}_${ARCH}..."
    CONSUL_URL="https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_${OS}_${ARCH}.zip"
    curl -sSf -o "$BIN_DIR/consul.zip" "$CONSUL_URL" || { log "Error: Failed to download Consul from $CONSUL_URL. Exiting."; exit 1; }
    unzip -o "$BIN_DIR/consul.zip" -d "$BIN_DIR"
    rm "$BIN_DIR/consul.zip"
    chmod +x "$BIN_DIR/consul"
    log "Consul binary installed to $BIN_DIR/consul"
  else
    log "Consul binary already exists at $BIN_DIR/consul. Skipping download."
  fi

  # Add BIN_DIR to PATH for the current script execution
  export PATH="$BIN_DIR:$PATH"
  log "Added $BIN_DIR to PATH for script execution."
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
    log "Error: Failed to extract unseal keys or root token. Vault initialization might have failed. Exiting."
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

  # Stop Vault process
  if [ -f "$BASE_DIR/vault.pid" ]; then
    VAULT_PID=$(cat "$BASE_DIR/vault.pid")
    if ps -p "$VAULT_PID" > /dev/null; then
      log "Stopping Vault (PID: $VAULT_PID)..."
      kill "$VAULT_PID"
      wait "$VAULT_PID" 2>/dev/null || true # Wait for process to terminate, ignore "no such process" error
    else
      log "Vault PID file found, but process $VAULT_PID is not running."
    fi
    rm -f "$BASE_DIR/vault.pid"
  else
    log "No Vault PID file found."
  fi

  # Stop Consul process
  if [ -f "$BASE_DIR/consul.pid" ]; then
    CONSUL_PID=$(cat "$BASE_DIR/consul.pid")
    if ps -p "$CONSUL_PID" > /dev/null; then
      log "Stopping Consul (PID: $CONSUL_PID)..."
      kill "$CONSUL_PID"
      wait "$CONSUL_PID" 2>/dev/null || true # Wait for process to terminate, ignore "no such process" error
    else
      log "Consul PID file found, but process $CONSUL_PID is not running."
    fi
    rm -f "$BASE_DIR/consul.pid"
  else
    log "No Consul PID file found."
  fi

  # Remove data directories, but add a confirmation if not running in CI/CD
  # Check if CI environment variable is set (common in CI/CD pipelines)
  if [ -z "${CI}" ]; then
    read -p "Do you want to remove all generated data (config and data directories)? (y/N): " -n 1 -r
    echo # (optional) move to a new line
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      log "Removing data directories: $BASE_DIR"
      rm -rf "$BASE_DIR"
    else
      log "Data directories retained."
    fi
  else
    log "Running in CI environment, automatically removing data directories: $BASE_DIR"
    rm -rf "$BASE_DIR"
  fi

  log "Cleanup complete."
  log "---"
}

# --- Main Execution ---

# Set up trap to call cleanup function on script exit (even on errors)
trap cleanup EXIT

log "Starting Vault with Consul setup script (monoshell version)."

# First, download and install binaries if they are not already present
download_and_install_binaries

# Now, check for necessary system commands (like curl, unzip, jq)
# Vault and Consul are now guaranteed to be in BIN_DIR due to download_and_install_binaries
check_command "curl"
check_command "unzip" # Required for extracting downloaded binaries
check_command "jq" # Used by some Vault output parsing or for general JSON handling

# Start Consul in background and wait for it to be ready
start_consul_background

# Start Vault in background and wait for it to be ready
start_vault_background

# Initialize and unseal Vault
initialize_and_unseal_vault

log "Vault with Consul setup completed successfully."
log "You can now interact with Vault:"
log "  Export VAULT_ADDR=http://127.0.0.1:8200"
log "  Export VAULT_TOKEN=$VAULT_TOKEN (already set in this shell for convenience)"
log "  Try running: vault status"
log "  Try running: vault secrets enable -path=secret/ kv-v2"
log "  Try running: vault kv put secret/my-secret value=my-value"
log "  Try running: vault kv get secret/my-secret"
log "---"
log "To stop and clean up: Just exit this shell, or manually run 'kill $(cat $BASE_DIR/consul.pid) $(cat $BASE_DIR/vault.pid)' and then 'rm -rf $BASE_DIR'."
