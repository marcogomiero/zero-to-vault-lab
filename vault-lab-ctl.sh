#!/usr/bin/env bash
set -euo pipefail
set -E

trap 'echo -e "\033[0;31m[ERROR]\033[0m Script aborted at line $LINENO" >&2' ERR

# ==========================================================
# Vault Lab – Ephemeral (FINAL, stateful & deterministic)
#
# PURPOSE
#   Spin up a fully ephemeral local HashiCorp Vault lab.
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
VAULT_VERSION="${VAULT_VERSION:-1.21.2}"

STATE_FILE="/tmp/vault-lab-current"

# ---------------- Logging ----------------
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log()   { echo -e "${GREEN}[INFO]${NC} $*"; }
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

# ---------------- Download ----------------
download_vault() {
  mkdir -p "$BIN_DIR"
  local exe
  exe=$(get_exe vault)

  if [ -x "$exe" ]; then
    local current
    current=$("$exe" --version | awk 'NR==1{print $2}' | sed 's/^v//')
    [ "$current" = "$VAULT_VERSION" ] && return
  fi

  log "Downloading Vault $VAULT_VERSION"
  curl -fsSL \
    "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip" \
    -o /tmp/vault.zip

  unzip -oq /tmp/vault.zip -d "$BIN_DIR"
  chmod +x "$exe"
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

  log "Vault ready (version $VAULT_VERSION)"
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

  vault secrets list | grep -q '^kv/'       || vault secrets enable -path=kv kv-v2
  vault secrets list | grep -q '^transit/'  || vault secrets enable transit
  vault auth list    | grep -q '^approle/'  || vault auth enable approle
  vault auth list    | grep -q '^userpass/' || vault auth enable userpass

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
