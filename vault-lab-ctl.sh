#!/bin/bash
# A script to deploy a local HashiCorp Vault lab environment.
# Main entrypoint - loads functions from the lib/ directory.

# --- Setup Script Directory ---
# Ensures that sourcing works correctly regardless of where the script is called from

# VERSION TO DOWNLOAF
VAULT_VERSION="${VAULT_VERSION:-latest}"
CONSUL_VERSION="${CONSUL_VERSION:-latest}"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# --- Global Configuration ---
BASE_DIR="/mnt/c/Users/gomiero1/PycharmProjects/PythonProject/zero-to-vault-lab-v2"
BIN_DIR="$BASE_DIR/bin"
VAULT_DIR="$BASE_DIR/vault-data"
CONSUL_DIR="$BASE_DIR/consul-data"
VAULT_ADDR="http://127.0.0.1:8200"
CONSUL_ADDR="http://127.0.0.1:8500"
LAB_VAULT_PID_FILE="$VAULT_DIR/vault.pid"
LAB_CONSUL_PID_FILE="$CONSUL_DIR/consul.pid"
LAB_CONFIG_FILE="$BASE_DIR/vault-lab-ctl.conf"
AUDIT_LOG_PATH="/dev/null"

# --- CLUSTER ---
CLUSTER_MODE=""   # single | multi, via --cluster or prompt

# --- TLS Configuration ---
ENABLE_TLS=false
TLS_ENABLED_FROM_ARG=false

# --- Script Behavior Flags ---
FORCE_CLEANUP_ON_START=false
VERBOSE_OUTPUT=false
BACKEND_TYPE_SET_VIA_ARG=false
BACKEND_TYPE="file" # Default backend

# --- Source Library Files ---
# Load all the logic from external files for better organization
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/dependencies.sh"
source "$SCRIPT_DIR/lib/consul.sh"
source "$SCRIPT_DIR/lib/vault.sh"
source "$SCRIPT_DIR/lib/backup.sh"
source "$SCRIPT_DIR/lib/tls.sh"
source "$SCRIPT_DIR/lib/lifecycle.sh"

# --- Execute Main Function ---
# The main function, defined in lib/lifecycle.sh, parses arguments and runs the requested command.
main "$@"