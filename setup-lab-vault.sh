#!/bin/bash

# --- Global Configuration ---
BASE_DIR="/mnt/c/Users/gomiero1/PycharmProjects/PythonProject/zero-to-vault-lab" # Your base directory for the Vault lab
BIN_DIR="$BASE_DIR/bin" # Directory where Vault binary will be stored
VAULT_DIR="$BASE_DIR/vault-lab" # Working directory for Vault data, config, and keys
VAULT_ADDR="http://127.0.0.1:8200" # Default Vault address for the lab environment
LAB_VAULT_PID_FILE="$VAULT_DIR/vault.pid" # File to store the PID of the running Vault server

# Path for the Audit Log (default for the lab is /dev/null for simplicity)
# To enable auditing to a real file, change this variable. Example:
# AUDIT_LOG_PATH="$VAULT_DIR/vault_audit.log"
AUDIT_LOG_PATH="/dev/null"

# --- Global Flags ---
FORCE_CLEANUP_ON_START=false # Flag to force a clean setup, removing existing data
VERBOSE_OUTPUT=false # Flag to enable more detailed output for debugging
COLORS_ENABLED=true # Flag to control colored output. Default to true.

# --- Colors for better output (initial setup) ---
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Logging Functions ---
# Logs informational messages in green
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# Logs warning messages in yellow
log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

# Logs error messages in red and exits with an error code
log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

# --- Function: Display Help Message ---
display_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "This script deploys a HashiCorp Vault lab environment."
    echo ""
    echo "Options:"
    echo "  -c, --clean    Forces a clean setup, removing any existing Vault data"
    echo "                 in '$VAULT_DIR' before starting."
    echo "  -h, --help     Display this help message and exit."
    echo "  -v, --verbose  Enable verbose output for troubleshooting (currently not fully implemented)."
    echo "  --no-color     Disable colored output, useful for logging or non-interactive environments."
    echo ""
    echo "Default Behavior (no options):"
    echo "  The script will detect an existing Vault lab in '$VAULT_DIR'."
    echo "  If found, it will ask if you want to clean it up or re-use it."
    echo ""
    echo "Examples:"
    echo "  $0"
    echo "  $0 --clean"
    echo "  $0 -v"
    echo "  $0 --no-color"
    echo ""
    exit 0 # Exit after displaying help
}


# --- Function: Check and Install Prerequisites ---
check_and_install_prerequisites() {
    log_info "=================================================="
    log_info "CHECKING PREREQUISITES"
    log_info "=================================================="

    local missing_pkgs=()
    local install_cmd=""
    local os_type=$(uname -s) # Get OS type (Linux, Darwin, MINGW64_NT, etc.)

    # Define packages to check for
    declare -A pkg_map
    pkg_map["curl"]="curl"
    pkg_map["jq"]="jq"
    pkg_map["unzip"]="unzip"
    pkg_map["lsof"]="lsof"

    for cmd_name in "${!pkg_map[@]}"; do
        if ! command -v "${pkg_map[$cmd_name]}" &> /dev/null; then
            missing_pkgs+=("${pkg_map[$cmd_name]}")
        fi
    done

    if [ ${#missing_pkgs[@]} -eq 0 ]; then
        log_info "All necessary prerequisites (curl, jq, unzip, lsof) are already installed. 👍"
        return 0 # All good
    fi

    log_warn "The following prerequisite packages are missing: ${missing_pkgs[*]}"

    # Determine installation command based on OS
    case "$os_type" in
        Linux*)
            if command -v apt-get &> /dev/null; then
                install_cmd="sudo apt-get update && sudo apt-get install -y"
            elif command -v yum &> /dev/null; then
                install_cmd="sudo yum install -y"
            elif command -v dnf &> /dev/null; then
                install_cmd="sudo dnf install -y"
            elif command -v pacman &> /dev/null; then
                install_cmd="sudo pacman -Sy --noconfirm" # pacman needs --noconfirm for non-interactive
            fi
            ;;
        Darwin*) # macOS
            if command -v brew &> /dev/null; then
                install_cmd="brew install"
            else
                log_error "Homebrew is not installed. Please install Homebrew (https://brew.sh/) to proceed."
            fi
            ;;
        MINGW64_NT*) # Git Bash on Windows
            log_warn "Detected Git Bash on Windows. Please install missing packages manually using 'choco' or equivalent (e.g., choco install ${missing_pkgs[*]})."
            echo -e "${YELLOW}Do you want to proceed without installing missing packages? (y/N): ${NC}"
            read choice
            if [[ "$choice" =~ ^[Yy]$ ]]; then
                log_warn "Proceeding without installing missing packages. This may cause errors. 🚧"
                return 0
            else
                log_error "Exiting. Please install missing prerequisites manually. 👋"
            fi
            ;;
        *)
            log_warn "Unsupported OS type: $os_type. Please install missing packages manually: ${missing_pkgs[*]} 🤷"
            echo -e "${YELLOW}Do you want to proceed without installing missing packages? (y/N): ${NC}"
            read choice
            if [[ "$choice" =~ ^[Yy]$ ]]; then
                log_warn "Proceeding without installing missing packages. This may cause errors. 🚧"
                return 0
            else
                log_error "Exiting. Please install missing prerequisites manually. 👋"
            fi
            ;;
    esac

    if [ -z "$install_cmd" ]; then
        log_error "Could not determine an automatic installation command for your system."
        log_error "Please install these packages manually: ${missing_pkgs[*]}"
    fi

    echo -e "\nTo ensure proper functioning, this script needs to install the missing packages."
    echo -e "${YELLOW}Do you want to install them now? (y/N): ${NC}"
    read choice

    if [[ "$choice" =~ ^[Yy]$ ]]; then
        log_info "Installing missing packages: ${missing_pkgs[*]}..."
        if eval "$install_cmd ${missing_pkgs[*]}"; then
            log_info "Prerequisites installed successfully! 🎉"
            for cmd_name in "${!pkg_map[@]}"; do
                if ! command -v "${pkg_map[$cmd_name]}" &> /dev/null; then
                    log_warn "${pkg_map[$cmd_name]} still missing after installation attempt. This might cause issues. ⚠️"
                fi
            done
        else
            log_error "Failed to install prerequisites. Please install them manually and re-run the script. ❌"
        fi
    else
        log_warn "Installation skipped. This script may not function correctly without these packages. 🤷"
        echo -e "${YELLOW}Do you still want to proceed? (y/N): ${NC}"
        read choice_proceed
        if [[ "$choice_proceed" =~ ^[Yy]$ ]]; then
            log_warn "Proceeding at your own risk. 🚧"
        else
            log_error "Exiting. Please install missing prerequisites manually. 👋"
        fi
    fi
    log_info "=================================================="
}

# --- Function: Stop Vault process by PID file ---
stop_vault() {
    log_info "Attempting to stop Vault server..."
    if [ -f "$LAB_VAULT_PID_FILE" ]; then
        local pid=$(cat "$LAB_VAULT_PID_FILE")
        if ps -p "$pid" > /dev/null; then
            log_info "Found running Vault process with PID $pid. Attempting graceful shutdown..."
            kill "$pid" >/dev/null 2>&1
            sleep 5 # Give it some time to shut down
            if ps -p "$pid" > /dev/null; then
                log_warn "Vault process (PID: $pid) did not shut down gracefully. Forcing kill..."
                kill -9 "$pid" >/dev/null 2>&1
                sleep 1 # Give it a moment to release the port
            fi
            if ! ps -p "$pid" > /dev/null; then
                log_info "Vault process (PID: $pid) stopped. ✅"
                rm -f "$LAB_VAULT_PID_FILE"
            else
                log_error "Vault process (PID: $pid) could not be stopped. Manual intervention may be required. 🛑"
            fi
        else
            log_info "No active Vault process found with PID $pid (from $LAB_VAULT_PID_FILE)."
            rm -f "$LAB_VAULT_PID_FILE" # Clean up stale PID file
        fi
    else
        log_info "No Vault PID file found ($LAB_VAULT_PID_FILE)."
    fi
    # Also check if anything else is on 8200
    local vault_port=$(echo "$VAULT_ADDR" | cut -d':' -f3)
    local lingering_pid=$(lsof -ti:"$vault_port" 2>/dev/null)
    if [ -n "$lingering_pid" ]; then
        log_warn "Found lingering process(es) on Vault port $vault_port (PIDs: $lingering_pid). Attempting to kill."
        kill -9 "$lingering_pid" >/dev/null 2>&1
        sleep 1
        if lsof -ti:"$vault_port" >/dev/null; then
             log_error "Could not clear port $vault_port. Manual intervention required. 🛑"
        else
            log_info "Lingering processes on port $vault_port cleared. ✅"
        fi
    fi
}


# --- Function: Download or update Vault binary ---
download_latest_vault_binary() {
    local bin_dir="$1"
    local platform="linux_amd64"

    local os_type=$(uname -s)
    if [ "$os_type" == "Darwin" ]; then
        platform="darwin_amd64"
    elif [[ "$os_type" == *"MINGW"* ]]; then
        platform="windows_amd64"
    fi

    local vault_exe="$bin_dir/vault"
    if [[ "$platform" == *"windows"* ]]; then
        vault_exe="$bin_dir/vault.exe"
    fi

    local temp_dir=$(mktemp -d)
    local success=1

    log_info "=================================================="
    log_info "VAULT BINARY MANAGEMENT: CHECK AND DOWNLOAD"
    log_info "=================================================="

    local vault_releases_json
    vault_releases_json=$(curl -s "https://releases.hashicorp.com/vault/index.json")

    if [ -z "$vault_releases_json" ]; then
        log_error "Error: 'curl' received no data from HashiCorp URL. Check internet connection or URL: https://releases.hashicorp.com/vault/index.json"
        rm -rf "$temp_dir"
        return 1
    fi

    local latest_version
    # Extract the latest non-enterprise version using jq
    latest_version=$(echo "$vault_releases_json" | \
                     tr -d '\r' | \
                     jq -r '.versions | to_entries | .[] | select((.key | contains("ent") | not) and (.key | contains("-rc") | not)) | .value.version' | \
                     sort -V | tail -n 1)

    if [ -z "$latest_version" ]; then
        log_error "Error: Could not determine the latest Vault version. JSON structure might have changed or no match found."
        rm -rf "$temp_dir"
        return 1
    fi

    log_info "Latest available version (excluding Enterprise): $latest_version"

    if [ -f "$vault_exe" ]; then
        local current_version
        # Get current Vault binary version
        current_version=$("$vault_exe" version -short 2>/dev/null | awk '{print $2}')
        current_version=${current_version#v} # Remove 'v' prefix

        if [ "$current_version" == "$latest_version" ]; then
            log_info "Current Vault binary (v$current_version) is already the latest version available."
            log_info "No download or update needed. Existing binary will be used."
            rm -rf "$temp_dir"
            return 0
        else
            log_info "Current Vault binary is v$current_version. Latest available version is v$latest_version."
            log_info "Proceeding with update..."
        fi
    else
        log_info "No Vault binary found in $bin_dir. Proceeding with downloading the latest version."
    fi

    local download_url="https://releases.hashicorp.com/vault/${latest_version}/vault_${latest_version}_${platform}.zip"
    local zip_file="$temp_dir/vault.zip"

    log_info "Downloading Vault v$latest_version for $platform from $download_url..."
    if ! curl -fsSL -o "$zip_file" "$download_url"; then
        log_error "Error: Failed to download Vault from $download_url. Check internet connection or URL."
        rm -rf "$temp_dir"
        return 1
    fi

    log_info "Extracting the binary..."
    if ! unzip -o "$zip_file" -d "$temp_dir" >/dev/null; then
        log_error "Error: Failed to extract the zip file. Ensure 'unzip' is installed and functional."
        rm -rf "$temp_dir"
        return 1
    fi

    if [ -f "$temp_dir/vault" ]; then
        log_info "Moving and configuring the new Vault binary to $bin_dir..."
        mkdir -p "$bin_dir" # Ensure bin directory exists
        mv "$temp_dir/vault" "$vault_exe"
        chmod +x "$vault_exe" # Make the binary executable
        success=0
        log_info "Vault v$latest_version downloaded and configured successfully. 🎉"
    else
        log_error "Error: 'vault' binary not found in the extracted archive."
    fi

    rm -rf "$temp_dir" # Clean up temporary directory
    return $success
}

# --- Function: Wait for Vault to be UP and respond to APIs ---
wait_for_vault_up() {
  local addr=$1
  local timeout=30
  local elapsed=0

  log_info "Waiting for Vault to listen on $addr..."
  while [[ $elapsed -lt $timeout ]]; do
    # Check if Vault's health endpoint (seal-status) returns 200 OK
    if curl -s -o /dev/null -w "%{http_code}" "$addr/v1/sys/seal-status" | grep -q "200"; then
      log_info "Vault is listening and responding to APIs after $elapsed seconds. ✅"
      return 0
    fi # Corrected from fì to fi
    sleep 1
    echo -n "." # Progress indicator
    ((elapsed++))
  done
  log_error "Vault did not become reachable after $timeout seconds. Check logs ($VAULT_DIR/vault.log). ❌"
  return 1 # Indicate failure
}

# --- Function: Clean up previous environment ---
cleanup_previous_environment() {
    log_info "=================================================="
    log_info "FULL CLEANUP OF PREVIOUS LAB ENVIRONMENT"
    log_info "=================================================="

    # Use the new stop_vault function for a more robust shutdown
    stop_vault

    log_info "Deleting previous working directories: $VAULT_DIR..."
    rm -rf "$VAULT_DIR"
    if [ $? -ne 0 ]; then
        log_error "Failed to remove '$VAULT_DIR'. Check permissions. ❌"
    fi

    log_info "Recreating empty directories: $VAULT_DIR..."
    mkdir -p "$VAULT_DIR"
    if [ $? -ne 0 ]; then
        log_error "Failed to create '$VAULT_DIR'. Check permissions. ❌"
    fi
    log_info "Cleanup completed. ✅"
}

# --- Function: Configure and start Vault ---
configure_and_start_vault() {
    log_info "\n=================================================="
    log_info "CONFIGURING LAB VAULT (SINGLE INSTANCE)"
    log_info "=================================================="

    local vault_port=$(echo "$VAULT_ADDR" | cut -d':' -f3)

    # Ensure Vault is not already running on the port by stopping it explicitly
    stop_vault # Call the new stop function here before starting

    log_info "Configuring Vault HCL file: $VAULT_DIR/config.hcl"
    cat > "$VAULT_DIR/config.hcl" <<EOF
storage "file" {
  path = "$VAULT_DIR/storage"
}

listener "tcp" {
  address     = "127.0.0.1:8200"
  tls_disable = 1
}

api_addr = "http://127.0.0.1:8200"
cluster_addr = "http://127.0.0.1:8201" # Required even for single instance for internal reasons
ui = true
EOF

    log_info "Starting Vault server in background..."
    local vault_exe="$BIN_DIR/vault"
    if [[ "$(uname -s)" == *"MINGW"* ]]; then
        vault_exe="$BIN_DIR/vault.exe"
    fi

    # Ensure the vault.log file is ready
    touch "$VAULT_DIR/vault.log"
    chmod 644 "$VAULT_DIR/vault.log" # Ensure it's readable

    # Start Vault server, redirecting output to a log file
    "$vault_exe" server -config="$VAULT_DIR/config.hcl" > "$VAULT_DIR/vault.log" 2>&1 &
    echo $! > "$LAB_VAULT_PID_FILE" # Store the PID of the background process in a file
    log_info "Vault server started. PID saved to $LAB_VAULT_PID_FILE"

    # Wait for Vault to come up and be reachable
    if ! wait_for_vault_up "$VAULT_ADDR"; then
        log_error "Vault server failed to start or respond. Check $VAULT_DIR/vault.log ❌"
    fi
}

# --- Function: Get Vault Status (JSON output) ---
get_vault_status() {
    local vault_exe="$BIN_DIR/vault"
    if [[ "$(uname -s)" == *"MINGW"* ]]; then
        vault_exe="$BIN_DIR/vault.exe"
    fi
    # Use -status to get current status, -format=json and jq for parsing
    # Ensure VAULT_ADDR is set for the status command
    VAULT_ADDR="$VAULT_ADDR" "$vault_exe" status -address="$VAULT_ADDR" -format=json 2>/dev/null
}

# --- Function: Wait for Vault to be UNSEALED and ready ---
wait_for_unseal_ready() {
  local addr=$1
  local timeout=30
  local elapsed=0

  log_info "Waiting for Vault to be fully unsealed and operational for APIs..."

  while [[ $elapsed -lt $timeout ]]; do
    local status_json=$(get_vault_status)
    # Check if Vault is initialized AND not sealed
    if echo "$status_json" | jq -e '.initialized == true and .sealed == false' &>/dev/null; then
      log_info "Vault is unsealed and operational after $elapsed seconds. ✅"
      return 0
    fi
    sleep 1
    echo -n "." # Progress indicator
    ((elapsed++))
  done
  log_error "Vault did not become operational (still sealed or not initialized) after $timeout seconds. Manual intervention may be required. ❌"
  return 1 # Indicate failure
}


# --- Function: Initialize and unseal Vault ---
initialize_and_unseal_vault() {
    log_info "\n=================================================="
    log_info "INITIALIZING AND UNSEALING VAULT"
    log_info "=================================================="

    export VAULT_ADDR="$VAULT_ADDR" # Ensure VAULT_ADDR is set for vault commands
    local vault_exe="$BIN_DIR/vault"
    if [[ "$(uname -s)" == *"MINGW"* ]]; then
        vault_exe="$BIN_DIR/vault.exe"
    fi

    local current_status_json=$(get_vault_status)
    if [ -z "$current_status_json" ]; then
        log_error "Could not get Vault status. Is Vault server running and reachable?"
    fi

    local is_initialized=$(echo "$current_status_json" | jq -r '.initialized')
    local is_sealed=$(echo "$current_status_json" | jq -r '.sealed')

    if [ "$is_initialized" == "true" ]; then
        log_info "Vault is already initialized. Skipping initialization. ✅"
    else
        log_info "Initializing Vault with 1 key share and 1 key threshold..."
        local INIT_OUTPUT
        INIT_OUTPUT=$("$vault_exe" operator init -key-shares=1 -key-threshold=1 -format=json)
        if [ $? -ne 0 ]; then
            log_error "Vault initialization failed. Please check $VAULT_DIR/vault.log for details. ❌"
        fi

        local ROOT_TOKEN_VAULT=$(echo "$INIT_OUTPUT" | jq -r '.root_token')
        local UNSEAL_KEY_VAULT=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[0]')

        echo "$ROOT_TOKEN_VAULT" > "$VAULT_DIR/root_token.txt"
        echo "$UNSEAL_KEY_VAULT" > "$VAULT_DIR/unseal_key.txt"
        log_info "Vault initialized. Root Token and Unseal Key saved in $VAULT_DIR. 🔑"
        log_warn "WARNING: Root Token and Unseal Key are saved in plain text files in $VAULT_DIR."
        log_warn "         This is INSECURE for production environments and only suitable for lab use."


        # After initialization, Vault IS sealed. Get updated status.
        current_status_json=$(get_vault_status)
        is_sealed=$(echo "$current_status_json" | jq -r '.sealed')
    fi

    if [ "$is_sealed" == "true" ]; then
        log_info "Vault is sealed. Attempting to unseal..."
        if [ -f "$VAULT_DIR/unseal_key.txt" ]; then
            local UNSEAL_KEY_STORED=$(cat "$VAULT_DIR/unseal_key.txt")
            if [ -z "$UNSEAL_KEY_STORED" ]; then
                log_error "Unseal key file ($VAULT_DIR/unseal_key.txt) exists but is empty. Cannot unseal. ❌"
            fi
            "$vault_exe" operator unseal "$UNSEAL_KEY_STORED" >/dev/null
            if [ $? -ne 0 ]; then
                log_error "Vault unseal failed with stored key. Manual unseal may be required. ❌"
            fi
            log_info "Vault unsealed successfully using stored key. ✅"
        else
            log_error "Vault is sealed but no unseal_key.txt found in $VAULT_DIR. Cannot unseal automatically. ⚠️"
            log_error "Please unseal Vault manually using 'vault operator unseal <KEY>'."
        fi
    else
        log_info "Vault is already unsealed. Skipping unseal. ✅"
    fi

    # Final check for unsealed state
    if ! wait_for_unseal_ready "$VAULT_ADDR"; then
        log_error "Vault did not reach unsealed state after initialization/unseal attempts. Exiting. ❌"
    fi

    # Set the VAULT_TOKEN for subsequent operations
    if [ -f "$VAULT_DIR/root_token.txt" ]; then
        local initial_root_token=$(cat "$VAULT_DIR/root_token.txt")
        if [ -n "$initial_root_token" ]; then
            export VAULT_TOKEN="$initial_root_token"
        else
            log_warn "$VAULT_DIR/root_token.txt is empty. Cannot set initial VAULT_TOKEN. ⚠️"
        fi
    else
        log_warn "$VAULT_DIR/root_token.txt not found. Cannot set initial VAULT_TOKEN. ⚠️"
    fi

    # Ensure the 'root' token with ID "root" is set up for lab ease of use
    log_info "Ensuring 'root' token with ID 'root' for lab use..."
    # Check if a token with ID 'root' exists and is valid
    if "$vault_exe" token lookup "root" &>/dev/null; then
        log_info "Root token 'root' already exists. ✅"
        export VAULT_TOKEN="root" # Switch to the simpler "root" token if it exists
    else
        log_info "Creating 'root' token with ID 'root'..."
        # Use the initial generated token to create the "root" token
        local temp_vault_token="$VAULT_TOKEN" # Store current token
        export VAULT_TOKEN="$initial_root_token" # Use initial token for creation

        "$vault_exe" token create -id="root" -policy="root" -no-default-policy -display-name="laboratory-root" >/dev/null
        if [ $? -eq 0 ]; then
            log_info "Root token with ID 'root' created successfully. ✅"
            echo "root" > "$VAULT_DIR/root_token.txt" # Overwrite for future use
            export VAULT_TOKEN="root" # Set VAULT_TOKEN to the simple "root"
        else
            log_warn "Failed to create 'root' token with ID 'root'. Falling back to initial generated token. ⚠️"
            export VAULT_TOKEN="$temp_vault_token" # Revert to initial token
        fi
    fi
}


# --- Function: Configure AppRole Auth Method ---
configure_approle() {
    log_info "\nEnabling and configuring AppRole Auth Method..."

    local vault_exe="$BIN_DIR/vault"
    if [[ "$(uname -s)" == *"MINGW"* ]]; then
        vault_exe="$BIN_DIR/vault.exe"
    fi

    log_info " - Enabling Auth Method 'approle' at 'approle/'"
    # Enable auth method, redirecting stdout/stderr as it might output "already enabled"
    "$vault_exe" auth enable approle &>/dev/null

    # Define a policy for AppRole
    cat > "$VAULT_DIR/approle-policy.hcl" <<EOF
path "secret/my-app/*" {
  capabilities = ["read", "list"]
}
path "secret/other-data" {
  capabilities = ["read"]
}
EOF

    log_info " - Creating 'my-app-policy' policy for AppRole..."
    "$vault_exe" policy write my-app-policy "$VAULT_DIR/approle-policy.hcl" &>/dev/null

    log_info " - Creating AppRole 'web-application' role..."
    "$vault_exe" write auth/approle/role/web-application \
        token_policies="default,my-app-policy" \
        token_ttl="1h" \
        token_max_ttl="24h" &>/dev/null

    local ROLE_ID
    ROLE_ID=$("$vault_exe" read -field=role_id auth/approle/role/web-application/role-id)
    if [ -z "$ROLE_ID" ]; then
        log_warn "Could not retrieve AppRole Role ID. AppRole setup might have issues. ⚠️"
    else
        log_info "   Role ID for 'web-application': $ROLE_ID (saved in $VAULT_DIR/approle_role_id.txt)"
        echo "$ROLE_ID" > "$VAULT_DIR/approle_role_id.txt"
    fi

    local SECRET_ID
    SECRET_ID=$("$vault_exe" write -f -field=secret_id auth/approle/role/web-application/secret-id)
    if [ -z "$SECRET_ID" ]; then
        log_warn "Could not retrieve AppRole Secret ID. AppRole setup might have issues. ⚠️"
    else
        log_info "   Secret ID for 'web-application': $SECRET_ID (saved in $VAULT_DIR/approle_secret_id.txt)"
        echo "$SECRET_ID" > "$VAULT_DIR/approle_secret_id.txt"
    fi

    log_info "AppRole configuration completed for role 'web-application'."
}


# --- Function: Configure Audit Device (uses global variable AUDIT_LOG_PATH) ---
configure_audit_device() {
    log_info "\nEnabling and configuring an Audit Device..."
    local vault_exe="$BIN_DIR/vault"
    if [[ "$(uname -s)" == *"MINGW"* ]]; then
        vault_exe="$BIN_DIR/vault.exe"
    fi

    log_info " - Enabling file audit device at '$AUDIT_LOG_PATH'"
    local audit_status=$("$vault_exe" audit list -format=json 2>/dev/null | jq -r '.["file/"]' 2>/dev/null)
    if [ "$audit_status" == "null" ] || [ -z "$audit_status" ]; then
        "$vault_exe" audit enable file file_path="$AUDIT_LOG_PATH" &>/dev/null
        log_info "Audit Device configured. Logs will be written to $AUDIT_LOG_PATH"
    else
        log_info "Audit Device already enabled. Path: $AUDIT_LOG_PATH ✅"
    fi
}

# --- NUOVE FUNZIONI PIÙ PICCOLE E MIRATE ---

# Function: Enable and configure secrets engines
enable_secrets_engines() {
    log_info "\nEnabling and configuring Vault secrets engines..."
    local vault_exe="$BIN_DIR/vault"
    if [[ "$(uname -s)" == *"MINGW"* ]]; then
        vault_exe="$BIN_DIR/vault.exe"
    fi

    log_info " - Enabling KV v2 secrets engine at 'secret/'"
    "$vault_exe" secrets enable -path=secret kv-v2 &>/dev/null

    log_info " - Enabling KV v2 secrets engine at 'kv/'"
    "$vault_exe" secrets enable -path=kv kv-v2 &>/dev/null

    log_info " - Enabling PKI secrets engine at 'pki/'"
    "$vault_exe" secrets enable pki &>/dev/null
    "$vault_exe" secrets tune -max-lease-ttl=87600h pki &>/dev/null # Set a long TTL for PKI certs
}

# Function: Configure Vault policies
configure_policies() {
    log_info "\nConfiguring Vault policies..."
    local vault_exe="$BIN_DIR/vault"
    if [[ "$(uname -s)" == *"MINGW"* ]]; then
        vault_exe="$BIN_DIR/vault.exe"
    fi

    log_info " - Creating 'dev-policy' for test users..."
    DEV_POLICY_PATH="$VAULT_DIR/dev-policy.hcl" # Store policy content in a temporary file
    cat > "$DEV_POLICY_PATH" <<EOF
path "secret/data/test-secret" {
  capabilities = ["read", "list"]
}
path "kv/data/test-secret" {
  capabilities = ["read", "list"]
}
# Allow listing secrets at the root of KV v2 mounts for better navigation
path "secret/metadata/*" {
  capabilities = ["list"]
}
path "kv/metadata/*" {
  capabilities = ["list"]
}
EOF
    "$vault_exe" policy write dev-policy "$DEV_POLICY_PATH" || log_error "Failed to write dev-policy."
}

# Function: Configure Userpass authentication method
configure_userpass_auth() {
    log_info "\nEnabling and configuring Userpass authentication..."
    local vault_exe="$BIN_DIR/vault"
    if [[ "$(uname -s)" == *"MINGW"* ]]; then
        vault_exe="$BIN_DIR/vault.exe"
    fi

    if ! "$vault_exe" auth list -format=json | jq -e '."userpass/" // empty' &>/dev/null; then
        log_info "Userpass authentication method not found, enabling it..."
        "$vault_exe" auth enable userpass || log_error "Failed to enable Userpass auth."
    else
        log_info "Userpass authentication method is already enabled. Skipping re-enable. ✅"
    fi

    log_info " - Creating example user 'devuser' with password 'devpass'"
    "$vault_exe" write auth/userpass/users/devuser password=devpass policies="default,dev-policy" &>/dev/null || \
    log_warn "User 'devuser' already exists or failed to create."
}

# Function: Populate test secrets
populate_test_secrets() {
    log_info "\n--- Populating test secrets ---"
    local vault_exe="$BIN_DIR/vault"
    if [[ "$(uname -s)" == *"MINGW"* ]]; then
        vault_exe="$BIN_DIR/vault.exe"
    fi

    log_info " - Writing test secret to secret/test-secret"
    "$vault_exe" kv put secret/test-secret message="Hello from Vault secret!" username="testuser" &>/dev/null

    log_info " - Writing test secret to kv/test-secret"
    "$vault_exe" kv put kv/test-secret message="Hello from Vault kv!" database="testdb" &>/dev/null
}


# --- Function: Enable and configure common features (aggiornata per chiamare le nuove funzioni) ---
configure_vault_features() {
    log_info "\n=================================================="
    log_info "CONFIGURING COMMON VAULT FEATURES"
    log_info "=================================================="

    enable_secrets_engines
    configure_policies
    configure_userpass_auth
    configure_approle
    configure_audit_device
    populate_test_secrets
}


# --- Function: Handle existing lab environment detection ---
handle_existing_lab() {
    local existing_vault_dir_found=false
    # Check if the VAULT_DIR exists and contains any files/directories
    if [ -d "$VAULT_DIR" ] && [ "$(ls -A "$VAULT_DIR" 2>/dev/null)" ]; then
        existing_vault_dir_found=true
    fi

    if [ "$existing_vault_dir_found" = true ]; then
        if [ "$FORCE_CLEANUP_ON_START" = true ]; then
            log_info "\nForce clean option activated. Cleaning up old Vault data..."
            cleanup_previous_environment
        else
            log_warn "\nAn existing Vault lab environment was detected in '$VAULT_DIR'."
            # Modifica qui: usa echo -e per stampare il prompt colorato, poi read
            echo -e "${YELLOW}Do you want to clean it up and start from scratch? (y/N): ${NC}"
            read choice
            case "$choice" in
                y|Y )
                    cleanup_previous_environment
                    ;;
                * )
                    log_info "Skipping full data cleanup. Attempting to re-use existing data."
                    log_info "Note: Re-using will ensure Vault is running, initialized, unsealed, and configurations reapplied."

                    # Ensure bin directory exists and Vault binary is downloaded/updated
                    mkdir -p "$BIN_DIR" || log_error "Failed to create $BIN_DIR."
                    download_latest_vault_binary "$BIN_DIR"

                    # Ensure Vault is started and its PID is set
                    configure_and_start_vault

                    # Intelligently initialize/unseal based on current Vault status
                    initialize_and_unseal_vault

                    # Re-apply configurations idempotently
                    configure_vault_features

                    log_info "\n=================================================="
                    log_info "VAULT LAB RE-USE COMPLETED."
                    log_info "=================================================="
                    display_final_info
                    exit 0 # Exit after successful re-use
                    ;;
            esac
        fi
    else
        log_info "\nNo existing Vault lab data found. Proceeding with a fresh setup. ✨"
    fi
}


# --- Function: Display final information ---
display_final_info() {
    log_info "\n=================================================="
    log_info "LAB VAULT IS READY TO USE!"
    log_info "=================================================="

    # Corrected lines: Added -e to echo for color interpretation
    echo -e "\n${YELLOW}MAIN ACCESS DETAILS:${NC}"
    echo -e "URL: ${GREEN}$VAULT_ADDR${NC}"
    echo -e "Root Token: ${GREEN}root${NC} (also saved in $VAULT_DIR/root_token.txt)"
    echo -e "Example user: ${GREEN}devuser / devpass${NC} (with 'default' policy)"

    echo -e "\n${RED}SECURITY WARNING:${NC}"
    echo -e "${RED}The Vault Root Token and Unseal Key are stored in plain text files in ${VAULT_DIR}.${NC}"
    echo -e "${RED}THIS IS ONLY FOR LAB/DEVELOPMENT PURPOSES AND IS HIGHLY INSECURE FOR PRODUCTION ENVIRONMENTS.${NC}"
    echo -e "${RED}In production, use secure methods for unsealing (e.g., Auto Unseal, Shamir's Secret Sharing) and manage root tokens with extreme care.${NC}"


    echo -e "\n${YELLOW}DETAILED ACCESS POINTS:${NC}"
    echo -e "You can read the test secret from 'secret/test-secret' using:"
    echo -e "  ${GREEN}$BIN_DIR/vault kv get secret/test-secret${NC}"
    echo -e "You can read the test secret from 'kv/test-secret' using:"
    echo -e "  ${GREEN}$BIN_DIR/vault kv get kv/test-secret${NC}"


    echo -e "\n${YELLOW}APPROLE 'web-application' DETAILS:${NC}"
    if [ -f "$VAULT_DIR/approle_role_id.txt" ]; then
        echo -e "Role ID: ${GREEN}$(cat "$VAULT_DIR/approle_role_id.txt")${NC}"
    else
        log_warn "AppRole Role ID file not found. AppRole may not be fully configured. ⚠️"
    fi
    if [ -f "$VAULT_DIR/approle_secret_id.txt" ]; then
        echo -e "Secret ID: ${GREEN}$(cat "$VAULT_DIR/approle_secret_id.txt")${NC}"
    else
        log_warn "AppRole Secret ID file not found. AppRole may not be fully configured. ⚠️"
    fi

    echo -e "\n${YELLOW}Current Vault status:${NC}"
    "$BIN_DIR/vault" status # This command's output might be colored by Vault itself or not, depends on Vault's internal logic.

    echo -e "\n${YELLOW}To access Vault UI/CLI, use:${NC}"
    echo "export VAULT_ADDR=$VAULT_ADDR"
    echo "export VAULT_TOKEN=root"
    echo "Or access the UI at the above address and use 'root' as the token."

    echo -e "\n${YELLOW}To test AppRole authentication:${NC}"
    echo "export VAULT_ADDR=$VAULT_ADDR"
    echo "vault write auth/approle/login role_id=\"$(cat "$VAULT_DIR/approle_role_id.txt" 2>/dev/null)\" secret_id=\"$(cat "$VAULT_DIR/approle_secret_id.txt" 2>/dev/null)\""
    echo "Note: The Secret ID is typically single-use for new creations. This command is for testing the login itself."

    echo -e "\n${YELLOW}To stop the server:${NC}"
    # Use the PID from the file for specific shutdown instruction
    local current_lab_vault_pid=""
    if [ -f "$LAB_VAULT_PID_FILE" ]; then
        current_lab_vault_pid=$(cat "$LAB_VAULT_PID_FILE")
    fi

    if [ -n "$current_lab_vault_pid" ]; then
        echo -e "  ${GREEN}kill $current_lab_vault_pid${NC} (uses PID from $LAB_VAULT_PID_FILE)"
    else
        echo -e "  Could not find Vault PID in $LAB_VAULT_PID_FILE. To stop Vault, find its PID (e.g., ${GREEN}lsof -ti:8200${NC}) and then ${GREEN}kill <PID>${NC}."
    fi
    echo "Or to stop all running Vault instances (less specific, use with caution):"
    echo -e "  ${GREEN}pkill -f \"vault server\"${NC}"
    echo "  (Note: Killing by PID from the .pid file is safer as it targets only this lab's Vault instance)."
    echo -e "  Alternatively, run: ${GREEN}$0 stop${NC} (if you implement a 'stop' command option)" # Suggest a future feature

    log_info "\nEnjoy your Vault!"
    log_info "Logs are available at: $VAULT_DIR/vault.log" # Emphasize log location
}


# --- Main Script Execution Logic ---
main() {
    # Determine if colors should be enabled by default (if stdout is a TTY)
    # This must happen before processing args, so --no-color can override it.
    if [ ! -t 1 ]; then # If stdout is NOT a TTY (e.g., redirected to a file or pipe)
        COLORS_ENABLED=false
    fi

    # Parse command-line arguments
    # This loop processes all arguments provided to the script.
    # It supports -h/--help for help, -c/--clean for forced cleanup, -v/--verbose for more output,
    # and --no-color to explicitly disable colors.
    local arg
    for arg in "$@"; do
        case $arg in
            -h|--help)
                display_help
                ;;
            -c|--clean)
                FORCE_CLEANUP_ON_START=true
                ;;
            -v|--verbose)
                VERBOSE_OUTPUT=true # Currently this flag is not fully integrated for conditional logging.
                ;;
            --no-color) # Handle new --no-color flag
                COLORS_ENABLED=false # User explicitly requests no colors
                ;;
            *)
                log_error "Unknown option '$arg'. Use -h or --help for usage."
                ;;
        esac
    done

    # Apply color disabling *after* parsing options and TTY check
    # This ensures that if COLORS_ENABLED is false (either by TTY check or --no-color),
    # the color variables are set to empty.
    if [ "$COLORS_ENABLED" = false ]; then
        GREEN=''
        YELLOW=''
        RED=''
        NC=''
    fi

    # Step 1: Check and install necessary prerequisites (curl, jq, unzip, lsof).
    # This ensures the script has all required tools before proceeding.
    check_and_install_prerequisites

    # Step 2: Handle existing lab environment.
    # This function checks if a previous Vault lab setup exists and prompts the user
    # to either clean it up or attempt to re-use it. If re-used, it intelligently
    # re-applies configurations.
    handle_existing_lab

    # If we reach here, it means either:
    # a) No existing lab was found.
    # b) User chose to clean up an existing lab.
    # So, we proceed with a fresh setup or a re-initialization.

    # Step 3: Download or update the Vault binary.
    # This ensures the latest stable non-enterprise version of Vault is available.
    mkdir -p "$BIN_DIR" || log_error "Failed to create directory $BIN_DIR. Check permissions."
    download_latest_vault_binary "$BIN_DIR"
    log_info "=================================================="

    # Step 4: Configure and start the Vault server.
    # This creates the necessary configuration file and launches the Vault process.
    configure_and_start_vault

    # Step 5: Initialize and unseal Vault.
    # If Vault is not initialized, it performs initialization and unseals it.
    # If already initialized, it attempts to unseal if sealed.
    initialize_and_unseal_vault

    # Step 6: Configure common Vault features.
    # This includes enabling KV secrets engines, PKI, Userpass auth, AppRole, and Audit Device.
    configure_vault_features

    # Step 7: Display final access information to the user.
    # Provides all details needed to interact with the deployed Vault lab.
    display_final_info
}

# Execute the main function
main "$@"