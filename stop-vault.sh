#!/bin/bash

# --- Configuration ---
BASE_DIR="/mnt/c/Users/gomiero1/PycharmProjects/PythonProject/zero-to-vault-lab" # Your base directory
BIN_DIR="$BASE_DIR/bin"
VAULT_DIR="$BASE_DIR/vault-lab"
VAULT_ADDR="http://127.0.0.1:8200" # Default Vault address

# --- PHASE 0: CLEANUP PREVIOUS ENVIRONMENT ---
echo "=================================================="
echo "FULL CLEANUP OF PREVIOUS LAB ENVIRONMENT"
echo "=================================================="

# Stop all Vault processes (there might be another instance listening)
echo "Stopping all Vault processes listening on port 8200..."
lsof -ti:8200 | xargs -r kill >/dev/null 2>&1
sleep 1

# Delete lab working directories
echo "Deleting previous working directories..."
rm -rf "$VAULT_DIR"

# Recreate empty directories
echo "Recreating empty directories..."
mkdir -p "$VAULT_DIR"