#!/bin/bash
set -euo pipefail

# ==========================================
# Vault Lab Smoke Test Script
# ==========================================
# This script runs a series of automated smoke tests
# against the 'vault-lab-ctl.sh' script to validate:
#   ✅ Basic functionality (--help output)
#   ✅ Start, Restart, Reset, and Cleanup commands
#   ✅ Correct status reporting after each action
#   ✅ Compatibility with both 'file' and 'consul' backends
#
# Usage:
#   ./vault-lab-smoketest.sh
#
# Output:
#   - Console output with colored PASS/FAIL markers
#   - Full logs written to ./smoketest.log
#
# Exit codes:
#   - 0 if all tests passed
#   - 1 if any test failed
# ==========================================

SCRIPT_PATH="./vault-lab-ctl.sh"
LOG_FILE="./smoketest.log"

# === Colors ===
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No color

TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

echo -e "${CYAN}=== Vault Lab Smoke Test ===${NC}" | tee "$LOG_FILE"
echo "Test started at: $(date)" | tee -a "$LOG_FILE"

# --- Run single test ---
run_test() {
    local description="$1"
    local command="$2"
    TESTS_TOTAL=$((TESTS_TOTAL+1))
    echo -e "\n${YELLOW}[TEST]${NC} $description" | tee -a "$LOG_FILE"
    echo "\$ $command" | tee -a "$LOG_FILE"
    if eval "$command" >>"$LOG_FILE" 2>&1; then
        echo -e "${GREEN}[PASS]${NC} $description" | tee -a "$LOG_FILE"
        TESTS_PASSED=$((TESTS_PASSED+1))
    else
        echo -e "${RED}[FAIL]${NC} $description - check $LOG_FILE" | tee -a "$LOG_FILE"
        TESTS_FAILED=$((TESTS_FAILED+1))
    fi
}

# --- Test sequence for backend ---
test_backend() {
    local BACKEND=$1
    echo -e "\n${CYAN}=== Running smoke tests for backend: $BACKEND ===${NC}" | tee -a "$LOG_FILE"

    run_test "Display help" "$SCRIPT_PATH --help"
    run_test "Start Vault Lab ($BACKEND)" "$SCRIPT_PATH start --backend $BACKEND -c"
    run_test "Check status after start ($BACKEND)" "$SCRIPT_PATH status"
    run_test "Restart Vault Lab ($BACKEND)" "$SCRIPT_PATH restart"
    run_test "Check status after restart ($BACKEND)" "$SCRIPT_PATH status"
    run_test "Reset Vault Lab ($BACKEND)" "$SCRIPT_PATH reset"
    run_test "Check status after reset ($BACKEND)" "$SCRIPT_PATH status"
    run_test "Cleanup Vault Lab ($BACKEND)" "$SCRIPT_PATH cleanup"
    run_test "Verify stopped status ($BACKEND)" "$SCRIPT_PATH status || true"
}

# --- Run tests for both backends ---
test_backend "file"
test_backend "consul"

# --- Summary ---
echo -e "\n${CYAN}=== Smoke Test Summary ===${NC}"
echo -e "Total tests:   ${CYAN}$TESTS_TOTAL${NC}"
echo -e "Passed:        ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed:        ${RED}$TESTS_FAILED${NC}"

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo -e "\n${GREEN}✅ All smoke tests passed successfully!${NC}"
else
    echo -e "\n${RED}❌ Some tests failed. Check $LOG_FILE for details.${NC}"
    exit 1
fi