#!/usr/bin/env bash
# Unified fast smoke tests for:
# - vault-lab-ctl.sh  (backends: file, consul)
# - bao-lab-ctl.sh    (backend: file only)
# Minimal console output; colored progress; logs under ./smoke-logs/

set -euo pipefail

# --- robust path bootstrap ---
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)"
VAULT_CTRL="${VAULT_CTRL:-${SCRIPT_DIR}/vault-lab-ctl.sh}"
BAO_CTRL="${BAO_CTRL:-${SCRIPT_DIR}/bao-lab-ctl.sh}"

for ctrl in "$VAULT_CTRL" "$BAO_CTRL"; do
  if [[ ! -x "$ctrl" ]]; then
    echo "ERROR: control script '$ctrl' not found or not executable" >&2
    exit 2
  fi
done

VAULT_DIR="$(cd -- "$(dirname -- "$VAULT_CTRL")" &>/dev/null && pwd -P)"
BAO_DIR="$(cd -- "$(dirname -- "$BAO_CTRL")" &>/dev/null && pwd -P)"
export PATH="${SCRIPT_DIR}/bin:${VAULT_DIR}/bin:${BAO_DIR}/bin:${PATH}"

VAULT_NAME="$(basename "$VAULT_CTRL")"
BAO_NAME="$(basename "$BAO_CTRL")"
# --- end bootstrap ---

# Colors (TTY only)
if [ -t 1 ]; then
  RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; RESET=$'\e[0m'
else
  RED=''; GREEN=''; YELLOW=''; RESET=''
fi

# Config
LOG_DIR="${LOG_DIR:-./smoke-logs}"
QUIET="${QUIET:-1}"

# Which tech to run (default: both)
RUN_VAULT="${RUN_VAULT:-1}"
RUN_BAO="${RUN_BAO:-1}"

# Vault backends (default: file,consul)
VAULT_BACKENDS="${VAULT_BACKENDS:-file,consul}"

# Per-test timeouts
TIMEOUT_START=${TIMEOUT_START:-60}
TIMEOUT_STATUS=${TIMEOUT_STATUS:-20}
TIMEOUT_RESTART=${TIMEOUT_RESTART:-60}
TIMEOUT_STOP=${TIMEOUT_STOP:-30}
SLEEP_AFTER_STOP=${SLEEP_AFTER_STOP:-2}

have_cmd(){ command -v "$1" >/dev/null 2>&1; }
secs_to_hms(){ s=$1; printf "%02d:%02d:%02d" $((s/3600)) $(((s%3600)/60)) $((s%60)); }

ensure_prereqs() {
  for c in timeout pgrep mktemp; do
    have_cmd "$c" || { echo "Missing '$c' in PATH" >&2; exit 2; }
  done
}

run_quiet(){ # $1 timeout_secs; rest: command...
  local t=$1; shift
  if [ "$QUIET" = "1" ]; then
    timeout --kill-after=5 "$t" "$@" >>"$_LOG" 2>&1
  else
    timeout --kill-after=5 "$t" "$@" 2>&1 | tee -a "$_LOG"
  fi
}

assert_not_running(){ ! pgrep -f "$1" >/dev/null 2>&1; }

# --- Vault block: reuse one BASE per backend ---
run_vault_block() {
  local BACKEND="$1"
  local BASE; BASE="$(mktemp -d)"
  local tests=(start status restart stop)

  for name in "${tests[@]}"; do
    N=$((N+1))
    _LOG="${LOG_DIR}/vault_${BACKEND}_${name}.log"; :> "$_LOG"

    local CMD_SHORT="${VAULT_NAME} --backend ${BACKEND} ${name}"
    local CMD_FULL=( "$VAULT_CTRL" --backend "$BACKEND" -b "$BASE" "$name" )

    echo "Running test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}"

    case "$name" in
      start)
        if run_quiet "$TIMEOUT_START" "${CMD_FULL[@]}" \
           && run_quiet "$TIMEOUT_STATUS" "$VAULT_CTRL" --backend "$BACKEND" -b "$BASE" status
        then echo "Test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}: ${GREEN}OK${RESET}"; VAULT_PASS=$((VAULT_PASS+1))
        else echo "Test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}: ${RED}FAIL${RESET} (see ${_LOG})"; VAULT_FAIL=$((VAULT_FAIL+1))
        fi
        ;;
      status)
        if run_quiet "$TIMEOUT_STATUS" "${CMD_FULL[@]}"
        then echo "Test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}: ${GREEN}OK${RESET}"; VAULT_PASS=$((VAULT_PASS+1))
        else echo "Test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}: ${RED}FAIL${RESET} (see ${_LOG})"; VAULT_FAIL=$((VAULT_FAIL+1))
        fi
        ;;
      restart)
        if run_quiet "$TIMEOUT_RESTART" "${CMD_FULL[@]}" \
           && run_quiet "$TIMEOUT_STATUS" "$VAULT_CTRL" --backend "$BACKEND" -b "$BASE" status
        then echo "Test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}: ${GREEN}OK${RESET}"; VAULT_PASS=$((VAULT_PASS+1))
        else echo "Test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}: ${RED}FAIL${RESET} (see ${_LOG})"; VAULT_FAIL=$((VAULT_FAIL+1))
        fi
        ;;
      stop)
        if run_quiet "$TIMEOUT_STOP" "${CMD_FULL[@]}"; then
          sleep "$SLEEP_AFTER_STOP"
          if [ "$BACKEND" = "consul" ]; then
            if assert_not_running "vault.*server" && assert_not_running "consul.*agent"; then
              echo "Test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}: ${GREEN}OK${RESET}"; VAULT_PASS=$((VAULT_PASS+1))
            else
              echo "Test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}: ${RED}FAIL${RESET} (see ${_LOG})"; VAULT_FAIL=$((VAULT_FAIL+1))
            fi
          else
            if assert_not_running "vault.*server"; then
              echo "Test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}: ${GREEN}OK${RESET}"; VAULT_PASS=$((VAULT_PASS+1))
            else
              echo "Test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}: ${RED}FAIL${RESET} (see ${_LOG})"; VAULT_FAIL=$((VAULT_FAIL+1))
            fi
          fi
        else
          echo "Test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}: ${RED}FAIL${RESET} (see ${_LOG})"; VAULT_FAIL=$((VAULT_FAIL+1))
        fi
        ;;
    esac
  done

  run_quiet 10 "$VAULT_CTRL" --backend "$BACKEND" -b "$BASE" stop || true
  run_quiet 10 "$VAULT_CTRL" -b "$BASE" cleanup || true
  rm -rf "$BASE"
}

# --- Bao block: only file backend, reuse one BASE ---
run_bao_block() {
  local BASE; BASE="$(mktemp -d)"
  local tests=(start status restart stop)

  for name in "${tests[@]}"; do
    N=$((N+1))
    _LOG="${LOG_DIR}/bao_${name}.log"; :> "$_LOG"

    local CMD_SHORT="${BAO_NAME} ${name}"
    local CMD_FULL=( "$BAO_CTRL" -b "$BASE" "$name" )

    echo "Running test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}"

    case "$name" in
      start)
        if run_quiet "$TIMEOUT_START" "${CMD_FULL[@]}" \
           && run_quiet "$TIMEOUT_STATUS" "$BAO_CTRL" -b "$BASE" status
        then echo "Test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}: ${GREEN}OK${RESET}"; BAO_PASS=$((BAO_PASS+1))
        else echo "Test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}: ${RED}FAIL${RESET} (see ${_LOG})"; BAO_FAIL=$((BAO_FAIL+1))
        fi
        ;;
      status)
        if run_quiet "$TIMEOUT_STATUS" "${CMD_FULL[@]}"
        then echo "Test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}: ${GREEN}OK${RESET}"; BAO_PASS=$((BAO_PASS+1))
        else echo "Test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}: ${RED}FAIL${RESET} (see ${_LOG})"; BAO_FAIL=$((BAO_FAIL+1))
        fi
        ;;
      restart)
        if run_quiet "$TIMEOUT_RESTART" "${CMD_FULL[@]}" \
           && run_quiet "$TIMEOUT_STATUS" "$BAO_CTRL" -b "$BASE" status
        then echo "Test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}: ${GREEN}OK${RESET}"; BAO_PASS=$((BAO_PASS+1))
        else echo "Test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}: ${RED}FAIL${RESET} (see ${_LOG})"; BAO_FAIL=$((BAO_FAIL+1))
        fi
        ;;
      stop)
        if run_quiet "$TIMEOUT_STOP" "${CMD_FULL[@]}"; then
          sleep "$SLEEP_AFTER_STOP"
          # Se vuoi, cambia la signature qui con quella reale del processo Bao:
          if assert_not_running "bao.*server"; then
            echo "Test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}: ${GREEN}OK${RESET}"; BAO_PASS=$((BAO_PASS+1))
          else
            echo "Test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}: ${RED}FAIL${RESET} (see ${_LOG})"; BAO_FAIL=$((BAO_FAIL+1))
          fi
        else
          echo "Test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}: ${RED}FAIL${RESET} (see ${_LOG})"; BAO_FAIL=$((BAO_FAIL+1))
        fi
        ;;
    esac
  done

  run_quiet 10 "$BAO_CTRL" -b "$BASE" stop || true
  run_quiet 10 "$BAO_CTRL" -b "$BASE" cleanup || true
  rm -rf "$BASE"
}

main() {
  ensure_prereqs
  mkdir -p "$LOG_DIR"

  echo "Using control script (Vault): $VAULT_CTRL"
  echo "Using control script (Bao)  : $BAO_CTRL"

  VAULT_PASS=0; VAULT_FAIL=0
  BAO_PASS=0;   BAO_FAIL=0
  N=0

  # Compute TOTAL
  TOTAL=0
  if [ "$RUN_VAULT" = "1" ]; then
    IFS=',' read -r -a VBKS <<< "$VAULT_BACKENDS"
    TOTAL=$(( TOTAL + ${#VBKS[@]} * 4 ))
  fi
  if [ "$RUN_BAO" = "1" ]; then
    TOTAL=$(( TOTAL + 4 )) # bao: only file
  fi

  local start_ts
  start_ts=$(date +%s)

  # Vault
  if [ "$RUN_VAULT" = "1" ]; then
    IFS=',' read -r -a VBKS <<< "$VAULT_BACKENDS"
    for be in "${VBKS[@]}"; do
      run_vault_block "$be"
    done
  fi

  # Bao
  if [ "$RUN_BAO" = "1" ]; then
    run_bao_block
  fi

  local dur=$(( $(date +%s) - start_ts ))
  local total_pass=$((VAULT_PASS + BAO_PASS))
  local total_fail=$((VAULT_FAIL + BAO_FAIL))
  local total_tests=$TOTAL

  echo "========== SUMMARY =========="
  echo "Total tests   : $total_tests"
  echo "Passed        : $total_pass"
  echo "Failed        : $total_fail"
  echo "Duration      : $(secs_to_hms "$dur")"
  echo "Logs directory: ${LOG_DIR}"

  echo
  echo "--- Vault summary ---"
  echo "Total tests   : $(( ${RUN_VAULT} == 1 ? ( $(echo "$VAULT_BACKENDS" | awk -F, '{print NF}') * 4 ) : 0 ))"
  echo "Passed        : $VAULT_PASS"
  echo "Failed        : $VAULT_FAIL"

  echo
  echo "--- Bao summary ---"
  echo "Total tests   : $(( ${RUN_BAO} == 1 ? 4 : 0 ))"
  echo "Passed        : $BAO_PASS"
  echo "Failed        : $BAO_FAIL"

  echo
  echo "Running final cleanup..."
  "$VAULT_CTRL" cleanup >>"${LOG_DIR}/final_cleanup_vault.log" 2>&1 || true
  "$BAO_CTRL"   cleanup >>"${LOG_DIR}/final_cleanup_bao.log"   2>&1 || true
  echo "Performed full cleanup via both control scripts ✅"

  [ "$total_fail" -eq 0 ] || exit 1
}

main "$@"
