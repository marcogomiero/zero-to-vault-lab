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

# --- Function: Download or update Vault binary ---
download_latest_vault_binary() {
    local bin_dir="$1"
    local platform="linux_amd64"
    local vault_exe="$bin_dir/vault"
    local temp_dir=$(mktemp -d)
    local success=1

    echo "=================================================="
    echo "VAULT BINARY MANAGEMENT: CHECK AND DOWNLOAD"
    echo "=================================================="

    local missing_deps=false
    if ! command -v jq &> /dev/null; then
        echo "WARNING: 'jq' not found. Please install it (e.g., 'sudo apt install jq')."
        missing_deps=true
    fi
    if ! command -v curl &> /dev/null; then
        echo "WARNING: 'curl' not found. Please install it (e.g., 'sudo apt install curl')."
        missing_deps=true
    fi
    if ! command -v unzip &> /dev/null; then
        echo "WARNING: 'unzip' not found. Please install it (e.g., 'sudo apt install unzip')."
        missing_deps=true
    fi

    if [ "$missing_deps" = true ]; then
        echo "Cannot proceed with automatic download due to missing dependencies."
        rm -rf "$temp_dir"
        return 1
    fi

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

    echo "Latest available version (including any release candidates): $latest_version"

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
        echo "Error: Failed to download Vault from $download_url."
        rm -rf "$temp_dir"
        return 1
    fi

    echo "Extracting the binary..."
    if ! unzip -o "$zip_file" -d "$temp_dir" >/dev/null; then
        echo "Error: Failed to extract the zip file."
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
  local timeout=30 # Maximum wait time in seconds
  local elapsed=0

  echo "Waiting for Vault to listen on $addr..."
  while [[ $elapsed -lt $timeout ]]; do
    if curl -s -o /dev/null -w "%{http_code}" "$addr/v1/sys/seal-status" | grep -q "200"; then
      echo "Vault is listening and responding to APIs after $elapsed seconds."
      return 0
    fi
    sleep 1
    echo -n "."
    ((elapsed++))
  done
  echo -e "\nVault did not become reachable after $timeout seconds. Check logs ($VAULT_DIR/vault.log)."
  exit 1
}

# --- Function: Clean up previous environment ---
cleanup_previous_environment() {
    echo "=================================================="
    echo "FULL CLEANUP OF PREVIOUS LAB ENVIRONMENT"
    echo "=================================================="

    echo "Stopping all Vault processes listening on port 8200..."
    lsof -ti:8200 | xargs -r kill >/dev/null 2>&1
    sleep 1

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
    "$BIN_DIR/vault" server -config="$VAULT_DIR/config.hcl" > "$VAULT_DIR/vault.log" 2>&1 &
    LAB_VAULT_PID=$!
    echo "Vault server PID: $LAB_VAULT_PID"

    # New call to the wait function
    wait_for_vault_up "$VAULT_ADDR"
}

# --- Function: Wait for Vault to be UNSEALED and ready ---
wait_for_unseal_ready() {
  local addr=$1
  local timeout=30
  local elapsed=0

  echo "Waiting for Vault to be fully unsealed and operational for APIs..."
  while [[ $elapsed -lt $timeout ]]; do
    status_output=$("$BIN_DIR/vault" status -address=$addr 2>/dev/null)
    if echo "$status_output" | grep -q "Sealed.*false"; then
      echo "Vault is unsealed and operational after $elapsed seconds."
      return 0
    fi
    sleep 1
    echo -n "."
    ((elapsed++))
  done
  echo -e "\nVault did not become operational after $timeout seconds. Check logs."
  exit 1
}


# --- Function: Initialize and unseal Vault ---
initialize_and_unseal_vault() {
    echo -e "\nInitializing Vault..."
    export VAULT_ADDR="$VAULT_ADDR"
    local INIT_OUTPUT
    INIT_OUTPUT=$("$BIN_DIR/vault" operator init -key-shares=1 -key-threshold=1 -format=json)

    local ROOT_TOKEN_VAULT
    ROOT_TOKEN_VAULT=$(echo "$INIT_OUTPUT" | jq -r '.root_token')
    local UNSEAL_KEY_VAULT
    UNSEAL_KEY_VAULT=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[0]')

    echo "$ROOT_TOKEN_VAULT" > "$VAULT_DIR/root_token.txt"
    echo "$UNSEAL_KEY_VAULT" > "$VAULT_DIR/unseal_key.txt"

    echo "Vault initialized."

    echo "Performing Vault unseal with the generated key..."
    "$BIN_DIR/vault" operator unseal "$UNSEAL_KEY_VAULT"
    echo "Vault unsealed."

    wait_for_unseal_ready "$VAULT_ADDR"

    echo "Setting root token to 'root' (lab only, not for production!)..."
    export VAULT_TOKEN="$ROOT_TOKEN_VAULT"
    "$BIN_DIR/vault" token create -id="root" -policy="root" -no-default-policy -display-name="laboratory-root" >/dev/null

    echo "root" > "$VAULT_DIR/root_token.txt"
    export VAULT_TOKEN="root"
}


# --- Function: Configure AppRole ---
configure_approle() {
    echo -e "\nEnabling and configuring AppRole Auth Method..."

    echo " - Enabling Auth Method 'approle' at 'approle/'"
    "$BIN_DIR/vault" auth enable approle

    cat > "$VAULT_DIR/approle-policy.hcl" <<EOF
path "secret/my-app/*" {
  capabilities = ["read", "list"]
}
path "secret/other-data" {
  capabilities = ["read"]
}
EOF

    echo " - Creating 'my-app-policy' policy for AppRole..."
    "$BIN_DIR/vault" policy write my-app-policy "$VAULT_DIR/approle-policy.hcl"

    echo " - Creating AppRole 'web-application' role..."
    "$BIN_DIR/vault" write auth/approle/role/web-application \
        token_policies="default,my-app-policy" \
        token_ttl="1h" \
        token_max_ttl="24h"

    local ROLE_ID
    ROLE_ID=$("$BIN_DIR/vault" read -field=role_id auth/approle/role/web-application/role-id)
    echo "   Role ID for 'web-application': $ROLE_ID (saved in $VAULT_DIR/approle_role_id.txt)"
    echo "$ROLE_ID" > "$VAULT_DIR/approle_role_id.txt"

    local SECRET_ID
    SECRET_ID=$("$BIN_DIR/vault" write -f -field=secret_id auth/approle/role/web-application/secret-id)
    echo "   Secret ID for 'web-application': $SECRET_ID (saved in $VAULT_DIR/approle_secret_id.txt)"
    echo "$SECRET_ID" > "$VAULT_DIR/approle_secret_id.txt"

    echo "AppRole configuration completed for role 'web-application'."
}


# --- Function: Configure Audit Device (uses global variable AUDIT_LOG_PATH) ---
configure_audit_device() {
    echo -e "\nEnabling and configuring an Audit Device..."
    echo " - Enabling file audit device at '$AUDIT_LOG_PATH'"
    "$BIN_DIR/vault" audit enable file file_path="$AUDIT_LOG_PATH"

    echo "Audit Device configured. Logs will be written to $AUDIT_LOG_PATH"
}


# --- Function: Enable and configure common features ---
configure_vault_features() {
    echo -e "\nEnabling and configuring common features..."

    echo " - Enabling KV v2 secrets engine at 'secret/'"
    "$BIN_DIR/vault" secrets enable -path=secret kv-v2

    echo " - Enabling KV v2 secrets engine at 'kv/'"
    "$BIN_DIR/vault" secrets enable -path=kv kv-v2

    echo " - Enabling PKI secrets engine at 'pki/'"
    "$BIN_DIR/vault" secrets enable pki
    "$BIN_DIR/vault" secrets tune -max-lease-ttl=87600h pki

    echo " - Enabling 'userpass' Auth Method at 'userpass/'"
    "$BIN_DIR/vault" auth enable userpass

    echo " - Creating example user 'devuser' with password 'devpass'"
    "$BIN_DIR/vault" write auth/userpass/users/devuser password=devpass policies=default

    configure_approle
    configure_audit_device

    echo -e "\n--- Populating test secrets ---"
    echo " - Writing test secret to secret/test-secret"
    "$BIN_DIR/vault" kv put secret/test-secret message="Hello from Vault secret!" username="testuser"

    echo " - Writing test secret to kv/test-secret"
    "$BIN_DIR/vault" kv put kv/test-secret message="Hello from Vault kv!" database="testdb"
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
    cleanup_previous_environment

    mkdir -p "$BIN_DIR"
    if download_latest_vault_binary "$BIN_DIR" "linux_amd64"; then
        echo "Vault binary is ready for use."
    else
        echo "Automatic Vault binary management did not fully succeed."
        if [ -f "$BIN_DIR/vault" ]; then
            echo "Existing Vault binary in $BIN_DIR/vault will be used."
        else
            echo "FATAL ERROR: No Vault binary available. Manually download the desired binary and place it in $BIN_DIR/vault."
            exit 1
        fi
    fi
    echo "=================================================="

    configure_and_start_vault
    initialize_and_unseal_vault
    configure_vault_features
    display_final_info
}

# Execute the main function
main