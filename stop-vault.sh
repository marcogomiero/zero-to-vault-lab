#!/bin/bash

# Script to stop the Vault lab environment.
# Provides an option to fully clean up the data and configuration.
#
# Usage:
#   ./stop.sh             - Stops Vault and prompts for data cleanup.
#   ./stop.sh --force     - Stops Vault and forces full data cleanup without prompting.
#   ./stop.sh -f          - Stops Vault and forces full data cleanup without prompting.
#   ./stop.sh --no-color  - Disables colored output.
#   ./stop.sh --help      - Displays this help message.
#   ./stop.sh -h          - Displays this help message.

# --- Configuration ---
BASE_DIR="/mnt/c/Users/gomiero1/PycharmProjects/PythonProject/zero-to-vault-lab" # Your base directory
BIN_DIR="$BASE_DIR/bin"
VAULT_DIR="$BASE_DIR/vault-lab" # Vault's data and config directory
VAULT_ADDR="http://127.0.0.1:8200" # Default Vault address
LAB_VAULT_PID_FILE="$VAULT_DIR/vault.pid" # File to store the PID of the running Vault server

# --- Global Flags ---
FORCE_CLEANUP=false
COLORS_ENABLED=true # Flag to control colored output. Default to true.

# --- Colors for better output (initial setup) ---
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Logging Functions (copied from setup-lab-vault.sh for consistency) ---
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

# --- Function: Display Help Message ---
display_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "This script stops the Vault lab environment and optionally cleans up its data."
    echo ""
    echo "Options:"
    echo "  -f, --force    Force full data cleanup without prompting for confirmation."
    echo "  -h, --help     Display this help message and exit."
    echo "  --no-color     Disable colored output, useful for logging or non-interactive environments."
    echo ""
    echo "Default Behavior (no options):"
    echo "  The script will stop any running Vault processes and then ask for confirmation"
    echo "  before deleting the Vault lab data and configuration from '$VAULT_DIR'."
    echo ""
    echo "Examples:"
    echo "  $0"
    echo "  $0 --force"
    echo "  $0 --no-color"
    echo ""
    exit 0 # Exit after displaying help
}

# --- Function: Stop Vault Processes (Enhanced) ---
stop_vault_processes() {
    log_info "=================================================="
    log_info "STOPPING VAULT PROCESSES"
    log_info "=================================================="

    local vault_port=$(echo "$VAULT_ADDR" | cut -d':' -f3)

    # First, try to stop using the PID file (most targeted approach)
    if [ -f "$LAB_VAULT_PID_FILE" ]; then
        local pid=$(cat "$LAB_VAULT_PID_FILE")
        if ps -p "$pid" > /dev/null; then
            log_info "Found running Vault process with PID $pid (from $LAB_VAULT_PID_FILE). Attempting graceful shutdown..."
            kill "$pid" >/dev/null 2>&1
            sleep 5 # Give it some time to shut down
            if ps -p "$pid" > /dev/null; then
                log_warn "Vault process (PID: $pid) did not shut down gracefully. Forcing kill..."
                kill -9 "$pid" >/dev/null 2>&1
                sleep 1 # Give it a moment to release the port
            fi
            if ! ps -p "$pid" > /dev/null; then
                log_info "Vault process (PID: $pid) stopped. ✅"
                rm -f "$LAB_VAULT_PID_FILE"
            else
                log_error "Vault process (PID: $pid) could not be stopped. Manual intervention may be required. 🛑"
                return 1 # Indicate failure
            fi
        else
            log_info "No active Vault process found with PID $pid (from $LAB_VAULT_PID_FILE). PID file seems stale."
            rm -f "$LAB_VAULT_PID_FILE" # Clean up stale PID file
        fi
    else
        log_info "No Vault PID file found ($LAB_VAULT_PID_FILE). Checking port $vault_port for active processes."
    fi

    # Fallback/additional check: use lsof to find and kill processes on the Vault port
    local lingering_pid=$(lsof -ti:"$vault_port" 2>/dev/null)
    if [ -n "$lingering_pid" ]; then
        log_warn "Found lingering process(es) on Vault port $vault_port (PIDs: $lingering_pid). Attempting to kill them."
        kill -9 "$lingering_pid" >/dev/null 2>&1
        sleep 1
        if lsof -ti:"$vault_port" >/dev/null; then
             log_error "Could not clear port $vault_port. Manual intervention required. 🛑"
             return 1 # Indicate failure
        else
            log_info "Lingering processes on port $vault_port cleared. ✅"
        fi
    else
        log_info "No lingering processes found on port $vault_port."
    fi

    log_info "Vault processes stop routine completed."
    return 0 # Indicate success
}

# --- Function: Clean Up Vault Data and Directories ---
clean_vault_data() {
    log_info "=================================================="
    log_info "CLEANING VAULT LAB DATA"
    log_info "=================================================="

    if [ -d "$VAULT_DIR" ]; then
        log_info "Deleting Vault lab working directory: $VAULT_DIR"
        rm -rf "$VAULT_DIR"
        if [ $? -ne 0 ]; then
            log_error "Failed to remove '$VAULT_DIR'. Check permissions. ❌"
        fi
        log_info "Vault data directory deleted. ✅"
    else
        log_info "Vault data directory '$VAULT_DIR' not found. Nothing to delete."
    fi

    # Recreate the base Vault directory for future runs, but keep it empty
    log_info "Recreating empty base directory: $VAULT_DIR"
    mkdir -p "$VAULT_DIR"
    if [ $? -ne 0 ]; then
        log_error "Failed to create '$VAULT_DIR'. Check permissions. ❌"
    fi
    log_info "Base directory recreated. ✅"
}

# --- Main Script Logic ---
main() {
    # Determine if colors should be enabled by default (if stdout is a TTY)
    # This must happen before processing args, so --no-color can override it.
    if [ ! -t 1 ]; then # If stdout is NOT a TTY (e.g., redirected to a file or pipe)
        COLORS_ENABLED=false
    fi

    # --- Argument Parsing ---
    local arg # Declare arg as local to this function

    # Process arguments to set global flags
    for arg in "$@"; do
        case $arg in
            -h|--help)
                display_help # This will exit the script immediately
                ;;
            -f|--force)
                FORCE_CLEANUP=true
                ;;
            --no-color)
                COLORS_ENABLED=false
                ;;
            *)
                log_error "Unknown option '$arg'. Use -h or --help for usage."
                ;;
        esac
    done

    # Apply color disabling *after* parsing options and TTY check
    if [ "$COLORS_ENABLED" = false ]; then
        GREEN=''
        YELLOW=''
        RED=''
        NC=''
    fi

    # Core logic begins
    stop_vault_processes || log_error "Failed to stop Vault processes. Exiting cleanup."

    # Check if the VAULT_DIR actually contains anything before asking/deleting
    if [ -d "$VAULT_DIR" ] && [ "$(ls -A "$VAULT_DIR" 2>/dev/null)" ]; then
        if [ "$FORCE_CLEANUP" = true ]; then
            log_info "Force cleanup activated. Removing all Vault data in '$VAULT_DIR' without prompt."
            clean_vault_data
        else
            log_warn "\nA Vault lab environment was detected in '$VAULT_DIR'."
            read -p "$(echo -e "${YELLOW}Do you want to completely remove all Vault data and configuration (start from scratch next time)? (y/N): ${NC}")" choice
            case "$choice" in
                y|Y )
                    clean_vault_data
                    ;;
                * )
                    log_info "Skipping full data cleanup. Vault data and configuration in '$VAULT_DIR' will be preserved."
                    log_info "You can re-use the existing data next time you start the lab, but it might require manual unsealing."
                    # Ensure the directory exists even if not cleaning, in case it was somehow removed earlier
                    mkdir -p "$VAULT_DIR"
                    ;;
            esac
        fi
    else
        log_info "No existing Vault lab data found in '$VAULT_DIR'. No data cleanup needed."
        mkdir -p "$VAULT_DIR" # Ensure it exists for consistency
    fi

    log_info "\n=================================================="
    log_info "VAULT LAB STOP SCRIPT COMPLETED."
    log_info "=================================================="
    log_info "To restart the lab, run your setup script (e.g., './setup-lab-vault.sh') again."
}

# Execute the main function
main "$@"