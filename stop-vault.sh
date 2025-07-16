#!/bin/bash

# Script to stop the Vault lab environment.
# Provides an option to fully clean up the data and configuration.
#
# Usage:
#   ./stop.sh             - Stops Vault and prompts for data cleanup.
#   ./stop.sh --force     - Stops Vault and forces full data cleanup without prompting.
#   ./stop.sh -f          - Stops Vault and forces full data cleanup without prompting.
#   ./stop.sh --help      - Displays this help message.
#   ./stop.sh -h          - Displays this help message.

# --- Configuration ---
BASE_DIR="/mnt/c/Users/gomiero1/PycharmProjects/PythonProject/zero-to-vault-lab" # Your base directory
BIN_DIR="$BASE_DIR/bin"
VAULT_DIR="$BASE_DIR/vault-lab" # Vault's data and config directory
VAULT_ADDR="http://127.0.0.1:8200" # Default Vault address

# --- Global Flags ---
FORCE_CLEANUP=false

# --- Function: Display Help Message ---
display_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "This script stops the Vault lab environment and optionally cleans up its data."
    echo ""
    echo "Options:"
    echo "  -f, --force    Force full data cleanup without prompting for confirmation."
    echo "  -h, --help     Display this help message and exit."
    echo ""
    echo "Default Behavior (no options):"
    echo "  The script will stop any running Vault processes and then ask for confirmation"
    echo "  before deleting the Vault lab data and configuration from '$VAULT_DIR'."
    echo ""
    echo "Examples:"
    echo "  $0"
    echo "  $0 --force"
    echo "  $0 -f"
    echo ""
    exit 0 # Exit after displaying help
}

# --- Function: Stop Vault Processes ---
stop_vault_processes() {
    echo "=================================================="
    echo "STOPPING VAULT PROCESSES"
    echo "=================================================="

    echo "Attempting to stop all Vault processes listening on port 8200..."
    # 'lsof -ti:8200' finds PIDs listening on port 8200
    # 'xargs -r kill' kills them. -r ensures kill isn't run if no PIDs found.
    # Redirecting output to /dev/null to keep it clean.
    lsof -ti:"$(echo "$VAULT_ADDR" | cut -d':' -f3)" | xargs -r kill >/dev/null 2>&1

    # Check if any Vault processes are still running on port 8200
    if lsof -ti:"$(echo "$VAULT_ADDR" | cut -d':' -f3)" >/dev/null; then
        echo "Some Vault processes might still be running. Waiting a moment..."
        sleep 2
        if lsof -ti:"$(echo "$VAULT_ADDR" | cut -d':' -f3)" >/dev/null; then
            echo "WARNING: Failed to stop all Vault processes on port 8200."
            echo "You might need to manually kill them (e.g., 'pkill -f \"vault server\"')."
        else
            echo "Vault processes stopped."
        fi
    else
        echo "No Vault processes found or they were successfully stopped."
    fi
}

# --- Function: Clean Up Vault Data and Directories ---
clean_vault_data() {
    echo "=================================================="
    echo "CLEANING VAULT LAB DATA"
    echo "=================================================="

    if [ -d "$VAULT_DIR" ]; then
        echo "Deleting Vault lab working directory: $VAULT_DIR"
        rm -rf "$VAULT_DIR"
        echo "Vault data directory deleted."
    else
        echo "Vault data directory '$VAULT_DIR' not found. Nothing to delete."
    fi

    # Recreate the base Vault directory for future runs, but keep it empty
    echo "Recreating empty base directory: $VAULT_DIR"
    mkdir -p "$VAULT_DIR"
}

# --- Main Script Logic ---
main() {
    # --- Argument Parsing ---
    # Process arguments using getopts or a manual loop.
    # A simple loop for few options is fine, but needs careful placement.
    # We will process help first, then others.

    local arg # Declare arg as local to this function

    # Check for help option specifically as the *first* thing
    for arg in "$@"; do
        case $arg in
            -h|--help)
                display_help # This will exit the script immediately
                ;;
            -f|--force)
                FORCE_CLEANUP=true
                ;;
            *)
                echo "Error: Unknown option '$arg'" >&2 # Redirect error to stderr
                display_help # Show help for unknown options and exit
                ;;
        esac
    done

    # If we reached here, it means --help was not given or it was processed.
    # Now proceed with the core logic.

    stop_vault_processes

    # Check if the VAULT_DIR actually contains anything before asking/deleting
    if [ -d "$VAULT_DIR" ] && [ "$(ls -A "$VAULT_DIR")" ]; then
        if [ "$FORCE_CLEANUP" = true ]; then
            echo -e "\nForce cleanup activated. Removing all Vault data in '$VAULT_DIR' without prompt."
            clean_vault_data
        else
            echo -e "\nA Vault lab environment was detected in '$VAULT_DIR'."
            read -p "Do you want to completely remove all Vault data and configuration (start from scratch next time)? (y/N): " choice
            case "$choice" in
                y|Y )
                    clean_vault_data
                    ;;
                * )
                    echo "Skipping full data cleanup. Vault data and configuration in '$VAULT_DIR' will be preserved."
                    echo "You can re-use the existing data next time you start the lab, but it might require manual unsealing."
                    # Ensure the directory exists even if not cleaning, in case it was somehow removed earlier
                    mkdir -p "$VAULT_DIR"
                    ;;
            esac
        fi
    else
        echo -e "\nNo existing Vault lab data found in '$VAULT_DIR'. No data cleanup needed."
        mkdir -p "$VAULT_DIR" # Ensure it exists for consistency
    fi

    echo -e "\n=================================================="
    echo "VAULT LAB STOP SCRIPT COMPLETED."
    echo "=================================================="
    echo "To restart the lab, run your start script again."
}

# Execute the main function
main "$@" # Pass all arguments to the main function