#!/bin/bash

# Script to configure a ready-to-use laboratory Vault environment.
# - A single Vault instance.
# - Already initialized and unsealed.
# - Root token set to "root".
# - Several common secrets engines enabled.
# - AppRole enabled and configured with an example.
# - Audit Device enabled.
# - Automatically downloads the latest Vault version (excluding enterprise versions).
# - Improved messaging for clarity on the download/update process.
# - Checks and optionally installs prerequisites (curl, jq, unzip, lsof)
#   based on OS, with user consent.
# - Detects existing Vault lab environment and prompts user for cleanup or reuse,
#   intelligently handling initialization and unsealing.

# --- Global Configuration ---
BASE_DIR="/mnt/c/Users/gomiero1/PycharmProjects/PythonProject/zero-to-vault-lab" # Your base directory
BIN_DIR="$BASE_DIR/bin"
VAULT_DIR="$BASE_DIR/vault-lab"
VAULT_ADDR="http://127.0.0.1:8200" # Default Vault address
LAB_VAULT_PID="" # Global variable for Vault PID

# Path for the Audit Log (default path for the lab is /dev/null)
# To enable auditing to a real file, change this variable. Example:
# AUDIT_LOG_PATH="$VAULT_DIR/vault_audit.log"
AUDIT_LOG_PATH="/dev/null"

# --- Global Flags ---
FORCE_CLEANUP_ON_START=false

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
    echo ""
    echo "Default Behavior (no options):"
    echo "  The script will detect an existing Vault lab in '$VAULT_DIR'."
    echo "  If found, it will ask if you want to clean it up or re-use it."
    echo ""
    echo "Examples:"
    echo "  $0"
    echo "  $0 --clean"
    echo "  $0 -c"
    echo ""
    exit 0 # Exit after displaying help
}


# --- Function: Check and Install Prerequisites ---
check_and_install_prerequisites() {
    echo "=================================================="
    echo "CHECKING PREREQUISITES"
    echo "=================================================="

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
        echo "All necessary prerequisites (curl, jq, unzip, lsof) are already installed. 👍"
        return 0 # All good
    fi

    echo -e "\nWARNING: The following prerequisite packages are missing: ${missing_pkgs[*]}"

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
                echo "Homebrew is not installed. Please install Homebrew (https://brew.sh/) to proceed."
                echo "Then run: brew install ${missing_pkgs[*]}"
                read -p "Do you want to proceed without installing missing packages? (y/N): " choice
                if [[ "$choice" =~ ^[Yy]$ ]]; then
                    echo "Proceeding without installing missing packages. This may cause errors. 🚧"
                    return 0
                else
                    echo "Exiting. Please install missing prerequisites manually. 👋"
                    exit 1
                fi
            fi
            ;;
        MINGW64_NT*) # Git Bash on Windows
            echo "Detected Git Bash on Windows. Please install missing packages manually using 'choco' or equivalent:"
            echo "choco install ${missing_pkgs[*]}"
            read -p "Do you want to proceed without installing missing packages? (y/N): " choice
            if [[ "$choice" =~ ^[Yy]$ ]]; then
                echo "Proceeding without installing missing packages. This may cause errors. 🚧"
                return 0
            else
                echo "Exiting. Please install missing prerequisites manually. 👋"
                exit 1
            fi
            ;;
        *)
            echo "Unsupported OS type: $os_type. Please install missing packages manually: ${missing_pkgs[*]} 🤷"
            read -p "Do you want to proceed without installing missing packages? (y/N): " choice
            if [[ "$choice" =~ ^[Yy]$ ]]; then
                echo "Proceeding without installing missing packages. This may cause errors. 🚧"
                return 0
            else
                echo "Exiting. Please install missing prerequisites manually. 👋"
                exit 1
            fi
            ;;
    esac

    if [ -z "$install_cmd" ]; then
        echo "Could not determine an automatic installation command for your system."
        echo "Please install these packages manually: ${missing_pkgs[*]}"
        read -p "Do you want to proceed without installing missing packages? (y/N): " choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            echo "Proceeding without installing missing packages. This may cause errors. 🚧"
            return 0
        else
            echo "Exiting. Please install missing prerequisites manually. 👋"
            exit 1
        fi
    fi

    echo -e "\nTo ensure proper functioning, this script needs to install the missing packages."
    read -p "Do you want to install them now? (y/N): " choice

    if [[ "$choice" =~ ^[Yy]$ ]]; then
        echo "Installing missing packages: ${missing_pkgs[*]}..."
        if eval "$install_cmd ${missing_pkgs[*]}"; then
            echo "Prerequisites installed successfully! 🎉"
            for cmd_name in "${!pkg_map[@]}"; do
                if ! command -v "${pkg_map[$cmd_name]}" &> /dev/null; then
                    echo "WARNING: ${pkg_map[$cmd_name]} still missing after installation attempt. This might cause issues. ⚠️"
                fi
            done
        else
            echo "ERROR: Failed to install prerequisites. Please install them manually and re-run the script. ❌"
            exit 1
        fi
    else
        echo "Installation skipped. This script may not function correctly without these packages. 🤷"
        read -p "Do you still want to proceed? (y/N): " choice_proceed
        if [[ "$choice_proceed" =~ ^[Yy]$ ]]; then
            echo "Proceeding at your own risk. 🚧"
        else
            echo "Exiting. Please install missing prerequisites manually. 👋"
            exit 1
        fi
    fi
    echo "=================================================="
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

    echo "=================================================="
    echo "VAULT BINARY MANAGEMENT: CHECK AND DOWNLOAD"
    echo "=================================================="

    local vault_releases_json
    vault_releases_json=$(curl -s "https://releases.hashicorp.com/vault/index.json")

    if [ -z "$vault_releases_json" ]; then
        echo "Error: 'curl' received no data from HashiCorp URL. Check internet connection or URL: https://releases.hashicorp.com/vault/index.json"
        rm -rf "$temp_dir"
        return 1
    fi

    local latest_version
    latest_version=$(echo "$vault_releases_json" | \
                     tr -d '\r' | \
                     jq -r '.versions | to_entries | .[] | select(.key | contains("ent") | not) | .value.version' | \
                     sort -V | tail -n 1)

    if [ -z "$latest_version" ]; then
        echo "Error: Could not determine the latest Vault version. JSON structure might have changed or no match found."
        rm -rf "$temp_dir"
        return 1
    fi

    echo "Latest available version (excluding Enterprise): $latest_version"

    if [ -f "$vault_exe" ]; then
        local current_version
        current_version=$("$vault_exe" version -short 2>/dev/null | awk '{print $2}')
        current_version=${current_version#v}

        if [ "$current_version" == "$latest_version" ]; then
            echo "Current Vault binary (v$current_version) is already the latest version available."
            echo "No download or update needed. Existing binary will be used."
            rm -rf "$temp_dir"
            return 0
        else
            echo "Current Vault binary is v$current_version. Latest available version is v$latest_version."
            echo "Proceeding with update..."
        fi
    else
        echo "No Vault binary found in $bin_dir. Proceeding with downloading the latest version."
    fi

    local download_url="https://releases.hashicorp.com/vault/${latest_version}/vault_${latest_version}_${platform}.zip"
    local zip_file="$temp_dir/vault.zip"

    echo "Downloading Vault v$latest_version for $platform from $download_url..."
    if ! curl -fsSL -o "$zip_file" "$download_url"; then
        echo "Error: Failed to download Vault from $download_url. Check internet connection or URL."
        rm -rf "$temp_dir"
        return 1
    fi

    echo "Extracting the binary..."
    if ! unzip -o "$zip_file" -d "$temp_dir" >/dev/null; then
        echo "Error: Failed to extract the zip file. Ensure 'unzip' is installed and functional."
        rm -rf "$temp_dir"
        return 1
    fi

    if [ -f "$temp_dir/vault" ]; then
        echo "Moving and configuring the new Vault binary to $bin_dir..."
        mkdir -p "$bin_dir"
        mv "$temp_dir/vault" "$vault_exe"
        chmod +x "$vault_exe"
        success=0
        echo "Vault v$latest_version downloaded and configured successfully."
    else
        echo "Error: 'vault' binary not found in the extracted archive."
    fi

    rm -rf "$temp_dir"
    return $success
}

# --- Function: Wait for Vault to be UP and respond to APIs ---
wait_for_vault_up() {
  local addr=$1
  local timeout=30
  local elapsed=0

  echo "Waiting for Vault to listen on $addr..."
  while [[ $elapsed -lt $timeout ]]; do
    if curl -s -o /dev/null -w "%{http_code}" "$addr/v1/sys/seal-status" | grep -q "200"; then
      echo "Vault is listening and responding to APIs after $elapsed seconds. ✅"
      return 0
    fi
    sleep 1
    echo -n "."
    ((elapsed++))
  done
  echo -e "\nVault did not become reachable after $timeout seconds. Check logs ($VAULT_DIR/vault.log). ❌"
  return 1 # Indicate failure
}

# --- Function: Clean up previous environment ---
cleanup_previous_environment() {
    echo "=================================================="
    echo "FULL CLEANUP OF PREVIOUS LAB ENVIRONMENT"
    echo "=================================================="

    echo "Stopping all Vault processes listening on port 8200..."
    local vault_pid=$(lsof -ti:8200 2>/dev/null)
    if [ -n "$vault_pid" ]; then
        kill -9 "$vault_pid" >/dev/null 2>&1
        echo "Killed Vault process (PID: $vault_pid)."
        sleep 1 # Give it a moment to release the port
    else
        echo "No Vault process found on port 8200."
    fi

    echo "Deleting previous working directories..."
    rm -rf "$VAULT_DIR"

    echo "Recreating empty directories..."
    mkdir -p "$VAULT_DIR"
}

# --- Function: Configure and start Vault ---
configure_and_start_vault() {
    echo -e "\n=================================================="
    echo "CONFIGURING LAB VAULT (SINGLE INSTANCE)"
    echo "=================================================="

    # Ensure Vault is not already running on the port
    if lsof -ti:"$(echo "$VAULT_ADDR" | cut -d':' -f3)" >/dev/null; then
        echo "Vault process already running on port $(echo "$VAULT_ADDR" | cut -d':' -f3). Stopping it first."
        local vault_pid=$(lsof -ti:"$(echo "$VAULT_ADDR" | cut -d':' -f3)" 2>/dev/null)
        if [ -n "$vault_pid" ]; then
            kill -9 "$vault_pid" >/dev/null 2>&1
            sleep 2
            if lsof -ti:"$(echo "$VAULT_ADDR" | cut -d':' -f3)" >/dev/null; then
                echo "ERROR: Could not stop existing Vault process. Manual intervention required. 🛑"
                exit 1
            fi
            echo "Existing Vault process stopped. ✅"
        else
            echo "No Vault process found to stop, but port is in use. May be another application. ⚠️"
            echo "Please ensure port 8200 is free."
            exit 1
        fi
    fi

    echo "Configuring Vault file..."
    cat > "$VAULT_DIR/config.hcl" <<EOF
storage "file" {
  path = "$VAULT_DIR/storage"
}

listener "tcp" {
  address     = "127.0.0.1:8200"
  tls_disable = 1
}

api_addr = "http://127.0.0.1:8200"
cluster_addr = "http://127.0.0.1:8201"
ui = true
EOF

    echo "Starting Vault server in background..."
    local vault_exe="$BIN_DIR/vault"
    if [[ "$(uname -s)" == *"MINGW"* ]]; then
        vault_exe="$BIN_DIR/vault.exe"
    fi

    "$vault_exe" server -config="$VAULT_DIR/config.hcl" > "$VAULT_DIR/vault.log" 2>&1 &
    LAB_VAULT_PID=$!
    echo "Vault server PID: $LAB_VAULT_PID"

    if ! wait_for_vault_up "$VAULT_ADDR"; then
        echo "ERROR: Vault server failed to start or respond. Check $VAULT_DIR/vault.log ❌"
        exit 1
    fi
}

# --- Function: Get Vault Status ---
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

  echo "Waiting for Vault to be fully unsealed and operational for APIs..."

  while [[ $elapsed -lt $timeout ]]; do
    local status_json=$(get_vault_status)
    if echo "$status_json" | jq -e '.sealed == false' &>/dev/null; then
      echo "Vault is unsealed and operational after $elapsed seconds. ✅"
      return 0
    fi
    sleep 1
    echo -n "."
    ((elapsed++))
  done
  echo -e "\nVault did not become operational (still sealed) after $timeout seconds. Manual intervention may be required. ❌"
  return 1 # Indicate failure
}


# --- Function: Initialize and unseal Vault ---
initialize_and_unseal_vault() {
    echo -e "\n=================================================="
    echo "INITIALIZING AND UNSEALING VAULT"
    echo "=================================================="

    export VAULT_ADDR="$VAULT_ADDR" # Ensure VAULT_ADDR is set for vault commands
    local vault_exe="$BIN_DIR/vault"
    if [[ "$(uname -s)" == *"MINGW"* ]]; then
        vault_exe="$BIN_DIR/vault.exe"
    fi

    local current_status_json=$(get_vault_status)
    local is_initialized=$(echo "$current_status_json" | jq -r '.initialized')
    local is_sealed=$(echo "$current_status_json" | jq -r '.sealed')

    if [ "$is_initialized" == "true" ]; then
        echo "Vault is already initialized. Skipping initialization. ✅"
    else
        echo "Initializing Vault..."
        local INIT_OUTPUT
        INIT_OUTPUT=$("$vault_exe" operator init -key-shares=1 -key-threshold=1 -format=json)
        if [ $? -ne 0 ]; then
            echo "ERROR: Vault initialization failed. Please check $VAULT_DIR/vault.log for details. ❌"
            exit 1
        fi

        local ROOT_TOKEN_VAULT=$(echo "$INIT_OUTPUT" | jq -r '.root_token')
        local UNSEAL_KEY_VAULT=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[0]')

        echo "$ROOT_TOKEN_VAULT" > "$VAULT_DIR/root_token.txt"
        echo "$UNSEAL_KEY_VAULT" > "$VAULT_DIR/unseal_key.txt"
        echo "Vault initialized. Root Token and Unseal Key saved in $VAULT_DIR. 🔑"

        # After initialization, Vault IS sealed. Update state variables.
        current_status_json=$(get_vault_status) # Get updated status
        is_sealed=$(echo "$current_status_json" | jq -r '.sealed')
    fi

    if [ "$is_sealed" == "true" ]; then
        echo "Vault is sealed. Attempting to unseal..."
        if [ -f "$VAULT_DIR/unseal_key.txt" ]; then
            local UNSEAL_KEY_STORED=$(cat "$VAULT_DIR/unseal_key.txt")
            if [ -z "$UNSEAL_KEY_STORED" ]; then
                echo "ERROR: Unseal key file ($VAULT_DIR/unseal_key.txt) exists but is empty. Cannot unseal. ❌"
                exit 1
            fi
            "$vault_exe" operator unseal "$UNSEAL_KEY_STORED" >/dev/null
            if [ $? -ne 0 ]; then
                echo "ERROR: Vault unseal failed with stored key. Manual unseal may be required. ❌"
                exit 1
            fi
            echo "Vault unsealed successfully using stored key. ✅"
        else
            echo "WARNING: Vault is sealed but no unseal_key.txt found in $VAULT_DIR. Cannot unseal automatically. ⚠️"
            echo "Please unseal Vault manually using 'vault operator unseal <KEY>'."
            exit 1 # Exit if cannot auto-unseal for lab setup
        fi
    else
        echo "Vault is already unsealed. Skipping unseal. ✅"
    fi

    if ! wait_for_unseal_ready "$VAULT_ADDR"; then
        echo "ERROR: Vault did not reach unsealed state after initialization/unseal attempts. Exiting. ❌"
        exit 1
    fi

    # Set the VAULT_TOKEN for subsequent operations
    if [ -f "$VAULT_DIR/root_token.txt" ]; then
        local initial_root_token=$(cat "$VAULT_DIR/root_token.txt")
        if [ -n "$initial_root_token" ]; then
            export VAULT_TOKEN="$initial_root_token"
        else
            echo "WARNING: $VAULT_DIR/root_token.txt is empty. Cannot set initial VAULT_TOKEN. ⚠️"
        fi
    else
        echo "WARNING: $VAULT_DIR/root_token.txt not found. Cannot set initial VAULT_TOKEN. ⚠️"
    fi

    # Now, try to create or ensure the 'root' token with ID "root"
    echo "Ensuring 'root' token with ID 'root' for lab use..."
    # Check if a token with ID 'root' exists and is valid
    # Use the current VAULT_TOKEN (the one generated or pre-existing) for this check/creation
    if "$vault_exe" token lookup "root" &>/dev/null; then
        echo "Root token 'root' already exists. ✅"
        export VAULT_TOKEN="root" # Switch to the simpler "root" token if it exists
    else
        echo "Creating 'root' token with ID 'root'..."
        # If the root_token.txt file exists and is not "root", use that for the creation command.
        # Otherwise, rely on the VAULT_TOKEN exported above.
        local token_for_create="$VAULT_TOKEN"
        if [ -f "$VAULT_DIR/root_token.txt" ] && [ "$(cat "$VAULT_DIR/root_token.txt")" != "root" ]; then
            token_for_create=$(cat "$VAULT_DIR/root_token.txt")
        fi

        # Temporarily use the full token to create the "root" token
        local temp_vault_token="$VAULT_TOKEN"
        export VAULT_TOKEN="$token_for_create"

        "$vault_exe" token create -id="root" -policy="root" -no-default-policy -display-name="laboratory-root" >/dev/null
        if [ $? -eq 0 ]; then
            echo "Root token with ID 'root' created successfully. ✅"
            echo "root" > "$VAULT_DIR/root_token.txt" # Overwrite for future use
            export VAULT_TOKEN="root" # Set VAULT_TOKEN to the simple "root"
        else
            echo "WARNING: Failed to create 'root' token with ID 'root'. Falling back to initial generated token. ⚠️"
            export VAULT_TOKEN="$temp_vault_token" # Revert to initial token
        fi
    fi
}


# --- Function: Configure AppRole ---
configure_approle() {
    echo -e "\nEnabling and configuring AppRole Auth Method..."

    local vault_exe="$BIN_DIR/vault"
    if [[ "$(uname -s)" == *"MINGW"* ]]; then
        vault_exe="$BIN_DIR/vault.exe"
    fi

    echo " - Enabling Auth Method 'approle' at 'approle/'"
    "$vault_exe" auth enable approle &>/dev/null # Suppress output if already enabled

    cat > "$VAULT_DIR/approle-policy.hcl" <<EOF
path "secret/my-app/*" {
  capabilities = ["read", "list"]
}
path "secret/other-data" {
  capabilities = ["read"]
}
EOF

    echo " - Creating 'my-app-policy' policy for AppRole..."
    "$vault_exe" policy write my-app-policy "$VAULT_DIR/approle-policy.hcl" &>/dev/null

    echo " - Creating AppRole 'web-application' role..."
    "$vault_exe" write auth/approle/role/web-application \
        token_policies="default,my-app-policy" \
        token_ttl="1h" \
        token_max_ttl="24h" &>/dev/null

    local ROLE_ID
    ROLE_ID=$("$vault_exe" read -field=role_id auth/approle/role/web-application/role-id)
    echo "   Role ID for 'web-application': $ROLE_ID (saved in $VAULT_DIR/approle_role_id.txt)"
    echo "$ROLE_ID" > "$VAULT_DIR/approle_role_id.txt"

    local SECRET_ID
    SECRET_ID=$("$vault_exe" write -f -field=secret_id auth/approle/role/web-application/secret-id)
    echo "   Secret ID for 'web-application': $SECRET_ID (saved in $VAULT_DIR/approle_secret_id.txt)"
    echo "$SECRET_ID" > "$VAULT_DIR/approle_secret_id.txt"

    echo "AppRole configuration completed for role 'web-application'."
}


# --- Function: Configure Audit Device (uses global variable AUDIT_LOG_PATH) ---
configure_audit_device() {
    echo -e "\nEnabling and configuring an Audit Device..."
    local vault_exe="$BIN_DIR/vault"
    if [[ "$(uname -s)" == *"MINGW"* ]]; then
        vault_exe="$BIN_DIR/vault.exe"
    fi

    echo " - Enabling file audit device at '$AUDIT_LOG_PATH'"
    local audit_status=$("$vault_exe" audit list -format=json 2>/dev/null | jq -r '.["file/"]' 2>/dev/null)
    if [ "$audit_status" == "null" ] || [ -z "$audit_status" ]; then
        "$vault_exe" audit enable file file_path="$AUDIT_LOG_PATH" &>/dev/null
        echo "Audit Device configured. Logs will be written to $AUDIT_LOG_PATH"
    else
        echo "Audit Device already enabled. Path: $AUDIT_LOG_PATH ✅"
    fi
}


# --- Function: Enable and configure common features ---
configure_vault_features() {
    echo -e "\nEnabling and configuring common features..."

    local vault_exe="$BIN_DIR/vault"
    if [[ "$(uname -s)" == *"MINGW"* ]]; then
        vault_exe="$BIN_DIR/vault.exe"
    fi

    echo " - Enabling KV v2 secrets engine at 'secret/'"
    "$vault_exe" secrets enable -path=secret kv-v2 &>/dev/null

    echo " - Enabling KV v2 secrets engine at 'kv/'"
    "$vault_exe" secrets enable -path=kv kv-v2 &>/dev/null

    echo " - Enabling PKI secrets engine at 'pki/'"
    "$vault_exe" secrets enable pki &>/dev/null
    "$vault_exe" secrets tune -max-lease-ttl=87600h pki &>/dev/null

    echo " - Enabling 'userpass' Auth Method at 'userpass/'"
    "$vault_exe" auth enable userpass &>/dev/null

    echo " - Creating example user 'devuser' with password 'devpass'"
    "$vault_exe" write auth/userpass/users/devuser password=devpass policies=default &>/dev/null || \
      echo "User 'devuser' already exists or failed to create."

    configure_approle
    configure_audit_device

    echo -e "\n--- Populating test secrets ---"
    echo " - Writing test secret to secret/test-secret"
    "$vault_exe" kv put secret/test-secret message="Hello from Vault secret!" username="testuser" &>/dev/null

    echo " - Writing test secret to kv/test-secret"
    "$vault_exe" kv put kv/test-secret message="Hello from Vault kv!" database="testdb" &>/dev/null
}


# --- Function: Display final information ---
display_final_info() {
    echo -e "\n=================================================="
    echo "LAB VAULT IS READY TO USE!"
    echo "=================================================="

    echo -e "\nMAIN ACCESS DETAILS:"
    echo "URL: $VAULT_ADDR"
    echo "Root Token: root (also saved in $VAULT_DIR/root_token.txt)"
    echo "Example user: devuser / devpass (with 'default' policy)"

    echo -e "\nDETAILED ACCESS POINTS:"
    echo "You can read the test secret from 'secret/test-secret' using:"
    echo "  $BIN_DIR/vault kv get secret/test-secret"
    echo "You can read the test secret from 'kv/test-secret' using:"
    echo "  $BIN_DIR/vault kv get kv/test-secret"


    echo -e "\nAPPROLE 'web-application' DETAILS:"
    echo "Role ID: $(cat "$VAULT_DIR/approle_role_id.txt")"
    echo "Secret ID: $(cat "$VAULT_DIR/approle_secret_id.txt")"

    echo -e "\nCurrent Vault status:"
    "$BIN_DIR/vault" status

    echo -e "\nTo access Vault UI/CLI, use:"
    echo "export VAULT_ADDR=$VAULT_ADDR"
    echo "export VAULT_TOKEN=root"
    echo "Or access the UI at the above address and use 'root' as the token."

    echo -e "\nTo test AppRole authentication:"
    echo "export VAULT_ADDR=$VAULT_ADDR"
    echo "vault write auth/approle/login role_id=\"$(cat "$VAULT_DIR/approle_role_id.txt")\" secret_id=\"$(cat "$VAULT_DIR/approle_secret_id.txt")\""
    echo "Remember that the Secret ID is single-use for new creations, but this token is valid for login."

    echo -e "\nTo stop the server: kill $LAB_VAULT_PID"
    echo "Or to stop all running Vault instances: pkill -f \"vault server\""

    echo -e "\nEnjoy your Vault!"
}


# --- Main Script Flow ---
main() {
    # Argument Parsing
    local arg
    for arg in "$@"; do
        case $arg in
            -h|--help)
                display_help
                ;;
            -c|--clean)
                FORCE_CLEANUP_ON_START=true
                ;;
            *)
                echo "Error: Unknown option '$arg'" >&2
                display_help
                ;;
        esac
    done

    # --- Step 0: Check and Install Prerequisites ---
    check_and_install_prerequisites

    # --- Step 1: Handle Existing Lab Environment ---
    local existing_vault_dir_found=false
    if [ -d "$VAULT_DIR" ] && [ "$(ls -A "$VAULT_DIR" 2>/dev/null)" ]; then
        existing_vault_dir_found=true
    fi

    if [ "$existing_vault_dir_found" = true ]; then
        if [ "$FORCE_CLEANUP_ON_START" = true ]; then
            echo -e "\nForce clean option activated. Cleaning up old Vault data..."
            cleanup_previous_environment
        else
            echo -e "\nAn existing Vault lab environment was detected in '$VAULT_DIR'."
            read -p "Do you want to clean it up and start from scratch? (y/N): " choice
            case "$choice" in
                y|Y )
                    cleanup_previous_environment
                    ;;
                * )
                    echo "Skipping full data cleanup. Attempting to re-use existing data."
                    echo "Note: Re-using will ensure Vault is running, initialized, unsealed, and configurations reapplied."

                    # Ensure bin directory exists and Vault binary is downloaded/updated
                    mkdir -p "$BIN_DIR"
                    download_latest_vault_binary "$BIN_DIR"

                    # Ensure Vault is started
                    configure_and_start_vault

                    # Intelligently initialize/unseal based on current Vault status
                    initialize_and_unseal_vault

                    # Re-apply configurations idempotently
                    configure_vault_features

                    echo -e "\n=================================================="
                    echo "VAULT LAB RE-USE COMPLETED."
                    echo "=================================================="
                    display_final_info
                    exit 0 # Exit after successful re-use
                    ;;
            esac
        fi
    else
        echo -e "\nNo existing Vault lab data found. Proceeding with a fresh setup. ✨"
    fi

    # --- Step 2: Core Setup Process (fresh setup or after forced cleanup) ---
    mkdir -p "$BIN_DIR" # Ensure bin directory exists for download
    download_latest_vault_binary "$BIN_DIR"
    echo "=================================================="

    configure_and_start_vault
    initialize_and_unseal_vault
    configure_vault_features
    display_final_info
}

# Execute the main function
main "$@"