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
#   - all (default):   Runs all tests.
#   - vault:           Runs basic tests for Vault (file and consul backends).
#   - bao:             Runs basic tests for OpenBao.
#   - advanced:        Runs advanced tests for Vault (AppRole auth & token renewal).
#
# Logs:
#   - Console output: colored PASS/FAIL markers, including the command
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
ROOT_TOKEN=""

echo -e "${CYAN}=== Vault & OpenBao Lab Smoke Test ===${NC}"
echo "Test started at: $(date)"

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
        echo -e "--- Dettagli del Fallimento ---" >>"$LOG_FILE"
        echo "$description fallito." >>"$LOG_FILE"
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

# --- Funzione per avviare il servizio e catturare il token ---
start_service_and_get_token() {
    local script="$1"
    local backend="$2"

    ROOT_TOKEN=""

    local description="Start $backend e cattura token"
    local command="$script start --backend $backend -c"

    if ! output=$(eval "$command" 2>&1); then
        echo -e "${RED}Errore critico nello start del servizio $backend. Uscita.${NC}"
        echo "$output" >>"$LOG_FILE"
        exit 1
    fi

    ROOT_TOKEN_FILE=$(echo "$output" | grep 'Root Token:' | awk '{print $NF}' | tr -d '()')

    if [ -n "$ROOT_TOKEN_FILE" ] && [ -f "$ROOT_TOKEN_FILE" ]; then
        ROOT_TOKEN=$(cat "$ROOT_TOKEN_FILE")
    fi

    if [ -z "$ROOT_TOKEN" ]; then
        echo -e "${RED}Impossibile estrarre il token di root dall'output di $backend.${NC}"
        echo -e "L'output completo dello script era:" >>"$LOG_FILE"
        echo "$output" >>"$LOG_FILE"
        return 1
    fi

    return 0
}

# --- Functional Tests ---
run_functional_tests() {
    local SCRIPT=$1
    local BACKEND=$2
    local PORT=$3
    local TOKEN=$ROOT_TOKEN

    echo -e "\n${YELLOW}--- Funzionali ---${NC}"

    if [ -z "$TOKEN" ]; then
        run_test "Verifica token" "echo 'Token non disponibile. Impossibile proseguire con i test funzionali.' && false"
        return 1
    fi

    local PROTOCOL="http"
    local INSECURE_FLAG=""
    if [ "$BACKEND" = "openbao" ]; then
        PROTOCOL="https"
        INSECURE_FLAG="-k"
    fi

    local BASE_URL="$PROTOCOL://127.0.0.1:$PORT/v1/secret/data/test-secret"
    local CURL_COMMAND_PREFIX="curl -s $INSECURE_FLAG -H 'X-Vault-Token: $TOKEN'"

    run_test "Scrivi segreto (backend: $BACKEND)" "$CURL_COMMAND_PREFIX -X POST -d '{\"data\":{\"value\":\"test_value\"}}' $BASE_URL"

    run_test "Leggi segreto e verifica (backend: $BACKEND)" "$CURL_COMMAND_PREFIX $BASE_URL | grep '\"value\":\"test_value\"'"

    run_test "Elimina segreto (backend: $BACKEND)" "$CURL_COMMAND_PREFIX -X DELETE $BASE_URL"
}

# --- Vault Tests (File Backend) ---
test_vault_file_backend() {
    local BACKEND="file"
    echo -e "\n${CYAN}=== Vault Test (Backend: $BACKEND) ===${NC}"
    echo -e "\n${YELLOW}--- Infrastrutturali ---${NC}"
    run_test "Vault help" "$VAULT_SCRIPT --help"
    start_service_and_get_token "$VAULT_SCRIPT" "$BACKEND"
    run_test "Vault status after start ($BACKEND)" "$VAULT_SCRIPT status"
    run_functional_tests "$VAULT_SCRIPT" "$BACKEND" "8200"
    run_test "Vault restart ($BACKEND)" "$VAULT_SCRIPT restart"
    run_test "Vault status after restart ($BACKEND)" "$VAULT_SCRIPT status"
    run_test "Vault reset ($BACKEND)" "$VAULT_SCRIPT reset"
    run_test "Vault status after reset ($BACKEND)" "$VAULT_SCRIPT status"
    run_test "Vault cleanup ($BACKEND)" "$VAULT_SCRIPT cleanup"
    run_test "Vault verify stopped ($BACKEND)" "$VAULT_SCRIPT status || true"
}

# --- Vault Tests (Consul Backend) ---
test_vault_consul_backend() {
    local BACKEND="consul"
    echo -e "\n${CYAN}=== Vault Test (Backend: $BACKEND) ===${NC}"
    echo -e "\n${YELLOW}--- Infrastrutturali ---${NC}"
    start_service_and_get_token "$VAULT_SCRIPT" "$BACKEND"
    run_test "Vault status after start ($BACKEND)" "$VAULT_SCRIPT status"
    run_functional_tests "$VAULT_SCRIPT" "$BACKEND" "8200"
    run_test "Vault cleanup ($BACKEND)" "$VAULT_SCRIPT cleanup"
    run_test "Vault verify stopped ($BACKEND)" "$VAULT_SCRIPT status || true"
}

# --- OpenBao Tests ---
test_bao() {
    local BACKEND="openbao"
    echo -e "\n${CYAN}=== OpenBao Test ===${NC}"
    echo -e "\n${YELLOW}--- Infrastrutturali ---${NC}"
    run_test "OpenBao help" "$BAO_SCRIPT --help"
    start_service_and_get_token "$BAO_SCRIPT" "$BACKEND"
    run_test "OpenBao status after start" "$BAO_SCRIPT status"
    run_functional_tests "$BAO_SCRIPT" "$BACKEND" "8200"
    run_test "OpenBao restart" "$BAO_SCRIPT restart"
    run_test "OpenBao status after restart" "$BAO_SCRIPT status"
    run_test "OpenBao reset" "$BAO_SCRIPT reset"
    run_test "OpenBao status after reset" "$BAO_SCRIPT status"
    run_test "OpenBao cleanup" "$BAO_SCRIPT cleanup"
    run_test "OpenBao verify stopped ($BACKEND)" "$BAO_SCRIPT status || true"
}

# --- Advanced Vault Tests (AppRole) ---
test_advanced_vault() {
    echo -e "\n${CYAN}=== Vault Advanced Tests (AppRole) ===${NC}"

    # 1. Start Vault (file backend) for the advanced tests
    start_service_and_get_token "$VAULT_SCRIPT" "file"
    if [ -z "$ROOT_TOKEN" ]; then
        echo -e "${RED}Impossibile avviare Vault per i test avanzati. Uscita.${NC}"
        exit 1
    fi

    local PORT="8200"
    local PROTOCOL="http"
    local VAULT_ADDR="$PROTOCOL://127.0.0.1:$PORT"
    local CURL_ROOT="curl -s -H 'X-Vault-Token: $ROOT_TOKEN'"

    echo -e "\n${YELLOW}--- Test AppRole ---${NC}"

    run_test "Abilita AppRole" "$CURL_ROOT -X POST -d '{\"type\":\"approle\"}' $VAULT_ADDR/v1/sys/auth/approle"

    run_test "Crea policy 'test-approle-policy'" "$CURL_ROOT -X POST -d '{\"policy\":\"path \\\"secret/*\\\" {capabilities = [\\\"read\\\"]}\"}' $VAULT_ADDR/v1/sys/policy/test-approle-policy"

    run_test "Crea AppRole 'test-approle'" "$CURL_ROOT -X POST -d '{\"policies\":[\"test-approle-policy\"]}' $VAULT_ADDR/v1/auth/approle/role/test-approle"

    # d. Ottieni il Role ID
    local ROLE_ID=""
    # --- AGGIUNGI QUI QUESTA RIGA PER DEBUGGARE ---
    log_info "DEBUG: Output raw del Role ID: $($CURL_ROOT $VAULT_ADDR/v1/auth/approle/role/test-approle/role-id)"
    # ----------------------------------------------
    ROLE_ID=$($CURL_ROOT $VAULT_ADDR/v1/auth/approle/role/test-approle/role-id | jq -r '.data.role_id')
    if [ -z "$ROLE_ID" ] || [ "$ROLE_ID" == "null" ]; then
        echo -e "${RED}Impossibile ottenere il Role ID (valore nullo). Uscita dai test avanzati.${NC}"
        exit 1
    fi
    run_test "Verifica Role ID" "echo \"Role ID è: $ROLE_ID\""

    local SECRET_ID=""
    SECRET_ID=$($CURL_ROOT -X POST $VAULT_ADDR/v1/auth/approle/role/test-approle/secret-id | jq -r '.data.secret_id')
    if [ -z "$SECRET_ID" ] || [ "$SECRET_ID" == "null" ]; then
        echo -e "${RED}Impossibile ottenere il Secret ID (valore nullo). Uscita dai test avanzati.${NC}"
        exit 1
    fi
    run_test "Verifica Secret ID" "echo \"Secret ID è: $SECRET_ID\""

    local APP_TOKEN=""
    local LOGIN_PAYLOAD="{\"role_id\":\"$ROLE_ID\",\"secret_id\":\"$SECRET_ID\"}"
    APP_TOKEN=$($CURL_ROOT -X POST -d "$LOGIN_PAYLOAD" $VAULT_ADDR/v1/auth/approle/login | jq -r '.auth.client_token')
    if [ -z "$APP_TOKEN" ] || [ "$APP_TOKEN" == "null" ]; then
        echo -e "${RED}Login con AppRole fallito. Uscita dai test avanzati.${NC}"
        exit 1
    fi
    run_test "Verifica token AppRole" "echo \"Token AppRole è: $APP_TOKEN\""

    echo -e "\n${YELLOW}--- Test funzionalità con token AppRole ---${NC}"
    local CURL_APP="curl -s -H 'X-Vault-Token: $APP_TOKEN'"

    # g. Verifica che il token AppRole ha solo permessi di lettura
    local output_app_token=""
    run_test "Scrivi segreto (dovrebbe fallire)" "output_app_token=$($CURL_APP -X POST -d '{\"data\":{\"value\":\"test_value_app\"}}' $VAULT_ADDR/v1/secret/data/test-secret-app 2>&1 | grep 'permission denied' | wc -l)"

    if [[ "$(eval echo "$output_app_token")" -eq 1 ]]; then
        echo -e "${GREEN}[PASS] Scrivi segreto (come atteso, permesso negato)${NC}"
        TESTS_PASSED=$((TESTS_PASSED+1))
    else
        echo -e "${RED}[FAIL] Scrivi segreto (il comando avrebbe dovuto fallire, ma è riuscito)${NC}"
        TESTS_FAILED=$((TESTS_FAILED+1))
    fi
    TESTS_TOTAL=$((TESTS_TOTAL+1))

    run_test "Leggi segreto con AppRole" "$CURL_APP $VAULT_ADDR/v1/secret/data/test-secret | grep '\"data\"'"

    echo -e "\n${YELLOW}--- Pulizia dei test avanzati ---${NC}"

    # i. Disabilita il metodo di autenticazione AppRole
    run_test "Disabilita AppRole" "$CURL_ROOT -X DELETE $VAULT_ADDR/v1/sys/auth/approle"

    # j. Elimina la policy
    run_test "Elimina policy 'test-approle-policy'" "$CURL_ROOT -X DELETE $VAULT_ADDR/v1/sys/policy/test-approle-policy"

    # k. Pulizia finale
    run_test "Vault cleanup (avanzato)" "$VAULT_SCRIPT cleanup --backend file"
}

# === Gestione dei parametri in ingresso ===
TEST_SCOPE="${1:-all}"
case "$TEST_SCOPE" in
    all)
        test_vault_file_backend
        test_vault_consul_backend
        test_bao
        test_advanced_vault
        ;;
    vault)
        test_vault_file_backend
        test_vault_consul_backend
        ;;
    bao)
        test_bao
        ;;
    advanced)
        test_advanced_vault
        ;;
    *)
        echo -e "${RED}Errore: Parametro non valido. Uso: $0 [all|vault|bao|advanced]${NC}"
        exit 1
        ;;
esac

# --- Summary ---
echo -e "\n${CYAN}=== Smoke Test Summary ===${NC}"
echo -e "Total tests:   ${CYAN}$TESTS_TOTAL${NC}"
echo -e "Passed:        ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed:        ${RED}$TESTS_FAILED${NC}"

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo -e "\n${GREEN}✅ Tutti i test sono passati con successo!${NC}"
    rm -f "$LOG_FILE"
else
    echo -e "\n${RED}❌ Alcuni test sono falliti. Controlla $LOG_FILE per i dettagli.${NC}"
    exit 1
fi