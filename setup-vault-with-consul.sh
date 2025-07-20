#!/bin/bash

# --- Configuration Variables ---
CONSUL_VERSION="1.19.4" # Ensure you use the latest stable version
VAULT_VERSION="1.17.3"  # Ensure you use the latest stable version
CONSUL_DATA_DIR="/opt/consul/data"
CONSUL_CONFIG_DIR="/etc/consul.d"
CONSUL_USER="consul"
CONSUL_GROUP="consul"
VAULT_CONFIG_DIR="/etc/vault.d"
VAULT_DATA_DIR="/opt/vault/data"
VAULT_USER="vault"
VAULT_GROUP="vault"
CONSUL_LOG_FILE="/var/log/consul.log"
VAULT_LOG_FILE="/var/log/vault.log"

# --- Utility Functions ---
log_info() {
    echo -e "\033[0;32m[INFO]\033[0m $1"
}

log_warn() {
    echo -e "\033[0;33m[WARN]\033[0m $1"
}

log_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1"
    exit 1
}

# --- Check for Existing Configuration ---
check_existing_config() {
    if [ -d "$CONSUL_DATA_DIR" ] || [ -d "$VAULT_DATA_DIR" ]; then
        log_warn "Existing Consul or Vault data directories found:"
        log_warn "  Consul data: $CONSUL_DATA_DIR"
        log_warn "  Vault data: $VAULT_DATA_DIR"
        read -p "Do you want to wipe existing configurations and restart from scratch? (yes/no): " choice
        case "$choice" in
            yes|Yes|YES )
                log_info "Wiping existing data and configurations..."
                sudo rm -rf "$CONSUL_DATA_DIR" "$CONSUL_CONFIG_DIR" "$VAULT_DATA_DIR" "$VAULT_CONFIG_DIR" "/usr/local/bin/consul" "/usr/local/bin/vault" "$CONSUL_LOG_FILE" "$VAULT_LOG_FILE"
                log_info "Existing data and binaries removed. Proceeding with fresh installation."
                ;;
            no|No|NO )
                log_info "Keeping existing data. Exiting script. You might need to manually start services if they are not running."
                exit 0
                ;;
            * )
                log_error "Invalid choice. Exiting."
                ;;
        esac
    fi
}

# --- Main Script Execution ---
check_existing_config

# --- 1. Install Dependencies ---
log_info "Updating packages and installing unzip and curl..."
sudo apt update -y
sudo apt install -y unzip curl

# --- 2. Create User and Group for Consul ---
log_info "Creating user and group for Consul..."
sudo useradd --system --home $CONSUL_CONFIG_DIR --shell /bin/false $CONSUL_USER || log_info "Consul user already exists."
sudo mkdir -p $CONSUL_DATA_DIR || log_error "Failed to create Consul data directory."
sudo chown -R $CONSUL_USER:$CONSUL_GROUP $CONSUL_DATA_DIR
sudo chmod 755 $CONSUL_DATA_DIR
sudo mkdir -p $(dirname $CONSUL_LOG_FILE)
sudo touch $CONSUL_LOG_FILE
sudo chown $CONSUL_USER:$CONSUL_GROUP $CONSUL_LOG_FILE
sudo chmod 640 $CONSUL_LOG_FILE


# --- 3. Download and Install Consul ---
log_info "Downloading and installing Consul v${CONSUL_VERSION}..."
CONSUL_ZIP="consul_${CONSUL_VERSION}_linux_amd64.zip"
curl -L -o /tmp/$CONSUL_ZIP "https://releases.hashicorp.com/consul/${CONSUL_VERSION}/$CONSUL_ZIP" || log_error "Failed to download Consul."
sudo unzip -o /tmp/$CONSUL_ZIP -d /usr/local/bin/ || log_error "Failed to unzip Consul."
sudo chmod +x /usr/local/bin/consul
sudo rm /tmp/$CONSUL_ZIP
log_info "Consul installed to /usr/local/bin/consul"

# --- 4. Configure Consul (Production Mode) ---
log_info "Creating Consul configuration directories..."
sudo mkdir -p $CONSUL_CONFIG_DIR || log_error "Failed to create Consul configuration directory."
sudo chown -R $CONSUL_USER:$CONSUL_GROUP $CONSUL_CONFIG_DIR
sudo chmod 750 $CONSUL_CONFIG_DIR

log_info "Generating gossip encryption key for Consul..."
GOSSIP_KEY=$(consul keygen)
if [ -z "$GOSSIP_KEY" ]; then
    log_error "Failed to generate gossip encryption key."
fi
log_info "Gossip key generated: $GOSSIP_KEY"

log_info "Creating Consul server configuration file..."
sudo tee $CONSUL_CONFIG_DIR/server.hcl > /dev/null <<EOF
datacenter = "dc1"
data_dir = "$CONSUL_DATA_DIR"
server = true
bootstrap_expect = 1 # IMPORTANT: For a real cluster, set this to the number of servers (e.g., 3 or 5)
client_addr = "0.0.0.0"
bind_addr = "{{GetInterfaceIP \"eth0\"}}" # Or your correct network interface
ui = true
encrypt = "$GOSSIP_KEY"
EOF
sudo chown $CONSUL_USER:$CONSUL_GROUP $CONSUL_CONFIG_DIR/server.hcl
sudo chmod 640 $CONSUL_CONFIG_DIR/server.hcl

# --- 5. Start Consul in the background ---
log_info "Starting Consul server in the background..."
# Ensure the log file is writable by the Consul user
sudo -u $CONSUL_USER /usr/local/bin/consul agent -config-dir=$CONSUL_CONFIG_DIR -log-file=$CONSUL_LOG_FILE &
CONSUL_PID=$!
echo $CONSUL_PID > /tmp/consul_pid.txt
log_info "Consul started with PID: $CONSUL_PID. Logs are written to $CONSUL_LOG_FILE"

# Give Consul some time to start up
log_info "Waiting for Consul to become ready (5 seconds)..."
sleep 5

log_info "Verifying Consul cluster members..."
consul members || log_error "Consul did not start correctly."

# --- VAULT ---

# --- 6. Create User and Group for Vault ---
log_info "Creating user and group for Vault..."
sudo useradd --system --home $VAULT_CONFIG_DIR --shell /bin/false $VAULT_USER || log_info "Vault user already exists."
sudo mkdir -p $VAULT_DATA_DIR || log_error "Failed to create Vault data directory."
sudo chown -R $VAULT_USER:$VAULT_GROUP $VAULT_DATA_DIR
sudo chmod 755 $VAULT_DATA_DIR
sudo mkdir -p $(dirname $VAULT_LOG_FILE)
sudo touch $VAULT_LOG_FILE
sudo chown $VAULT_USER:$VAULT_GROUP $VAULT_LOG_FILE
sudo chmod 640 $VAULT_LOG_FILE

# --- 7. Download and Install Vault ---
log_info "Downloading and installing Vault v${VAULT_VERSION}..."
VAULT_ZIP="vault_${VAULT_VERSION}_linux_amd64.zip"
curl -L -o /tmp/$VAULT_ZIP "https://releases.hashicorp.com/vault/${VAULT_VERSION}/$VAULT_ZIP" || log_error "Failed to download Vault."
sudo unzip -o /tmp/$VAULT_ZIP -d /usr/local/bin/ || log_error "Failed to unzip Vault."
sudo chmod +x /usr/local/bin/vault
sudo rm /tmp/$VAULT_ZIP
log_info "Vault installed to /usr/local/bin/vault"

# --- 8. Configure Vault ---
log_info "Creating Vault configuration directories..."
sudo mkdir -p $VAULT_CONFIG_DIR || log_error "Failed to create Vault configuration directory."
sudo chown -R $VAULT_USER:$VAULT_GROUP $VAULT_CONFIG_DIR
sudo chmod 750 $VAULT_CONFIG_DIR

log_info "Creating Vault configuration file..."
sudo tee $VAULT_CONFIG_DIR/vault.hcl > /dev/null <<EOF
listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = "true" # For development/lab environment. Enable TLS for production!
}

storage "consul" {
  address = "127.0.0.1:8500" # Ensure Consul is listening here
  path    = "vault/"
}

ui = true
EOF
sudo chown $VAULT_USER:$VAULT_GROUP $VAULT_CONFIG_DIR/vault.hcl
sudo chmod 640 $VAULT_CONFIG_DIR/vault.hcl

# --- 9. Start Vault in the background ---
log_info "Starting Vault server in the background..."
# Ensure the log file is writable by the Vault user
sudo -u $VAULT_USER /usr/local/bin/vault server -config=$VAULT_CONFIG_DIR/vault.hcl -log-file=$VAULT_LOG_FILE &
VAULT_PID=$!
echo $VAULT_PID > /tmp/vault_pid.txt
log_info "Vault started with PID: $VAULT_PID. Logs are written to $VAULT_LOG_FILE"

# Give Vault some time to start up
log_info "Waiting for Vault to become ready (5 seconds)..."
sleep 5

log_info "Checking Vault status..."
export VAULT_ADDR='http://127.0.0.1:8200'
vault status || log_error "Vault did not start correctly."

log_info "Vault and Consul have been configured and started successfully."
log_info "You can access the Consul UI at http://<YOUR_MACHINE_IP>:8500/ui"
log_info "You can access the Vault UI at http://<YOUR_MACHINE_IP>:8200"

log_info "To manage your environment, you can use the following commands:"
log_info "  View Consul logs: tail -f $CONSUL_LOG_FILE"
log_info "  View Vault logs:  tail -f $VAULT_LOG_FILE"
log_info "  Stop Consul:      sudo kill $(cat /tmp/consul_pid.txt) # Or use 'sudo pkill consul'"
log_info "  Stop Vault:       sudo kill $(cat /tmp/vault_pid.txt)  # Or use 'sudo pkill vault'"

log_info "To initialize Vault, run the following commands:"
echo "export VAULT_ADDR='http://127.0.0.1:8200'"
echo "vault operator init"
echo "vault operator unseal"
echo "Make sure to save your unseal keys and root token!"