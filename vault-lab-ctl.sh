#!/usr/bin/env bash
set -euo pipefail
set -E

trap 'echo -e "\033[0;31m[ERROR]\033[0m Script aborted at line $LINENO" >&2' ERR

# ==========================================================
# Vault Lab – Ephemeral (FINAL, safe auto-update + fallback)
#
# PURPOSE
#   Spin up a fully ephemeral local HashiCorp Vault lab.
#
# UPDATE POLICY
#   - Check latest STABLE Vault version (no rc/beta)
#   - Try to download it
#   - On any failure, fallback to local binary
#
# USAGE
#   ./vault-lab-ctl.sh <command>
#
# COMMANDS
#   start        Start Vault if not running
#   restart     Destroy and recreate Vault
#   bootstrap   Configure demo engines, auths and data
#   status      Show Vault status (root token)
#   env         Print env exports (manual)
#   stop        Destroy the lab
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

is_vault_running() {
  ss -ltn "( sport = :$VAULT_PORT )" 2>/dev/null | grep -q ":$VAULT_PORT"
}

wait_for_port_free() {
  for _ in {1..10}; do
    if ! is_vault_running; then
      return
    fi
    sleep 1
  done
  fatal "Port $VAULT_PORT still in use"
}

# ---------------- Version handling ----------------
get_latest_stable_vault_version() {
  curl -fsSL https://releases.hashicorp.com/vault/index.json \
  | jq -r '.versions | keys[]' \
  | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
  | sort -V \
  | tail -1
}

get_local_vault_version() {
  local exe="$1"
  [ -x "$exe" ] || return 1
  "$exe" --version | awk 'NR==1{print $2}' | sed 's/^v//'
}

try_download_vault() {
  local version="$1"
  local exe="$2"
  local tmpdir

  log "Attempting to download Vault $version"

  tmpdir="$(mktemp -d)"

  if ! curl -fsSL \
      "https://releases.hashicorp.com/vault/${version}/vault_${version}_linux_amd64.zip" \
      -o "$tmpdir/vault.zip"; then
    warn "Download failed"
    rm -rf "$tmpdir"
    return 1
  fi

  if ! unzip -oq "$tmpdir/vault.zip" -d "$tmpdir"; then
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
  runtime_dir="$(cat "$STATE_FILE")"

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

wait_for_vault() {
  log "Waiting for Vault API..."
  for _ in {1..20}; do
    curl -s "$VAULT_ADDR/v1/sys/health" >/dev/null && return
    sleep 1
  done
  fatal "Vault did not start"
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
ui = true
EOF

  "$(get_exe vault)" server -config="$VAULT_DIR/vault.hcl" \
    >"$VAULT_DIR/vault.log" 2>&1 &

  wait_for_vault

  out=$("$(get_exe vault)" operator init -key-shares=1 -key-threshold=1 -format=json)
  echo "$out" | jq -r '.root_token' > "$VAULT_DIR/root.token"
  echo "$out" | jq -r '.unseal_keys_b64[0]' > "$VAULT_DIR/unseal.key"

  "$(get_exe vault)" operator unseal "$(cat "$VAULT_DIR/unseal.key")"

  log "Vault ready"
  print_access_info "$(cat "$VAULT_DIR/root.token")"
}

# ---------------- Commands ----------------
cmd_start() {
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

  log "Bootstrapping Vault"

  vault secrets enable -path=kv kv-v2 2>/dev/null || true
  vault secrets enable transit 2>/dev/null || true
  vault auth enable approle 2>/dev/null || true
  vault auth enable userpass 2>/dev/null || true

  vault policy write app-read - <<EOF
path "kv/data/*" {
  capabilities = ["read"]
}
EOF

  vault policy write user-demo - <<EOF
path "kv/data/demo/*" {
  capabilities = ["read", "create", "update"]
}
path "sys/health" {
  capabilities = ["read"]
}
EOF

  vault write auth/approle/role/demo-app token_policies="app-read" token_ttl=1h
  vault write auth/userpass/users/demo password="demo" policies="user-demo"

  vault kv put kv/demo/config app="demo" env="lab"
  vault kv put kv/demo/credentials username="demo" password="secret"

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
  cat <<EOF
export VAULT_ADDR=$VAULT_ADDR
export VAULT_TOKEN=$token
EOF
}

cmd_stop() {
  pgrep -f '/tmp/vault-lab-.*/vault.hcl' | xargs -r kill -9 || true
  rm -rf /tmp/vault-lab-* || true
  rm -f "$STATE_FILE" || true
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
