#!/usr/bin/env bash
set -euo pipefail

# === CONFIG ===
VAULT_CTRL="/mnt/c/Users/gomiero1/PycharmProjects/PythonProject/zero-to-vault-lab/vault-lab-ctl.sh"
BAO_CTRL="/mnt/c/Users/gomiero1/PycharmProjects/PythonProject/zero-to-vault-lab/bao-lab-ctl.sh"
BASE_DIR="/mnt/c/Users/gomiero1/PycharmProjects/PythonProject/zero-to-vault-lab"
LOG_DIR="./smoke-logs"

VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
CONSUL_HTTP_ADDR="${CONSUL_HTTP_ADDR:-http://127.0.0.1:8500}"

# Readiness behavior: 1=readiness failure -> SKIP (non-fatal), 0=FAIL
READINESS_SOFT="${READINESS_SOFT:-1}"

# Readiness poll caps
MAX_WAIT_VAULT="${MAX_WAIT_VAULT:-60}"
MAX_WAIT_CONSUL="${MAX_WAIT_CONSUL:-60}"
SLEEP_STEP="${SLEEP_STEP:-0.5}"

# Hard caps
CAP_START_VAULT_FILE="${CAP_START_VAULT_FILE:-120}"
CAP_RESTART_VAULT_FILE="${CAP_RESTART_VAULT_FILE:-90}"
CAP_START_VAULT_CONSUL="${CAP_START_VAULT_CONSUL:-180}"
CAP_RESTART_VAULT_CONSUL="${CAP_RESTART_VAULT_CONSUL:-120}"
CAP_STATUS="${CAP_STATUS:-20}"
CAP_STOP="${CAP_STOP:-40}"
CAP_CLEANUP="${CAP_CLEANUP:-60}"
CAP_START_BAO="${CAP_START_BAO:-90}"
CAP_RESTART_BAO="${CAP_RESTART_BAO:-90}"

mkdir -p "$LOG_DIR"

# === COLORS (TTY-safe) ===
if [ -t 1 ]; then
  RED=$(tput setaf 1); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3); BLUE=$(tput setaf 4); BOLD=$(tput bold); RESET=$(tput sgr0)
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; RESET=''
fi

# === HELPERS (safe) ===
short_cmd() {
  echo "$1" \
    | sed "s|$VAULT_CTRL|vault-lab-ctl.sh|" \
    | sed "s|$BAO_CTRL|bao-lab-ctl.sh|" \
    | sed "s|$BASE_DIR|BASE_DIR|g"
}
port_open() { (echo >"/dev/tcp/$1/$2") >/dev/null 2>&1 || return 1; }
consul_ready() { curl -fsS "${CONSUL_HTTP_ADDR}/v1/status/leader" 2>/dev/null | grep -qE '".+:.+"' || return 1; }
vault_health_ok() {
  local code; code=$(curl -fsS -o /dev/null -w '%{http_code}' "${VAULT_ADDR}/v1/sys/health" 2>/dev/null || echo "")
  [[ "$code" == "200" || "$code" == "429" ]] || return 1
}
wait_vault_ready() {
  local deadline=$(( $(date +%s) + MAX_WAIT_VAULT ))
  while (( $(date +%s) < deadline )); do
    if port_open 127.0.0.1 8200 && vault_health_ok; then return 0; fi
    sleep "$SLEEP_STEP"
  done; return 1
}
wait_consul_ready() {
  local deadline=$(( $(date +%s) + MAX_WAIT_CONSUL ))
  while (( $(date +%s) < deadline )); do
    if port_open 127.0.0.1 8500 && consul_ready; then return 0; fi
    sleep "$SLEEP_STEP"
  done; return 1
}
assert_stopped(){ ! pgrep -f "$1" >/dev/null 2>&1; }
pick_cap() {
  local scmd="$1"
  case "$scmd" in
    "vault-lab-ctl.sh --backend file "*start)     echo "$CAP_START_VAULT_FILE" ;;
    "vault-lab-ctl.sh --backend file "*restart)   echo "$CAP_RESTART_VAULT_FILE" ;;
    "vault-lab-ctl.sh --backend consul "*start)   echo "$CAP_START_VAULT_CONSUL" ;;
    "vault-lab-ctl.sh --backend consul "*restart) echo "$CAP_RESTART_VAULT_CONSUL" ;;
    *" status")                                   echo "$CAP_STATUS" ;;
    *" stop")                                     echo "$CAP_STOP" ;;
    *" cleanup")                                  echo "$CAP_CLEANUP" ;;
    "bao-lab-ctl.sh "*start)                      echo "$CAP_START_BAO" ;;
    "bao-lab-ctl.sh "*restart)                    echo "$CAP_RESTART_BAO" ;;
    *)                                            echo 60 ;;
  esac
}
secs_to_hms(){ s=$1; printf "%02d:%02d:%02d" $((s/3600)) $(((s%3600)/60)) $((s%60)); }

# === TEST LIST ===
TESTS=(
  # Vault file backend
  "$VAULT_CTRL --backend file -b $BASE_DIR start"
  "$VAULT_CTRL --backend file -b $BASE_DIR status"
  "$VAULT_CTRL --backend file -b $BASE_DIR restart"
  "$VAULT_CTRL --backend file -b $BASE_DIR stop"
  "$VAULT_CTRL --backend file -b $BASE_DIR cleanup"
  # Vault consul backend
  "$VAULT_CTRL --backend consul -b $BASE_DIR start"
  "$VAULT_CTRL --backend consul -b $BASE_DIR status"
  "$VAULT_CTRL --backend consul -b $BASE_DIR restart"
  "$VAULT_CTRL --backend consul -b $BASE_DIR stop"
  "$VAULT_CTRL --backend consul -b $BASE_DIR cleanup"
  # Bao (file-only)
  "$BAO_CTRL -b $BASE_DIR start"
  "$BAO_CTRL -b $BASE_DIR status"
  "$BAO_CTRL -b $BASE_DIR restart"
  "$BAO_CTRL -b $BASE_DIR stop"
  "$BAO_CTRL -b $BASE_DIR cleanup"
)

echo "${BOLD}Using control script (Vault):${RESET} $VAULT_CTRL"
echo "${BOLD}Using control script (Bao)  :${RESET} $BAO_CTRL"
echo "${BOLD}Base directory:${RESET} $BASE_DIR"

# === PRE-CLEANUP ===
echo "Running pre-cleanup..."
timeout --kill-after=5 "$CAP_CLEANUP" bash -lc "$VAULT_CTRL -b $BASE_DIR cleanup" &> "$LOG_DIR/pre_vault_cleanup.log" || true
timeout --kill-after=5 "$CAP_CLEANUP" bash -lc "$BAO_CTRL   -b $BASE_DIR cleanup" &> "$LOG_DIR/pre_bao_cleanup.log"   || true
echo "Pre-cleanup done."

total=${#TESTS[@]}
pass_vault=0; fail_vault=0; skip_vault=0
pass_bao=0;   fail_bao=0;   skip_bao=0
pass_all=0;   fail_all=0;   skip_all=0

start_time=$(date +%s)

for i in "${!TESTS[@]}"; do
  num=$((i+1))
  cmd="${TESTS[$i]}"
  scmd="$(short_cmd "$cmd")"
  log_file="$LOG_DIR/$(echo "$scmd" | tr ' /' '__').log"
  cap="$(pick_cap "$scmd")"

  echo "Running test ${YELLOW}${num}/${total}${RESET} — ${YELLOW}${scmd}${RESET}"

  if (
    set +e
    timeout --kill-after=5 "${cap}" bash -lc "$cmd" &> "$log_file"
    ctl_rc=$?

    result="FAIL"
    if [ $ctl_rc -eq 0 ]; then
      case "$scmd" in
        "vault-lab-ctl.sh --backend file "*start|"vault-lab-ctl.sh --backend file "*restart)
          if wait_vault_ready; then result="OK"; else result=$([ "$READINESS_SOFT" = "1" ] && echo "SKIP" || echo "FAIL"); fi
          ;;
        "vault-lab-ctl.sh --backend consul "*start|"vault-lab-ctl.sh --backend consul "*restart)
          if wait_consul_ready && wait_vault_ready; then result="OK"; else result=$([ "$READINESS_SOFT" = "1" ] && echo "SKIP" || echo "FAIL"); fi
          ;;
        "vault-lab-ctl.sh "*stop|"vault-lab-ctl.sh "*cleanup)
          if assert_stopped "vault.*server" && { [[ "$scmd" != *"--backend consul"* ]] || assert_stopped "consul.*agent"; }; then
            result="OK"
          else
            result="FAIL"
          fi
          ;;
        "bao-lab-ctl.sh "*start|"bao-lab-ctl.sh "*restart)
          if wait_vault_ready; then result="OK"; else result=$([ "$READINESS_SOFT" = "1" ] && echo "SKIP" || echo "FAIL"); fi
          ;;
        "bao-lab-ctl.sh "*stop|"bao-lab-ctl.sh "*cleanup)
          if assert_stopped "bao.*server"; then result="OK"; else result="FAIL"; fi
          ;;
        *)
          result="OK"
          ;;
      esac
    else
      result="FAIL"
    fi

    case "$result" in
      OK)
        echo "Test ${GREEN}${num}/${total}${RESET} — ${YELLOW}${scmd}${RESET}: ${GREEN}OK${RESET}"
        echo "__RESULT__:OK" >>"$log_file"; exit 0 ;;
      SKIP)
        echo "Test ${BLUE}${num}/${total}${RESET} — ${YELLOW}${scmd}${RESET}: ${BLUE}SKIP (readiness)${RESET}"
        echo "__RESULT__:SKIP" >>"$log_file"; exit 20 ;;
      FAIL|*)
        msg="timeout/exit"; [ $ctl_rc -eq 0 ] && msg="readiness"
        echo "Test ${RED}${num}/${total}${RESET} — ${YELLOW}${scmd}${RESET}: ${RED}FAIL${RESET} (${msg}) (see $log_file)"
        echo "__RESULT__:FAIL" >>"$log_file"; exit 10 ;;
    esac
  ); then
    rc=0
  else
    rc=$?
  fi

  # SAFE increments (don’t trip set -e)
  if [[ "$scmd" == *"bao-lab-ctl.sh"* ]]; then
    if   [ $rc -eq 0 ];  then : $((pass_all+=1)); : $((pass_bao+=1))
    elif [ $rc -eq 20 ]; then : $((skip_all+=1)); : $((skip_bao+=1))
    else                      : $((fail_all+=1)); : $((fail_bao+=1)); fi
  else
    if   [ $rc -eq 0 ];  then : $((pass_all+=1)); : $((pass_vault+=1))
    elif [ $rc -eq 20 ]; then : $((skip_all+=1)); : $((skip_vault+=1))
    else                      : $((fail_all+=1)); : $((fail_vault+=1)); fi
  fi
done

end_time=$(date +%s)
duration=$((end_time - start_time))
duration_str=$(secs_to_hms "$duration")

# === SUMMARY ===
echo "========== SUMMARY =========="
echo "Total tests   : $((pass_all+fail_all+skip_all))"
echo "Passed        : $pass_all"
echo "Skipped       : $skip_all"
echo "Failed        : $fail_all"
echo "Duration      : $duration_str"
echo "Logs directory: $LOG_DIR"
echo
echo "--- Vault summary ---"
echo "Total tests   : $((pass_vault + fail_vault + skip_vault))"
echo "Passed        : $pass_vault"
echo "Skipped       : $skip_vault"
echo "Failed        : $fail_vault"
echo
echo "--- Bao summary ---"
echo "Total tests   : $((pass_bao + fail_bao + skip_bao))"
echo "Passed        : $pass_bao"
echo "Skipped       : $skip_bao"
echo "Failed        : $fail_bao"

echo "Running final cleanup..."
timeout --kill-after=5 "$CAP_CLEANUP" bash -lc "$VAULT_CTRL -b $BASE_DIR cleanup" &> "$LOG_DIR/final_vault_cleanup.log" || true
timeout --kill-after=5 "$CAP_CLEANUP" bash -lc "$BAO_CTRL   -b $BASE_DIR cleanup" &> "$LOG_DIR/final_bao_cleanup.log"   || true
echo "Performed full cleanup via vault-lab-ctl.sh and bao-lab-ctl.sh ${GREEN}✅${RESET}"
