#!/usr/bin/env bash
set -euo pipefail
set -E

# $BASH_COMMAND shows the failing command, not just the line number.
trap 'echo -e "\033[0;31m[ERROR]\033[0m Script aborted at line $LINENO: $BASH_COMMAND" >&2' ERR

# ==========================================================
# Vault Lab – Ephemeral (FINAL, safe auto-update + fallback)
#
# PURPOSE
#   Spin up a fully ephemeral local HashiCorp Vault lab.
#
# UPDATE POLICY
#   - Check latest STABLE Vault version (no rc/beta)
#   - Try to download it (multi-platform: linux/darwin; amd64/arm64)
#   - On any failure, fallback to local binary (if present)
#
# USAGE
#   ./vault-lab-ctl.sh <command>
#
# COMMANDS
#   start       Start Vault if not running
#   restart     Destroy and recreate Vault
#   bootstrap   Configure demo engines, auths and data
#   status      Show Vault status (root token)
#   env         Print env exports (manual)
#   stop        Destroy the lab
#
# REQUIREMENTS
#   curl, jq, unzip
#   Linux: ss (or netstat)   | macOS: lsof (or netstat)
# ==========================================================

SCRIPT_DIR="$(pwd)"
BIN_DIR="$SCRIPT_DIR/bin"

VAULT_ADDR="http://127.0.0.1:8200"
VAULT_PORT="8200"

STATE_FILE="/tmp/vault-lab-current"

# ---------------- Logging ----------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()   { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
fatal() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ---------------- Helpers ----------------
get_exe() { echo "$BIN_DIR/$1"; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }

# ---------------- Package manager detection ----------------
detect_pkg_manager() {
  if has_cmd apt-get; then echo "apt-get"
  elif has_cmd dnf;     then echo "dnf"
  elif has_cmd yum;     then echo "yum"
  elif has_cmd brew;    then echo "brew"
  else echo "none"
  fi
}

try_install() {
  local pkg="$1"
  local mgr
  mgr="$(detect_pkg_manager)"

  if [[ "$mgr" = "none" ]]; then
    warn "No supported package manager found (apt-get/dnf/yum/brew). Cannot auto-install $pkg."
    return 1
  fi

  log "Installing $pkg via $mgr..."
  # Bypass corporate proxy for package managers: loopback and internal mirrors
  # may be blocked if http_proxy/https_proxy are set in the environment.
  local proxy_env=""
  if [[ -n "${http_proxy:-}${https_proxy:-}${HTTP_PROXY:-}${HTTPS_PROXY:-}" ]]; then
    warn "Corporate proxy detected. Attempting install with proxy bypass..."
    proxy_env="env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY"
  fi

  case "$mgr" in
    apt-get) $proxy_env apt-get install -y "$pkg" >/dev/null 2>&1 ;;
    dnf|yum) $proxy_env "$mgr" install -y "$pkg" >/dev/null 2>&1 ;;
    brew)    $proxy_env brew install "$pkg" >/dev/null 2>&1 ;;
  esac
}

# jq fallback: use python3 to extract JSON fields.
# Mimics: jq -r '<expr>' where expr is either:
#   .versions | keys[]       -> list all keys of .versions
#   .root_token              -> extract scalar field
#   .unseal_keys_b64[0]      -> extract first array element
JQ_USE_PYTHON=false
UNZIP_USE_PYTHON=false

jq_compat() {
  # Usage: jq_compat '<jq_expr>' [input]
  # Reads from stdin if no input provided.
  local expr="$1"
  local py_expr

  case "$expr" in
    ".versions | keys[]")
      py_expr='import sys,json; d=json.load(sys.stdin); [print(k) for k in sorted(d.get("versions",{}).keys())]'
      ;;
    ".root_token")
      py_expr='import sys,json; print(json.load(sys.stdin)["root_token"])'
      ;;
    ".unseal_keys_b64[0]")
      py_expr='import sys,json; print(json.load(sys.stdin)["unseal_keys_b64"][0])'
      ;;
    *)
      warn "jq_compat: unsupported expression: $expr"
      return 1
      ;;
  esac

  python3 -c "$py_expr"
}

# Wrapper: routes jq calls through jq_compat when jq is unavailable.
jq_run() {
  # Usage: jq_run -r '<expr>'  (reads stdin)
  # Ignores -r flag (always raw output).
  local expr="${2:-$1}"
  if [[ "$JQ_USE_PYTHON" = true ]]; then
    jq_compat "$expr"
  else
    jq -r "$expr"
  fi
}

# unzip fallback: use python3 zipfile to extract a zip archive.
# Usage: unzip_compat <zipfile> <destdir>
unzip_compat() {
  local zipfile="$1"
  local destdir="$2"
  python3 -c "
import zipfile, sys
with zipfile.ZipFile('$zipfile') as z:
    z.extractall('$destdir')
"
}

# Wrapper: routes unzip calls through unzip_compat when unzip is unavailable.
unzip_run() {
  # Mimics: unzip -oq <zipfile> -d <destdir>
  local zipfile destdir
  # Parse: unzip_run -oq <zipfile> -d <destdir>
  shift  # skip -oq
  zipfile="$1"; shift  # zip path
  shift  # skip -d
  destdir="$1"
  if [[ "$UNZIP_USE_PYTHON" = true ]]; then
    unzip_compat "$zipfile" "$destdir"
  else
    unzip -oq "$zipfile" -d "$destdir"
  fi
}

# ---------------- Requirements ----------------
check_requirements() {
  # Tools that can be replaced by a python3 fallback if install fails/declined.
  # Tools that can be replaced by a python3 fallback if install fails/declined.
  # unzip: python3 zipfile module. jq: python3 json module.
  local python_replaceable="jq unzip"

  for cmd in curl jq unzip; do
    if has_cmd "$cmd"; then
      continue
    fi

    warn "Required tool not found: $cmd"

    # Ask user whether to attempt auto-install.
    local answer="n"
    if [[ -t 0 ]]; then
      read -r -p "  Attempt to install $cmd automatically? [y/N] " answer || true
    fi

    if [[ "${answer,,}" = "y" ]]; then
      if try_install "$cmd"; then
        if has_cmd "$cmd"; then
          log "$cmd installed successfully."
          continue
        else
          warn "$cmd install reported success but binary not found."
        fi
      else
        warn "Auto-install of $cmd failed."
      fi
    fi

    # Install declined or failed: try python3 fallback for replaceable tools.
    if echo "$python_replaceable" | grep -qw "$cmd"; then
      if has_cmd python3; then
        warn "Falling back to python3 for $cmd operations."
        [[ "$cmd" = "jq"    ]] && JQ_USE_PYTHON=true
        [[ "$cmd" = "unzip" ]] && UNZIP_USE_PYTHON=true
        continue
      else
        fatal "$cmd not available and python3 fallback not found. Install one of: $cmd, python3"
      fi
    fi

    fatal "$cmd is required and could not be installed. Please install it manually."
  done
}

detect_platform() {
  # Returns "os_arch" (e.g., linux_amd64, linux_arm64, darwin_amd64, darwin_arm64)
  local os arch

  case "$(uname -s)" in
    Linux)  os="linux" ;;
    Darwin) os="darwin" ;;
    *) fatal "Unsupported OS: $(uname -s)" ;;
  esac

  case "$(uname -m)" in
    x86_64)  arch="amd64" ;;
    aarch64) arch="arm64" ;;
    arm64)   arch="arm64" ;; # macOS (Apple Silicon) reports arm64
    *) fatal "Unsupported architecture: $(uname -m)" ;;
  esac

  echo "${os}_${arch}"
}

is_vault_running() {
  # Cross-platform port check for localhost:$VAULT_PORT
  # Prefer ss (Linux), fallback to lsof (macOS), then netstat
  if has_cmd ss; then
    ss -ltn "( sport = :$VAULT_PORT )" 2>/dev/null | grep -q ":$VAULT_PORT" && return 0 || return 1
  elif has_cmd lsof; then
    lsof -nP -i TCP:"$VAULT_PORT" -sTCP:LISTEN >/dev/null 2>&1 && return 0 || return 1
  elif has_cmd netstat; then
    netstat -an 2>/dev/null | grep -E "[:\.]$VAULT_PORT[[:space:]]" | grep -qi LISTEN && return 0 || return 1
  else
    warn "No suitable port checking tool found (ss/lsof/netstat). Assuming not running."
    return 1
  fi
}

# ---------------- wait_for_port_free ----------------
# Uses an explicit counter to avoid unreliable brace-expansion loops
# under set -euo pipefail.
wait_for_port_free() {
  local i=0
  while (( i < 10 )); do
    (( i++ )) || true
    if ! is_vault_running; then
      return 0
    fi
    sleep 1
  done
  fatal "Port $VAULT_PORT still in use after ${i}s"
}

# ---------------- Version handling ----------------
get_latest_stable_vault_version() {
  # Capture curl output explicitly so a non-JSON response (captive portal,
  # HTTP error with 200 body) causes jq to fail and propagate via pipefail.
  local raw
  raw="$(curl -fsSL --max-time 10 --connect-timeout 5 \
    https://releases.hashicorp.com/vault/index.json 2>/dev/null)" || return 1
  # Only pure OSS releases match strict semver (no +ent, +ent.hsm, +ent.fips* suffix).
  # Enterprise builds require raft/consul storage and a valid license,
  # neither of which is available in this ephemeral lab setup.
  echo "$raw" | jq_run -r '.versions | keys[]' 2>/dev/null \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -V \
    | tail -1
}

get_local_vault_version() {
  local exe="$1"
  [ -x "$exe" ] || return 1
  "$exe" --version | awk 'NR==1{print $2}' | sed 's/^v//'
}

# Warn if the local binary is a Vault Enterprise build.
# Enterprise requires raft/consul storage and a license; it will not
# work with this lab's ephemeral file-based configuration.
check_local_binary_edition() {
  local exe="$1"
  [ -x "$exe" ] || return 0
  local ver
  ver="$("$exe" --version 2>/dev/null | awk 'NR==1{print $2}')"
  if echo "$ver" | grep -qi '+ent'; then
    warn "Local Vault binary appears to be an Enterprise build ($ver)."
    warn "Vault Enterprise requires raft/consul storage and a license."
    warn "Replace bin/vault with an OSS build from:"
    warn "  https://releases.hashicorp.com/vault/"
    fatal "Enterprise binary detected. Cannot start ephemeral lab."
  fi
}

try_download_vault() {
  local version="$1"
  local exe="$2"
  local tmpdir platform url

  log "Attempting to download Vault $version"

  tmpdir="$(mktemp -d)"
  platform="$(detect_platform)"
  url="https://releases.hashicorp.com/vault/${version}/vault_${version}_${platform}.zip"

  log "Platform detected: $platform"
  log "Download URL: $url"

  if ! curl -fsSL --max-time 60 --connect-timeout 5 "$url" -o "$tmpdir/vault.zip"; then
    warn "Download failed"
    rm -rf "$tmpdir"
    return 1
  fi

  if ! unzip_run -oq "$tmpdir/vault.zip" -d "$tmpdir"; then
    warn "Unzip failed"
    rm -rf "$tmpdir"
    return 1
  fi

  if [ ! -f "$tmpdir/vault" ]; then
    warn "Vault binary not found in archive"
    rm -rf "$tmpdir"
    return 1
  fi

  mv -f "$tmpdir/vault" "$exe"
  chmod +x "$exe"
  rm -rf "$tmpdir"

  log "Vault $version installed successfully"
}

download_vault() {
  mkdir -p "$BIN_DIR"
  local exe
  exe="$(get_exe vault)"

  local local_version=""
  local latest_version=""

  log "Checking latest stable Vault version..."

  local_version="$(get_local_vault_version "$exe" || true)"

  if latest_version="$(get_latest_stable_vault_version 2>/dev/null)"; then
    log "Latest stable Vault version: $latest_version"

    if [ -n "$local_version" ]; then
      log "Local Vault version: $local_version"
    else
      log "No local Vault binary found"
    fi

    if [ "$latest_version" != "$local_version" ]; then
      try_download_vault "$latest_version" "$exe" || \
        warn "Using local Vault binary ($local_version)"
    else
      log "Vault already up to date ($local_version)"
    fi
  else
    warn "Unable to check latest Vault version (offline?)"
  fi

  [ -x "$exe" ] || fatal "Vault binary not available and download failed"
  check_local_binary_edition "$exe"
}

# ---------------- Output ----------------
print_access_info() {
  local token="$1"

  echo
  echo "=================================================="
  echo "Vault Lab ready"
  echo
  echo "1) Export environment variables in YOUR shell:"
  echo
  echo "   export VAULT_ADDR=$VAULT_ADDR"
  [ -n "$token" ] && echo "   export VAULT_TOKEN=$token"
  echo
  echo "2) Verify Vault status:"
  echo
  echo "   vault status"
  echo
  echo "3) Userpass login example (AFTER bootstrap):"
  echo
  echo "   unset VAULT_TOKEN"
  echo "   rm -f ~/.vault-token"
  echo "   vault login -method=userpass username=demo password=demo"
  echo
  echo "IMPORTANT NOTES:"
  echo " - Vault CLI persists tokens in ~/.vault-token"
  echo " - Unsetting VAULT_TOKEN alone may NOT be enough"
  echo " - After restart, Vault is EMPTY until bootstrap is run"
  echo "=================================================="
  echo
}

# ---------------- State handling ----------------
load_root_token() {
  [ -f "$STATE_FILE" ] || fatal "Vault lab state not found. Is the lab running?"

  local runtime_dir
  runtime_dir="$(cat "$STATE_FILE")" || fatal "Cannot read state file: $STATE_FILE"

  local token_file="$runtime_dir/vault/root.token"
  [ -f "$token_file" ] || fatal "Root token not found. Is the lab initialized?"

  cat "$token_file"
}

# ---------------- Runtime ----------------
create_runtime() {
  RUNTIME_DIR=$(mktemp -d /tmp/vault-lab-XXXXXX)
  VAULT_DIR="$RUNTIME_DIR/vault"
  mkdir -p "$VAULT_DIR"

  echo "$RUNTIME_DIR" > "$STATE_FILE"
}

# ---------------- wait_for_vault ----------------
# Uses an explicit counter to avoid unreliable brace-expansion loops
# under set -euo pipefail.
wait_for_vault() {
  log "Waiting for Vault API..."
  local i=0
  while (( i < 20 )); do
    (( i++ )) || true
    if curl -s --noproxy "*" "$VAULT_ADDR/v1/sys/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  fatal "Vault did not start after ${i}s"
}

# ---------------- Vault ----------------
start_vault() {
  download_vault
  export VAULT_ADDR="$VAULT_ADDR"

  cat > "$VAULT_DIR/vault.hcl" <<EOF
storage "file" {
  path = "$VAULT_DIR/data"
}
listener "tcp" {
  address = "127.0.0.1:${VAULT_PORT}"
  tls_disable = 1
}
# Required on WSL: mlockall on Windows-mounted filesystems causes Vault
# to shut down immediately after start.
disable_mlock = true
ui = true
EOF

  # Bypass corporate proxy for loopback: without this, Vault internal
  # cluster traffic and health checks may be routed through the proxy.
  NO_PROXY="127.0.0.1,localhost" no_proxy="127.0.0.1,localhost" \
  "$(get_exe vault)" server -config="$VAULT_DIR/vault.hcl" \
    >"$VAULT_DIR/vault.log" 2>&1 &

  wait_for_vault

  # Declare 'out' as local to avoid polluting the global scope.
  local out
  out=$("$(get_exe vault)" operator init -key-shares=1 -key-threshold=1 -format=json)
  echo "$out" | jq_run -r '.root_token'    > "$VAULT_DIR/root.token"
  echo "$out" | jq_run -r '.unseal_keys_b64[0]' > "$VAULT_DIR/unseal.key"

  "$(get_exe vault)" operator unseal "$(cat "$VAULT_DIR/unseal.key")"

  log "Vault ready"
  print_access_info "$(cat "$VAULT_DIR/root.token")"
}

# ---------------- Commands ----------------
cmd_start() {
  check_requirements
  is_vault_running && fatal "Vault already running. Use 'status' or 'restart'."
  log "Starting Vault lab"
  create_runtime
  start_vault
}

cmd_restart() {
  cmd_stop || true
  wait_for_port_free
  cmd_start
}

cmd_bootstrap() {
  export VAULT_ADDR="$VAULT_ADDR"
  export VAULT_TOKEN
  VAULT_TOKEN="$(load_root_token)"

  # Use the managed binary consistently, not whatever 'vault' is in PATH.
  local v
  v="$(get_exe vault)"

  log "Bootstrapping Vault"

  "$v" secrets enable -path=kv kv-v2 2>/dev/null || true
  "$v" secrets enable transit   2>/dev/null || true
  "$v" auth enable approle      2>/dev/null || true
  "$v" auth enable userpass     2>/dev/null || true

  "$v" policy write app-read - <<EOF
path "kv/data/*" {
  capabilities = ["read"]
}
EOF

  "$v" policy write user-demo - <<EOF
path "kv/data/demo/*" {
  capabilities = ["read", "create", "update"]
}
path "sys/health" {
  capabilities = ["read"]
}
EOF

  "$v" write auth/approle/role/demo-app token_policies="app-read" token_ttl=1h
  "$v" write auth/userpass/users/demo password="demo" policies="user-demo"

  "$v" kv put kv/demo/config      app="demo" env="lab"
  "$v" kv put kv/demo/credentials username="demo" password="secret"

  log "Bootstrap completed"
  print_access_info "$VAULT_TOKEN"
}

cmd_status() {
  export VAULT_ADDR="$VAULT_ADDR"
  export VAULT_TOKEN
  VAULT_TOKEN="$(load_root_token)"
  "$(get_exe vault)" status
}

cmd_env() {
  local token
  token="$(load_root_token)"
  warn "Root token will appear in shell history if you eval this output."
  cat <<EOF
export VAULT_ADDR=$VAULT_ADDR
export VAULT_TOKEN=$token
EOF
}

# ---------------- cmd_stop ----------------
# Sends SIGTERM first to allow Vault to flush file storage cleanly,
# then SIGKILL after 2s for any process that did not exit.
cmd_stop() {
  local pids
  pids="$(pgrep -f '/tmp/vault-lab-.*/vault.hcl' || true)"

  if [ -n "$pids" ]; then
    echo "$pids" | xargs -r kill -15 || true
    sleep 2
    echo "$pids" | xargs -r kill -9 2>/dev/null || true
  fi

  rm -rf /tmp/vault-lab-* || true
  rm -f "$STATE_FILE"     || true
  log "Lab destroyed"
}

# ---------------- Main ----------------
case "${1:-}" in
  start)     cmd_start ;;
  restart)   cmd_restart ;;
  bootstrap) cmd_bootstrap ;;
  status)    cmd_status ;;
  env)       cmd_env ;;
  stop)      cmd_stop ;;
  -h|--help|"")
    sed -n '/^# ==========================================================/,/^# ==========================================================/p' "$0" \
      | sed '1d;$d;s/^# \{0,1\}//'
    ;;
  *) fatal "Unknown command" ;;
esac