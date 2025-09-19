#!/bin/bash


# Consenti override da ambiente, default latest
VAULT_VERSION="${VAULT_VERSION:-latest}"
CONSUL_VERSION="${CONSUL_VERSION:-latest}"

SCRIPT_DIR="$(pwd)"
BASE_DIR="$SCRIPT_DIR"

BIN_DIR="$SCRIPT_DIR/bin"
VAULT_DIR="$SCRIPT_DIR/vault-data"
CONSUL_DIR="$SCRIPT_DIR/consul-data"
VAULT_ADDR="http://127.0.0.1:8200"
CONSUL_ADDR="http://127.0.0.1:8500"
LAB_VAULT_PID_FILE="$VAULT_DIR/vault.pid"
LAB_CONSUL_PID_FILE="$CONSUL_DIR/consul.pid"
LAB_CONFIG_FILE="$SCRIPT_DIR/vault-lab-ctl.conf"
AUDIT_LOG_PATH="/dev/null"

CLUSTER_MODE=""
ENABLE_TLS=false
TLS_ENABLED_FROM_ARG=false
FORCE_CLEANUP_ON_START=false
VERBOSE_OUTPUT=false
BACKEND_TYPE_SET_VIA_ARG=false
BACKEND_TYPE="file"

# --- Configuration ---
TLS_DIR="$SCRIPT_DIR/tls"
CA_DIR="$TLS_DIR/ca"
CERTS_DIR="$TLS_DIR/certs"
CA_KEY="$CA_DIR/ca-key.pem"
CA_CERT="$CA_DIR/ca-cert.pem"
CA_CONFIG="$CA_DIR/ca-config.json"
CA_CSR="$CA_DIR/ca-csr.json"

BACKUP_DIR="$SCRIPT_DIR/backups"
BACKUP_METADATA_FILE="backup_metadata.json"

is_windows() {
    case "$(uname -s)" in
      *MINGW*|*MSYS*|*CYGWIN*) return 0 ;;
      *) [ -n "$OS" ] && [ "$OS" = "Windows_NT" ] && return 0 || return 1 ;;
    esac
}

get_exe() {
    local name="$1"
    if is_windows; then
      echo "$BIN_DIR/${name}.exe"
    else
      echo "$BIN_DIR/${name}"
    fi
}

log() {
    local level=$1; shift
    local color=""
    case "$level" in
        DEBUG) [ "$VERBOSE_OUTPUT" = true ] || return 0; color=$GREEN ;;
        INFO)  color=$GREEN ;;
        WARN)  color=$YELLOW ;;
        ERROR) color=$RED ;;
    esac
    echo -e "${color}[${level}]${NC} $*" >&2
    [ "$level" = "ERROR" ] && exit 1
}

log_debug() { log DEBUG "$@"; }
log_info()  { log INFO  "$@"; }
log_warn()  { log WARN  "$@"; }
log_error() { log ERROR "$@"; }

# --- Error-handling helpers ---
safe_run() {
  local msg="$1"; shift
  if ! "$@"; then log ERROR "$msg (cmd: $*)"
  fi
}

warn_run() {
  local msg="$1"; shift
  if ! "$@"; then
    log WARN "$msg (cmd: $*)"
    return 1
  fi
}

# --- Validation Functions ---
validate_ports_available() {
    local vault_port=8200
    local consul_port=8500

    if lsof -Pi :$vault_port -sTCP:LISTEN -t >/dev/null ; then
        log ERROR "La porta $vault_port  gi in uso. Chiudi il processo o usa una porta diversa."
    fi

    if [ "$BACKEND_TYPE" == "consul" ] && lsof -Pi :$consul_port -sTCP:LISTEN -t >/dev/null ; then
        log ERROR "La porta $consul_port  gi in uso. Chiudi il processo o usa una porta diversa."
    fi
    log INFO "Port validation successful. "
}

validate_directories() {
    if [ ! -w "$SCRIPT_DIR" ]; then
        log ERROR "La directory base $SCRIPT_DIR non  scrivibile. Controlla i permessi."
    fi
    if [ ! -w "$(dirname "$BIN_DIR")" ]; then
        log ERROR "La directory padre di $BIN_DIR non  scrivibile. Controlla i permessi."
    fi
    log INFO "Directory validation successful. "
}

# --- Generic service stopper ---
stop_service() {
    local name="$1"
    local pid_file="$2"
    local process_pattern="$3"
    local port="$4"

    log INFO "Attempting to stop ${name} server..."
    pids=$(pgrep -f "$process_pattern" || true)
    if [ -n "$pids" ]; then
        log INFO "Trovati processi ${name} esistenti: $pids. Terminazione..."
        kill -TERM $pids 2>/dev/null || true; sleep 2; kill -9 $pids 2>/dev/null || true
    fi

    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if ps -p "$pid" >/dev/null; then
            log INFO "Stopping ${name} process with PID $pid..."
            kill "$pid" >/dev/null 2>&1; sleep 5
            if ps -p "$pid" >/dev/null; then
                log WARN "Forcing kill for ${name} (PID: $pid)..."
                kill -9 "$pid" >/dev/null 2>&1
            fi
            log INFO "${name} process stopped. "
        fi
        rm -f "$pid_file"
    fi

    if [ -n "$port" ]; then
        lingering_pid=$(lsof -ti:"$port" 2>/dev/null || true)
        if [ -n "$lingering_pid" ]; then
            log WARN "Processi residui sulla porta $port: $lingering_pid. Terminazione..."
            kill -9 "$lingering_pid" 2>/dev/null || true
        fi
    fi
}

# --- Network Helpers ---
get_host_accessible_ip() {
    # Default to localhost
    local ip="127.0.0.1"
    # If running in WSL, get the specific IP for the eth0 interface
    if grep -q "microsoft" /proc/version &>/dev/null; then
        wsl_ip=$(ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
        if [ -n "$wsl_ip" ]; then
            ip="$wsl_ip"
        fi
    fi
    echo "$ip"
}

wait_for_http_up() {
    local url=$1 timeout=${2:-30} name=${3:-Service}
    local elapsed=0
    log_info "Waiting for $name on $url (timeout ${timeout}s)"
    while (( elapsed < timeout )); do
        if curl -sk -o /dev/null -w "%{http_code}" "$url" | grep -q "200"; then
            log_info "$name reachable after ${elapsed}s"
            return 0
        fi
        sleep 1
        ((elapsed++))
    done
    log_error "$name not reachable on $url after $timeout seconds."
}

check_and_install_prerequisites() {
    log INFO "CHECKING PREREQUISITES"
    local missing_pkgs=()
    declare -A pkg_map
    pkg_map["curl"]="curl"; pkg_map["jq"]="jq"; pkg_map["unzip"]="unzip"; pkg_map["lsof"]="lsof"

    for cmd_name in "${!pkg_map[@]}"; do
        if ! command -v "${pkg_map[$cmd_name]}" &> /dev/null; then
            missing_pkgs+=("${pkg_map[$cmd_name]}")
        fi
    done

    if [ ${#missing_pkgs[@]} -eq 0 ]; then
        log INFO "All necessary prerequisites are already installed. "
        return 0
    fi

    log WARN "The following prerequisite packages are missing: ${missing_pkgs[*]}"
    local install_cmd=""
    case "$(uname -s)" in
        Linux*)
            if command -v apt-get &> /dev/null; then install_cmd="sudo apt-get update && sudo apt-get install -y"
            elif command -v yum &> /dev/null; then install_cmd="sudo yum install -y"
            elif command -v dnf &> /dev/null; then install_cmd="sudo dnf install -y"
            elif command -v pacman &> /dev/null; then install_cmd="sudo pacman -Sy --noconfirm"
            fi
            ;;
        Darwin*)
            if command -v brew &> /dev/null; then install_cmd="brew install"
            else log ERROR "Homebrew is not installed. Please install it to proceed."
            fi
            ;;
        *)
            log WARN "Unsupported OS. Please install missing packages manually: ${missing_pkgs[*]}"
            read -p "Do you want to proceed anyway? (y/N): " choice
            [[ "$choice" =~ ^[Yy]$ ]] || log ERROR "Exiting."
            return 0
            ;;
    esac

    read -p "Do you want to install them now? (y/N): " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        if ! eval "$install_cmd ${missing_pkgs[*]}"; then
            log ERROR "Failed to install prerequisites. Please install them manually."
        fi
    else
        log ERROR "Installation skipped. Exiting."
    fi
}

_download_hashicorp_binary() {
    local product="$1" bin_dir="$2"           # es: vault, consul
    local requested_version="${3:-latest}"    # terzo arg facoltativo
    local platform="linux_amd64"

    case "$(uname -s)" in
        Darwin*)  platform="darwin_amd64" ;;
        *MINGW*)  platform="windows_amd64" ;;
    esac

    local product_exe
    product_exe=$(get_exe "$product")
    local temp_dir
    temp_dir=$(mktemp -d) || log ERROR "Cannot create temp dir"
    trap 'rm -rf "$temp_dir"' EXIT INT TERM

    log INFO "${product^^} binary management: check and download"

    # Determine target version if 'latest'
    local target_version="$requested_version"
    if [ "$requested_version" = "latest" ]; then
        local releases_json
        releases_json=$(curl -s "https://releases.hashicorp.com/${product}/index.json") \
            || log ERROR "Failed to fetch ${product} releases. Check internet connection."

        target_version=$(echo "$releases_json" \
            | jq -r '.versions | keys[]' \
            | grep -Ev 'ent|rc|beta|preview' \
            | sort -V | tail -n 1)

        [ -z "$target_version" ] && log ERROR "Could not determine the latest ${product} version."
        log INFO "Latest available ${product} version: $target_version"
    else
        log INFO "Requested ${product} version: $target_version"
    fi

    # --- NEW: check system-wide binary first ---
    if command -v "$product" >/dev/null 2>&1; then
        local sys_version
        sys_version=$("$product" --version | awk 'NR==1{print $2}' | sed 's/^v//')
        if [ "$sys_version" = "$target_version" ]; then
            log INFO "System-wide ${product} (v$sys_version) is up to date. Skipping download."
            trap - EXIT INT TERM; rm -rf "$temp_dir"
            return 0
        fi
    fi

    # If bin_dir binary exists and is correct, skip download
    if [ -x "$product_exe" ]; then
        local current_version
        current_version=$("$product_exe" --version | head -n1 | awk '{print $2}' | sed 's/^v//')
        if [ "$current_version" = "$target_version" ]; then
            log INFO "Current local ${product} binary (v$current_version) is up to date."
            trap - EXIT INT TERM; rm -rf "$temp_dir"
            return 0
        fi
        log INFO "Updating ${product} from v$current_version to v$target_version..."
    fi

    # Download and install if needed
    local url="https://releases.hashicorp.com/${product}/${target_version}/${product}_${target_version}_${platform}.zip"
    log INFO "Downloading ${product} v$target_version from $url"
    curl -fsSL -o "$temp_dir/${product}.zip" "$url" || log ERROR "Download failed."

    unzip -o "$temp_dir/${product}.zip" -d "$bin_dir" >/dev/null || log ERROR "Extraction failed."
    chmod +x "$product_exe"

    log INFO "${product^} v$target_version downloaded and configured successfully."
    trap - EXIT INT TERM; rm -rf "$temp_dir"
}

download_latest_vault_binary() {
    _download_hashicorp_binary "vault" "$BIN_DIR" "${VAULT_VERSION:-latest}"
}

download_latest_consul_binary() {
    _download_hashicorp_binary "consul" "$BIN_DIR" "${CONSUL_VERSION:-latest}"
}

get_consul_exe() { get_exe "consul"; }

wait_for_consul_up() {
    wait_for_http_up "$1/v1/status/leader" "${2:-30}" "Consul"
}

stop_consul() {
  local consul_port=$(echo "$CONSUL_ADDR" | cut -d':' -f3)
  stop_service "Consul" "$LAB_CONSUL_PID_FILE" "consul agent" "$consul_port"
}

get_consul_status() {
    local consul_exe=$(get_consul_exe)
    CONSUL_ADDR="$CONSUL_ADDR" ${CONSUL_CACERT:+CONSUL_CACERT="$CONSUL_CACERT"} "$consul_exe" members -format=json 2>/dev/null
}

configure_and_start_consul() {
    log INFO "CONFIGURING AND STARTING CONSUL (SINGLE NODE SERVER)"
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

    log INFO "Starting Consul server in background..."
    local consul_exe=$(get_consul_exe)
    "$consul_exe" agent -config-dir="$CONSUL_DIR" > "$CONSUL_DIR/consul.log" 2>&1 &
    echo $! > "$LAB_CONSUL_PID_FILE"
    log INFO "Consul PID saved to $LAB_CONSUL_PID_FILE"

    wait_for_consul_up "$CONSUL_ADDR"
    sleep 5 # Wait for stabilization

    log INFO "Bootstrapping Consul ACL Master Token..."
    local token_file="$CONSUL_DIR/acl_master_token.txt"
    if [ -f "$token_file" ]; then
        log INFO "Re-using existing Consul ACL Master Token."
        export CONSUL_HTTP_TOKEN=$(cat "$token_file")
    else
        local bootstrap_output
        bootstrap_output=$("$consul_exe" acl bootstrap -format=json)
        local root_token=$(echo "$bootstrap_output" | jq -r '.SecretID')
        if [ -z "$root_token" ] || [ "$root_token" == "null" ]; then
            log ERROR "Failed to extract Consul ACL Master Token."
        fi
        echo "$root_token" > "$token_file"
        log INFO "Consul ACL Master Token saved to $token_file."
        export CONSUL_HTTP_TOKEN="$root_token"
    fi
}

start_consul_with_tls()        { start_consul_tls; }

start_consul_with_tls_no_acl() { start_consul_tls --no-acl; }

get_vault_exe() { get_exe "vault"; }

wait_for_vault_up() {
    wait_for_http_up "$1/v1/sys/seal-status" "${2:-30}" "Vault"
}

wait_for_unseal_ready() {
  local addr=$1; local timeout=30; local elapsed=0
  log INFO "Waiting for Vault to be fully unsealed..."
  while [[ $elapsed -lt $timeout ]]; do
    local status_json=$(get_vault_status)
    if echo "$status_json" | jq -e '.initialized == true and .sealed == false' &>/dev/null; then
      log INFO "Vault is unsealed and operational."; return 0
    fi
    sleep 1; echo -n "."; ((elapsed++))
  done
  log ERROR "\nVault did not become operational after $timeout seconds."
}

wait_for_vault_ready() {
    local max_attempts=15
    local attempt=1

    log INFO "Waiting for Vault to be fully ready..."

    while [ $attempt -le $max_attempts ]; do
        # Prova una chiamata API semplice invece del status JSON
        if [ "$ENABLE_TLS" = true ]; then
            local response=$(curl -s -w "%{http_code}" -o /dev/null --cacert "$CA_CERT" -H "X-Vault-Token: $(cat "$VAULT_DIR/root_token.txt")" "$VAULT_ADDR/v1/sys/health" 2>/dev/null || echo "000")
        else
            local response=$(curl -s -w "%{http_code}" -o /dev/null -H "X-Vault-Token: $(cat "$VAULT_DIR/root_token.txt")" "$VAULT_ADDR/v1/sys/health" 2>/dev/null || echo "000")
        fi

        # Vault health check restituisce 200 se unsealed e ready
        if [ "$response" = "200" ]; then
            log INFO "Vault is ready after $attempt attempts."
            return 0
        fi

        log DEBUG "Attempt $attempt: HTTP response code: $response"
        sleep 3
        ((attempt++))
    done

    log WARN "Vault readiness check timed out after $max_attempts attempts, proceeding anyway..."
    return 0  # Non blocchiamo il processo, procediamo comunque
}

stop_vault() {
    # --- CLUSTER ---
    if [ -f "$VAULT_DIR/vault_pids" ]; then
        while read -r pid; do
            kill "$pid" 2>/dev/null || true
        done < "$VAULT_DIR/vault_pids"
        rm -f "$VAULT_DIR/vault_pids"
        log INFO "All Vault nodes stopped."
        return
    fi
    local vault_port=$(echo "$VAULT_ADDR" | cut -d':' -f3)
    stop_service "Vault" "$LAB_VAULT_PID_FILE" "vault server" "$vault_port"
}

get_vault_status() {
    local vault_exe=$(get_vault_exe)
    # Assicurati che le variabili ambiente siano impostate correttamente
    if [ "$ENABLE_TLS" = true ]; then
        VAULT_ADDR="$VAULT_ADDR" VAULT_CACERT="$CA_CERT" "$vault_exe" status -format=json 2>/dev/null
    else
        VAULT_ADDR="$VAULT_ADDR" "$vault_exe" status -format=json 2>/dev/null
    fi
}

configure_and_start_vault() {
    log INFO "CONFIGURING AND STARTING VAULT"
    stop_vault

    local storage_config=""
    if [ "$BACKEND_TYPE" == "file" ]; then
        storage_config="storage \"file\" { path = \"$VAULT_DIR/storage\" }"
    elif [ "$BACKEND_TYPE" == "consul" ]; then
        local consul_token=$(cat "$CONSUL_DIR/acl_master_token.txt")
        storage_config="storage \"consul\" { address = \"$CONSUL_ADDR\" path = \"vault/\" token = \"$consul_token\" }"
    fi

    cat > "$VAULT_DIR/config.hcl" <<EOF
$storage_config
listener "tcp" {
  address     = "127.0.0.1:8200"
  tls_disable = 1
}
api_addr = "$VAULT_ADDR"
cluster_addr = "http://127.0.0.1:8201"
ui = true
EOF

    log INFO "Starting Vault server in background..."
    local vault_exe=$(get_vault_exe)
    "$vault_exe" server -config="$VAULT_DIR/config.hcl" > "$VAULT_DIR/vault.log" 2>&1 &
    echo $! > "$LAB_VAULT_PID_FILE"
    log INFO "Vault PID saved to $LAB_VAULT_PID_FILE"
    wait_for_vault_up "$VAULT_ADDR"
}

start_vault_with_tls() {
    log INFO "Starting Vault server with TLS in background..."
    local vault_exe=$(get_vault_exe)

    # Imposta le variabili ambiente per TLS
    export VAULT_CACERT="$CA_CERT"

    "$vault_exe" server -config="$VAULT_DIR/config.hcl" > "$VAULT_DIR/vault.log" 2>&1 &
    echo $! > "$LAB_VAULT_PID_FILE"
    log INFO "Vault PID saved to $LAB_VAULT_PID_FILE"
    wait_for_vault_up "$VAULT_ADDR"
}

# --- CLUSTER ---
start_vault_nodes() {
    log INFO "CONFIGURING AND STARTING 3-NODE VAULT CLUSTER (Consul backend)"
    stop_vault
    local consul_token=$(cat "$CONSUL_DIR/acl_master_token.txt")
    rm -f "$VAULT_DIR/vault_pids"
    for i in 1 2 3; do
        local port=$((8200 + i - 1))
        local cluster_port=$((8300 + i - 1))
        local node_dir="$VAULT_DIR/node_$i"
        mkdir -p "$node_dir"
        cat > "$node_dir/config.hcl" <<EOF
storage "consul" { address = "$CONSUL_ADDR" path = "vault/" token = "$consul_token" }
listener "tcp" { address = "127.0.0.1:$port" tls_disable = 1 }
api_addr = "http://127.0.0.1:$port"
cluster_addr = "http://127.0.0.1:$cluster_port"
ui = true
EOF
        local vault_exe=$(get_vault_exe)
        "$vault_exe" server -config="$node_dir/config.hcl" > "$node_dir/vault.log" 2>&1 &
        echo $! >> "$VAULT_DIR/vault_pids"
        log INFO "Vault node $i started on port $port"
        wait_for_vault_up "http://127.0.0.1:$port"
    done
}

start_vault_nodes_with_tls() {
    log INFO "CONFIGURING AND STARTING 3-NODE VAULT CLUSTER WITH TLS (Consul backend)"
    stop_vault
    local consul_token=$(cat "$CONSUL_DIR/acl_master_token.txt")
    rm -f "$VAULT_DIR/vault_pids"

    for i in 1 2 3; do
        local port=$((8200 + i - 1))
        local cluster_port=$((8300 + i - 1))
        local node_dir="$VAULT_DIR/node_$i"
        mkdir -p "$node_dir"

        # Genera certificato per questo nodo
        generate_vault_certificate "vault-node$i" "127.0.0.1"

        cat > "$node_dir/config.hcl" <<EOF
storage "consul" {
    address = "127.0.0.1:8500"
    path = "vault/"
    token = "$consul_token"
    scheme = "https"
    tls_ca_file = "$CA_CERT"
}
listener "tcp" {
    address = "127.0.0.1:$port"
    tls_cert_file = "$CERTS_DIR/vault-node$i.pem"
    tls_key_file = "$CERTS_DIR/vault-node$i-key.pem"
    tls_ca_file = "$CA_CERT"
}
api_addr = "https://127.0.0.1:$port"
cluster_addr = "https://127.0.0.1:$cluster_port"
ui = true
EOF

        local vault_exe=$(get_vault_exe)
        VAULT_CACERT="$CA_CERT" "$vault_exe" server -config="$node_dir/config.hcl" > "$node_dir/vault.log" 2>&1 &
        echo $! >> "$VAULT_DIR/vault_pids"
        log INFO "Vault node $i started on port $port with TLS"

        # Wait for this node to start
        export VAULT_CACERT="$CA_CERT"
        wait_for_vault_up "https://127.0.0.1:$port"
    done

    # Aggiorna VAULT_ADDR per il primo nodo
    VAULT_ADDR="https://127.0.0.1:8200"
    export VAULT_CACERT="$CA_CERT"
    export VAULT_ADDR="$VAULT_ADDR"
}

initialize_and_unseal_vault() {
    log INFO "INITIALIZING AND UNSEALING VAULT"

    # Imposta le variabili ambiente per TLS se abilitato
    if [ "$ENABLE_TLS" = true ]; then
        export VAULT_CACERT="$CA_CERT"
    fi
    export VAULT_ADDR="$VAULT_ADDR"

    local vault_exe=$(get_vault_exe)
    local status_json=$(get_vault_status)

    if [ "$(echo "$status_json" | jq -r '.initialized')" == "true" ]; then
        log INFO "Vault is already initialized."
    else
        log INFO "Initializing Vault..."
        local init_output=$("$vault_exe" operator init -key-shares=1 -key-threshold=1 -format=json)
        local root_token=$(echo "$init_output" | jq -r '.root_token')
        local unseal_key=$(echo "$init_output" | jq -r '.unseal_keys_b64[0]')
        echo "$root_token" > "$VAULT_DIR/root_token.txt"
        echo "$unseal_key" > "$VAULT_DIR/unseal_key.txt"
        log INFO "Vault initialized. Root Token and Unseal Key saved."
        log WARN "INSECURE: Credentials are saved in plain text in $VAULT_DIR."
    fi

    # Ricontrolla lo status dopo l'inizializzazione
    status_json=$(get_vault_status)
    if [ "$(echo "$status_json" | jq -r '.sealed')" == "true" ]; then
        log INFO "Vault is sealed. Unsealing..."
        local unseal_key=$(cat "$VAULT_DIR/unseal_key.txt")

        if [ "$CLUSTER_MODE" = "multi" ]; then
            for port in 8200 8201 8202; do
                local node_addr="$(echo "$VAULT_ADDR" | sed 's/8200/'$port'/')"
                if [ "$ENABLE_TLS" = true ]; then
                    VAULT_ADDR="$node_addr" VAULT_CACERT="$CA_CERT" "$vault_exe" operator unseal "$unseal_key" >/dev/null
                else
                    VAULT_ADDR="$node_addr" "$vault_exe" operator unseal "$unseal_key" >/dev/null
                fi
                log INFO "Node on port $port unsealed."
            done
        else
            "$vault_exe" operator unseal "$unseal_key" >/dev/null
            log INFO "Vault unsealed successfully."
        fi

        # Aspetta un momento per stabilizzazione
        sleep 5

        # Verifica di nuovo lo status
        status_json=$(get_vault_status)
        if [ "$(echo "$status_json" | jq -r '.sealed')" == "true" ]; then
            log ERROR "Vault is still sealed after unseal operation. Check logs."
        fi
    else
        log INFO "Vault is already unsealed."
    fi

    wait_for_unseal_ready "$VAULT_ADDR"
    export VAULT_TOKEN=$(cat "$VAULT_DIR/root_token.txt")

    # Attendi che Vault sia completamente pronto
    wait_for_vault_ready

    # Debug: mostra status finale
    local final_status=$(get_vault_status)
    log DEBUG "Final Vault status: sealed=$(echo "$final_status" | jq -r '.sealed'), initialized=$(echo "$final_status" | jq -r '.initialized')"
}

configure_vault_features() {
    log INFO "CONFIGURING COMMON VAULT FEATURES"

    # Verifica che Vault sia unsealed prima di procedere
    local status_json=$(get_vault_status)
    if [ "$(echo "$status_json" | jq -r '.sealed')" == "true" ]; then
        log ERROR "Cannot configure Vault features: Vault is sealed!"
        return 1
    fi

    # Assicurati che le variabili ambiente siano impostate
    if [ "$ENABLE_TLS" = true ]; then
        export VAULT_CACERT="$CA_CERT"
    fi
    export VAULT_ADDR="$VAULT_ADDR"
    export VAULT_TOKEN=$(cat "$VAULT_DIR/root_token.txt")

    local vault_exe=$(get_vault_exe)

    # --- KV v2 ---
    log INFO " - Enabling KV v2 secrets engine at 'secret/'"
    "$vault_exe" secrets enable -path=secret kv-v2 &>/dev/null || log WARN "Failed to enable KV v2 engine"

    # --- PKI ---
    log INFO " - Enabling PKI secrets engine at 'pki/'"
    "$vault_exe" secrets enable pki &>/dev/null || log WARN "Failed to enable PKI engine"
    "$vault_exe" secrets tune -max-lease-ttl=87600h pki &>/dev/null || log WARN "Failed to tune PKI engine"

    # --- Policies and Auth ---
    log INFO " - Creating 'dev-policy' for test users..."
    echo 'path "secret/*" {
      capabilities = ["list"]
    }
    path "secret/data/*" {
      capabilities = ["create","read","update","delete","list","patch","sudo"]
    }
    path "secret/metadata/*" {
      capabilities = ["create","read","update","delete","list","patch","sudo"]
    }' | "$vault_exe" policy write dev-policy - || log WARN "Failed to create dev-policy"

    log INFO " - Enabling Userpass authentication..."
    "$vault_exe" auth enable userpass &>/dev/null || log WARN "Failed to enable userpass auth"
    "$vault_exe" write auth/userpass/users/devuser password=devpass policies="default,dev-policy" &>/dev/null || log WARN "Failed to create devuser"

    log INFO " - Enabling and configuring AppRole Auth Method..."
    "$vault_exe" auth enable approle &>/dev/null || log WARN "Failed to enable approle auth"
    echo 'path "secret/*" {
      capabilities = ["list"]
    }
    path "secret/data/my-app/*" {
      capabilities = ["create","read","update","delete","list","patch","sudo"]
    }
    path "secret/metadata/my-app/*" {
      capabilities = ["create","read","update","delete","list","patch","sudo"]
    }' | "$vault_exe" policy write my-app-policy - || log WARN "Failed to create my-app-policy"

    "$vault_exe" write auth/approle/role/web-application token_policies="default,my-app-policy" || log WARN "Failed to create approle role"
    local role_id=$("$vault_exe" read -field=role_id auth/approle/role/web-application/role-id 2>/dev/null || echo "")
    local secret_id=$("$vault_exe" write -f -field=secret_id auth/approle/role/web-application/secret-id 2>/dev/null || echo "")

    if [ -n "$role_id" ]; then
        echo "$role_id" > "$VAULT_DIR/approle_role_id.txt"
    fi
    if [ -n "$secret_id" ]; then
        echo "$secret_id" > "$VAULT_DIR/approle_secret_id.txt"
    fi

    log INFO " - Enabling file audit device to $AUDIT_LOG_PATH"
    "$vault_exe" audit enable file file_path="$AUDIT_LOG_PATH" &>/dev/null || log WARN "Failed to enable audit device"

    log INFO " - Writing test secret to secret/test-secret"
    "$vault_exe" kv put secret/test-secret message="Hello from Vault!" username="testuser" &>/dev/null || log WARN "Failed to write test secret"

    # ------------------------------------------------------------------
    # --- NEW DEMO ENGINES ---------------------------------------------
    # ------------------------------------------------------------------

    # --- Transit engine demo ---
    log INFO " - Enabling Transit secrets engine for encryption-as-a-service"
    "$vault_exe" secrets enable transit &>/dev/null || log WARN "Failed to enable transit engine"
    "$vault_exe" write -f transit/keys/lab-key &>/dev/null || log WARN "Failed to create transit key"
    log INFO "   Transit key 'lab-key' ready. Example: vault write transit/encrypt/lab-key plaintext=$(base64 <<< 'hello')"

    # --- Database secrets engine (mock/demo only) ---
    log INFO " - Enabling Database secrets engine (no backend configured)"
    "$vault_exe" secrets enable database &>/dev/null \
    || log WARN "Could not enable database engine"
    log INFO "   Database engine configured"
}

# --- TLS Management Functions ---

check_tls_prerequisites() {
    # Usa OpenSSL che  universalmente disponibile
    if ! command -v openssl &> /dev/null; then
        log ERROR "OpenSSL is required but not found. Please install OpenSSL."
    fi
    log INFO "TLS prerequisites satisfied (OpenSSL available)."
}

generate_ca_certificate() {
    log INFO "Generating Certificate Authority (CA) with OpenSSL..."
    mkdir -p "$CA_DIR"

    # Genera CA se non esiste
    if [ ! -f "$CA_CERT" ] || [ ! -f "$CA_KEY" ]; then
        log INFO "Creating CA private key..."
        openssl genrsa -out "$CA_KEY" 2048 || log ERROR "Failed to generate CA private key"

        log INFO "Creating CA certificate..."
        openssl req -new -x509 -key "$CA_KEY" -sha256 -days 3650 -out "$CA_CERT" \
            -subj "/C=IT/ST=Virtual/L=Lab/O=Vault Lab/CN=Vault Lab CA" \
            || log ERROR "Failed to generate CA certificate"

        log INFO "CA certificate generated: $CA_CERT"
    else
        log INFO "CA certificate already exists, reusing."
    fi

    # Verifica che i file CA esistano
    if [ ! -f "$CA_CERT" ] || [ ! -f "$CA_KEY" ]; then
        log ERROR "CA certificate or key missing after generation"
    fi
}

generate_vault_certificate() {
    local node_name="${1:-vault-server}"
    local node_ip="${2:-127.0.0.1}"
    local additional_sans="${3:-}"

    log INFO "Generating TLS certificate for Vault node: $node_name"
    mkdir -p "$CERTS_DIR"

    local cert_file="$CERTS_DIR/${node_name}.pem"
    local key_file="$CERTS_DIR/${node_name}-key.pem"
    local csr_file="$CERTS_DIR/${node_name}.csr"

    if [ ! -f "$cert_file" ] || [ ! -f "$key_file" ]; then
        # Genera chiave privata
        openssl genrsa -out "$key_file" 2048 || log ERROR "Failed to generate private key for $node_name"

        # Crea CSR
        openssl req -new -key "$key_file" -out "$csr_file" \
            -subj "/C=IT/ST=Virtual/L=Lab/O=Vault Lab/CN=$node_name" \
            || log ERROR "Failed to generate CSR for $node_name"

        # Crea config per Subject Alternative Names
        local san_config="$CERTS_DIR/${node_name}.conf"
        cat > "$san_config" <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req

[req_distinguished_name]

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = $node_name
IP.1 = 127.0.0.1
IP.2 = $node_ip
EOF

        # Aggiungi SAN aggiuntivi se specificati
        if [ -n "$additional_sans" ]; then
            echo "# Additional SANs" >> "$san_config"
            echo "$additional_sans" >> "$san_config"
        fi

        # Genera certificato firmato dalla CA
        openssl x509 -req -in "$csr_file" -CA "$CA_CERT" -CAkey "$CA_KEY" \
            -CAcreateserial -out "$cert_file" -days 365 \
            -extensions v3_req -extfile "$san_config" \
            || log ERROR "Failed to generate certificate for $node_name"

        # Cleanup
        rm -f "$csr_file" "$san_config"

        log INFO "Vault certificate generated: $cert_file"
    else
        log INFO "Vault certificate already exists for $node_name, reusing."
    fi

    # Restituisci i percorsi dei file
    echo "CERT_FILE=$cert_file"
    echo "KEY_FILE=$key_file"
}

generate_consul_certificate() {
    local node_name="${1:-consul-server}"
    local node_ip="${2:-127.0.0.1}"

    log INFO "Generating TLS certificate for Consul node: $node_name"
    mkdir -p "$CERTS_DIR"

    local cert_file="$CERTS_DIR/${node_name}.pem"
    local key_file="$CERTS_DIR/${node_name}-key.pem"
    local csr_file="$CERTS_DIR/${node_name}.csr"

    if [ ! -f "$cert_file" ] || [ ! -f "$key_file" ]; then
        # Genera chiave privata
        openssl genrsa -out "$key_file" 2048 || log ERROR "Failed to generate private key for $node_name"

        # Crea CSR
        openssl req -new -key "$key_file" -out "$csr_file" \
            -subj "/C=IT/ST=Virtual/L=Lab/O=Vault Lab/CN=$node_name" \
            || log ERROR "Failed to generate CSR for $node_name"

        # Crea config per SAN
        cat > "$CERTS_DIR/${node_name}.conf" <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req

[req_distinguished_name]

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = $node_name
IP.1 = 127.0.0.1
IP.2 = $node_ip
EOF

        # Genera certificato firmato dalla CA
        openssl x509 -req -in "$csr_file" -CA "$CA_CERT" -CAkey "$CA_KEY" \
            -CAcreateserial -out "$cert_file" -days 365 \
            -extensions v3_req -extfile "$CERTS_DIR/${node_name}.conf" \
            || log ERROR "Failed to generate certificate for $node_name"

        # Cleanup
        rm -f "$csr_file" "$CERTS_DIR/${node_name}.conf"

        log INFO "Consul certificate generated: $cert_file"
    else
        log INFO "Consul certificate already exists for $node_name, reusing."
    fi

    echo "CERT_FILE=$cert_file"
    echo "KEY_FILE=$key_file"
}

setup_tls_infrastructure() {
    log INFO "SETTING UP TLS INFRASTRUCTURE"

    check_tls_prerequisites
    generate_ca_certificate

    # Genera certificati per Vault
    if [ "$CLUSTER_MODE" = "multi" ]; then
        for i in 1 2 3; do
            generate_vault_certificate "vault-node$i" "127.0.0.1"
        done
    else
        generate_vault_certificate "vault-server" "127.0.0.1"
    fi

    # Genera certificati per Consul se necessario
    if [ "$BACKEND_TYPE" == "consul" ]; then
        generate_consul_certificate "consul-server" "127.0.0.1"
    fi

    log INFO "TLS infrastructure setup completed."
}

verify_certificate() {
    local cert_file="$1"
    local service_name="$2"

    if [ ! -f "$cert_file" ]; then
        log ERROR "Certificate file not found: $cert_file"
        return 1
    fi

    log INFO "Verifying certificate for $service_name..."

    # Verifica validit del certificato
    if ! openssl x509 -in "$cert_file" -text -noout >/dev/null 2>&1; then
        log ERROR "Invalid certificate format: $cert_file"
        return 1
    fi

    # Verifica data di scadenza
    local expiry_date=$(openssl x509 -in "$cert_file" -enddate -noout | cut -d= -f2)
    local expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$expiry_date" +%s 2>/dev/null || echo "0")
    local current_epoch=$(date +%s)

    if [ "$expiry_epoch" -le "$current_epoch" ]; then
        log WARN "Certificate for $service_name has expired or expires soon: $expiry_date"
        return 1
    fi

    local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
    log INFO "Certificate for $service_name is valid for $days_until_expiry more days."

    return 0
}

cleanup_expired_certificates() {
    log INFO "Checking for expired certificates..."

    local expired_found=false
    for cert_file in "$CERTS_DIR"/*.pem; do
        if [ -f "$cert_file" ] && [[ "$cert_file" != *"-key.pem" ]]; then
            local service_name=$(basename "$cert_file" .pem)
            if ! verify_certificate "$cert_file" "$service_name"; then
                log INFO "Removing expired certificate: $cert_file"
                rm -f "$cert_file" "${cert_file%-*}-key.pem"
                expired_found=true
            fi
        fi
    done

    if [ "$expired_found" = true ]; then
        log INFO "Expired certificates removed. Run setup again to regenerate."
    else
        log INFO "No expired certificates found."
    fi
}

# --- Integration functions to modify existing Vault/Consul configs ---

configure_vault_with_tls() {
    local node_name="vault-server"
    local port="8200"
    local cluster_port="8201"

    setup_tls_infrastructure

    local storage_config=""
    if [ "$BACKEND_TYPE" == "file" ]; then
        storage_config="storage \"file\" { path = \"$VAULT_DIR/storage\" }"
    elif [ "$BACKEND_TYPE" == "consul" ]; then
        local consul_token=$(cat "$CONSUL_DIR/acl_master_token.txt" 2>/dev/null)
        if [ -z "$consul_token" ]; then
            log ERROR "Consul ACL token not found. Start Consul first."
        fi
        storage_config="storage \"consul\" {
            address = \"127.0.0.1:8500\"
            path = \"vault/\"
            token = \"$consul_token\"
            scheme = \"https\"
            tls_ca_file = \"$CA_CERT\"
        }"
    fi

    cat > "$VAULT_DIR/config.hcl" <<EOF
$storage_config
listener "tcp" {
  address       = "127.0.0.1:$port"
  tls_cert_file = "$CERTS_DIR/${node_name}.pem"
  tls_key_file  = "$CERTS_DIR/${node_name}-key.pem"
  tls_ca_file   = "$CA_CERT"
}
api_addr = "https://127.0.0.1:$port"
cluster_addr = "https://127.0.0.1:$cluster_port"
ui = true
EOF

    # Aggiorna le variabili globali per usare HTTPS
    VAULT_ADDR="https://127.0.0.1:$port"
    export VAULT_CACERT="$CA_CERT"
    export VAULT_ADDR="$VAULT_ADDR"
}

configure_consul_with_tls() {
    setup_tls_infrastructure

    cat > "$CONSUL_DIR/consul_config.hcl" <<EOF
datacenter = "dc1"
data_dir = "$CONSUL_DIR/data"
server = true
bootstrap_expect = 1
client_addr = "0.0.0.0"
ui_config {
  enabled = true
}
ports {
    http = -1
    https = 8500
}
ca_file = "$CA_CERT"
cert_file = "$CERTS_DIR/consul-server.pem"
key_file = "$CERTS_DIR/consul-server-key.pem"
verify_incoming = false
verify_outgoing = false
verify_server_hostname = false
acl = {
  enabled = true
  default_policy = "deny"
  enable_token_persistence = true
}
EOF

    # Aggiorna CONSUL_ADDR per usare HTTPS
    CONSUL_ADDR="https://127.0.0.1:8500"
    export CONSUL_CACERT="$CA_CERT"
}

configure_consul_with_tls_simple() {
    setup_tls_infrastructure

    cat > "$CONSUL_DIR/consul_config.hcl" <<EOF
datacenter = "dc1"
data_dir = "$CONSUL_DIR/data"
server = true
bootstrap_expect = 1
client_addr = "0.0.0.0"
ui_config {
  enabled = true
}
ports {
    https = 8500
}
ca_file = "$CA_CERT"
cert_file = "$CERTS_DIR/consul-server.pem"
key_file = "$CERTS_DIR/consul-server-key.pem"
acl = {
  enabled = true
  default_policy = "deny"
  enable_token_persistence = true
}
EOF

    CONSUL_ADDR="https://127.0.0.1:8500"
    export CONSUL_CACERT="$CA_CERT"
}

list_backups() {
    log INFO "LISTING AVAILABLE BACKUPS"

    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        log WARN "No backups found in $BACKUP_DIR"
        return 1
    fi

    echo -e "\n${YELLOW}Available backups:${NC}"
    echo "----------------------------------------"
    printf "%-25s %-15s %-8s %-12s %s\n" "NAME" "BACKEND" "TLS" "SIZE" "DATE"
    echo "----------------------------------------"

    for backup_path in "$BACKUP_DIR"/*; do
        if [ -d "$backup_path" ]; then
            local backup_name=$(basename "$backup_path")
            local metadata_file="$backup_path/$BACKUP_METADATA_FILE"

            if [ -f "$metadata_file" ]; then
                local backend_type=$(jq -r '.backend_type // "unknown"' "$metadata_file" 2>/dev/null)
                local tls_enabled=$(jq -r '.tls_enabled // false' "$metadata_file" 2>/dev/null)
                local created_date=$(jq -r '.created_date // "unknown"' "$metadata_file" 2>/dev/null)
                local size=$(du -sh "$backup_path" 2>/dev/null | cut -f1)
                local tls_status=$([ "$tls_enabled" = "true" ] && echo "YES" || echo "NO")

                printf "%-25s %-15s %-8s %-12s %s\n" "$backup_name" "$backend_type" "$tls_status" "$size" "$created_date"
            else
                printf "%-25s %-15s %-8s %-12s %s\n" "$backup_name" "unknown" "?" "?" "No metadata"
            fi
        fi
    done
    echo "----------------------------------------"
}

create_backup() {
    local backup_name="$1"
    local backup_description="$2"

    # Se non viene fornito un nome, genera uno automatico
    if [ -z "$backup_name" ]; then
        backup_name="backup_$(date +%Y%m%d_%H%M%S)"
    fi

    # Valida il nome del backup
    if [[ ! "$backup_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log ERROR "Backup name must contain only letters, numbers, hyphens, and underscores."
    fi

    local backup_path="$BACKUP_DIR/$backup_name"

    if [ -d "$backup_path" ]; then
        log ERROR "Backup '$backup_name' already exists. Choose a different name or delete the existing backup."
    fi

    log INFO "CREATING BACKUP: $backup_name"
    log INFO "Description: ${backup_description:-"No description provided"}"

    # Controlla se il lab  attivo
    local lab_running=false
    if [ -f "$LAB_VAULT_PID_FILE" ] && ps -p "$(cat "$LAB_VAULT_PID_FILE")" > /dev/null 2>&1; then
        lab_running=true
        log INFO "Lab is currently running. Creating hot backup..."
    else
        log INFO "Lab is stopped. Creating cold backup..."
    fi

    # Crea la directory di backup
    mkdir -p "$backup_path" || log ERROR "Failed to create backup directory: $backup_path"

    # Backup dei dati Vault
    if [ -d "$VAULT_DIR" ]; then
        log INFO "Backing up Vault data..."
        cp -r "$VAULT_DIR" "$backup_path/vault-data" || log ERROR "Failed to backup Vault data"

        # Se il lab  in esecuzione, esporta anche i dati via API
        if [ "$lab_running" = true ] && [ -f "$VAULT_DIR/root_token.txt" ]; then
            log INFO "Exporting Vault configuration via API..."
            export VAULT_ADDR="$VAULT_ADDR"

            # Imposta VAULT_CACERT se TLS  abilitato
            if [ "$ENABLE_TLS" = true ] && [ -f "$CA_CERT" ]; then
                export VAULT_CACERT="$CA_CERT"
            fi

            export VAULT_TOKEN=$(cat "$VAULT_DIR/root_token.txt")
            local vault_exe=$(get_vault_exe)

            # Esporta policies
            mkdir -p "$backup_path/api_export"
            "$vault_exe" policy list -format=json > "$backup_path/api_export/policies_list.json" 2>/dev/null || true

            # Esporta auth methods
            "$vault_exe" auth list -format=json > "$backup_path/api_export/auth_methods.json" 2>/dev/null || true

            # Esporta secrets engines
            "$vault_exe" secrets list -format=json > "$backup_path/api_export/secrets_engines.json" 2>/dev/null || true

            # Esporta alcune configurazioni specifiche (se esistono)
            "$vault_exe" read -format=json auth/approle/role/web-application > "$backup_path/api_export/approle_config.json" 2>/dev/null || true
        fi
    fi

    # Backup dei dati Consul (se presente)
    if [ -d "$CONSUL_DIR" ] && [ "$BACKEND_TYPE" == "consul" ]; then
        log INFO "Backing up Consul data..."
        cp -r "$CONSUL_DIR" "$backup_path/consul-data" || log ERROR "Failed to backup Consul data"

        # Se Consul  in esecuzione, esporta anche il KV store
        if [ "$lab_running" = true ] && [ -f "$CONSUL_DIR/acl_master_token.txt" ]; then
            log INFO "Exporting Consul KV store..."
            export CONSUL_HTTP_TOKEN=$(cat "$CONSUL_DIR/acl_master_token.txt")

            # Imposta CONSUL_CACERT se TLS  abilitato
            if [ "$ENABLE_TLS" = true ] && [ -f "$CA_CERT" ]; then
                export CONSUL_CACERT="$CA_CERT"
            fi

            local consul_exe=$(get_consul_exe)

            mkdir -p "$backup_path/consul_export"
            "$consul_exe" kv export > "$backup_path/consul_export/kv_export.json" 2>/dev/null || true
        fi
    fi

    # Backup dei certificati TLS (se presente)
    if [ "$ENABLE_TLS" = true ] && [ -d "$TLS_DIR" ]; then
        log INFO "Backing up TLS certificates..."
        cp -r "$TLS_DIR" "$backup_path/tls-data" || log ERROR "Failed to backup TLS data"
    fi

    # Backup della configurazione del lab
    if [ -f "$LAB_CONFIG_FILE" ]; then
        log INFO "Backing up lab configuration..."
        cp "$LAB_CONFIG_FILE" "$backup_path/" || log ERROR "Failed to backup lab configuration"
    fi

    # Crea i metadati del backup
    local metadata="{
        \"backup_name\": \"$backup_name\",
        \"description\": \"${backup_description:-""}\",
        \"created_date\": \"$(date -Iseconds)\",
        \"backend_type\": \"$BACKEND_TYPE\",
        \"tls_enabled\": $ENABLE_TLS,
        \"cluster_mode\": \"$CLUSTER_MODE\",
        \"lab_was_running\": $lab_running,
        \"vault_version\": \"$(get_vault_exe --version 2>/dev/null | head -n1 | awk '{print $2}' || echo "unknown")\",
        \"consul_version\": \"$([ "$BACKEND_TYPE" == "consul" ] && get_consul_exe --version 2>/dev/null | head -n1 | awk '{print $2}' || echo "n/a")\",
        \"script_version\": \"$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")\",
        \"hostname\": \"$(hostname)\",
        \"user\": \"$(whoami)\"
    }"

    echo "$metadata" | jq '.' > "$backup_path/$BACKUP_METADATA_FILE" 2>/dev/null || {
        echo "$metadata" > "$backup_path/$BACKUP_METADATA_FILE"
    }

    # Calcola checksum per verifica integrit
    log INFO "Calculating backup integrity checksum..."
    find "$backup_path" -type f -exec sha256sum {} \; | sort > "$backup_path/checksums.sha256"

    local backup_size=$(du -sh "$backup_path" | cut -f1)
    log INFO "Backup '$backup_name' completed successfully! Size: $backup_size"
    log INFO "Backup location: $backup_path"
}

restore_backup() {
    local backup_name="$1"
    local force_restore="$2"

    if [ -z "$backup_name" ]; then
        log ERROR "Backup name is required for restore operation."
    fi

    local backup_path="$BACKUP_DIR/$backup_name"

    if [ ! -d "$backup_path" ]; then
        log ERROR "Backup '$backup_name' not found in $BACKUP_DIR"
    fi

    local metadata_file="$backup_path/$BACKUP_METADATA_FILE"
    if [ ! -f "$metadata_file" ]; then
        log ERROR "Backup metadata not found. This might be a corrupted backup."
    fi

    # Verifica integrit del backup
    log INFO "VERIFYING BACKUP INTEGRITY"
    if [ -f "$backup_path/checksums.sha256" ]; then
        if ! (cd "$backup_path" && sha256sum -c checksums.sha256 --quiet); then
            log ERROR "Backup integrity check failed! The backup might be corrupted."
        fi
        log INFO "Backup integrity verified"
    else
        log WARN "No integrity checksums found. Proceeding without verification."
    fi

    # Leggi i metadati
    local backup_backend=$(jq -r '.backend_type // "unknown"' "$metadata_file" 2>/dev/null)
    local backup_tls=$(jq -r '.tls_enabled // false' "$metadata_file" 2>/dev/null)
    local backup_cluster=$(jq -r '.cluster_mode // "single"' "$metadata_file" 2>/dev/null)
    local backup_date=$(jq -r '.created_date // "unknown"' "$metadata_file" 2>/dev/null)
    local backup_desc=$(jq -r '.description // ""' "$metadata_file" 2>/dev/null)

    log INFO "RESTORING BACKUP: $backup_name"
    log INFO "Created: $backup_date"
    log INFO "Backend: $backup_backend"
    log INFO "TLS: $([ "$backup_tls" = "true" ] && echo "enabled" || echo "disabled")"
    log INFO "Cluster: $backup_cluster"
    [ -n "$backup_desc" ] && log INFO "Description: $backup_desc"

    # Controllo di sicurezza
    if [ "$force_restore" != "--force" ]; then
        echo -e "\n${YELLOW}WARNING: This will completely replace your current lab environment!${NC}"
        echo -e "Current data will be ${RED}permanently lost${NC}."
        read -p "Are you sure you want to continue? (yes/NO): " confirmation
        if [[ ! "$confirmation" =~ ^[Yy][Ee][Ss]$ ]]; then
            log INFO "Restore cancelled by user."
            return 0
        fi
    fi

    # Ferma il lab se  in esecuzione
    log INFO "Stopping current lab environment..."
    stop_lab_environment 2>/dev/null || true

    # Pulisci l'ambiente corrente
    log INFO "Cleaning current environment..."
    rm -rf "$VAULT_DIR" "$CONSUL_DIR" "$TLS_DIR" "$LAB_CONFIG_FILE" 2>/dev/null || true

    # Ripristina i dati
    if [ -d "$backup_path/vault-data" ]; then
        log INFO "Restoring Vault data..."
        cp -r "$backup_path/vault-data" "$VAULT_DIR" || log ERROR "Failed to restore Vault data"
    fi

    if [ -d "$backup_path/consul-data" ]; then
        log INFO "Restoring Consul data..."
        cp -r "$backup_path/consul-data" "$CONSUL_DIR" || log ERROR "Failed to restore Consul data"
    fi

    if [ -d "$backup_path/tls-data" ]; then
        log INFO "Restoring TLS certificates..."
        cp -r "$backup_path/tls-data" "$TLS_DIR" || log ERROR "Failed to restore TLS data"
    fi

    if [ -f "$backup_path/$(basename "$LAB_CONFIG_FILE")" ]; then
        log INFO "Restoring lab configuration..."
        cp "$backup_path/$(basename "$LAB_CONFIG_FILE")" "$LAB_CONFIG_FILE" || log ERROR "Failed to restore lab configuration"
    fi

    # Aggiorna le variabili dalle configurazioni ripristinate
    load_backend_type_from_config
    [ -n "$ENABLE_TLS" ] && log INFO "Restored TLS setting: $ENABLE_TLS"

    log INFO "Backup '$backup_name' restored successfully!"
    log INFO "You can now start the lab with: $0 start"
}

delete_backup() {
    local backup_name="$1"
    local force_delete="$2"

    if [ -z "$backup_name" ]; then
        log ERROR "Backup name is required for delete operation."
    fi

    local backup_path="$BACKUP_DIR/$backup_name"

    if [ ! -d "$backup_path" ]; then
        log ERROR "Backup '$backup_name' not found in $BACKUP_DIR"
    fi

    # Mostra info del backup prima di eliminarlo
    local metadata_file="$backup_path/$BACKUP_METADATA_FILE"
    if [ -f "$metadata_file" ]; then
        local backup_date=$(jq -r '.created_date // "unknown"' "$metadata_file" 2>/dev/null)
        local backup_backend=$(jq -r '.backend_type // "unknown"' "$metadata_file" 2>/dev/null)
        local backup_tls=$(jq -r '.tls_enabled // false' "$metadata_file" 2>/dev/null)
        log INFO "Backup details - Date: $backup_date, Backend: $backup_backend, TLS: $backup_tls"
    fi

    # Controllo di sicurezza
    if [ "$force_delete" != "--force" ]; then
        echo -e "\n${YELLOW}WARNING: This will permanently delete backup '$backup_name'!${NC}"
        read -p "Are you sure you want to continue? (yes/NO): " confirmation
        if [[ ! "$confirmation" =~ ^[Yy][Ee][Ss]$ ]]; then
            log INFO "Delete cancelled by user."
            return 0
        fi
    fi

    log INFO "Deleting backup '$backup_name'..."
    rm -rf "$backup_path" || log ERROR "Failed to delete backup"
    log INFO "Backup '$backup_name' deleted successfully!"
}

export_backup() {
    local backup_name="$1"
    local export_path="$2"

    if [ -z "$backup_name" ]; then
        log ERROR "Backup name is required for export operation."
    fi

    local backup_path="$BACKUP_DIR/$backup_name"

    if [ ! -d "$backup_path" ]; then
        log ERROR "Backup '$backup_name' not found in $BACKUP_DIR"
    fi

    # Se non specificato, usa la directory corrente
    if [ -z "$export_path" ]; then
        export_path="./$(basename "$backup_name").tar.gz"
    fi

    log INFO "Exporting backup '$backup_name' to '$export_path'..."

    # Crea un archivio compresso
    tar -czf "$export_path" -C "$BACKUP_DIR" "$backup_name" || log ERROR "Failed to create export archive"

    local export_size=$(du -sh "$export_path" | cut -f1)
    log INFO "Backup exported successfully! Size: $export_size"
    log INFO "Export location: $export_path"
}

import_backup() {
    local import_path="$1"
    local backup_name="$2"

    if [ -z "$import_path" ]; then
        log ERROR "Import file path is required."
    fi

    if [ ! -f "$import_path" ]; then
        log ERROR "Import file '$import_path' not found."
    fi

    # Se non specificato, estrai il nome dal file
    if [ -z "$backup_name" ]; then
        backup_name=$(basename "$import_path" .tar.gz)
    fi

    local backup_path="$BACKUP_DIR/$backup_name"

    if [ -d "$backup_path" ]; then
        log ERROR "Backup '$backup_name' already exists. Delete it first or choose a different name."
    fi

    log INFO "Importing backup from '$import_path' as '$backup_name'..."

    # Crea la directory di backup se non esiste
    mkdir -p "$BACKUP_DIR" || log ERROR "Failed to create backup directory"

    # Estrai l'archivio
    tar -xzf "$import_path" -C "$BACKUP_DIR" || log ERROR "Failed to extract import archive"

    # Se necessario, rinomina la directory estratta
    local extracted_name=$(tar -tzf "$import_path" | head -1 | cut -d/ -f1)
    if [ "$extracted_name" != "$backup_name" ]; then
        mv "$BACKUP_DIR/$extracted_name" "$backup_path" || log ERROR "Failed to rename imported backup"
    fi

    log INFO "Backup imported successfully!"
    log INFO "You can now restore it with: $0 restore $backup_name"
}

display_help() {
    cat <<'EOF'
Usage:
  ./vault-lab-ctl.sh [OPTIONS] COMMAND [ARGS]

Deploy a local HashiCorp Vault lab environment with optional Consul backend.

Options:
  -c, --clean                   Force clean setup before start
  -h, --help                    Show this help and exit
  -v, --verbose                 Verbose output
      --no-color                Disable colored output
      --backend <file|consul>   Storage backend (default: file)
      --cluster <single|multi>  Cluster mode (default: single)
      --tls                     Enable TLS/SSL encryption

Commands:
  start        Start the lab (default if no command is given)
  stop         Stop Vault/Consul processes
  restart      Restart the lab and unseal Vault
  reset        Clean and start from scratch
  status       Show current status of Vault/Consul
  cleanup      Remove all lab data and configs
  shell        Drop into an interactive shell with env set

Backup/Restore:
  backup [name] [description]       Create a backup of the current lab state
  restore <name> [--force]          Restore from a backup
  list-backups                      List all available backups
  delete-backup <name> [--force]    Delete a specific backup
  export-backup <name> [path]       Export a backup as a tar.gz file
  import-backup <path> [name]       Import a backup from a tar.gz file

Examples:
  ./vault-lab-ctl.sh --tls start
  ./vault-lab-ctl.sh --cluster multi --backend consul start
  ./vault-lab-ctl.sh backup my-config "Working KV setup"
  ./vault-lab-ctl.sh restore my-config
EOF
    exit 0
}

save_backend_type_to_config() {
    echo "BACKEND_TYPE=\"$BACKEND_TYPE\"" > "$LAB_CONFIG_FILE"
    echo "CLUSTER_MODE=\"$CLUSTER_MODE\"" >> "$LAB_CONFIG_FILE"
    echo "ENABLE_TLS=\"$ENABLE_TLS\"" >> "$LAB_CONFIG_FILE"
}

load_backend_type_from_config() {
    if [ -f "$LAB_CONFIG_FILE" ]; then
        source "$LAB_CONFIG_FILE"
        log INFO "Loaded backend type from config: $BACKEND_TYPE"
        [ -n "$CLUSTER_MODE" ] && log INFO "Loaded cluster mode from config: $CLUSTER_MODE"
        [ -n "$ENABLE_TLS" ] && log INFO "Loaded TLS mode from config: $ENABLE_TLS"

        # Aggiorna VAULT_ADDR e CONSUL_ADDR se TLS  abilitato
        if [ "$ENABLE_TLS" = true ]; then
            VAULT_ADDR="https://127.0.0.1:8200"
            CONSUL_ADDR="https://127.0.0.1:8500"
        fi
    fi
}

stop_lab_environment() {
    log INFO "STOPPING VAULT LAB ENVIRONMENT (Backend: $BACKEND_TYPE)"
    stop_vault
    if [ "$BACKEND_TYPE" == "consul" ]; then
        stop_consul
    fi
    log INFO "Vault lab environment stopped. "
}

cleanup_previous_environment() {
    log INFO "FULL CLEANUP OF PREVIOUS LAB ENVIRONMENT"

    # Stop Consul if running
    if [ -f "$CONSUL_DIR/consul.pid" ]; then
        log INFO "Stopping Consul server..."
        kill "$(cat "$CONSUL_DIR/consul.pid")" 2>/dev/null || true
        rm -f "$CONSUL_DIR/consul.pid"
    fi

    # Stop all Vault nodes
    if [ -d "$VAULT_DIR" ]; then
        log INFO "Stopping Vault server(s)..."
        # kill any pid files in vault-data and its subdirectories
        find "$VAULT_DIR" -name 'vault.pid' -print | while read -r pidfile; do
            kill "$(cat "$pidfile")" 2>/dev/null || true
            rm -f "$pidfile"
        done
        # safety net: kill any leftover vault server processes
        pkill -f 'vault server' 2>/dev/null || true
    fi

    log INFO "Deleting previous working directories..."
    rm -rf "$VAULT_DIR" "$CONSUL_DIR" "$CERTS_DIR"
    log INFO "Cleanup completed."
}

check_lab_status() {
    log INFO "CHECKING VAULT LAB STATUS (Backend: $BACKEND_TYPE)"
    local vault_running=false
    if [ -f "$LAB_VAULT_PID_FILE" ] && ps -p "$(cat "$LAB_VAULT_PID_FILE")" > /dev/null; then
        vault_running=true
    fi

    if [ "$vault_running" = true ]; then
        log INFO "Vault process is RUNNING. PID: $(cat "$LAB_VAULT_PID_FILE")"

        # Imposta le variabili necessarie per il controllo dello stato
        if [ "$ENABLE_TLS" = true ]; then
            export VAULT_CACERT="$CA_CERT"
        fi
        export VAULT_ADDR="$VAULT_ADDR"

        local status_json=$(get_vault_status)
        if [ "$(echo "$status_json" | jq -r '.sealed')" == "false" ]; then
            log INFO "Vault is UNSEALED and READY. "
        else
            log WARN "Vault is SEALED.  Run 'restart' to unseal."
        fi
    else
        log INFO "Vault server is NOT RUNNING. "
    fi

    if [ "$BACKEND_TYPE" == "consul" ]; then
        if [ -f "$LAB_CONSUL_PID_FILE" ] && ps -p "$(cat "$LAB_CONSUL_PID_FILE")" > /dev/null; then
            log INFO "Consul process is RUNNING. PID: $(cat "$LAB_CONSUL_PID_FILE")"
        else
            log INFO "Consul server is NOT RUNNING. "
        fi
    fi

    if [ "$ENABLE_TLS" = true ]; then
        log INFO "TLS encryption is ENABLED. "
    else
        log INFO "TLS encryption is DISABLED. "
    fi
}

display_final_info() {
    log INFO "LAB VAULT IS READY TO USE!"
    local vault_root_token=$(cat "$VAULT_DIR/root_token.txt" 2>/dev/null)
    local approle_role_id=$(cat "$VAULT_DIR/approle_role_id.txt" 2>/dev/null)
    local approle_secret_id=$(cat "$VAULT_DIR/approle_secret_id.txt" 2>/dev/null)
    local consul_token=$(cat "$CONSUL_DIR/acl_master_token.txt" 2>/dev/null)

    # Determina gli IP corretti in base all'ambiente
    local vault_ip="127.0.0.1"  # Vault sempre su localhost
    local consul_ip="127.0.0.1" # Default per Consul

    # Su WSL, usa l'IP della VM per Consul per accessibilit esterna
    if grep -q "microsoft" /proc/version &>/dev/null; then
        local wsl_ip=$(ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
        if [ -n "$wsl_ip" ]; then
            consul_ip="$wsl_ip"
        fi
    fi

    local protocol="http"
    local tls_note=""
    if [ "$ENABLE_TLS" = true ]; then
        protocol="https"
        tls_note=" ( TLS enabled)"
    fi

    echo -e "\n${YELLOW}--- ACCESS DETAILS ---${NC}"
    echo -e "   Vault UI: ${GREEN}${protocol}://${vault_ip}:8200${NC}${tls_note}"
    echo -e "   Vault Root Token: ${GREEN}$vault_root_token${NC}"

    if [ "$BACKEND_TYPE" == "consul" ]; then
        echo -e "  ---"
        echo -e "   Consul UI: ${GREEN}${protocol}://${consul_ip}:8500${NC}${tls_note}"
        echo -e "   Consul ACL Token: ${GREEN}$consul_token${NC}"
    fi

    if [ "$CLUSTER_MODE" = "multi" ]; then
        echo -e "\n${YELLOW}Vault cluster nodes:${NC}"
        echo "  ${protocol}://${vault_ip}:8200"
        echo "  ${protocol}://${vault_ip}:8201"
        echo "  ${protocol}://${vault_ip}:8202"
    fi

    if [ "$ENABLE_TLS" = true ]; then
        echo -e "\n${YELLOW}--- TLS CERTIFICATE INFO ---${NC}"
        echo -e "   CA Certificate: ${GREEN}$CA_CERT${NC}"
        echo -e "   Certificates Directory: ${GREEN}$CERTS_DIR${NC}"
        echo -e "\n  To trust the CA certificate:"
        echo -e "  ${CYAN}Linux:${NC} sudo cp $CA_CERT /usr/local/share/ca-certificates/vault-lab-ca.crt && sudo update-ca-certificates"
        echo -e "  ${CYAN}macOS:${NC} sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain $CA_CERT"
        echo -e "  ${CYAN}Windows:${NC} Import CA cert via certmgr.msc into Trusted Root Certification Authorities"

        if grep -q "microsoft" /proc/version &>/dev/null; then
            echo -e "\n  ${YELLOW}WSL Note:${NC} Vault uses localhost (127.0.0.1) for local access"
            echo -e "  Consul uses VM IP ($consul_ip) for Windows host access"
        fi
    fi
}

start_lab_environment_core() {
    log INFO "Validating environment..."
    validate_directories
    validate_ports_available
    mkdir -p "$BIN_DIR"

    # --- NEW: create all required directories up front ---
    mkdir -p "$VAULT_DIR" "$CONSUL_DIR" "$TLS_DIR" "$CERTS_DIR" "$CA_DIR" || \
        log ERROR "Failed to create base directories"

    check_and_install_prerequisites
    download_latest_vault_binary "$BIN_DIR"

    if [ "$BACKEND_TYPE" == "consul" ]; then
        download_latest_consul_binary "$BIN_DIR"
        if [ "$ENABLE_TLS" = true ]; then
            configure_consul_with_tls
            start_consul_with_tls
        else
            configure_and_start_consul
        fi
    fi

    if [ "$CLUSTER_MODE" = "multi" ]; then
        if [ "$ENABLE_TLS" = true ]; then
            start_vault_nodes_with_tls
        else
            start_vault_nodes
        fi
    else
        if [ "$ENABLE_TLS" = true ]; then
            configure_vault_with_tls
            start_vault_with_tls
        else
            configure_and_start_vault
        fi
    fi

    initialize_and_unseal_vault
    configure_vault_features
    save_backend_type_to_config
    display_final_info
}

restart_lab_environment() {
    log INFO "RESTARTING VAULT LAB ENVIRONMENT (Backend: $BACKEND_TYPE)"
    mkdir -p "$BIN_DIR"
    download_latest_vault_binary "$BIN_DIR"
    if [ "$BACKEND_TYPE" == "consul" ]; then
        download_latest_consul_binary "$BIN_DIR"
    fi
    stop_lab_environment
    sleep 3

    if [ "$BACKEND_TYPE" == "consul" ]; then
        if [ "$ENABLE_TLS" = true ]; then
            configure_consul_with_tls
            start_consul_with_tls
        else
            configure_and_start_consul
        fi
    fi

    if [ "$CLUSTER_MODE" = "multi" ]; then
        if [ "$ENABLE_TLS" = true ]; then
            start_vault_nodes_with_tls
        else
            start_vault_nodes
        fi
    else
        if [ "$ENABLE_TLS" = true ]; then
            configure_vault_with_tls
            start_vault_with_tls
        else
            configure_and_start_vault
        fi
    fi

    initialize_and_unseal_vault
    log INFO "Vault lab environment restarted and unsealed. "
    display_final_info
}

reset_lab_environment() {
    log INFO "RESETTING VAULT LAB ENVIRONMENT"
    cleanup_previous_environment
    start_lab_environment_core
}

# Unified function to start Consul with TLS
# Usage: start_consul_tls [--no-acl]
start_consul_tls() {
    local disable_acl=false
    [[ "$1" == "--no-acl" ]] && disable_acl=true

    log INFO "Starting Consul server with TLS in background..."
    local consul_exe
    consul_exe=$(get_consul_exe)

    # Make sure we have TLS material
    export CONSUL_CACERT="$CA_CERT"

    # If requested, disable ACL in the config
    if $disable_acl; then
        sed -i 's/enabled = true/enabled = false/' "$CONSUL_DIR/consul_config.hcl" \
            || log ERROR "Failed to modify Consul config for no-ACL mode"
        log WARN "ACL disabled for lab simplicity."
    fi

    "$consul_exe" agent -config-dir="$CONSUL_DIR" > "$CONSUL_DIR/consul.log" 2>&1 &
    echo $! > "$LAB_CONSUL_PID_FILE"
    log INFO "Consul PID saved to $LAB_CONSUL_PID_FILE"

    # Update environment for HTTPS
    CONSUL_ADDR="https://127.0.0.1:8500"
    export CONSUL_CACERT="$CA_CERT"
    export CONSUL_HTTP_ADDR="$CONSUL_ADDR"
    export CONSUL_HTTP_SSL=true

    wait_for_http_up "$CONSUL_ADDR/v1/status/leader" 30 "Consul"

    # Bootstrap ACL master token only if ACL is enabled
    if ! $disable_acl; then
        log INFO "Bootstrapping Consul ACL Master Token..."
        local token_file="$CONSUL_DIR/acl_master_token.txt"
        if [ -f "$token_file" ]; then
            log INFO "Re-using existing Consul ACL Master Token."
            export CONSUL_HTTP_TOKEN=$(cat "$token_file")
        else
            local bootstrap_output
            bootstrap_output=$(CONSUL_HTTP_ADDR="$CONSUL_ADDR" CONSUL_CACERT="$CA_CERT" \
                CONSUL_HTTP_SSL=true "$consul_exe" acl bootstrap -format=json 2>&1) \
                || log ERROR "ACL bootstrap failed: $bootstrap_output"

            local root_token
            root_token=$(echo "$bootstrap_output" | jq -r '.SecretID' 2>/dev/null)
            [ -z "$root_token" ] && log ERROR "Failed to extract Consul ACL Master Token."
            echo "$root_token" > "$token_file"
            export CONSUL_HTTP_TOKEN="$root_token"
            log INFO "Consul ACL Master Token saved to $token_file."
        fi
    fi
}

parse_args() {
    # reset variabili globali
    FORCE_CLEANUP_ON_START=false
    VERBOSE_OUTPUT=false
    COLORS_ENABLED=true
    TLS_ENABLED_FROM_ARG=false
    BACKEND_TYPE_SET_VIA_ARG=false
    COMMAND=""
    REMAINING_ARGS=()

    # parse con getopts (gestione di opzioni lunghe con '-:')
    while getopts ":chv-:" opt; do
        case $opt in
            c) FORCE_CLEANUP_ON_START=true ;;
            h) display_help ;;
            v) VERBOSE_OUTPUT=true ;;
            -)
                case "${OPTARG}" in
                    no-color) COLORS_ENABLED=false ;;
                    backend)  BACKEND_TYPE="$2"; BACKEND_TYPE_SET_VIA_ARG=true; shift ;;
                    cluster)  CLUSTER_MODE="$2"; shift ;;
                    tls)      ENABLE_TLS=true; TLS_ENABLED_FROM_ARG=true ;;
                    help)     display_help ;;
                    *) log ERROR "Unknown option --${OPTARG}" ;;
                esac
                ;;
            \?) log ERROR "Unknown option -$OPTARG" ;;
        esac
    done
    shift $((OPTIND-1))

    # primo argomento dopo le opzioni  il comando
    COMMAND="${1:-start}"
    shift || true
    REMAINING_ARGS=("$@")
}

main() {
    parse_args "$@"

    # carica backend da file se serve
    case "$COMMAND" in
        start|reset|backup|list-backups|delete-backup|export-backup|import-backup) ;;
        *) load_backend_type_from_config ;;
    esac

    # prompt interattivi (cluster/backend/tls) solo per start/reset
    if [[ "$COMMAND" =~ ^(start|reset)$ ]]; then
        if [[ ! "$CLUSTER_MODE" =~ ^(single|multi)$ ]]; then
            echo -e "\n${YELLOW}Cluster mode (single/multi) [single]:${NC}"
            read -r cchoice
            CLUSTER_MODE=${cchoice:-single}
        fi
        echo -e "Using cluster mode: ${GREEN}$CLUSTER_MODE${NC}"

        if [ "$BACKEND_TYPE_SET_VIA_ARG" = false ]; then
            if [ "$CLUSTER_MODE" = "multi" ]; then
                BACKEND_TYPE="consul"
                echo -e "Cluster mode is multi: forcing backend to ${GREEN}consul${NC}"
            else
                echo -e "\n${YELLOW}Choose storage backend (file/consul) [file]:${NC}"
                read -r choice
                BACKEND_TYPE=${choice:-file}
            fi
        fi
        echo -e "Using backend: ${GREEN}$BACKEND_TYPE${NC}"

        if [ "$TLS_ENABLED_FROM_ARG" = false ]; then
            echo -e "\n${YELLOW}Enable TLS/SSL encryption? (y/N):${NC}"
            read -r tls_choice
            [[ "$tls_choice" =~ ^[Yy] ]] && ENABLE_TLS=true
        fi
        echo -e "TLS encryption: ${GREEN}$([ "$ENABLE_TLS" = true ] && echo enabled || echo disabled)${NC}"

        [ "$ENABLE_TLS" = true ] && {
            VAULT_ADDR="https://127.0.0.1:8200"
            CONSUL_ADDR="https://127.0.0.1:8500"
        }
    fi

    # esecuzione comando
    case "$COMMAND" in
        start)   $FORCE_CLEANUP_ON_START && cleanup_previous_environment; start_lab_environment_core ;;
        stop)    stop_lab_environment ;;
        restart) restart_lab_environment ;;
        reset)   reset_lab_environment ;;
        status)  check_lab_status ;;
        cleanup) cleanup_previous_environment ;;
        shell)
            [ "$ENABLE_TLS" = true ] && export VAULT_CACERT="$CA_CERT"
            export VAULT_ADDR PATH="$BIN_DIR:$PATH"
            [ -f "$VAULT_DIR/root_token.txt" ] && export VAULT_TOKEN="$(cat "$VAULT_DIR/root_token.txt")"
            echo " Lab shell active. Type 'exit' to leave."
            exec "${SHELL:-bash}" -i
            ;;
        backup)         create_backup "${REMAINING_ARGS[0]}" "${REMAINING_ARGS[1]}" ;;
        restore)        restore_backup "${REMAINING_ARGS[0]}" "${REMAINING_ARGS[1]}" ;;
        list-backups)   list_backups ;;
        delete-backup)  delete_backup "${REMAINING_ARGS[0]}" "${REMAINING_ARGS[1]}" ;;
        export-backup)  export_backup "${REMAINING_ARGS[0]}" "${REMAINING_ARGS[1]}" ;;
        import-backup)  import_backup "${REMAINING_ARGS[0]}" "${REMAINING_ARGS[1]}" ;;
        *) log ERROR "Invalid command '$COMMAND'." ;;
    esac
}

main "$@"