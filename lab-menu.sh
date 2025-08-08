#!/usr/bin/env bash
set -euo pipefail

#########################################################
# Unified Lab Menu (Vault + OpenBao) with auto-detection
# - On startup, detects any running Vault/Consul/Bao
# - Prompts: Keep & exit / Wipe & continue / Wipe & exit
# - Menu to run actions for Vault (file/consul) or Bao
# - Shows the exact command with "-b BASE_DIR"
# - English output and comments
#########################################################

# ---------- Configuration ----------
BASE_DIR="${BASE_DIR:-/mnt/c/Users/gomiero1/PycharmProjects/PythonProject/zero-to-vault-lab}"
VAULT_CTRL="${VAULT_CTRL:-${BASE_DIR}/vault-lab-ctl.sh}"
BAO_CTRL="${BAO_CTRL:-${BASE_DIR}/bao-lab-ctl.sh}"

# Optional behavior flags
PAUSE="${PAUSE:-1}"             # 1=pause after actions, 0=don't pause
ONCE="${ONCE:-0}"               # 1=run a single action then exit
AUTO_MODE="${AUTO_MODE:-}"      # keep | wipe-continue | wipe-exit (skip the startup prompt)

# ---------- Colors (TTY-safe) ----------
if [ -t 1 ]; then
  RED=$(tput setaf 1); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3)
  BLUE=$(tput setaf 4); BOLD=$(tput bold); RESET=$(tput sgr0)
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; RESET=''
fi

# ---------- Helpers ----------
die() { echo "${RED}Error:${RESET} $*" >&2; exit 1; }

short_cmd() {
  # Replace absolute paths and real base dir with friendly names/placeholders
  echo "$1" \
    | sed "s|$VAULT_CTRL|vault-lab-ctl.sh|g" \
    | sed "s|$BAO_CTRL|bao-lab-ctl.sh|g" \
    | sed "s|$BASE_DIR|BASE_DIR|g"
}

press_enter() {
  if [[ "$PAUSE" = "1" && -t 0 ]]; then
    echo
    read -r -p "Press Enter to continue..." _ || true
  fi
}

run_cmd() {
  local cmd="$1"
  local shown; shown="$(short_cmd "$cmd")"
  echo "→ Running: ${YELLOW}${shown}${RESET}"
  echo
  # Run in a login-ish shell so env behaves like a normal terminal
  if bash -lc "$cmd"; then
    echo
    echo "${GREEN}Done.${RESET}"
  else
    echo
    echo "${RED}Command failed.${RESET}"
  fi
}

check_ctrl() {
  [ -x "$VAULT_CTRL" ] || die "Vault controller not found or not executable: $VAULT_CTRL"
  [ -x "$BAO_CTRL" ]   || die "Bao controller not found or not executable: $BAO_CTRL"
}

is_running() { pgrep -f "$1" >/dev/null 2>&1; }

detect_active() {
  # Sets global flags VAULT_UP, CONSUL_UP, BAO_UP
  VAULT_UP=0; CONSUL_UP=0; BAO_UP=0
  is_running "vault.*server"  && VAULT_UP=1
  is_running "consul.*agent"  && CONSUL_UP=1
  is_running "bao.*server"    && BAO_UP=1

  # Also check PID files (best-effort info)
  VAULT_PID_FILE="${BASE_DIR}/vault-lab/vault.pid"
  CONSUL_PID_FILE="${BASE_DIR}/consul-lab/consul.pid"
  BAO_PID_FILE="${BASE_DIR}/bao-lab/bao.pid"
}

show_active_summary() {
  echo "${BOLD}Detected running instances:${RESET}"
  printf "  Vault : %s\n"  "$([ $VAULT_UP  -eq 1 ] && echo "${GREEN}running${RESET}" || echo "${YELLOW}stopped${RESET}")"
  printf "  Consul: %s\n"  "$([ $CONSUL_UP -eq 1 ] && echo "${GREEN}running${RESET}" || echo "${YELLOW}stopped${RESET}")"
  printf "  Bao   : %s\n"  "$([ $BAO_UP    -eq 1 ] && echo "${GREEN}running${RESET}" || echo "${YELLOW}stopped${RESET}")"
  echo
  # PID file hints (if present)
  [ -f "$VAULT_PID_FILE" ]  && echo "  (vault pid file:  $VAULT_PID_FILE)"
  [ -f "$CONSUL_PID_FILE" ] && echo "  (consul pid file: $CONSUL_PID_FILE)"
  [ -f "$BAO_PID_FILE" ]    && echo "  (bao pid file:    $BAO_PID_FILE)"
  echo
}

cleanup_all() {
  echo "→ Cleaning up Vault and Bao lab data..."
  bash -lc "$VAULT_CTRL -b $BASE_DIR cleanup" || true
  bash -lc "$BAO_CTRL   -b $BASE_DIR cleanup" || true
  echo "${GREEN}Cleanup completed.${RESET}"
}

initial_guard() {
  detect_active
  if (( VAULT_UP==0 && CONSUL_UP==0 && BAO_UP==0 )); then
    # Nothing running: go straight to menu
    return 0
  fi

  # If AUTO_MODE is set, follow it without prompting
  case "$AUTO_MODE" in
    keep)
      show_active_summary
      echo "${YELLOW}AUTO_MODE=keep:${RESET} leaving current state as-is and exiting."
      exit 0
      ;;
    wipe-continue)
      show_active_summary
      echo "${YELLOW}AUTO_MODE=wipe-continue:${RESET} wiping everything, then continuing to menu..."
      cleanup_all
      return 0
      ;;
    wipe-exit)
      show_active_summary
      echo "${YELLOW}AUTO_MODE=wipe-exit:${RESET} wiping everything and exiting..."
      cleanup_all
      exit 0
      ;;
    "") : ;;
    *) echo "${YELLOW}Unknown AUTO_MODE='$AUTO_MODE' ignored.${RESET}" ;;
  esac

  # Interactive prompt
  clear
  show_active_summary
  cat <<EOF
Choose what to do with the current state:
  K) Keep as-is and exit
  W) Wipe everything and continue to menu
  X) Wipe everything and exit
EOF
  echo
  read -r -p "Select an option [K/W/X]: " choice || true
  case "${choice:-K}" in
    K|k)
      echo "Leaving current state as-is. Exiting."
      exit 0
      ;;
    W|w)
      cleanup_all
      return 0
      ;;
    X|x)
      cleanup_all
      exit 0
      ;;
    *)
      echo "${YELLOW}Invalid choice. Defaulting to Keep & exit.${RESET}"
      exit 0
      ;;
  esac
}

trap 'echo; echo "${YELLOW}Interrupted. Returning to menu...${RESET}"' INT

# ---------- Menus ----------
menu_main() {
  clear
  cat <<EOF
${BOLD}Unified Lab Menu${RESET}
Base directory: ${BLUE}${BASE_DIR}${RESET}

Controllers:
  Vault: ${BLUE}${VAULT_CTRL}${RESET}
  Bao  : ${BLUE}${BAO_CTRL}${RESET}

Choose a technology:
  1) Vault
  2) Bao
  q) Quit
EOF
  echo
  read -r -p "Select an option [1/2/q]: " choice || true
  case "$choice" in
    1) menu_vault ;;
    2) menu_bao ;;
    q|Q) exit 0 ;;
    *) echo "${YELLOW}Invalid choice.${RESET}"; press_enter ;;
  esac
}

menu_actions() {
  cat <<EOF
Choose an action:
  1) start
  2) status
  3) restart
  4) stop
  5) cleanup
  6) reset
  b) Back
  q) Quit
EOF
  echo
  read -r -p "Select an option [1-6/b/q]: " choice || true
  case "$choice" in
    1) action="start" ;;
    2) action="status" ;;
    3) action="restart" ;;
    4) action="stop" ;;
    5) action="cleanup" ;;
    6) action="reset" ;;
    b|B) action="__back" ;;
    q|Q) action="__quit" ;;
    *) action="__invalid" ;;
  esac
}

menu_vault() {
  while true; do
    clear
    echo "${BOLD}Vault Menu${RESET}"
    echo "Backend:"
    echo "  1) file (default)"
    echo "  2) consul"
    echo
    read -r -p "Select backend [1/2, default 1]: " be || true
    case "${be:-1}" in
      1) backend="file" ;;
      2) backend="consul" ;;
      *) echo "${YELLOW}Invalid choice. Using 'file'.${RESET}"; backend="file" ;;
    esac

    echo
    menu_actions
    case "$action" in
      __back) return 0 ;;
      __quit) exit 0 ;;
      __invalid) echo "${YELLOW}Invalid choice.${RESET}"; press_enter; continue ;;
      *) : ;;
    esac

    clear
    echo "${BOLD}Vault → ${backend} → ${action}${RESET}"
    echo
    run_cmd "$VAULT_CTRL --backend $backend -b $BASE_DIR $action"
    press_enter
    [[ "$ONCE" = "1" ]] && exit 0
  done
}

menu_bao() {
  while true; do
    clear
    echo "${BOLD}Bao Menu${RESET}"
    echo "(Bao uses file storage with TLS by default)"
    echo
    menu_actions
    case "$action" in
      __back) return 0 ;;
      __quit) exit 0 ;;
      __invalid) echo "${YELLOW}Invalid choice.${RESET}"; press_enter; continue ;;
      *) : ;;
    esac

    clear
    echo "${BOLD}Bao → ${action}${RESET}"
    echo
    run_cmd "$BAO_CTRL -b $BASE_DIR $action"
    press_enter
    [[ "$ONCE" = "1" ]] && exit 0
  done
}

# ---------- Main ----------
check_ctrl
initial_guard
menu_main