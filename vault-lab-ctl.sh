#!/usr/bin/env bash
set -euo pipefail
set -E

trap 'echo -e "\033[0;31m[ERROR]\033[0m Script aborted at line $LINENO" >&2' ERR

# ==========================================================
# Vault Lab – Ephemeral v3.3
#
# PURPOSE
#   Spin up a fully ephemeral local HashiCorp Vault lab.
#   Deterministic lifecycle, opinionated bootstrap.
#
# USAGE
#   ./vault-lab-ctl-dev.sh <command>
#
# COMMANDS
#   start
#       Start a new Vault lab if none is running.
#
#   restart
#       Stop any existing lab and start a fresh one.
#
#   bootstrap
#       Opinionated, idempotent Vault bootstrap:
#         - kv-v2 engine
#         - transit engine
#         - approle auth
#         - userpass auth
#         - demo policies, roles and users
#
#   status
#       Show Vault status.
#
#   shell
#       Open an interactive shell with Vault env vars set.
#
#   stop
#       Stop Vault and remove all runtime data.
#
#   -h, --help
#       Show this help message.
#
# VERSIONING
#   Vault version pinned to major.minor.patch.
#   Default: 1.21.2
#
#   Override with:
#     VAULT_VERSION=1.21.3 ./vault-lab-ctl-dev.sh start
#
# NOTES
#   - TLS disabled (lab only)
#   - All data is ephemeral under /tmp/vault-lab-*
#   - Root token exists only for lab lifetime
#   - WSL-safe
# ==========================================================

SCRIPT_DIR="$(pwd)"
BIN_DIR="$SCRIPT_DIR/bin"

VAULT_ADDR="http://127.0.0.1:8200"
VAULT_PORT="8200"
VAULT_VERSION="${VAULT_VERSION:-1.21.2}"

# ---------------- Logging ----------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
fatal(){ echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ---------------- Helpers ----------------
get_exe() { echo "$BIN_DIR/$1"; }

print_access_info() {
  echo
  echo "=================================================="
  echo "Vault Lab ready"
  echo
  echo "Vault address:"
  echo "  $VAULT_ADDR"
  echo
  echo "Vault token:"
  echo "  $VAULT_TOKEN"
  echo
  echo "Userpass login example:"
  echo "  vault login -method=userpass username=demo password=demo"
  echo "=================================================="
  echo
}

load_access() {
  local token_file
  token_file=$(ls -1 /tmp/vault-lab-*/root.token 2>/dev/null | head -1 || true)

  [ -f "$token_file" ] || fatal "No Vault token found. Is the lab running?"

  export VAULT_ADDR="http://127.0.0.1:8200"
  export VAULT_TOKEN
  VAULT_TOKEN="$(cat "$token_file")"
}

wait_for_port_free() {
  for _ in {1..10}; do
    if ! ss -ltn "( sport = :$VAULT_PORT )" 2>/dev/null | grep -q ":$VAULT_PORT"; then
      return
    fi
    sleep 1
  done
  fatal "Port $VAULT_PORT still in use"
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
  ROOT_TOKEN_FILE="$RUNTIME_DIR/root.token"
  mkdir -p "$VAULT_DIR"
}

# ---------------- Vault ----------------
wait_for_vault() {
  log "Waiting for Vault API..."
  for _ in {1..20}; do
    curl -s "$VAULT_ADDR/v1/sys/health" >/dev/null && return
    sleep 1
  done
  fatal "Vault did not start"
}

start_vault() {
  download_vault
  export VAULT_ADDR

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
  echo "$out" | jq -r '.root_token' > "$ROOT_TOKEN_FILE"
  echo "$out" | jq -r '.unseal_keys_b64[0]' > "$VAULT_DIR/unseal.key"

  "$(get_exe vault)" operator unseal "$(cat "$VAULT_DIR/unseal.key")"

  export VAULT_TOKEN
  VAULT_TOKEN="$(cat "$ROOT_TOKEN_FILE")"

  log "Vault ready (version $VAULT_VERSION)"
  print_access_info
}

# ---------------- Bootstrap ----------------
cmd_bootstrap() {
  load_access
  log "Bootstrapping Vault"

  vault secrets list | grep -q '^kv/'       || vault secrets enable -path=kv kv-v2
  vault secrets list | grep -q '^transit/'  || vault secrets enable transit
  vault auth list    | grep -q '^approle/'  || vault auth enable approle
  vault auth list    | grep -q '^userpass/' || vault auth enable userpass

  vault policy read app-read >/dev/null 2>&1 || vault policy write app-read - <<EOF
path "kv/data/*" {
  capabilities = ["read"]
}
EOF

  vault policy read user-demo >/dev/null 2>&1 || vault policy write user-demo - <<EOF
path "kv/data/demo/*" {
  capabilities = ["read", "create", "update"]
}

path "sys/health" {
  capabilities = ["read"]
}
EOF

  vault read auth/approle/role/demo-app >/dev/null 2>&1 || \
    vault write auth/approle/role/demo-app token_policies="app-read" token_ttl=1h

  vault read auth/userpass/users/demo >/dev/null 2>&1 || \
    vault write auth/userpass/users/demo password="demo" policies="user-demo"

  vault kv put kv/demo/config app="demo" env="lab"
  vault kv put kv/demo/credentials username="demo" password="secret"

  log "Bootstrap completed"
  print_access_info
}

# ---------------- Stop / Restart ----------------
cmd_stop() {
  pgrep -f '/tmp/vault-lab-.*/vault.hcl' | xargs -r kill -9 || true
  wait_for_port_free || true
  rm -rf /tmp/vault-lab-* || true
  log "Lab destroyed"
}

# ---------------- Commands ----------------
cmd_start() {
  cmd_stop || true
  log "Starting Vault lab"
  create_runtime
  start_vault
}

cmd_restart() { cmd_start; }
cmd_status()  { load_access; "$(get_exe vault)" status; }
cmd_shell()   { load_access; exec "${SHELL:-bash}" -i; }

# ---------------- Help ----------------
show_help() {
  sed -n '/^# ==========================================================/,/^# ==========================================================/p' "$0" \
    | sed '1d;$d;s/^# \{0,1\}//'
}

# ---------------- Main ----------------
case "${1:-}" in
  start)     cmd_start ;;
  restart)   cmd_restart ;;
  bootstrap) cmd_bootstrap ;;
  status)    cmd_status ;;
  shell)     cmd_shell ;;
  stop)      cmd_stop ;;
  -h|--help|"") show_help ;;
  *) fatal "Unknown command" ;;
esac