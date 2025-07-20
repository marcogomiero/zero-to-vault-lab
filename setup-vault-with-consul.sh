#!/bin/bash

# ==============================================================================
# Script to install and configure Vault with Consul as a storage backend.
# It automatically detects the latest stable versions.
#
# WARNING: This script is intended for LAB/DEVELOPMENT environments,
# not for production. It runs commands with 'sudo'.
# ==============================================================================

set -e # Exit immediately if a command fails
set -o pipefail # Fail a pipeline if any command in it fails

# --- 1. Dependency Check ---
echo "Checking dependencies (jq, unzip)..."
for cmd in jq unzip; do
  if ! command -v $cmd &> /dev/null; then
    echo "ERROR: Command '$cmd' not found. Please install it before continuing."
    echo "On Debian/Ubuntu systems: sudo apt-get install $cmd"
    exit 1
  fi
done
echo "Dependencies satisfied."
echo

# --- 2. Version Detection and Download ---
echo "Detecting the latest versions of Vault and Consul..."

# We use the HashiCorp API to find the latest versions
VAULT_VERSION=$(curl -s "https://api.releases.hashicorp.com/v1/releases/vault" | jq -r '[.versions[] | select(.version | test("ent|beta|rc|alpha") | not) | .version] | first')
CONSUL_VERSION=$(curl -s "https://api.releases.hashicorp.com/v1/releases/consul" | jq -r '[.versions[] | select(.version | test("ent|beta|rc|alpha") | not) | .version] | first')

if [ -z "$VAULT_VERSION" ] || [ -z "$CONSUL_VERSION" ]; then
    echo "ERROR: Could not determine the latest version for Vault or Consul."
    exit 1
fi

echo "Latest stable Vault version: $VAULT_VERSION"
echo "Latest stable Consul version: $CONSUL_VERSION"
echo

# File variables
ARCH="amd64"
VAULT_ZIP="vault_${VAULT_VERSION}_linux_${ARCH}.zip"
CONSUL_ZIP="consul_${CONSUL_VERSION}_linux_${ARCH}.zip"
VAULT_URL="https://releases.hashicorp.com/vault/${VAULT_VERSION}/${VAULT_ZIP}"
CONSUL_URL="https://releases.hashicorp.com/consul/${CONSUL_VERSION}/${CONSUL_ZIP}"
INSTALL_DIR="/usr/local/bin"

# Download
echo "Downloading Vault..."
curl -sL -o "/tmp/${VAULT_ZIP}" "$VAULT_URL"

echo "Downloading Consul..."
curl -sL -o "/tmp/${CONSUL_ZIP}" "$CONSUL_URL"
echo

# --- 3. Installation ---
echo "Installing Vault and Consul to $INSTALL_DIR..."
# Unzip and move
sudo unzip -o "/tmp/${VAULT_ZIP}" -d "$INSTALL_DIR"
sudo unzip -o "/tmp/${CONSUL_ZIP}" -d "$INSTALL_DIR"

# Clean up temporary files
rm "/tmp/${VAULT_ZIP}" "/tmp/${CONSUL_ZIP}"

echo "Installation complete."
echo

# --- 4. Consul Setup and Startup ---
echo "Configuring Consul..."
# Create data directory for Consul
sudo mkdir -p /opt/consul

# Start Consul in 'dev' mode (ideal for labs)
# We run it in the background and redirect output to a log file
echo "Starting Consul in 'dev' mode..."
nohup consul agent -dev -client=0.0.0.0 > /tmp/consul.log 2>&1 &
CONSUL_PID=$!

echo "Consul started with PID: $CONSUL_PID. The Consul UI will be available at http://127.0.0.1:8500"
# Give Consul a few seconds to start up
sleep 5
echo

# --- 5. Vault Configuration ---
echo "Creating Vault configuration file..."
CONFIG_DIR="/etc/vault.d"
CONFIG_FILE="${CONFIG_DIR}/vault.hcl"

sudo mkdir -p "$CONFIG_DIR"

# Create the HCL configuration file
sudo tee "$CONFIG_FILE" > /dev/null <<EOF
# Vault configuration to use Consul as the backend

storage "consul" {
  address = "127.0.0.1:8500"
  path    = "vault/"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = "true"
}

ui = true
api_addr = "http://127.0.0.1:8200"
cluster_addr = "http://127.0.0.1:8201"
EOF

echo "Configuration file created at $CONFIG_FILE"
echo

# --- 6. Vault Startup ---
echo "Starting Vault server..."
# Set the Vault address for subsequent commands
export VAULT_ADDR='http://127.0.0.1:8200'

# Start the Vault server in the background with the specified configuration
nohup vault server -config="$CONFIG_FILE" > /tmp/vault.log 2>&1 &
VAULT_PID=$!

echo "Vault started with PID: $VAULT_PID."
# Give Vault a few seconds to start up
sleep 5
echo

# --- 7. Initialization and Unseal ---
echo "Initializing Vault..."
# Check the status to ensure it's ready for initialization
STATUS=$(vault status -format=json | jq -r .initialized)

if [ "$STATUS" = "true" ]; then
    echo "Vault is already initialized. Skipping this step."
else
    echo "Vault is not initialized. Proceeding with initialization."
    # Initialize Vault with 1 unseal key and save everything to a file
    vault operator init -key-shares=1 -key-threshold=1 -format=json > /tmp/vault-keys.json

    # Extract the keys and the token
    UNSEAL_KEY=$(jq -r .unseal_keys_b64[0] /tmp/vault-keys.json)
    ROOT_TOKEN=$(jq -r .root_token /tmp/vault-keys.json)

    echo "Vault initialized. Keys saved to /tmp/vault-keys.json"
    echo

    echo "Unsealing Vault..."
    vault operator unseal "$UNSEAL_KEY"

    # Verify that the unseal was successful
    SEALED_STATUS=$(vault status -format=json | jq -r .sealed)
    if [ "$SEALED_STATUS" = "true" ]; then
        echo "ERROR: Failed to unseal Vault."
        exit 1
    fi
    echo "Vault unsealed successfully."
    echo
    echo "===== ROOT TOKEN (SAVE THIS IN A SAFE PLACE) ====="
    echo "$ROOT_TOKEN"
    echo "======================================================"
    echo
fi

# --- 8. Set Environment Variables ---
echo "Configuring environment variables in ~/.bashrc..."

# Extract the root token if the file already exists
if [ -f "/tmp/vault-keys.json" ]; then
    ROOT_TOKEN=$(jq -r .root_token /tmp/vault-keys.json)
else
    echo "Warning: Keys file not found. You will need to set VAULT_TOKEN manually."
    ROOT_TOKEN="YOUR_TOKEN_HERE"
fi

# Remove old configurations if they exist
sed -i '/# Vault & Consul Lab Setup/,+2d' ~/.bashrc

# Add the new configurations
tee -a ~/.bashrc > /dev/null <<EOF

# Vault & Consul Lab Setup
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='${ROOT_TOKEN}'
EOF

echo "---"
echo "✅ Setup complete!"
echo
echo "To apply the changes, run this command or open a new terminal:"
echo "source ~/.bashrc"
echo
echo "Once done, you can use the 'vault' and 'consul' commands directly."
echo "Example: vault status"
echo
echo "User Interfaces:"
echo "  -> Vault UI: http://127.0.0.1:8200 (use the Root Token to log in)"
echo "  -> Consul UI: http://127.0.0.1:8500"
echo
echo "To stop the services:"
echo "  kill $VAULT_PID $CONSUL_PID"
echo "------------------------------------------------------------------"