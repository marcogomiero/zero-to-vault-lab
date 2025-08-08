#!/bin/bash

# --- Global Configuration ---
# Default base directory for the OpenBao lab. Can be overridden by --base-dir option.
BASE_DIR="/mnt/c/Users/gomiero1/PycharmProjects/PythonProject/zero-to-vault-lab"
BIN_DIR="$BASE_DIR/bin" # Directory where OpenBao binaries will be stored
BAO_DIR="$BASE_DIR/bao-lab" # Working directory for OpenBao data, config, and keys
BAO_ADDR="https://127.0.0.1:8200" # Default OpenBao address for the lab environment (NOW HTTPS)
LAB_BAO_PID_FILE="$BAO_DIR/bao.pid" # File to store the PID of the running OpenBao server

# Path for the Audit Log (default for the lab is /dev/null for simplicity)
AUDIT_LOG_PATH="/dev/null"

# --- Global Flags ---
FORCE_CLEANUP_ON_START=false # Flag to force a clean setup, removing existing data
VERBOSE_OUTPUT=false # Flag to enable more detailed output for debugging
COLORS_ENABLED=true # Flag to control colored output. Default to true.
BACKEND_TYPE="file" # Only 'file' backend is supported in this version

# --- Colors for better output (initial setup) ---
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Logging Functions ---
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

# --- Function: Display Help Message ---
display_help() {
    echo "Usage: $0 [OPTIONS] [COMMAND]"
    echo ""
    echo "This script deploys an OpenBao lab environment using 'file' storage backend."
    echo "Options:"
    echo "  -c, --clean        Forces a clean setup (removes existing data)."
    echo "  -h, --help         Display this help message."
    echo "  -v, --verbose      Enable verbose output."
    echo "  --no-color         Disable colored output."
    echo "  -b, --base-directory <path>  Specify custom base directory."
    echo ""
    echo "Commands:"
    echo "  start              Setup and start OpenBao lab (default)."
    echo "  stop               Stop OpenBao server."
    echo "  restart            Restart OpenBao and unseal it without reconfiguring."
    echo "  reset              Fully reset the lab (cleanup + fresh start)."
    echo "  status             Show current OpenBao status."
    echo "  cleanup            Remove all lab data and stop any running instance."
    exit 0
}

# --- Restart Lab ---
restart_lab_environment() {
    log_info "\n=================================================="
    log_info "RESTARTING OPENBAO LAB ENVIRONMENT"
    log_info "=================================================="

    stop_lab_environment
    log_info "Waiting briefly before restarting..."
    sleep 3

    configure_and_start_bao
    initialize_and_unseal_bao

    log_info "OpenBao lab restarted and unsealed. 🔄"
}

# --- Reset Lab ---
reset_lab_environment() {
    log_info "\n=================================================="
    log_info "RESETTING OPENBAO LAB ENVIRONMENT"
    log_info "=================================================="

    cleanup_previous_environment
    mkdir -p "$BIN_DIR" || log_error "Failed to create $BIN_DIR."
    download_latest_bao_binary "$BIN_DIR"
    configure_and_start_bao
    initialize_and_unseal_bao
    configure_bao_features
    display_final_info
}

# --- Stop Lab ---
stop_lab_environment() {
    log_info "\n=================================================="
    log_info "STOPPING OPENBAO LAB"
    log_info "=================================================="
    stop_bao
    log_info "OpenBao lab environment stopped."
}

# --- Function: Check and Install Prerequisites ---
check_and_install_prerequisites() {
    log_info "=================================================="
    log_info "CHECKING PREREQUISITES"
    log_info "=================================================="

    local missing_pkgs=()
    local install_cmd=""
    local os_type=$(uname -s)

    declare -A pkg_map
    pkg_map["curl"]="curl"
    pkg_map["jq"]="jq"
    pkg_map["tar"]="tar"
    pkg_map["lsof"]="lsof"
    pkg_map["openssl"]="openssl" # Added openssl

    for cmd_name in "${!pkg_map[@]}"; do
        if ! command -v "${pkg_map[$cmd_name]}" &> /dev/null; then
            missing_pkgs+=("${pkg_map[$cmd_name]}")
        fi
    done

    if [ ${#missing_pkgs[@]} -eq 0 ]; then
        log_info "All necessary prerequisites (curl, jq, tar, lsof, openssl) are already installed. 👍"
        return 0
    fi

    log_warn "The following prerequisite packages are missing: ${missing_pkgs[*]}"

    case "$os_type" in
        Linux*)
            if command -v apt-get &> /dev/null; then
                install_cmd="sudo apt-get update && sudo apt-get install -y"
            elif command -v yum &> /dev/null; then
                install_cmd="sudo yum install -y"
            elif command -v dnf &> /dev/null; then
                install_cmd="sudo dnf install -y"
            elif command -v pacman &> /dev/null; then
                install_cmd="sudo pacman -Sy --noconfirm"
            fi
            ;;
        Darwin*)
            if command -v brew &> /dev/null; then
                install_cmd="brew install"
            else
                log_error "Homebrew is not installed. Please install Homebrew (https://brew.sh/) to proceed."
            fi
            ;;
        MINGW64_NT*)
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

# --- Function: Stop OpenBao process by PID file ---
stop_bao() {
    log_info "Attempting to stop OpenBao server..."
    if [ -f "$LAB_BAO_PID_FILE" ]; then
        local pid=$(cat "$LAB_BAO_PID_FILE")
        if ps -p "$pid" > /dev/null; then
            log_info "Found running OpenBao process with PID $pid. Attempting graceful shutdown..."
            kill "$pid" >/dev/null 2>&1
            sleep 5
            if ps -p "$pid" > /dev/null; then
                log_warn "OpenBao process (PID: $pid) did not shut down gracefully. Forcing kill..."
                kill -9 "$pid" >/dev/null 2>&1
                sleep 1
            fi
            if ! ps -p "$pid" > /dev/null; then
                log_info "OpenBao process (PID: $pid) stopped. ✅"
                rm -f "$LAB_BAO_PID_FILE"
            else
                log_error "OpenBao process (PID: $pid) could not be stopped. Manual intervention may be required. 🛑"
            fi
        else
            log_info "No active OpenBao process found with PID $pid (from $LAB_BAO_PID_FILE)."
            rm -f "$LAB_BAO_PID_FILE"
        fi
    else
        log_info "No OpenBao PID file found ($LAB_BAO_PID_FILE)."
    fi
    local bao_port=$(echo "$BAO_ADDR" | cut -d':' -f3)
    local lingering_pid=$(lsof -ti:"$bao_port" 2>/dev/null)
    if [ -n "$lingering_pid" ]; then
        log_warn "Found lingering process(es) on OpenBao port $bao_port (PIDs: $lingering_pid). Attempting to kill."
        kill -9 "$lingering_pid" >/dev/null 2>&1
        sleep 1
        if lsof -ti:"$bao_port" >/dev/null; then
             log_error "Could not clear port $bao_port. Manual intervention required. 🛑"
        else
            log_info "Lingering processes on port $bao_port cleared. ✅"
        fi
    fi
}

# --- Function: Download or update OpenBao binary ---
download_latest_bao_binary() {
    local bin_dir="$1"
    local platform="linux_amd64" # Default to this, but adjust if specific URL needs different string

    local os_type=$(uname -s)
    if [ "$os_type" == "Darwin" ]; then
        platform="darwin_amd64"
    elif [[ "$os_type" == *"MINGW"* ]]; then
        platform="windows_amd64"
    fi

    local bao_exe="$bin_dir/bao"
    if [[ "$platform" == *"windows"* ]]; then
        bao_exe="$bin_dir/bao.exe"
    fi

    local temp_dir=$(mktemp -d)
    local success=1

    log_info "=================================================="
    log_info "OPENBAO BINARY MANAGEMENT: CHECK AND DOWNLOAD"
    log_info "=================================================="

    # --- AGGIORNARE QUESTE VARIABILI PER OPENBAO ---
    local latest_version="2.3.1" # <<< ULTIMA VERSIONE DI OPENBAO FORNITA
    # Nota: la stringa della piattaforma nell'URL può variare. Per 'Linux_x86_64.tar.gz'
    # dobbiamo adattare 'platform_in_url' se diversa da 'platform'
    local platform_in_url="Linux_x86_64"
    if [ "$os_type" == "Darwin" ]; then
        platform_in_url="Darwin_x86_64" # Se ci fosse un pacchetto analogo per macOS
    elif [[ "$os_type" == *"MINGW"* ]]; then
        platform_in_url="Windows_x86_64" # Se ci fosse un pacchetto analogo per Windows
    fi

    log_info "NOTE: OpenBao's latest version is now set to 2.3.1. URL pattern updated."

    if [ -f "$bao_exe" ]; then
        local current_version
        current_version=$("$bao_exe" version -short 2>/dev/null | awk '{print $2}')
        current_version=${current_version#v}

        if [ "$current_version" == "$latest_version" ]; then
            log_info "Current OpenBao binary (v$current_version) is already the latest version available."
            log_info "No download or update needed. Existing binary will be used."
            rm -rf "$temp_dir"
            return 0
        else
            log_info "Current OpenBao binary is v$current_version. Latest available version is v$latest_version."
            log_info "Proceeding with update..."
        fi
    else
        log_info "No OpenBao binary found in $bin_dir. Proceeding with downloading the latest version."
    fi

    # --- AGGIORNARE L'URL DI DOWNLOAD PER IL FORMATO .tar.gz ---
    local download_url="https://github.com/openbao/openbao/releases/download/v${latest_version}/bao_${latest_version}_${platform_in_url}.tar.gz"

    local tar_gz_file="$temp_dir/bao.tar.gz" # Nuovo nome per il file scaricato

    log_info "Downloading OpenBao v$latest_version for $platform from $download_url..."
    if ! curl -fsSL -o "$tar_gz_file" "$download_url"; then
        log_error "Error: Failed to download OpenBao from $download_url. Check internet connection or URL. ❌"
        rm -rf "$temp_dir"
        return 1
    fi

    log_info "Extracting the binary from .tar.gz..."
    # Cambiato da unzip a tar -xzf
    if ! tar -xzf "$tar_gz_file" -C "$temp_dir" >/dev/null; then
        log_error "Error: Failed to extract the .tar.gz file. Ensure 'tar' is installed and functional. ❌"
        rm -rf "$temp_dir"
        return 1
    fi

    # Il binario estratto dal .tar.gz dovrebbe essere 'bao' direttamente nella root dell'archivio.
    if [ -f "$temp_dir/bao" ]; then
        log_info "Moving and configuring the new OpenBao binary to $bin_dir..."
        mkdir -p "$bin_dir"
        mv "$temp_dir/bao" "$bao_exe"
        chmod +x "$bao_exe"
        success=0
        log_info "OpenBao v$latest_version downloaded and configured successfully. 🎉"
    else
        log_error "Error: 'bao' binary not found in the extracted archive. Check archive content. ❌"
    fi

    rm -rf "$temp_dir"
    return $success
}


# --- Function: Wait for OpenBao to be UP and respond to APIs ---
wait_for_bao_up() {
  local addr=$1
  local timeout=30
  local elapsed=0

  log_info "Waiting for OpenBao to listen on $addr..."
  while [[ $elapsed -lt $timeout ]]; do
    # Use -k for curl to ignore self-signed certificate in lab environment
    if curl -s -k -o /dev/null -w "%{http_code}" "$addr/v1/sys/seal-status" | grep -q "200"; then
      log_info "OpenBao is listening and responding to APIs after $elapsed seconds. ✅"
      return 0
    fi
    sleep 1
    echo -n "."
    ((elapsed++))
  done
  log_error "OpenBao did not become reachable after $timeout seconds. Check logs ($BAO_DIR/bao.log). ❌"
  return 1
}


# --- Function: Clean up previous environment ---
cleanup_previous_environment() {
    log_info "=================================================="
    log_info "FULL CLEANUP OF PREVIOUS LAB ENVIRONMENT"
    log_info "=================================================="

    stop_bao

    log_info "Deleting previous working directory: $BAO_DIR..."
    rm -rf "$BAO_DIR"
    if [ $? -ne 0 ]; then
        log_error "Failed to remove '$BAO_DIR'. Check permissions. ❌"
    fi

    log_info "Recreating empty directory: $BAO_DIR..."
    mkdir -p "$BAO_DIR"
    if [ $? -ne 0 ]; then
        log_error "Failed to create '$BAO_DIR'. Check permissions. ❌"
    fi
    log_info "Cleanup completed. ✅"
}

# --- Function: Generate Self-Signed TLS Certificate and Key ---
generate_self_signed_tls() {
    log_info "\n=================================================="
    log_info "GENERATING SELF-SIGNED TLS CERTIFICATE FOR OPENBAO"
    log_info "=================================================="

    local tls_dir="$BAO_DIR/tls"
    mkdir -p "$tls_dir" || log_error "Failed to create TLS directory: $tls_dir. Check permissions."

    local key_path="$tls_dir/bao-key.pem"
    local cert_path="$tls_dir/bao-cert.pem"

    if [ -f "$key_path" ] && [ -f "$cert_path" ]; then
        log_info "TLS key and certificate already exist. Reusing existing. ✅"
        return 0
    fi

    log_info "Generating private key ($key_path)..."
    openssl genrsa -out "$key_path" 2048 2>/dev/null || log_error "Failed to generate private key. Ensure openssl is installed. ❌"
    chmod 600 "$key_path" # Restrict permissions

    log_info "Generating self-signed certificate ($cert_path) for localhost..."
    openssl req -new -x509 -key "$key_path" -out "$cert_path" -days 365 \
        -subj "/CN=127.0.0.1" \
        -addext "subjectAltName = IP:127.0.0.1" \
        -nodes 2>/dev/null || log_error "Failed to generate self-signed certificate. ❌"
    chmod 644 "$cert_path" # Allow read by others

    log_info "Self-signed TLS certificate and key generated successfully. 🎉"
}

# --- Function: Configure and start OpenBao ---
configure_and_start_bao() {
    log_info "\n=================================================="
    log_info "CONFIGURING LAB OPENBAO (SINGLE INSTANCE)"
    log_info "=================================================="

    local bao_port=$(echo "$BAO_ADDR" | cut -d':' -f3)

    stop_bao

    # Generate TLS assets before configuring HCL
    generate_self_signed_tls

    log_info "Configuring OpenBao HCL file: $BAO_DIR/config.hcl"

    # Only 'file' backend is supported in this version
    local BAO_STORAGE_CONFIG=$(cat <<EOF
storage "file" {
  path = "$BAO_DIR/storage"
}
EOF
)
    mkdir -p "$BAO_DIR/storage" || log_error "Failed to create OpenBao file storage directory."
    log_info "OpenBao will use 'file' storage backend."


    cat > "$BAO_DIR/config.hcl" <<EOF
$BAO_STORAGE_CONFIG

listener "tcp" {
  address     = "127.0.0.1:8200"
  tls_disable = 0 # Enable TLS
  tls_cert_file = "$BAO_DIR/tls/bao-cert.pem"
  tls_key_file  = "$BAO_DIR/tls/bao-key.pem"
}

api_addr = "https://127.0.0.1:8200" # Updated to HTTPS
cluster_addr = "https://127.0.0.1:8201" # Updated to HTTPS
ui = true
EOF

    log_info "Starting OpenBao server in background..."
    local bao_exe="$BIN_DIR/bao"
    if [[ "$(uname -s)" == *"MINGW"* ]]; then
        bao_exe="$BIN_DIR/bao.exe"
    fi

    touch "$BAO_DIR/bao.log"
    chmod 644 "$BAO_DIR/bao.log"

    "$bao_exe" server -config="$BAO_DIR/config.hcl" > "$BAO_DIR/bao.log" 2>&1 &
    local bao_pid=$!
    echo "$bao_pid" > "$LAB_BAO_PID_FILE"
    log_info "OpenBao server started. PID saved to $LAB_BAO_PID_FILE (PID: $bao_pid)"

    # Give it a moment to either start or crash immediately
    sleep 2

    if ! ps -p "$bao_pid" > /dev/null; then
        log_error "OpenBao server (PID: $bao_pid) crashed immediately after startup. Check $BAO_DIR/bao.log for details. ❌"
    fi

    if ! wait_for_bao_up "$BAO_ADDR"; then
        log_error "OpenBao server failed to start or respond after initial check. Check $BAO_DIR/bao.log ❌"
    fi
}

# --- Function: Get OpenBao Status (JSON output) ---
get_bao_status() {
    local bao_exe="$BIN_DIR/bao"
    if [[ "$(uname -s)" == *"MINGW"* ]]; then
        bao_exe="$BIN_DIR/bao.exe"
    fi
    # Flags for 'status' go after 'status'
    # Rely on BAO_ADDR and BAO_SKIP_VERIFY environment variables
    "$bao_exe" status -format=json
}

# --- Function: Wait for OpenBao to be UNSEALED and ready ---
wait_for_unseal_ready() {
  local addr=$1
  local timeout=30
  local elapsed=0

  log_info "Waiting for OpenBao to be fully unsealed and operational for APIs..."

  while [[ $elapsed -lt $timeout ]]; do
    local status_json=$(get_bao_status)
    if echo "$status_json" | jq -e '.initialized == true and .sealed == false' &>/dev/null; then
      log_info "OpenBao is unsealed and operational after $elapsed seconds. ✅"
      return 0
    fi
    sleep 1
    echo -n "."
    ((elapsed++))
  done
  log_error "OpenBao did not become operational (still sealed or not initialized) after $timeout seconds. Manual intervention may be required. ❌"
  return 1
}


# --- Function: Initialize and unseal OpenBao ---
initialize_and_unseal_bao() {
    log_info "\n=================================================="
    log_info "INITIALIZING AND UNSEALING OPENBAO"
    log_info "=================================================="

    export BAO_ADDR="$BAO_ADDR"
    # Set BAO_SKIP_VERIFY environment variable for all subsequent bao commands
    export BAO_SKIP_VERIFY="true"
    export BAO_TOKEN="" # Ensure this is set, even if empty, for consistency

    local bao_exe="$BIN_DIR/bao"
    if [[ "$(uname -s)" == *"MINGW"* ]]; then
        bao_exe="$BIN_DIR/bao.exe"
    fi

    sleep 2 # Give OpenBao a little more time after startup

    local current_status_json=$(get_bao_status)
    if [ -z "$current_status_json" ]; then
        log_error "Could not get OpenBao status. Is OpenBao server running and reachable? (No JSON output or error from 'bao status')"
    fi

    local is_initialized=$(echo "$current_status_json" | jq -r '.initialized')
    local is_sealed=$(echo "$current_status_json" | jq -r '.sealed')

    if [ "$is_initialized" == "true" ]; then
        log_info "OpenBao is already initialized. Skipping initialization. ✅"
    else
        log_info "Initializing OpenBao with 1 key share and 1 key threshold..."
        local INIT_OUTPUT
        # Rely on BAO_ADDR and BAO_SKIP_VERIFY environment variables
        INIT_OUTPUT=$("$bao_exe" operator init -key-shares=1 -key-threshold=1 -format=json)
        if [ $? -ne 0 ]; then
            log_error "OpenBao initialization failed. Please check $BAO_DIR/bao.log for details. ❌"
        fi

        local ROOT_TOKEN_BAO=$(echo "$INIT_OUTPUT" | jq -r '.root_token')
        local UNSEAL_KEY_BAO=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[0]')

        echo "$ROOT_TOKEN_BAO" > "$BAO_DIR/root_token.txt"
        echo "$UNSEAL_KEY_BAO" > "$BAO_DIR/unseal_key.txt"
        log_info "OpenBao initialized. Root Token and Unseal Key saved in $BAO_DIR. 🔑"
        log_warn "WARNING: Root Token and Unseal Key are saved in plain text files in $BAO_DIR."
        log_warn "         This is INSECURE for production environments and only suitable for lab use."


        current_status_json=$(get_bao_status)
        is_sealed=$(echo "$current_status_json" | jq -r '.sealed')
    fi

    if [ "$is_sealed" == "true" ]; then
        log_info "OpenBao is sealed. Attempting to unseal..."
        if [ -f "$BAO_DIR/unseal_key.txt" ]; then
            local UNSEAL_KEY_STORED=$(cat "$BAO_DIR/unseal_key.txt")
            if [ -z "$UNSEAL_KEY_STORED" ]; then
                log_error "Unseal key file ($BAO_DIR/unseal_key.txt) exists but is empty. Cannot unseal. ❌"
            fi
            # Rely on BAO_ADDR and BAO_SKIP_VERIFY environment variables
            "$bao_exe" operator unseal "$UNSEAL_KEY_STORED" >/dev/null
            if [ $? -ne 0 ]; then
                log_error "OpenBao unseal failed with stored key. Manual unseal may be required. ❌"
            fi
            log_info "OpenBao unsealed successfully using stored key. ✅"
        else
            log_error "OpenBao is sealed but no unseal_key.txt found in $BAO_DIR. Cannot unseal automatically. ⚠️"
            log_error "Please unseal OpenBao manually using 'bao operator unseal <KEY>'."
        fi
    else
        log_info "OpenBao is already unsealed. Skipping unseal. ✅"
    fi

    if ! wait_for_unseal_ready "$BAO_ADDR"; then
        log_error "OpenBao did not reach unsealed state after initialization/unseal attempts. Exiting. ❌"
    fi

    if [ -f "$BAO_DIR/root_token.txt" ]; then
        local initial_root_token=$(cat "$BAO_DIR/root_token.txt")
        if [ -n "$initial_root_token" ]; then
            export BAO_TOKEN="$initial_root_token"
        else
            log_warn "$BAO_DIR/root_token.txt is empty. Cannot set initial BAO_TOKEN. ⚠️"
        fi
    else
        log_warn "$BAO_DIR/root_token.txt not found. Cannot set initial BAO_TOKEN. ⚠️"
    fi

    log_info "Ensuring 'root' token with ID 'root' for lab use..."
    # Rely on BAO_ADDR and BAO_SKIP_VERIFY environment variables
    if "$bao_exe" token lookup "root" &>/dev/null; then
        log_info "Root token 'root' already exists. ✅"
        export BAO_TOKEN="root"
    else
        log_info "Creating 'root' token with ID 'root'..."
        local temp_bao_token="$BAO_TOKEN"
        export BAO_TOKEN="$initial_root_token"

        # Rely on BAO_ADDR and BAO_SKIP_VERIFY environment variables
        "$bao_exe" token create -id="root" -policy="root" -no-default-policy -display-name="laboratory-root" >/dev/null
        if [ $? -eq 0 ]; then
            log_info "Root token with ID 'root' created successfully. ✅"
            echo "root" > "$BAO_DIR/root_token.txt"
            export BAO_TOKEN="root"
        else
            log_warn "Failed to create 'root' token with ID 'root'. Falling back to initial generated token. ⚠️"
            export BAO_TOKEN="$temp_bao_token"
        fi
    fi
}


# --- Function: Configure AppRole Auth Method ---
configure_approle() {
    log_info "\nEnabling and configuring AppRole Auth Method..."

    local bao_exe="$BIN_DIR/bao"
    if [[ "$(uname -s)" == *"MINGW"* ]]; then
        bao_exe="$BIN_DIR/bao.exe"
    fi

    log_info " - Enabling Auth Method 'approle' at 'approle/'"
    # Rely on BAO_ADDR and BAO_SKIP_VERIFY environment variables
    "$bao_exe" auth enable approle &>/dev/null

    cat > "$BAO_DIR/approle-policy.hcl" <<EOF
path "secret/my-app/*" {
  capabilities = ["read", "list"]
}
path "secret/other-data" {
  capabilities = ["read"]
}
EOF

    log_info " - Creating 'my-app-policy' policy for AppRole..."
    # Rely on BAO_ADDR and BAO_SKIP_VERIFY environment variables
    "$bao_exe" policy write my-app-policy "$BAO_DIR/approle-policy.hcl" &>/dev/null

    log_info " - Creating AppRole 'web-application' role..."
    # Rely on BAO_ADDR and BAO_SKIP_VERIFY environment variables
    "$bao_exe" write auth/approle/role/web-application \
        token_policies="default,my-app-policy" \
        token_ttl="1h" \
        token_max_ttl="24h" &>/dev/null

    local ROLE_ID
    # Rely on BAO_ADDR and BAO_SKIP_VERIFY environment variables
    ROLE_ID=$("$bao_exe" read -field=role_id auth/approle/role/web-application/role-id)
    if [ -z "$ROLE_ID" ]; then
        log_warn "Could not retrieve AppRole Role ID. AppRole setup might have issues. ⚠️"
    else
        log_info "   Role ID for 'web-application': $ROLE_ID (saved in $BAO_DIR/approle_role_id.txt)"
        echo "$ROLE_ID" > "$BAO_DIR/approle_role_id.txt"
    fi

    local SECRET_ID
    # Rely on BAO_ADDR and BAO_SKIP_VERIFY environment variables
    SECRET_ID=$("$bao_exe" write -f -field=secret_id auth/approle/role/web-application/secret-id)
    if [ -z "$SECRET_ID" ]; then
        log_warn "Could not retrieve AppRole Secret ID. AppRole setup might have issues. ⚠️"
    else
        log_info "   Secret ID for 'web-application': $SECRET_ID (saved in $BAO_DIR/approle_secret_id.txt)"
        echo "$SECRET_ID" > "$BAO_DIR/approle_secret_id.txt"
    fi

    log_info "AppRole configuration completed for role 'web-application'."
}


# --- Function: Configure Audit Device (uses global variable AUDIT_LOG_PATH) ---
configure_audit_device() {
    log_info "\nEnabling and configuring an Audit Device..."
    local bao_exe="$BIN_DIR/bao"
    if [[ "$(uname -s)" == *"MINGW"* ]]; then
        bao_exe="$BIN_DIR/bao.exe"
    fi

    log_info " - Enabling file audit device at '$AUDIT_LOG_PATH'"
    # Rely on BAO_ADDR and BAO_SKIP_VERIFY environment variables
    local audit_status=$("$bao_exe" audit list -format=json 2>/dev/null | jq -r '.["file/"]' 2>/dev/null)
    if [ "$audit_status" == "null" ] || [ -z "$audit_status" ]; then
        # Rely on BAO_ADDR and BAO_SKIP_VERIFY environment variables
        "$bao_exe" audit enable file file_path="$AUDIT_LOG_PATH" &>/dev/null
        log_info "Audit Device configured. Logs will be written to $AUDIT_LOG_PATH"
    else
        log_info "Audit Device already enabled. Path: $AUDIT_LOG_PATH ✅"
    fi
}

# --- Function: Enable and configure secrets engines ---
enable_secrets_engines() {
    log_info "\nEnabling and configuring OpenBao secrets engines..."
    local bao_exe="$BIN_DIR/bao"
    if [[ "$(uname -s)" == *"MINGW"* ]]; then
        bao_exe="$BIN_DIR/bao.exe"
    fi

    log_info " - Enabling KV v2 secrets engine at 'secret/'"
    # Rely on BAO_ADDR and BAO_SKIP_VERIFY environment variables
    "$bao_exe" secrets enable -path=secret kv-v2 &>/dev/null

    log_info " - Enabling KV v2 secrets engine at 'kv/'"
    # Rely on BAO_ADDR and BAO_SKIP_VERIFY environment variables
    "$bao_exe" secrets enable -path=kv kv-v2 &>/dev/null

    log_info " - Enabling PKI secrets engine at 'pki/'"
    # Rely on BAO_ADDR and BAO_SKIP_VERIFY environment variables
    "$bao_exe" secrets enable pki &>/dev/null
    # Rely on BAO_ADDR and BAO_SKIP_VERIFY environment variables
    "$bao_exe" secrets tune -max-lease-ttl=87600h pki &>/dev/null
}

# --- Function: Configure OpenBao policies ---
configure_policies() {
    log_info "\nConfiguring OpenBao policies..."
    local bao_exe="$BIN_DIR/bao"
    if [[ "$(uname -s)" == *"MINGW"* ]]; then
        bao_exe="$BIN_DIR/bao.exe"
    fi

    log_info " - Creating 'dev-policy' for test users..."
    DEV_POLICY_PATH="$BAO_DIR/dev-policy.hcl"
    cat > "$DEV_POLICY_PATH" <<EOF
path "secret/data/test-secret" {
  capabilities = ["read", "list"]
}
path "kv/data/test-secret" {
  capabilities = ["read", "list"]
}
path "secret/metadata/*" {
  capabilities = ["list"]
}
path "kv/metadata/*" {
  capabilities = ["list"]
}
EOF
    # Rely on BAO_ADDR and BAO_SKIP_VERIFY environment variables
    "$bao_exe" policy write dev-policy "$DEV_POLICY_PATH" || log_error "Failed to write dev-policy."
}

# --- Function: Configure Userpass authentication method ---
configure_userpass_auth() {
    log_info "\nEnabling and configuring Userpass authentication..."
    local bao_exe="$BIN_DIR/bao"
    if [[ "$(uname -s)" == *"MINGW"* ]]; then
        bao_exe="$BIN_DIR/bao.exe"
    fi

    # Rely on BAO_ADDR and BAO_SKIP_VERIFY environment variables
    if ! "$bao_exe" auth list -format=json | jq -e '."userpass/" // empty' &>/dev/null; then
        log_info "Userpass authentication method not found, enabling it..."
        # Rely on BAO_ADDR and BAO_SKIP_VERIFY environment variables
        "$bao_exe" auth enable userpass || log_error "Failed to enable Userpass auth."
    else
        log_info "Userpass authentication method is already enabled. Skipping re-enable. ✅"
    fi

    log_info " - Creating example user 'devuser' with password 'devpass'"
    # Rely on BAO_ADDR and BAO_SKIP_VERIFY environment variables
    "$bao_exe" write auth/userpass/users/devuser password=devpass policies="default,dev-policy" &>/dev/null || \
    log_warn "User 'devuser' already exists or failed to create."
}

# --- Function: Populate test secrets ---
populate_test_secrets() {
    log_info "\n--- Populating test secrets ---"
    local bao_exe="$BIN_DIR/bao"
    if [[ "$(uname -s)" == *"MINGW"* ]]; then
        bao_exe="$BIN_DIR/bao.exe"
    fi

    log_info " - Writing test secret to secret/test-secret"
    # Rely on BAO_ADDR and BAO_SKIP_VERIFY environment variables
    "$bao_exe" kv put secret/test-secret message="Hello from OpenBao secret!" username="testuser" &>/dev/null

    log_info " - Writing test secret to kv/test-secret"
    # Rely on BAO_ADDR and BAO_SKIP_VERIFY environment variables
    "$bao_exe" kv put kv/test-secret message="Hello from OpenBao kv!" database="testdb" &>/dev/null
}

# --- Function: Enable and configure common features ---
configure_bao_features() {
    log_info "\n=================================================="
    log_info "CONFIGURING COMMON OPENBAO FEATURES"
    log_info "=================================================="

    # Set BAO_SKIP_VERIFY for all commands in this function
    export BAO_SKIP_VERIFY="true"

    enable_secrets_engines
    configure_policies
    configure_userpass_auth
    configure_approle
    configure_audit_device
    populate_test_secrets
}

# --- Function: Handle existing lab environment detection ---
handle_existing_lab() {
    local existing_bao_dir_found=false
    if [ -d "$BAO_DIR" ] && [ "$(ls -A "$BAO_DIR" 2>/dev/null)" ]; then
        existing_bao_dir_found=true
    fi

    if [ "$existing_bao_dir_found" = true ]; then
        if [ "$FORCE_CLEANUP_ON_START" = true ]; then
            log_info "\nForce clean option activated. Cleaning up old lab data..."
            cleanup_previous_environment
        else
            log_warn "\nAn existing OpenBao lab environment was detected in '$BAO_DIR'."
            echo -e "${YELLOW}Do you want to clean it up and start from scratch (Y/N, default: N)? ${NC}"
            read choice
            case "$choice" in
                y|Y )
                    cleanup_previous_environment
                    ;;
                * )
                    log_info "Skipping full data cleanup. Attempting to re-use existing data."
                    log_info "Note: Re-using will ensure services are running, initialized, and configurations reapplied."

                    mkdir -p "$BIN_DIR" || log_error "Failed to create $BIN_DIR."
                    download_latest_bao_binary "$BIN_DIR"

                    configure_and_start_bao
                    initialize_and_unseal_bao
                    configure_bao_features

                    log_info "\n=================================================="
                    log_info "OPENBAO LAB RE-USE COMPLETED."
                    log_info "=================================================="
                    display_final_info
                    exit 0
                    ;;
            esac
        fi
    else
        log_info "\nNo existing OpenBao lab data found. Proceeding with a fresh setup. ✨"
    fi
}

# --- Function: Stop the entire lab environment ---
stop_lab_environment() {
    log_info "\n=================================================="
    log_info "STOPPING OPENBAO LAB ENVIRONMENT"
    log_info "=================================================="
    stop_bao
    log_info "OpenBao lab environment stopped. 👋"
}

# --- Function: Restart the entire lab environment ---
restart_lab_environment() {
    log_info "\n=================================================="
    log_info "RESTARTING OPENBAO LAB ENVIRONMENT"
    log_info "=================================================="

    # Stop OpenBao
    stop_lab_environment
    log_info "Waiting a moment before restarting OpenBao..."
    sleep 3

    # Avvia direttamente Bao senza ripetere setup/config
    log_info "Restarting OpenBao using existing configuration..."
    local bao_exe="$BIN_DIR/bao"
    if [[ "$(uname -s)" == *"MINGW"* ]]; then bao_exe="$BIN_DIR/bao.exe"; fi

    "$bao_exe" server -config="$BAO_DIR/config.hcl" > "$BAO_DIR/bao.log" 2>&1 &
    echo $! > "$LAB_BAO_PID_FILE"

    wait_for_bao_up "$BAO_ADDR"

    # Unseal automatico
    initialize_and_unseal_bao

    log_info "OpenBao restarted and unsealed. 🔄"
}

# --- Function: Check and display lab status ---
check_lab_status() {
    log_info "\n=================================================="
    log_info "CHECKING OPENBAO LAB STATUS"
    log_info "=================================================="

    export BAO_ADDR="$BAO_ADDR"
    export BAO_SKIP_VERIFY="true"

    local bao_exe="$BIN_DIR/bao"
    if [[ "$(uname -s)" == *"MINGW"* ]]; then
        bao_exe="$BIN_DIR/bao.exe"
    fi

    if [ ! -f "$bao_exe" ]; then
        log_warn "OpenBao binary not found at $bao_exe. Cannot check status. ⚠️"
        return 1
    fi

    log_info "Attempting to get OpenBao server status..."
    local status_output=$("$bao_exe" status -format=json 2>/dev/null)
    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        log_info "OpenBao server is running. Details:"
        echo "$status_output" | jq .
        local initialized=$(echo "$status_output" | jq -r '.initialized')
        local sealed=$(echo "$status_output" | jq -r '.sealed')
        local active_node=$(echo "$status_output" | jq -r '.active_node')
        local cluster_name=$(echo "$status_output" | jq -r '.cluster_name')

        echo -e "\n${YELLOW}Summary:${NC}"
        echo -e "  Initialized: ${GREEN}$initialized${NC}"
        echo -e "  Sealed:      ${GREEN}$sealed${NC}"
        echo -e "  Active Node: ${GREEN}${active_node:-N/A}${NC}"
        echo -e "  Cluster:     ${GREEN}${cluster_name:-N/A}${NC}"

        if [ "$sealed" == "true" ]; then
            log_warn "OpenBao is SEALED. You need to unseal it to use it. 🔓"
        elif [ "$initialized" == "false" ]; then
            log_warn "OpenBao is NOT INITIALIZED. You need to initialize it. ⚙️"
        else
            log_info "OpenBao is UNSEALED and READY. 🎉"
        fi
    elif [ $exit_code -eq 2 ]; then
        log_warn "OpenBao server is SEALED or NOT INITIALIZED. Please run '$0 start' to initialize/unseal. 🔒"
    else
        log_warn "OpenBao server is NOT RUNNING or not reachable on $BAO_ADDR. 🔴"
        log_warn "Check if the process is running or if the port is open."
        if [ -f "$LAB_BAO_PID_FILE" ]; then
            local pid=$(cat "$LAB_BAO_PID_FILE")
            if ps -p "$pid" > /dev/null; then
                log_warn "A PID file exists ($LAB_BAO_PID_FILE) indicating PID $pid, but the server is not responding."
                log_warn "This might be a zombie process. Consider running '$0 stop' then '$0 cleanup'."
            else
                log_warn "PID file ($LAB_BAO_PID_FILE) exists but no process with that PID ($pid) is running."
                log_warn "The PID file might be stale. Consider running '$0 cleanup'."
            fi
        else
            log_warn "No PID file found. OpenBao might not have been started or crashed unexpectedly."
        fi
    fi
    log_info "=================================================="
}

# --- Function: Display final information ---
display_final_info() {
    log_info "\n=================================================="
    log_info "LAB OPENBAO IS READY TO USE!"
    log_info "=================================================="

    echo -e "\n${YELLOW}MAIN ACCESS DETAILS:${NC}"
    echo -e "URL: ${GREEN}$BAO_ADDR${NC}"
    echo -e "Root Token: ${GREEN}root${NC} (also saved in $BAO_DIR/root_token.txt)"
    echo -e "Example user: ${GREEN}devuser / devpass${NC} (with 'default' policy)"

    echo -e "\n${RED}SECURITY WARNING:${NC}"
    echo -e "${RED}The OpenBao Root Token and Unseal Key are stored in plain text files in ${BAO_DIR}.${NC}"
    echo -e "${RED}THIS IS ONLY FOR LAB/DEVELOPMENT PURPOSES AND IS HIGHLY INSECURE FOR PRODUCTION ENVIRONMENTS.${NC}"
    echo -e "${RED}In production, use secure methods for unsealing (e.g., Auto Unseal, Shamir's Secret Sharing) and manage root tokens/ACLs with extreme care.${NC}"
    echo -e "${RED}Also, you are using a self-signed TLS certificate. Your browser will show a warning.${NC}"
    echo -e "${RED}You may need to explicitly trust the certificate or bypass the warning.${NC}"


    echo -e "\n${YELLOW}DETAILED ACCESS POINTS:${NC}"
    echo -e "To interact with OpenBao via CLI, ensure these environment variables are set in your session:"
    echo -e "  export BAO_ADDR=$BAO_ADDR"
    echo -e "  export BAO_TOKEN=root"
    echo -e "  export BAO_SKIP_VERIFY=true"
    echo -e "Then you can use commands like:"
    echo -e "  ${GREEN}$BIN_DIR/bao kv get secret/test-secret${NC}"
    echo -e "  ${GREEN}$BIN_DIR/bao kv get kv/test-secret${NC}"


    echo -e "\n${YELLOW}APPROLE 'web-application' DETAILS:${NC}"
    if [ -f "$BAO_DIR/approle_role_id.txt" ]; then
        echo -e "Role ID: ${GREEN}$(cat "$BAO_DIR/approle_role_id.txt")${NC}"
    else
        log_warn "AppRole Role ID file not found. AppRole may not be fully configured. ⚠️"
    fi
    if [ -f "$BAO_DIR/approle_secret_id.txt" ]; then
        echo -e "Secret ID: ${GREEN}$(cat "$BAO_DIR/approle_secret_id.txt")${NC}"
    else
        log_warn "AppRole Secret ID file not found. AppRole may not be fully configured. ⚠️"
    fi

    echo -e "\n${YELLOW}Current OpenBao status (run '$0 status' for live check):${NC}"
    check_lab_status # Call the status function for immediate display

    echo -e "\n${YELLOW}To test AppRole authentication:${NC}"
    echo "export BAO_ADDR=$BAO_ADDR"
    echo "export BAO_SKIP_VERIFY=true"
    echo "bao write auth/approle/login role_id=\"$(cat "$BAO_DIR/approle_role_id.txt" 2>/dev/null)\" secret_id=\"$(cat "$BAO_DIR/approle_secret_id.txt" 2>/dev/null)\""
    echo "Note: The Secret ID is typically single-use for new creations. This command is for testing the login itself."

    echo -e "\n${YELLOW}To manage the lab environment:${NC}"
    echo -e "  Stop the server: ${GREEN}$0 stop${NC}"
    echo -e "  Restart the server: ${GREEN}$0 restart${NC}"
    echo -e "  Check status:    ${GREEN}$0 status${NC}"
    echo -e "  Clean up all data: ${GREEN}$0 cleanup${NC}"

    log_info "\nEnjoy your OpenBao!"
    log_info "OpenBao logs are available at: $BAO_DIR/bao.log"
}


# --- Main Script Execution Logic ---
main() {
    if [ ! -t 1 ]; then COLORS_ENABLED=false; fi

    local command="start"
    local temp_base_dir=""

    local i=1
    while [[ $i -le $# ]]; do
        local arg="${!i}"
        case "$arg" in
            -h|--help) display_help ;;
            -c|--clean) FORCE_CLEANUP_ON_START=true ;;
            -v|--verbose) VERBOSE_OUTPUT=true ;;
            --no-color) COLORS_ENABLED=false ;;
            -b|--base-directory) i=$((i+1)); temp_base_dir="${!i}" ;;
            start|stop|restart|reset|status|cleanup) command="$arg" ;;
            # non setto qui shell/with-bao, li intercettiamo subito dopo
        esac
        i=$((i+1))
    done

    if [ -n "$temp_base_dir" ]; then
        BASE_DIR="$temp_base_dir"
        BIN_DIR="$BASE_DIR/bin"
        BAO_DIR="$BASE_DIR/bao-lab"
        LAB_BAO_PID_FILE="$BAO_DIR/bao.pid"
    fi

    # ====== COMANDI SPECIALI: niente backend, niente setup ======
    if [[ "$1" == "shell" ]]; then
        export BAO_ADDR="https://127.0.0.1:8200"
        export BAO_SKIP_VERIFY="true"
        [ -f "$BAO_DIR/root_token.txt" ] && export BAO_TOKEN="$(cat "$BAO_DIR/root_token.txt")"
        # dedup BIN_DIR dal PATH
        PATH="$(echo "$PATH" | awk -v RS=: -v ORS=: -v drop="$BIN_DIR" '$0!=drop' | sed 's/:$//')"
        export PATH="$BIN_DIR:$PATH"
        echo "🔒 OpenBao lab shell attiva. Digita 'exit' per uscire."
        exec "${SHELL:-bash}" -i
        return 0
    fi

    if [[ "$1" == "with-bao" ]]; then
        shift
        (
          export BAO_ADDR="https://127.0.0.1:8200"
          export BAO_SKIP_VERIFY="true"
          [ -f "$BAO_DIR/root_token.txt" ] && export BAO_TOKEN="$(cat "$BAO_DIR/root_token.txt")"
          PATH="$(echo "$PATH" | awk -v RS=: -v ORS=: -v drop="$BIN_DIR" '$0!=drop' | sed 's/:$//')"
          export PATH="$BIN_DIR:$PATH"
          "$@"
        )
        return $?
    fi
    # ====== FINE COMANDI SPECIALI ======

    if [ "$COLORS_ENABLED" = false ]; then GREEN=''; YELLOW=''; RED=''; NC=''; fi

    case "$command" in
        start)
            check_and_install_prerequisites
            handle_existing_lab
            mkdir -p "$BIN_DIR" || log_error "Failed to create $BIN_DIR."
            download_latest_bao_binary "$BIN_DIR"
            configure_and_start_bao
            initialize_and_unseal_bao
            configure_bao_features
            display_final_info
            ;;
        stop) stop_lab_environment ;;
        restart) restart_lab_environment ;;
        reset) reset_lab_environment ;;
        status) check_lab_status ;;
        cleanup) cleanup_previous_environment ;;
        *) log_error "Invalid command '$command'. Use -h for help." ;;
    esac
}

main "$@"
