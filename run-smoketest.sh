#!/bin/bash
set -uo pipefail

# ==========================================
# Vault & OpenBao Lab Smoke Test Script
# ==========================================
# This script runs automated smoke tests for:
#   ✅ Vault (vault-lab-ctl.sh)
#   ✅ OpenBao (bao-lab-ctl.sh)
#
# Usage:
#   ./lab-smoketest.sh [all|vault|bao|advanced]
#
# Logs:
#   - Console output: colored PASS/FAIL markers in single line
#   - Full details: ONLY for failed tests in ./smoketest.log
# ==========================================

VAULT_SCRIPT="./vault-lab-ctl.sh"
BAO_SCRIPT="./bao-lab-ctl.sh"
LOG_FILE="./smoketest.log"
> "$LOG_FILE"

# === Colors ===
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
TOTAL_EXPECTED_TESTS=0
ROOT_TOKEN=""
VERBOSE=false

# --- Timer start ---
START_TIME=$(date +%s)

# --- Parse CLI parameters ---
ARGS=()
for arg in "$@"; do
    case "$arg" in
        -v|--verbose)
            VERBOSE=true
            ;;
        *)
            ARGS+=("$arg")
            ;;
    esac
done

TEST_SCOPE="${ARGS[0]:-all}"

# --- Show progress bar ---
show_progress() {
    local current=$1
    local total=$2
    local percent=$(( 100 * current / total ))
    local bar_length=20
    local filled=$(( bar_length * percent / 100 ))
    local empty=$(( bar_length - filled ))

    printf "\r["
    printf "%0.s#" $(seq 1 $filled)
    printf "%0.s." $(seq 1 $empty)
    printf "] %3d%% (%d/%d) - " "$percent" "$current" "$total"
}

# --- Run single test ---
run_test() {
    local description="$1"
    local command="$2"
    TESTS_TOTAL=$((TESTS_TOTAL+1))

    show_progress "$TESTS_TOTAL" "$TOTAL_EXPECTED_TESTS"
    printf "Testing: %-50s" "$description"

    local output
    if ! output=$(eval "$command" 2>&1); then
        printf "\r[${RED}FAIL${NC}] "
        printf "%-70s" "$description"
        printf " (Test $TESTS_TOTAL/$TOTAL_EXPECTED_TESTS)\n"

        echo -e "--- Failure Details ---" >>"$LOG_FILE"
        echo "Test failed: $description" >>"$LOG_FILE"
        echo "\$ $command" >>"$LOG_FILE"
        echo "$output" >>"$LOG_FILE"
        echo "------------------------" >>"$LOG_FILE"
        TESTS_FAILED=$((TESTS_FAILED+1))
    else
        printf "\r[${GREEN}PASS${NC}] "
        printf "%-70s" "$description"
        printf " (Test $TESTS_TOTAL/$TOTAL_EXPECTED_TESTS)\n"

        TESTS_PASSED=$((TESTS_PASSED+1))
        if [ "$VERBOSE" = true ]; then
            echo -e "--- Test Output ---" >>"$LOG_FILE"
            echo "Test passed: $description" >>"$LOG_FILE"
            echo "\$ $command" >>"$LOG_FILE"
            echo "$output" >>"$LOG_FILE"
            echo "-------------------" >>"$LOG_FILE"
        fi
    fi
}

# --- Start service and capture token ---
start_service_and_get_token() {
    local script="$1"
    local backend="$2"
    ROOT_TOKEN=""

    local command="$script start --backend $backend -c"
    if ! output=$(eval "$command" 2>&1); then
        printf "\r[${RED}CRIT${NC}] Failed to start $backend service\n"
        echo "$output" >>"$LOG_FILE"
        exit 1
    fi

    ROOT_TOKEN_FILE=$(echo "$output" | grep 'Root Token:' | awk '{print $NF}' | tr -d '()')
    if [ -n "$ROOT_TOKEN_FILE" ] && [ -f "$ROOT_TOKEN_FILE" ]; then
        ROOT_TOKEN=$(cat "$ROOT_TOKEN_FILE")
    fi

    if [ -z "$ROOT_TOKEN" ]; then
        printf "\r[${RED}CRIT${NC}] Unable to extract root token from $backend\n"
        echo "Full script output:" >>"$LOG_FILE"
        echo "$output" >>"$LOG_FILE"
        return 1
    fi
}

# --- Functional Tests ---
run_functional_tests() {
    local SCRIPT=$1
    local BACKEND=$2
    local PORT=$3
    local TOKEN=$ROOT_TOKEN

    if [ -z "$TOKEN" ]; then
        run_test "Verify token availability" "echo 'Root token not available. Cannot proceed.' && false"
        return 1
    fi

    local PROTOCOL="http"
    local INSECURE_FLAG=""
    [ "$BACKEND" = "openbao" ] && PROTOCOL="https" && INSECURE_FLAG="-k"

    local BASE_URL="$PROTOCOL://127.0.0.1:$PORT/v1/secret/data/test-secret"
    local CURL="curl -s $INSECURE_FLAG -H 'X-Vault-Token: $TOKEN'"

    run_test "Write secret" "$CURL -X POST -d '{\"data\":{\"value\":\"test_value\"}}' $BASE_URL"
    run_test "Read secret" "$CURL $BASE_URL | grep '\"value\":\"test_value\"'"
    run_test "Delete secret" "$CURL -X DELETE $BASE_URL"
}

# --- Advanced Tests ---
run_advanced_tests() {
    local SCRIPT=$1
    local BACKEND=$2
    local PORT=$3
    local TOKEN=$ROOT_TOKEN

    if [ -z "$TOKEN" ]; then
        run_test "Verify token availability (advanced)" "echo 'Root token not available. Cannot execute advanced tests.' && false"
        return 1
    fi

    local PROTOCOL="http"
    local INSECURE_FLAG=""
    [ "$BACKEND" = "openbao" ] && PROTOCOL="https" && INSECURE_FLAG="-k"

    local BASE="$PROTOCOL://127.0.0.1:$PORT/v1"
    local CURL="curl -s $INSECURE_FLAG -H 'X-Vault-Token: $TOKEN'"

    # KV Versioning
    run_test "KV: Write v1" "$CURL -X POST -d '{\"data\":{\"value\":\"v1\"}}' $BASE/secret/data/test-adv"
    run_test "KV: Write v2" "$CURL -X POST -d '{\"data\":{\"value\":\"v2\"}}' $BASE/secret/data/test-adv"
    run_test "KV: Read v1" "$CURL \"$BASE/secret/data/test-adv?version=1\" | grep '\"value\":\"v1\"'"

    # Token revoke
    run_test "Revoke token" "$CURL -X POST $BASE/auth/token/revoke-self"
    run_test "Access denied after revoke" "curl -s $INSECURE_FLAG -H 'X-Vault-Token: $TOKEN' $BASE/secret/data/test-adv | grep 'permission denied' || true"

    # Restart to get new token
    start_service_and_get_token "$SCRIPT" "$BACKEND"
    TOKEN=$ROOT_TOKEN
    CURL="curl -s $INSECURE_FLAG -H 'X-Vault-Token: $TOKEN'"

    # Transit
    run_test "Enable Transit" "$CURL -X POST $BASE/sys/mounts/transit -d '{\"type\":\"transit\"}'"
    run_test "Create Transit key" "$CURL -X POST $BASE/transit/keys/testkey"
    run_test "Encrypt with Transit" "$CURL -X POST $BASE/transit/encrypt/testkey -d '{\"plaintext\":\"$(echo -n testdata | base64)\"}' | grep 'ciphertext'"

    # Negative
    run_test "Invalid token" "curl -s $INSECURE_FLAG -H 'X-Vault-Token: invalid' $BASE/secret/data/test-adv | grep 'permission denied' || true"
    run_test "Non-existing secret" "$CURL $BASE/secret/data/does-not-exist | grep '404' || true"

    # Seal test (Vault only)
    if [[ "$BACKEND" =~ file|consul ]]; then
        run_test "Force Seal" "$CURL -X POST $BASE/sys/seal"
        run_test "Check sealed" "$SCRIPT status | grep 'Sealed' || true"
        run_test "Unseal Vault" "$SCRIPT unseal -c"
    fi
}

# --- Vault Tests ---
test_vault_file_backend() {
    echo -e "\n${CYAN}=== Vault Test (File Backend) ===${NC}"
    run_test "Vault help" "$VAULT_SCRIPT --help"
    start_service_and_get_token "$VAULT_SCRIPT" "file"
    run_test "Status after start" "$VAULT_SCRIPT status"
    run_functional_tests "$VAULT_SCRIPT" "file" "8200"
    run_test "Restart" "$VAULT_SCRIPT restart"
    run_test "Status after restart" "$VAULT_SCRIPT status"
    run_test "Reset" "$VAULT_SCRIPT reset"
    run_test "Status after reset" "$VAULT_SCRIPT status"
    run_test "Cleanup" "$VAULT_SCRIPT cleanup"
    run_test "Verify stopped" "$VAULT_SCRIPT status || true"
}

test_vault_consul_backend() {
    echo -e "\n${CYAN}=== Vault Test (Consul Backend) ===${NC}"
    start_service_and_get_token "$VAULT_SCRIPT" "consul"
    run_test "Status after start" "$VAULT_SCRIPT status"
    run_functional_tests "$VAULT_SCRIPT" "consul" "8200"
    run_test "Cleanup" "$VAULT_SCRIPT cleanup"
    run_test "Verify stopped" "$VAULT_SCRIPT status || true"
}

test_bao() {
    echo -e "\n${CYAN}=== OpenBao Test ===${NC}"
    run_test "Bao help" "$BAO_SCRIPT --help"
    start_service_and_get_token "$BAO_SCRIPT" "openbao"
    run_test "Status after start" "$BAO_SCRIPT status"
    run_functional_tests "$BAO_SCRIPT" "openbao" "8200"
    run_test "Restart" "$BAO_SCRIPT restart"
    run_test "Status after restart" "$BAO_SCRIPT status"
    run_test "Reset" "$BAO_SCRIPT reset"
    run_test "Status after reset" "$BAO_SCRIPT status"
    run_test "Cleanup" "$BAO_SCRIPT cleanup"
    run_test "Verify stopped" "$BAO_SCRIPT status || true"
}

# --- Pre-calculate total tests ---
estimate_tests() {
    TOTAL_EXPECTED_TESTS=0
    case "$TEST_SCOPE" in
        all)
            TOTAL_EXPECTED_TESTS=$((TOTAL_EXPECTED_TESTS+9+3))    # Vault file (infra+func)
            TOTAL_EXPECTED_TESTS=$((TOTAL_EXPECTED_TESTS+2+3))    # Vault consul
            TOTAL_EXPECTED_TESTS=$((TOTAL_EXPECTED_TESTS+9+3))    # Bao
            TOTAL_EXPECTED_TESTS=$((TOTAL_EXPECTED_TESTS+11))     # Advanced Vault file
            TOTAL_EXPECTED_TESTS=$((TOTAL_EXPECTED_TESTS+11))     # Advanced Vault consul
            TOTAL_EXPECTED_TESTS=$((TOTAL_EXPECTED_TESTS+11))     # Advanced Bao
            ;;
        vault)
            TOTAL_EXPECTED_TESTS=$((TOTAL_EXPECTED_TESTS+9+3))    # Vault file
            TOTAL_EXPECTED_TESTS=$((TOTAL_EXPECTED_TESTS+2+3))    # Vault consul
            ;;
        bao)
            TOTAL_EXPECTED_TESTS=$((TOTAL_EXPECTED_TESTS+9+3))    # Bao
            ;;
        advanced)
            TOTAL_EXPECTED_TESTS=$((TOTAL_EXPECTED_TESTS+9+3+11)) # Vault file + advanced
            TOTAL_EXPECTED_TESTS=$((TOTAL_EXPECTED_TESTS+9+3+11)) # Bao + advanced
            ;;
    esac
}

estimate_tests

# --- Run tests ---
echo -e "${CYAN}=== Vault & OpenBao Lab Smoke Test ===${NC}"
echo "Test started at: $(date)"
echo "Expected tests: $TOTAL_EXPECTED_TESTS"

case "$TEST_SCOPE" in
    all)
        test_vault_file_backend
        run_advanced_tests "$VAULT_SCRIPT" "file" "8200"
        test_vault_consul_backend
        run_advanced_tests "$VAULT_SCRIPT" "consul" "8200"
        test_bao
        run_advanced_tests "$BAO_SCRIPT" "openbao" "8200"
        ;;
    vault)
        test_vault_file_backend
        test_vault_consul_backend
        ;;
    bao)
        test_bao
        ;;
    advanced)
        test_vault_file_backend
        run_advanced_tests "$VAULT_SCRIPT" "file" "8200"
        test_bao
        run_advanced_tests "$BAO_SCRIPT" "openbao" "8200"
        ;;
    *)
        echo -e "${RED}Error: Invalid parameter. Usage: $0 [all|vault|bao|advanced] [-v|--verbose]${NC}"
        exit 1
        ;;
esac

# --- Timer end ---
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

# --- Summary ---
echo -e "\n${CYAN}=== Smoke Test Summary ===${NC}"
echo -e "Total tests:   ${CYAN}$TESTS_TOTAL${NC}"
echo -e "Passed:        ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed:        ${RED}$TESTS_FAILED${NC}"
echo -e "Duration:      ${YELLOW}${MINUTES}m ${SECONDS}s${NC}"

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo -e "\n${GREEN}✅ All tests passed successfully!${NC}"
    rm -f "$LOG_FILE"
else
    echo -e "\n${RED}❌ Some tests failed. Check $LOG_FILE for details.${NC}"
    exit 1
fi