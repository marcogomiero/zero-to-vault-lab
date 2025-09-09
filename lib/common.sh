#!/bin/bash
# lib/common.sh
# Funzioni comuni di logging, helpers per OS, validazione e gestione dei processi.

# --- Global Configuration ---
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'
COLORS_ENABLED=true

# --- Helpers OS/Binary & Logging ---
apply_color_settings() {
    if [ ! -t 1 ] || [ "$COLORS_ENABLED" != true ]; then
        GREEN=""; YELLOW=""; RED=""; NC=""
    fi
}

is_windows() {
    case "$(uname -s)" in
      *MINGW*|*MSYS*|*CYGWIN*) return 0 ;;
      *) [ -n "$OS" ] && [ "$OS" = "Windows_NT" ] && return 0 || return 1 ;;
    esac
}

get_exe() {
    local name="$1"
    if is_windows; then
      echo "$BIN_DIR/${name}.exe"
    else
      echo "$BIN_DIR/${name}"
    fi
}

log_debug() {
    [ "$VERBOSE_OUTPUT" = true ] && echo -e "${GREEN}[DEBUG]${NC} $*"
}

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }

# --- Error-handling helpers ---
safe_run() {
  local msg="$1"; shift
  if ! "$@"; then log_error "$msg (cmd: $*)"
  fi
}

warn_run() {
  local msg="$1"; shift
  if ! "$@"; then
    log_warn "$msg (cmd: $*)"
    return 1
  fi
}

# --- Validation Functions ---
validate_ports_available() {
    local vault_port=8200
    local consul_port=8500

    if lsof -Pi :$vault_port -sTCP:LISTEN -t >/dev/null ; then
        log_error "La porta $vault_port è già in uso. Chiudi il processo o usa una porta diversa."
    fi

    if [ "$BACKEND_TYPE" == "consul" ] && lsof -Pi :$consul_port -sTCP:LISTEN -t >/dev/null ; then
        log_error "La porta $consul_port è già in uso. Chiudi il processo o usa una porta diversa."
    fi
    log_info "Port validation successful. ✅"
}

validate_directories() {
    if [ ! -w "$BASE_DIR" ]; then
        log_error "La directory base $BASE_DIR non è scrivibile. Controlla i permessi."
    fi
    if [ ! -w "$(dirname "$BIN_DIR")" ]; then
        log_error "La directory padre di $BIN_DIR non è scrivibile. Controlla i permessi."
    fi
    log_info "Directory validation successful. ✅"
}

# --- Generic service stopper ---
stop_service() {
    local name="$1"
    local pid_file="$2"
    local process_pattern="$3"
    local port="$4"

    log_info "Attempting to stop ${name} server..."
    pids=$(pgrep -f "$process_pattern" || true)
    if [ -n "$pids" ]; then
        log_info "Trovati processi ${name} esistenti: $pids. Terminazione..."
        kill -TERM $pids 2>/dev/null || true; sleep 2; kill -9 $pids 2>/dev/null || true
    fi

    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if ps -p "$pid" >/dev/null; then
            log_info "Stopping ${name} process with PID $pid..."
            kill "$pid" >/dev/null 2>&1; sleep 5
            if ps -p "$pid" >/dev/null; then
                log_warn "Forcing kill for ${name} (PID: $pid)..."
                kill -9 "$pid" >/dev/null 2>&1
            fi
            log_info "${name} process stopped. ✅"
        fi
        rm -f "$pid_file"
    fi

    if [ -n "$port" ]; then
        lingering_pid=$(lsof -ti:"$port" 2>/dev/null || true)
        if [ -n "$lingering_pid" ]; then
            log_warn "Processi residui sulla porta $port: $lingering_pid. Terminazione..."
            kill -9 "$lingering_pid" 2>/dev/null || true
        fi
    fi
}

# --- Network Helpers ---
get_host_accessible_ip() {
    # Default to localhost
    local ip="127.0.0.1"
    # If running in WSL, get the specific IP for the eth0 interface
    if grep -q "microsoft" /proc/version &>/dev/null; then
        wsl_ip=$(ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
        if [ -n "$wsl_ip" ]; then
            ip="$wsl_ip"
        fi
    fi
    echo "$ip"
}