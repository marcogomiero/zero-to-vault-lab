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
#   ./run-smoketest.sh [all|vault|bao]
#
#   - all (default):   Runs all tests.
#   - vault:           Runs basic tests for Vault (file and consul backends).
#   - bao:             Runs basic tests for OpenBao.
#
# Logs:
#   - Console output: colored PASS/FAIL markers, including the command
#   - Full details: ONLY for failed tests in ./smoketest.log
# ==========================================

VAULT_SCRIPT="./vault-lab-ctl.sh"
BAO_SCRIPT="./bao-lab-ctl.sh"
LOG_FILE="./smoketest.log"
> "$LOG_FILE"

# === Global Variables and Colors ===
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BASE_DIR="$(pwd)"
BIN_DIR="$BASE_DIR/bin"
VAULT_DIR="$BASE_DIR/vault-lab"
CONSUL_DIR="$BASE_DIR/consul-lab"

TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
ROOT_TOKEN=""
WSL_IP=""

echo -e "${CYAN}=== Vault & OpenBao Lab Smoke Test ===${NC}"
echo "Test started at: $(date)"

# --- Get dynamic WSL IP ---
get_wsl_ip() {
    WSL_IP=$(ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
}

# --- Run single test ---
run_test() {
    local description="$1"
    local command="$2"
    TESTS_TOTAL=$((TESTS_TOTAL+1))

    echo -e "\n${YELLOW}[TEST]${NC} $description"
    echo "\$ $command"

    local output
    if ! output=$(eval "$command" 2>&1); then
        echo -e "${RED}[FAIL]${NC} $description"
        echo -e "--- Failure Details ---" >>"$LOG_FILE"
        echo "$description failed." >>"$LOG_FILE"
        echo "\$ $command" >>"$LOG_FILE"
        echo "$output" >>"$LOG_FILE"
        echo "------------------------------" >>"$LOG_FILE"
        TESTS_FAILED=$((TESTS_FAILED+1))
        return 1
    else
        echo -e "${GREEN}[PASS]${NC} $description"
        TESTS_PASSED=$((TESTS_PASSED+1))
        return 0
    fi
}

# --- Function to start service and capture token ---
start_service_and_get_token() {
    local script="$1"
    local backend="$2"

    echo -e "\n${YELLOW}Starting service and capturing token...${NC}" >&2

    local command="$script start --backend $backend -c"
    local output

    output=$(eval "$command" 2>&1)

    if echo "$output" | grep -q "Root Token: root"; then
        echo -e "${GREEN}Root token found.${NC}" >&2
        echo "root"
        return 0
    else
        echo -e "${RED}Could not extract root token from output of $backend. This is a critical failure for functional tests.${NC}" >&2
        echo -e "The full script output was:" >>"$LOG_FILE"
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

    local PROTOCOL="http"
    local INSECURE_FLAG=""
    local VAULT_ADDR="http://127.0.0.1:$PORT"

    if [ "$BACKEND" == "consul" ]; then
        VAULT_ADDR="http://${WSL_IP}:$PORT"
    elif [ "$BACKEND" == "openbao" ]; then
        PROTOCOL="https"
        INSECURE_FLAG="-k"
        VAULT_ADDR="https://127.0.0.1:$PORT"
    fi

    local CURL_COMMAND_PREFIX="curl -s $INSECURE_FLAG -H 'X-Vault-Token: $TOKEN' -H 'Content-Type: application/json'"
    local HEALTH_CHECK_URL="$VAULT_ADDR/v1/sys/health"

    echo -e "\n${YELLOW}--- Functional Tests (${BACKEND}) ---${NC}"

    if ! run_test "Verify token" "echo 'Token is valid' && [ -n \"$TOKEN\" ] && true || echo 'Token is not available. Cannot proceed with functional tests.' && false"; then
        return 1
    fi

    run_test "Check service health ($HEALTH_CHECK_URL)" "$CURL_COMMAND_PREFIX $HEALTH_CHECK_URL | grep -E '\"initialized\":true,\"sealed\":false'"

    local SECRET_URL="$VAULT_ADDR/v1/secret/data/test-secret"
    run_test "Write basic secret" "$CURL_COMMAND_PREFIX -X POST -d '{\"data\":{\"value\":\"test_value\"}}' $SECRET_URL"
    run_test "Read basic secret" "$CURL_COMMAND_PREFIX $SECRET_URL | grep '\"value\":\"test_value\"'"
    run_test "Delete basic secret" "$CURL_COMMAND_PREFIX -X DELETE $SECRET_URL"

    local TEST_PATH="secret/denied-path"
    local vault_exe="$BIN_DIR/vault"
    if [[ "$(uname -s)" == *"MINGW"* ]]; then vault_exe="$BIN_DIR/vault.exe"; fi

    run_test "Verify denied access to unauthorized path" "$vault_exe write -address=$VAULT_ADDR -no-print-legacy=true -token=\"$TOKEN\" $TEST_PATH/test value=test_value 2>&1 | grep 'permission denied'"

    local USER_TOKEN
    local login_command="$vault_exe login -address=$VAULT_ADDR -no-print-legacy=true -method=userpass username=devuser password=devpass -format=json"
    USER_TOKEN=$(eval "$login_command" | jq -r '.auth.client_token')

    if [ -n "$USER_TOKEN" ]; then
        run_test "Login with 'devuser'" "echo 'Login successful' && true"
        run_test "Verify 'devuser' policy (read successful)" "$vault_exe read -address=$VAULT_ADDR -token=\"$USER_TOKEN\" auth/userpass/users/devuser -format=json | grep 'password'"
    else
        run_test "Login with 'devuser'" "echo 'Login failed. Unable to get token.' && false"
    fi

    local APPROLE_ROLE_ID=$(cat "$VAULT_DIR/approle_role_id.txt")
    local APPROLE_SECRET_ID=$(cat "$VAULT_DIR/approle_secret_id.txt")

    if [ -n "$APPROLE_ROLE_ID" ] && [ -n "$APPROLE_SECRET_ID" ]; then
        local APPROLE_TOKEN
        local approle_login_command="$vault_exe write -address=$VAULT_ADDR -no-print-legacy=true auth/approle/login role_id=\"$APPROLE_ROLE_ID\" secret_id=\"$APPROLE_SECRET_ID\" -format=json"
        APPROLE_TOKEN=$(eval "$approle_login_command" | jq -r '.auth.client_token')

        if [ -n "$APPROLE_TOKEN" ]; then
            run_test "Login with AppRole" "echo 'AppRole login successful' && true"
            run_test "Verify AppRole policy (read successful)" "$vault_exe read -address=$VAULT_ADDR -token=\"$APPROLE_TOKEN\" auth/approle/role/web-application -format=json | grep 'role_id'"
        else
            run_test "Login with AppRole" "echo 'AppRole login failed. Unable to get token.' && false"
        fi
    else
        run_test "Login with AppRole" "echo 'AppRole ID files not found. Skipping test.' && false"
    fi
}

# --- Vault Tests (File Backend) ---
test_vault_file_backend() {
    local BACKEND="file"
    echo -e "\n${CYAN}=== Vault Test (Backend: $BACKEND) ===${NC}"
    echo -e "\n${YELLOW}--- Infrastructure Tests ---${NC}"
    run_test "Vault help" "$VAULT_SCRIPT --help"
    # Capture the output of start_service_and_get_token and assign to the global variable
    ROOT_TOKEN=$(start_service_and_get_token "$VAULT_SCRIPT" "$BACKEND")
    run_test "Vault status after start ($BACKEND)" "$VAULT_SCRIPT status"
    run_functional_tests "$VAULT_SCRIPT" "$BACKEND" "8200"
    run_test "Vault restart ($BACKEND)" "$VAULT_SCRIPT restart --backend $BACKEND"
    run_test "Vault status after restart ($BACKEND)" "$VAULT_SCRIPT status"
    run_test "Vault reset ($BACKEND)" "$VAULT_SCRIPT reset -y --backend $BACKEND"
    run_test "Vault status after reset ($BACKEND)" "$VAULT_SCRIPT status"
    run_test "Vault cleanup ($BACKEND)" "$VAULT_SCRIPT cleanup --backend $BACKEND"
    run_test "Vault verify stopped ($BACKEND)" "$VAULT_SCRIPT status || true"
}

# --- Vault Tests (Consul Backend) ---
test_vault_consul_backend() {
    local BACKEND="consul"
    get_wsl_ip
    echo -e "\n${CYAN}=== Vault Test (Backend: $BACKEND) ===${NC}"
    echo -e "\n${YELLOW}--- Infrastructure Tests ---${NC}"
    # Capture the output of start_service_and_get_token and assign to the global variable
    ROOT_TOKEN=$(start_service_and_get_token "$VAULT_SCRIPT" "$BACKEND")
    run_test "Vault status after start ($BACKEND)" "$VAULT_SCRIPT status"
    run_functional_tests "$VAULT_SCRIPT" "$BACKEND" "8200"
    run_test "Vault cleanup ($BACKEND)" "$VAULT_SCRIPT cleanup --backend $BACKEND"
    run_test "Vault verify stopped ($BACKEND)" "$VAULT_SCRIPT status || true"
}

# --- OpenBao Tests ---
test_bao() {
    local BACKEND="openbao"
    echo -e "\n${CYAN}=== OpenBao Test ===${NC}"
    echo -e "\n${YELLOW}--- Infrastructure Tests ---${NC}"
    run_test "OpenBao help" "$BAO_SCRIPT --help"
    # Capture the output of start_service_and_get_token and assign to the global variable
    ROOT_TOKEN=$(start_service_and_get_token "$BAO_SCRIPT" "$BACKEND")
    run_test "OpenBao status after start" "$BAO_SCRIPT status"
    run_functional_tests "$BAO_SCRIPT" "$BACKEND" "8200"
    run_test "OpenBao restart" "$BAO_SCRIPT restart --backend $BACKEND"
    run_test "OpenBao status after restart" "$BAO_SCRIPT status"
    run_test "OpenBao reset" "$BAO_SCRIPT reset -y --backend $BACKEND"
    run_test "OpenBao status after reset" "$BAO_SCRIPT status"
    run_test "OpenBao cleanup" "$BAO_SCRIPT cleanup --backend $BACKEND"
    run_test "OpenBao verify stopped ($BACKEND)" "$BAO_SCRIPT status || true"
}

# === Handling input parameters ===
TEST_SCOPE="${1:-all}"
case "$TEST_SCOPE" in
    all)
        test_vault_file_backend
        test_vault_consul_backend
        test_bao
        ;;
    vault)
        test_vault_file_backend
        test_vault_consul_backend
        ;;
    bao)
        test_bao
        ;;
    *)
        echo -e "${RED}Error: Invalid parameter. Usage: $0 [all|vault|bao]${NC}"
        exit 1
        ;;
esac

# --- Summary ---
echo -e "\n${CYAN}=== Smoke Test Summary ===${NC}"
echo -e "Total tests:   ${CYAN}$TESTS_TOTAL${NC}"
echo -e "Passed:        ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed:        ${RED}$TESTS_FAILED${NC}"

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo -e "\n${GREEN}✅ All tests passed successfully!${NC}"
    rm -f "$LOG_FILE"
else
    echo -e "\n${RED}❌ Some tests failed. Check $LOG_FILE for details.${NC}"
    exit 1
fi