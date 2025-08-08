#!/usr/bin/env bash
# Fast smoke tests for vault-lab-ctl.sh (minimal console output)

set -euo pipefail

# --- robust path bootstrap ---
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)"
CTRL_SCRIPT="${CTRL_SCRIPT:-${SCRIPT_DIR}/vault-lab-ctl.sh}"
if [[ ! -x "$CTRL_SCRIPT" ]]; then
  echo "ERROR: CTRL_SCRIPT '$CTRL_SCRIPT' not found or not executable" >&2
  exit 2
fi
CTRL_DIR="$(cd -- "$(dirname -- "$CTRL_SCRIPT")" &>/dev/null && pwd -P)"
export PATH="${SCRIPT_DIR}/bin:${CTRL_DIR}/bin:${PATH}"
CTRL_SCRIPT_NAME="$(basename "$CTRL_SCRIPT")"
# --- end bootstrap ---

# Colors
if [ -t 1 ]; then
  RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; RESET=$'\e[0m'
else
  RED=''; GREEN=''; YELLOW=''; RESET=''
fi

# Config
LOG_DIR="${LOG_DIR:-./smoke-logs}"
QUIET="${QUIET:-1}"
BACKENDS="${BACKENDS:-file,consul}"

TIMEOUT_START=${TIMEOUT_START:-60}
TIMEOUT_STATUS=${TIMEOUT_STATUS:-20}
TIMEOUT_RESTART=${TIMEOUT_RESTART:-60}
TIMEOUT_STOP=${TIMEOUT_STOP:-30}
SLEEP_AFTER_STOP=${SLEEP_AFTER_STOP:-2}

have_cmd() { command -v "$1" >/dev/null 2>&1; }
secs_to_hms(){ s=$1; printf "%02d:%02d:%02d" $((s/3600)) $(((s%3600)/60)) $((s%60)); }

ensure_prereqs() {
  for c in timeout pgrep mktemp; do
    have_cmd "$c" || { echo "Missing '$c' in PATH" >&2; exit 2; }
  done
}

run_quiet() { local t=$1; shift
  if [ "$QUIET" = "1" ]; then
    timeout --kill-after=5 "$t" "$@" >>"$_LOG" 2>&1
  else
    timeout --kill-after=5 "$t" "$@" 2>&1 | tee -a "$_LOG"
  fi
}

assert_not_running(){ ! pgrep -f "$1" >/dev/null 2>&1; }

run_block() {
  local BACKEND="$1"
  local BASE; BASE="$(mktemp -d)"
  local tests=(start status restart stop)

  for name in "${tests[@]}"; do
    N=$((N+1))
    _LOG="${LOG_DIR}/${BACKEND}_${name}.log"; :> "$_LOG"

    local CMD_SHORT="${CTRL_SCRIPT_NAME} --backend ${BACKEND} ${name}"
    local CMD_FULL=( "$CTRL_SCRIPT" --backend "$BACKEND" -b "$BASE" "$name" )

    echo "Running test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}"

    case "$name" in
      start)
        if run_quiet "$TIMEOUT_START" "${CMD_FULL[@]}" \
           && run_quiet "$TIMEOUT_STATUS" "$CTRL_SCRIPT" --backend "$BACKEND" -b "$BASE" status
        then echo "Test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}: ${GREEN}OK${RESET}"; PASS=$((PASS+1))
        else echo "Test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}: ${RED}FAIL${RESET} (see ${_LOG})"; FAIL=$((FAIL+1))
        fi
        ;;
      status)
        if run_quiet "$TIMEOUT_STATUS" "${CMD_FULL[@]}"
        then echo "Test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}: ${GREEN}OK${RESET}"; PASS=$((PASS+1))
        else echo "Test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}: ${RED}FAIL${RESET} (see ${_LOG})"; FAIL=$((FAIL+1))
        fi
        ;;
      restart)
        if run_quiet "$TIMEOUT_RESTART" "${CMD_FULL[@]}" \
           && run_quiet "$TIMEOUT_STATUS" "$CTRL_SCRIPT" --backend "$BACKEND" -b "$BASE" status
        then echo "Test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}: ${GREEN}OK${RESET}"; PASS=$((PASS+1))
        else echo "Test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}: ${RED}FAIL${RESET} (see ${_LOG})"; FAIL=$((FAIL+1))
        fi
        ;;
      stop)
        if run_quiet "$TIMEOUT_STOP" "${CMD_FULL[@]}"; then
          sleep "$SLEEP_AFTER_STOP"
          if [ "$BACKEND" = "consul" ]; then
            if assert_not_running "vault.*server" && assert_not_running "consul.*agent"; then
              echo "Test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}: ${GREEN}OK${RESET}"; PASS=$((PASS+1))
            else
              echo "Test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}: ${RED}FAIL${RESET} (see ${_LOG})"; FAIL=$((FAIL+1))
            fi
          else
            if assert_not_running "vault.*server"; then
              echo "Test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}: ${GREEN}OK${RESET}"; PASS=$((PASS+1))
            else
              echo "Test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}: ${RED}FAIL${RESET} (see ${_LOG})"; FAIL=$((FAIL+1))
            fi
          fi
        else
          echo "Test ${YELLOW}${N}/${TOTAL}${RESET} — ${CMD_SHORT}: ${RED}FAIL${RESET} (see ${_LOG})"; FAIL=$((FAIL+1))
        fi
        ;;
    esac
  done

  run_quiet 10 "$CTRL_SCRIPT" --backend "$BACKEND" -b "$BASE" stop || true
  run_quiet 10 "$CTRL_SCRIPT" -b "$BASE" cleanup || true
  rm -rf "$BASE"
}

main() {
  ensure_prereqs
  mkdir -p "$LOG_DIR"

  PASS=0; FAIL=0; SKIP=0; N=0

  IFS=',' read -r -a BKS <<< "$BACKENDS"
  TOTAL=$(( ${#BKS[@]} * 4 ))

  echo "Using control script: $CTRL_SCRIPT"
  local start_ts=$(date +%s)

  for be in "${BKS[@]}"; do
    run_block "$be"
  done

  local dur=$(( $(date +%s) - start_ts ))
  echo "========== SUMMARY =========="
  echo "Total tests   : $TOTAL"
  echo "Passed        : $PASS"
  echo "Skipped       : $SKIP"
  echo "Failed        : $FAIL"
  echo "Duration      : $(secs_to_hms "$dur")"
  echo "Logs directory: ${LOG_DIR}"

  echo "Running final cleanup..."
  if "$CTRL_SCRIPT" cleanup >>"${LOG_DIR}/final_cleanup.log" 2>&1; then
    echo "Performed full cleanup via vault-lab-ctl.sh cleanup ✅"
  else
    echo "WARNING: Cleanup failed (see ${LOG_DIR}/final_cleanup.log)"
  fi

  [ "$FAIL" -eq 0 ] || exit 1
}

main "$@"
