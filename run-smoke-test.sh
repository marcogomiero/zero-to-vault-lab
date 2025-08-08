#!/usr/bin/env bash
set -euo pipefail

# Minimal-verbosity smoke tests for vault-lab-ctl.sh
# Adds "status" tests for file and consul backends.
# - Prints only per-test start/end with status (OK/FAIL/SKIP)
# - On failure, prints the log file location (and last lines)
# - Summary at the end: total, passed, skipped, failed, duration
# - Creates isolated temp dirs per test (-b) and uses -c to avoid prompts
# - Skips Consul tests if 'consul' is not available

CTRL_SCRIPT="${CTRL_SCRIPT:-./vault-lab-ctl.sh}"
LOG_DIR="${LOG_DIR:-./smoke-logs}"
QUIET="${QUIET:-1}"           # 1=minimal output, 0=pass-through (verbose)
TAIL_ON_FAIL="${TAIL_ON_FAIL:-30}"  # how many log lines to show on failure

TIMEOUT_START_FILE=${TIMEOUT_START_FILE:-180}
TIMEOUT_STOP_FILE=${TIMEOUT_STOP_FILE:-60}
TIMEOUT_RESTART_FILE=${TIMEOUT_RESTART_FILE:-120}
TIMEOUT_STATUS_FILE=${TIMEOUT_STATUS_FILE:-30}

TIMEOUT_START_CONSUL=${TIMEOUT_START_CONSUL:-240}
TIMEOUT_STOP_CONSUL=${TIMEOUT_STOP_CONSUL:-90}
TIMEOUT_RESTART_CONSUL=${TIMEOUT_RESTART_CONSUL:-180}
TIMEOUT_STATUS_CONSUL=${TIMEOUT_STATUS_CONSUL:-30}

SLEEP_AFTER_STOP=${SLEEP_AFTER_STOP:-2}

# Colors (disabled if not a TTY)
if [ -t 1 ]; then
  RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
else
  RED=''; GREEN=''; YELLOW=''; BOLD=''; RESET=''
fi

have_cmd() { command -v "$1" >/dev/null 2>&1; }
timestamp() { date +%H:%M:%S; }
secs_to_hms() { # $1 seconds
  local s=$1 h m
  h=$((s/3600)); m=$(((s%3600)/60)); s=$((s%60))
  printf "%02d:%02d:%02d" "$h" "$m" "$s"
}

ensure_prereqs() {
  local missing=0
  for c in timeout pgrep mktemp; do
    if ! have_cmd "$c"; then echo "Missing '$c' in PATH" >&2; missing=1; fi
  done
  if [ $missing -ne 0 ]; then
    echo "Install prerequisites and retry." >&2
    exit 2
  fi
}

run_quiet() { # $1 timeout_secs, rest = command...
  local t=$1; shift
  if [ "${QUIET}" = "1" ]; then
    timeout "$t" "$@" >>"$_LOG" 2>&1
  else
    timeout "$t" "$@" 2>&1 | tee -a "$_LOG"
  fi
}

pgrep_running() { pgrep -f "$1" >/dev/null 2>&1; }
assert_running() { pgrep_running "$1"; }
assert_not_running() { ! pgrep_running "$1"; }

with_tmpdir() {
  local __var=$1
  local d; d=$(mktemp -d)
  eval "$__var=\"$d\""
}

cleanup_env() {
  local base=$1 backend=$2
  "$CTRL_SCRIPT" --backend "$backend" -b "$base" stop >>"$_LOG" 2>&1 || true
  "$CTRL_SCRIPT" -b "$base" cleanup >>"$_LOG" 2>&1 || true
}

# ------------------ Tests ------------------
t_start_file() {
  with_tmpdir BASE
  trap 'cleanup_env "$BASE" file; rm -rf "$BASE"' RETURN
  run_quiet "$TIMEOUT_START_FILE" "$CTRL_SCRIPT" --backend file -c -b "$BASE" start || return 1
  assert_running "vault.*server"
}

t_status_file() {
  with_tmpdir BASE
  trap 'cleanup_env "$BASE" file; rm -rf "$BASE"' RETURN
  run_quiet "$TIMEOUT_START_FILE" "$CTRL_SCRIPT" --backend file -c -b "$BASE" start || return 1
  run_quiet "$TIMEOUT_STATUS_FILE" "$CTRL_SCRIPT" --backend file -b "$BASE" status || return 1
  assert_running "vault.*server"
}

t_stop_file() {
  with_tmpdir BASE
  trap 'cleanup_env "$BASE" file; rm -rf "$BASE"' RETURN
  run_quiet "$TIMEOUT_START_FILE" "$CTRL_SCRIPT" --backend file -c -b "$BASE" start || return 1
  run_quiet "$TIMEOUT_STOP_FILE" "$CTRL_SCRIPT" --backend file -b "$BASE" stop || return 1
  sleep "$SLEEP_AFTER_STOP"
  assert_not_running "vault.*server"
}

t_restart_file() {
  with_tmpdir BASE
  trap 'cleanup_env "$BASE" file; rm -rf "$BASE"' RETURN
  run_quiet "$TIMEOUT_START_FILE" "$CTRL_SCRIPT" --backend file -c -b "$BASE" start || return 1
  run_quiet "$TIMEOUT_RESTART_FILE" "$CTRL_SCRIPT" --backend file -b "$BASE" restart || return 1
  assert_running "vault.*server"
}

t_start_consul() {
  have_cmd consul || return 77  # skip
  with_tmpdir BASE
  trap 'cleanup_env "$BASE" consul; rm -rf "$BASE"' RETURN
  run_quiet "$TIMEOUT_START_CONSUL" "$CTRL_SCRIPT" --backend consul -c -b "$BASE" start || return 1
  assert_running "vault.*server" && assert_running "consul.*agent"
}

t_status_consul() {
  have_cmd consul || return 77  # skip
  with_tmpdir BASE
  trap 'cleanup_env "$BASE" consul; rm -rf "$BASE"' RETURN
  run_quiet "$TIMEOUT_START_CONSUL" "$CTRL_SCRIPT" --backend consul -c -b "$BASE" start || return 1
  run_quiet "$TIMEOUT_STATUS_CONSUL" "$CTRL_SCRIPT" --backend consul -b "$BASE" status || return 1
  assert_running "vault.*server" && assert_running "consul.*agent"
}

t_stop_consul() {
  have_cmd consul || return 77  # skip
  with_tmpdir BASE
  trap 'cleanup_env "$BASE" consul; rm -rf "$BASE"' RETURN
  run_quiet "$TIMEOUT_START_CONSUL" "$CTRL_SCRIPT" --backend consul -c -b "$BASE" start || return 1
  run_quiet "$TIMEOUT_STOP_CONSUL" "$CTRL_SCRIPT" --backend consul -b "$BASE" stop || return 1
  sleep "$SLEEP_AFTER_STOP"
  assert_not_running "vault.*server" && assert_not_running "consul.*agent"
}

t_restart_consul() {
  have_cmd consul || return 77  # skip
  with_tmpdir BASE
  trap 'cleanup_env "$BASE" consul; rm -rf "$BASE"' RETURN
  run_quiet "$TIMEOUT_START_CONSUL" "$CTRL_SCRIPT" --backend consul -c -b "$BASE" start || return 1
  run_quiet "$TIMEOUT_RESTART_CONSUL" "$CTRL_SCRIPT" --backend consul -b "$BASE" restart || return 1
  assert_running "vault.*server" && assert_running "consul.*agent"
}

# -------------- Runner --------------
main() {
  ensure_prereqs
  mkdir -p "$LOG_DIR"

  declare -a NAMES=(
    "start (file)"
    "status (file)"
    "stop (file)"
    "restart (file)"
    "start (consul)"
    "status (consul)"
    "stop (consul)"
    "restart (consul)"
  )
  declare -a FUNCS=(
    t_start_file
    t_status_file
    t_stop_file
    t_restart_file
    t_start_consul
    t_status_consul
    t_stop_consul
    t_restart_consul
  )

  local total=${#FUNCS[@]}
  local pass=0 skip=0 fail=0
  local start_ts; start_ts=$(date +%s)

  for i in "${!FUNCS[@]}"; do
    local idx=$((i+1))
    local name="${NAMES[$i]}"
    local fn="${FUNCS[$i]}"
    _LOG="${LOG_DIR}/$(printf "%02d" "$idx")_${fn}.log"
    : > "$_LOG"

    echo "[${BOLD}$(timestamp)${RESET}] start test ${idx}/${total}: ${name}"

    if "$fn"; then
      echo "[${BOLD}$(timestamp)${RESET}] end   test ${idx}/${total}: ${name} - ${GREEN}OK${RESET}"
      pass=$((pass+1))
    else
      rc=$?
      if [ "$rc" -eq 77 ]; then
        echo "[${BOLD}$(timestamp)${RESET}] end   test ${idx}/${total}: ${name} - ${YELLOW}SKIP${RESET}"
        skip=$((skip+1))
      else
        echo "[${BOLD}$(timestamp)${RESET}] end   test ${idx}/${total}: ${name} - ${RED}FAIL${RESET}"
        echo "  -> log: ${_LOG}"
        if [ "$TAIL_ON_FAIL" -gt 0 ]; then
          echo "  -- last ${TAIL_ON_FAIL} log lines --"
          tail -n "$TAIL_ON_FAIL" "$_LOG" | sed 's/^/  /'
        fi
        fail=$((fail+1))
      fi
    fi
  done

  local end_ts; end_ts=$(date +%s)
  local dur=$((end_ts - start_ts))

  echo
  echo "========== SUMMARY =========="
  echo "Total tests   : $total"
  echo "Passed        : $pass"
  echo "Skipped       : $skip"
  echo "Failed        : $fail"
  echo "Duration      : $(secs_to_hms "$dur")"
  echo "Logs directory: ${LOG_DIR}"
  if [ "$fail" -eq 0 ]; then exit 0; else exit 1; fi
}

main "$@"
