#!/bin/bash
# smoke-tests.sh - run all sanity checks for dev.sh Vault lab helper
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_SH="$SCRIPT_DIR/dev.sh"
VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_ADDR

TESTS=()
PASSES=0
FAILS=0

run_test() {
  local name="$1"; shift
  echo -n "[TEST] $name ... "
  if "$@" >/dev/null 2>&1; then
    echo "PASS"
    TESTS+=("✔ $name")
    ((PASSES++))
  else
    echo "FAIL"
    TESTS+=("✘ $name")
    ((FAILS++))
  fi
}

# Cleanup iniziale
$DEV_SH cleanup >/dev/null 2>&1 || true

# --- File backend tests ---
run_test "start lab (file backend)"         $DEV_SH --backend file start
run_test "status shows unsealed"            bash -c "$DEV_SH status | grep -q 'UNSEALED'"
run_test "userpass login works"             bash -c "vault login -method=userpass username=devuser password=devpass >/dev/null"
run_test "kv put/get secret/test-secret"    bash -c "vault kv put secret/test-secret foo=bar && vault kv get -field=foo secret/test-secret | grep -q bar"
run_test "kv put/get kv/test-secret"        bash -c "vault kv put kv/test-secret fizz=buzz && vault kv get -field=fizz kv/test-secret | grep -q buzz"
run_test "pki secrets engine enabled"       bash -c "vault secrets list -format=json | jq -e 'has(\"pki/\")'"
run_test "audit device enabled"             bash -c "vault audit list -format=json | jq -e 'has(\"file/\")'"
run_test "approle role-id file exists"      bash -c "test -s vault-lab/approle_role_id.txt"
run_test "approle secret-id file exists"    bash -c "test -s vault-lab/approle_secret_id.txt"
run_test "stop lab (file backend)"          $DEV_SH stop

# --- Consul backend tests ---
run_test "reset lab (consul backend)"       $DEV_SH --backend consul reset
run_test "status shows consul running"      bash -c "$DEV_SH status | grep -q Consul"
run_test "approle login with role+secret"   bash -c "vault write -field=token auth/approle/login role_id=$(cat vault-lab/approle_role_id.txt) secret_id=$(cat vault-lab/approle_secret_id.txt)"
run_test "restart lab (consul backend)"     $DEV_SH restart
run_test "status shows unsealed after restart" bash -c "$DEV_SH status | grep -q 'UNSEALED'"
run_test "stop lab (consul backend)"        $DEV_SH stop
run_test "cleanup lab"                      $DEV_SH cleanup

# --- Summary ---
echo
echo "==== Smoke Test Report ===="
for t in "${TESTS[@]}"; do echo "  $t"; done
echo
echo "Total: $((PASSES+FAILS)), Passed: $PASSES, Failed: $FAILS"

[ $FAILS -eq 0 ] || exit 1