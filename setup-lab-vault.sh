#!/bin/bash

# --- Global Configuration ---
BASE_DIR="/mnt/c/Users/gomiero1/PycharmProjects/PythonProject/zero-to-vault-lab" # Your base directory for the Vault lab
BIN_DIR="$BASE_DIR/bin" # Directory where Vault and Consul binaries will be stored
VAULT_DIR="$BASE_DIR/vault-lab" # Working directory for Vault data, config, and keys
CONSUL_DIR="$BASE_DIR/consul-lab" # NEW: Working directory for Consul data and config
VAULT_ADDR="http://127.0.0.1:8200" # Default Vault address for the lab environment
CONSUL_ADDR="http://127.0.0.1:8500" # NEW: Default Consul address for the lab environment
LAB_VAULT_PID_FILE="$VAULT_DIR/vault.pid" # File to store the PID of the running Vault server
LAB_CONSUL_PID_FILE="$CONSUL_DIR/consul.pid" # NEW: File to store the PID of the running Consul server

# Path for the Audit Log (default for the lab is /dev/null for simplicity)
# To enable auditing to a real file, change this variable. Example:
# AUDIT_LOG_PATH="$VAULT_DIR/vault_audit.log"
AUDIT_LOG_PATH="/dev/null"

# --- Global Flags ---
FORCE_CLEANUP_ON_START=false # Flag to force a clean setup, removing existing data
VERBOSE_OUTPUT=false # Flag to enable more detailed output for debugging
COLORS_ENABLED=true # Flag to control colored output. Default to true.
BACKEND_TYPE_SET_VIA_ARG=false # NEW: Flag to track if backend type was set by arg
BACKEND_TYPE="file" # Default backend type for Vault (file or consul)

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
    echo "  -c, --clean        Forces a clean setup, removing any existing Vault data"
    echo "                     in '$VAULT_DIR' and Consul data in '$CONSUL_DIR' before starting."
    echo "  -h, --help         Display this help message and exit."
    echo "  -v, --verbose      Enable verbose output for troubleshooting (currently not fully implemented)."
    echo "  --no-color         Disable colored output, useful for logging or non-interactive environments."
    echo "  --backend <type>   Choose Vault storage backend: 'file' (default) or 'consul'."
    echo "                     If not specified, the script will prompt you interactively."
    echo ""
    echo "Default Behavior (no options):"
    echo "  The script will prompt you to choose the backend type."
    echo "  It will then detect an existing Vault/Consul lab in '$VAULT_DIR' and '$CONSUL_DIR'."
    echo "  If found, it will ask if you want to clean it up or re-use it."
    echo ""
    echo "Examples:"
    echo "  $0"
    echo "  $0 --clean"
    echo "  $0 --backend consul"
    echo "  $0 -v --backend file"
    echo "  $0 --no-color --clean --backend consul"
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

# NEW: --- Function: Stop Consul process by PID file ---
stop_consul() {
    log_info "Attempting to stop Consul server..."
    if [ -f "$LAB_CONSUL_PID_FILE" ]; then
        local pid=$(cat "$LAB_CONSUL_PID_FILE")
        if ps -p "$pid" > /dev/null; then
            log_info "Found running Consul process with PID $pid. Attempting graceful shutdown..."
            kill "$pid" >/dev/null 2>&1
            sleep 5 # Give it some time to shut down
            if ps -p "$pid" > /dev/null; then
                log_warn "Consul process (PID: $pid) did not shut down gracefully. Forcing kill..."
                kill -9 "$pid" >/dev/null 2>&1
                sleep 1 # Give it a moment to release the port
            fi
            if ! ps -p "$pid" > /dev/null; then
                log_info "Consul process (PID: $pid) stopped. ✅"
                rm -f "$LAB_CONSUL_PID_FILE"
            else
                log_error "Consul process (PID: $pid) could not be stopped. Manual intervention may be required. 🛑"
            fi
        else
            log_info "No active Consul process found with PID $pid (from $LAB_CONSUL_PID_FILE)."
            rm -f "$LAB_CONSUL_PID_FILE" # Clean up stale PID file
        fi
    else
        log_info "No Consul PID file found ($LAB_CONSUL_PID_FILE)."
    fi
    # Also check if anything else is on 8500
    local consul_port=$(echo "$CONSUL_ADDR" | cut -d':' -f3)
    local lingering_pid=$(lsof -ti:"$consul_port" 2>/dev/null)
    if [ -n "$lingering_pid" ]; then
        log_warn "Found lingering process(es) on Consul port $consul_port (PIDs: $lingering_pid). Attempting to kill."
        kill -9 "$lingering_pid" >/dev/null 2>&1
        sleep 1
        if lsof -ti:"$consul_port" >/dev/null; then
             log_error "Could not clear port $consul_port. Manual intervention required. 🛑"
        else
            log_info "Lingering processes on port $consul_port cleared. ✅"
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

    log_info "Latest available Vault version (excluding Enterprise): $latest_version"

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

# NEW: --- Function: Download or update Consul binary ---
download_latest_consul_binary() {
    local bin_dir="$1"
    local platform="linux_amd64"

    local os_type=$(uname -s)
    if [ "$os_type" == "Darwin" ]; then
        platform="darwin_amd64"
    elif [[ "$os_type" == *"MINGW"* ]]; then
        platform="windows_amd64"
    fi

    local consul_exe="$bin_dir/consul"
    if [[ "$platform" == *"windows"* ]]; then
        consul_exe="$bin_dir/consul.exe"
    fi

    local temp_dir=$(mktemp -d)
    local success=1

    log_info "=================================================="
    log_info "CONSUL BINARY MANAGEMENT: CHECK AND DOWNLOAD"
    log_info "=================================================="

    local consul_releases_json
    consul_releases_json=$(curl -s "https://releases.hashicorp.com/consul/index.json")

    if [ -z "$consul_releases_json" ]; then
        log_error "Error: 'curl' received no data from HashiCorp URL. Check internet connection or URL: https://releases.hashicorp.com/consul/index.json"
        rm -rf "$temp_dir"
        return 1
    fi

    local latest_version
    # Extract the latest non-enterprise version using jq, similar to Vault
    latest_version=$(echo "$consul_releases_json" | \
                     tr -d '\r' | \
                     jq -r '.versions | to_entries | .[] | select((.key | contains("ent") | not) and (.key | contains("-beta") | not) and (.key | contains("-rc") | not) and (.key | contains("-preview") | not)) | .value.version' | \
                     sort -V | tail -n 1)

    if [ -z "$latest_version" ]; then
        log_error "Error: Could not determine the latest Consul version. JSON structure might have changed or no match found."
        rm -rf "$temp_dir"
        return 1
    fi

    log_info "Latest available Consul version (excluding Enterprise/Beta/RC/Preview): $latest_version"

    if [ -f "$consul_exe" ]; then
        local current_version
        # Get current Consul binary version - requires running it with version flag
        current_version=$("$consul_exe" version -short 2>/dev/null | head -n 1 | awk '{print $2}')
        current_version=${current_version#v} # Remove 'v' prefix

        if [ "$current_version" == "$latest_version" ]; then
            log_info "Current Consul binary (v$current_version) is already the latest version available."
            log_info "No download or update needed. Existing binary will be used."
            rm -rf "$temp_dir"
            return 0
        else
            log_info "Current Consul binary is v$current_version. Latest available version is v$latest_version."
            log_info "Proceeding with update..."
        fi
    else
        log_info "No Consul binary found in $bin_dir. Proceeding with downloading the latest version."
    fi

    local download_url="https://releases.hashicorp.com/consul/${latest_version}/consul_${latest_version}_${platform}.zip"
    local zip_file="$temp_dir/consul.zip"

    log_info "Downloading Consul v$latest_version for $platform from $download_url..."
    if ! curl -fsSL -o "$zip_file" "$download_url"; then
        log_error "Error: Failed to download Consul from $download_url. Check internet connection or URL."
        rm -rf "$temp_dir"
        return 1
    fi

    log_info "Extracting the binary..."
    if ! unzip -o "$zip_file" -d "$temp_dir" >/dev/null; then
        log_error "Error: Failed to extract the zip file. Ensure 'unzip' is installed and functional."
        rm -rf "$temp_dir"
        return 1
    fi

    if [ -f "$temp_dir/consul" ]; then
        log_info "Moving and configuring the new Consul binary to $bin_dir..."
        mkdir -p "$bin_dir" # Ensure bin directory exists
        mv "$temp_dir/consul" "$consul_exe"
        chmod +x "$consul_exe" # Make the binary executable
        success=0
        log_info "Consul v$latest_version downloaded and configured successfully. 🎉"
    else
        log_error "Error: 'consul' binary not found in the extracted archive."
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
    fi
    sleep 1
    echo -n "." # Progress indicator
    ((elapsed++))
  done
  log_error "Vault did not become reachable after $timeout seconds. Check logs ($VAULT_DIR/vault.log). ❌"
  return 1 # Indicate failure
}

# NEW: --- Function: Wait for Consul to be UP and respond to APIs ---
wait_for_consul_up() {
  local addr=$1
  local timeout=30
  local elapsed=0

  log_info "Waiting for Consul to listen on $addr..."
  while [[ $elapsed -lt $timeout ]]; do
    # Check if Consul's health endpoint returns 200 OK
    if curl -s -o /dev/null -w "%{http_code}" "$addr/v1/status/leader" | grep -q "200"; then
      log_info "Consul is listening and responding to APIs after $elapsed seconds. ✅"
      return 0
    fi
    sleep 1
    echo -n "." # Progress indicator
    ((elapsed++))
  done
  log_error "Consul did not become reachable after $timeout seconds. Check logs ($CONSUL_DIR/consul.log). ❌"
  return 1 # Indicate failure
}


# --- Function: Clean up previous environment ---
cleanup_previous_environment() {
    log_info "=================================================="
    log_info "FULL CLEANUP OF PREVIOUS LAB ENVIRONMENT"
    log_info "=================================================="

    # Use the new stop_vault function for a more robust shutdown
    stop_vault

    # NEW: Stop Consul if running
    stop_consul

    log_info "Deleting previous working directories: $VAULT_DIR and $CONSUL_DIR..."
    rm -rf "$VAULT_DIR"
    if [ $? -ne 0 ]; then
        log_error "Failed to remove '$VAULT_DIR'. Check permissions. ❌"
    fi
    rm -rf "$CONSUL_DIR" # NEW
    if [ $? -ne 0 ]; then
        log_error "Failed to remove '$CONSUL_DIR'. Check permissions. ❌"
    fi


    log_info "Recreating empty directories: $VAULT_DIR and $CONSUL_DIR..."
    mkdir -p "$VAULT_DIR"
    if [ $? -ne 0 ]; then
        log_error "Failed to create '$VAULT_DIR'. Check permissions. ❌"
    fi
    mkdir -p "$CONSUL_DIR" # NEW
    if [ $? -ne 0 ]; then
        log_error "Failed to create '$CONSUL_DIR'. Check permissions. ❌"
    fi
    log_info "Cleanup completed. ✅"
}

# NEW: --- Function: Configure and start Consul ---
configure_and_start_consul() {
    log_info "\n=================================================="
    log_info "CONFIGURING AND STARTING CONSUL (SINGLE NODE SERVER)"
    log_info "=================================================="

    local consul_port=$(echo "$CONSUL_ADDR" | cut -d':' -f3)

    # Ensure Consul is not already running on the port by stopping it explicitly
    stop_consul

    log_info "Configuring Consul HCL file: $CONSUL_DIR/consul_config.hcl"
    cat > "$CONSUL_DIR/consul_config.hcl" <<EOF
datacenter = "dc1"
data_dir = "$CONSUL_DIR/data"
server = true
bootstrap_expect = 1
client_addr = "0.0.0.0"
bind_addr = "0.0.0.0"
ui = true
ports {
  http = 8500
  grpc = 8502 # Needed for some newer client features, especially with Vault
}

# ACL Configuration
acl = {
  enabled = true
  default_policy = "deny"
  down_policy = "deny"
  enable_token_persistence = true
}

# Add telemetry for better debugging if needed
# telemetry {
#   prometheus_metrics = true
#   disable_hostname = true
# }
EOF

    # Ensure data directory exists
    mkdir -p "$CONSUL_DIR/data" || log_error "Failed to create Consul data directory."

    log_info "Starting Consul server in background..."
    local consul_exe="$BIN_DIR/consul"
    if [[ "$(uname -s)" == *"MINGW"* ]]; then
        consul_exe="$BIN_DIR/consul.exe"
    fi

    # Ensure the consul.log file is ready
    touch "$CONSUL_DIR/consul.log"
    chmod 644 "$CONSUL_DIR/consul.log" # Ensure it's readable

    # Start Consul server, redirecting output to a log file
    "$consul_exe" agent -config-dir="$CONSUL_DIR" > "$CONSUL_DIR/consul.log" 2>&1 &
    echo $! > "$LAB_CONSUL_PID_FILE" # Store the PID of the background process in a file
    log_info "Consul server started. PID saved to $LAB_CONSUL_PID_FILE"

    # Wait for Consul to come up and be reachable
    if ! wait_for_consul_up "$CONSUL_ADDR"; then
        log_error "Consul server failed to start or respond. Check $CONSUL_DIR/consul.log ❌"
    fi

    log_info "Bootstrapping Consul ACL Master Token..."
    local consul_acl_master_token_file="$CONSUL_DIR/acl_master_token.txt"
    if [ -f "$consul_acl_master_token_file" ]; then
        log_info "Consul ACL Master Token already exists. Re-using existing token. ✅"
        export CONSUL_HTTP_TOKEN=$(cat "$consul_acl_master_token_file")
    else
        local ACL_BOOTSTRAP_OUTPUT
        ACL_BOOTSTRAP_OUTPUT=$("$consul_exe" acl bootstrap -format=json)
        if [ $? -ne 0 ]; then
            log_error "Consul ACL bootstrap failed. Check $CONSUL_DIR/consul.log. ❌"
        fi
        local CONSUL_ROOT_TOKEN=$(echo "$ACL_BOOTSTRAP_OUTPUT" | jq -r '.SecretID')
        if [ -z "$CONSUL_ROOT_TOKEN" ] || [ "$CONSUL_ROOT_TOKEN" == "null" ]; then
            log_error "Failed to extract Consul ACL Master Token from bootstrap output. ❌"
        fi
        echo "$CONSUL_ROOT_TOKEN" > "$consul_acl_master_token_file"
        log_info "Consul ACL Master Token saved to $consul_acl_master_token_file. 🔑"
        log_warn "WARNING: Consul ACL Master Token is saved in plain text files in $CONSUL_DIR."
        log_warn "         This is INSECURE for production environments and only suitable for lab use."
        export CONSUL_HTTP_TOKEN="$CONSUL_ROOT_TOKEN" # Set for subsequent Consul commands
    fi
    log_info "Consul configured and started with ACLs enabled. ✅"
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

    # Conditional storage configuration based on BACKEND_TYPE
    local VAULT_STORAGE_CONFIG=""
    if [ "$BACKEND_TYPE" == "file" ]; then
        VAULT_STORAGE_CONFIG=$(cat <<EOF
storage "file" {
  path = "$VAULT_DIR/storage"
}
EOF
)
        mkdir -p "$VAULT_DIR/storage" || log_error "Failed to create Vault file storage directory."
    elif [ "$BACKEND_TYPE" == "consul" ]; then
        if [ ! -f "$CONSUL_DIR/acl_master_token.txt" ]; then
            log_error "Consul ACL Master Token not found ($CONSUL_DIR/acl_master_token.txt). Cannot configure Vault with Consul backend without it. ❌"
        fi
        local consul_acl_token=$(cat "$CONSUL_DIR/acl_master_token.txt")
        VAULT_STORAGE_CONFIG=$(cat <<EOF
storage "consul" {
  address = "127.0.0.1:8500"
  path    = "vault/"
  token   = "$consul_acl_token" # Use the Consul ACL master token
}
EOF
)
    fi

    # Write the main Vault config file
    cat > "$VAULT_DIR/config.hcl" <<EOF
$VAULT_STORAGE_CONFIG

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

    local existing_consul_dir_found=false # NEW
    if [ "$BACKEND_TYPE" == "consul" ]; then
        # Check if CONSUL_DIR exists and contains any files/directories (e.g., data/ config files)
        if [ -d "$CONSUL_DIR" ] && [ "$(ls -A "$CONSUL_DIR" 2>/dev/null)" ]; then
            existing_consul_dir_found=true
        fi
    fi

    if [ "$existing_vault_dir_found" = true ] || [ "$existing_consul_dir_found" = true ]; then
        if [ "$FORCE_CLEANUP_ON_START" = true ]; then
            log_info "\nForce clean option activated. Cleaning up old lab data..."
            cleanup_previous_environment
        else
            log_warn "\nAn existing Vault/Consul lab environment was detected in '$VAULT_DIR' and/or '$CONSUL_DIR'."
            # Modifica qui: usa echo -e per stampare il prompt colorato, poi read
            echo -e "${YELLOW}Do you want to clean it up and start from scratch (Y/N, default: N)? ${NC}"
            read choice
            case "$choice" in
                y|Y )
                    cleanup_previous_environment
                    ;;
                * )
                    log_info "Skipping full data cleanup. Attempting to re-use existing data."
                    log_info "Note: Re-using will ensure services are running, initialized, and configurations reapplied."

                    # Ensure bin directory exists and binaries are downloaded/updated
                    mkdir -p "$BIN_DIR" || log_error "Failed to create $BIN_DIR."
                    download_latest_vault_binary "$BIN_DIR"
                    if [ "$BACKEND_TYPE" == "consul" ]; then # NEW
                        download_latest_consul_binary "$BIN_DIR" # NEW
                        configure_and_start_consul # NEW: Start Consul first for Vault to connect
                    fi

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
        log_info "\nNo existing Vault/Consul lab data found. Proceeding with a fresh setup. ✨"
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

    if [ "$BACKEND_TYPE" == "consul" ]; then # NEW
        echo -e "\n${YELLOW}CONSUL DETAILS:${NC}"
        echo -e "Consul URL: ${GREEN}$CONSUL_ADDR${NC}"
        echo -e "Consul UI: ${GREEN}$CONSUL_ADDR/ui${NC}"
        if [ -f "$CONSUL_DIR/acl_master_token.txt" ]; then
            echo -e "Consul ACL Master Token (for management): ${GREEN}$(cat "$CONSUL_DIR/acl_master_token.txt")${NC}"
            echo -e "Export for CLI: ${GREEN}export CONSUL_HTTP_TOKEN=\"$(cat "$CONSUL_DIR/acl_master_token.txt")\"${NC}"
            echo -e "Test connection: ${GREEN}$BIN_DIR/consul members${NC} (after exporting token)"
        fi
    fi

    echo -e "\n${RED}SECURITY WARNING:${NC}"
    echo -e "${RED}The Vault Root Token and Unseal Key are stored in plain text files in ${VAULT_DIR}.${NC}"
    echo -e "${RED}If using Consul backend, the Consul ACL Master Token is stored in ${CONSUL_DIR}.${NC}"
    echo -e "${RED}THIS IS ONLY FOR LAB/DEVELOPMENT PURPOSES AND IS HIGHLY INSECURE FOR PRODUCTION ENVIRONMENTS.${NC}"
    echo -e "${RED}In production, use secure methods for unsealing (e.g., Auto Unseal, Shamir's Secret Sharing) and manage root tokens/ACLs with extreme care.${NC}"


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

    echo -e "\n${YELLOW}To stop the server(s):${NC}"
    # Use the PID from the file for specific shutdown instruction
    local current_lab_vault_pid=""
    if [ -f "$LAB_VAULT_PID_FILE" ]; then
        current_lab_vault_pid=$(cat "$LAB_VAULT_PID_FILE")
    fi
    local current_lab_consul_pid="" # NEW
    if [ -f "$LAB_CONSUL_PID_FILE" ]; then # NEW
        current_lab_consul_pid=$(cat "$LAB_CONSUL_PID_FILE") # NEW
    fi


    if [ -n "$current_lab_vault_pid" ]; then
        echo -e "  ${GREEN}kill $current_lab_vault_pid${NC} (Vault PID from $LAB_VAULT_PID_FILE)"
    else
        log_warn "Vault PID file not found. Can't provide specific kill command for Vault. ⚠️"
    fi

    if [ -n "$current_lab_consul_pid" ]; then # NEW
        echo -e "  ${GREEN}kill $current_lab_consul_pid${NC} (Consul PID from $LAB_CONSUL_PID_FILE)" # NEW
    else # NEW
        log_warn "Consul PID file not found. Can't provide specific kill command for Consul. ⚠️" # NEW
    fi

    echo "Or to stop all running HashiCorp instances (less specific, use with caution):"
    echo -e "  ${GREEN}pkill -f \"vault server\"${NC}"
    echo -e "  ${GREEN}pkill -f \"consul agent\"${NC}" # NEW
    echo "  (Note: Killing by PID from the .pid file is safer as it targets only this lab's instance)."
    echo -e "  Alternatively, run: ${GREEN}$0 stop${NC} (if you implement a 'stop' command option)" # Suggest a future feature

    log_info "\nEnjoy your Vault!"
    log_info "Vault logs are available at: $VAULT_DIR/vault.log" # Emphasize log location
    if [ "$BACKEND_TYPE" == "consul" ]; then # NEW
        log_info "Consul logs are available at: $CONSUL_DIR/consul.log" # NEW
    fi
}


# --- Main Script Execution Logic ---
main() {
    # Determine if colors should be enabled by default (if stdout is a TTY)
    # This must happen before processing args, so --no-color can override it.
    if [ ! -t 1 ]; then # If stdout is NOT a TTY (e.g., redirected to a file or pipe)
        COLORS_ENABLED=false
    fi

    # Parse command-line arguments
    local arg
    while [[ $# -gt 0 ]]; do # Loop through all arguments
        arg="$1"
        case $arg in
            -h|--help)
                display_help
                ;;
            -c|--clean)
                FORCE_CLEANUP_ON_START=true
                shift
                ;;
            -v|--verbose)
                VERBOSE_OUTPUT=true
                shift
                ;;
            --no-color)
                COLORS_ENABLED=false
                shift
                ;;
            --backend)
                if [[ -n "$2" && ("$2" == "file" || "$2" == "consul") ]]; then
                    BACKEND_TYPE="$2"
                    BACKEND_TYPE_SET_VIA_ARG=true # Set flag to true
                    shift 2
                else
                    log_error "Error: --backend requires 'file' or 'consul' as an argument."
                fi
                ;;
            *)
                log_error "Unknown option '$arg'. Use -h or --help for usage."
                ;;
        esac
    done

    # Apply color disabling *after* parsing options and TTY check
    if [ "$COLORS_ENABLED" = false ]; then
        GREEN=''
        YELLOW=''
        RED=''
        NC=''
    fi

    # NEW: Interactive prompt for backend type if not set via argument
    if [ "$BACKEND_TYPE_SET_VIA_ARG" = false ]; then
        echo -e "\n${YELLOW}Choose Vault storage backend (file/consul, default: file): ${NC}"
        read -p "Type 'file' or 'consul': " user_backend_choice
        case "$user_backend_choice" in
            consul|CONSUL )
                BACKEND_TYPE="consul"
                ;;
            file|FILE|"" ) # Empty input defaults to file
                BACKEND_TYPE="file"
                ;;
            * )
                log_warn "Invalid backend choice '$user_backend_choice'. Defaulting to 'file'."
                BACKEND_TYPE="file"
                ;;
        esac
        log_info "Selected backend: $BACKEND_TYPE"
    fi

    # Step 1: Check and install necessary prerequisites (curl, jq, unzip, lsof).
    check_and_install_prerequisites

    # Step 2: Handle existing lab environment.
    handle_existing_lab

    # If we reach here, it means either:
    # a) No existing lab was found.
    # b) User chose to clean up an existing lab.
    # So, we proceed with a fresh setup or a re-initialization.

    # Step 3: Download or update the Vault binary.
    mkdir -p "$BIN_DIR" || log_error "Failed to create directory $BIN_DIR. Check permissions."
    download_latest_vault_binary "$BIN_DIR"
    log_info "=================================================="

    # If Consul backend is chosen, download and start Consul first
    if [ "$BACKEND_TYPE" == "consul" ]; then
        download_latest_consul_binary "$BIN_DIR"
        configure_and_start_consul
    fi

    # Step 4: Configure and start the Vault server.
    configure_and_start_vault

    # Step 5: Initialize and unseal Vault.
    initialize_and_unseal_vault

    # Step 6: Configure common Vault features.
    configure_vault_features

    # Step 7: Display final access information to the user.
    display_final_info
}

# Execute the main function
main "$@"