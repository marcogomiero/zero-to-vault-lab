#!/bin/bash

# --- Configurazione ---
BASE_DIR="/mnt/c/Users/gomiero1/PycharmProjects/YAML/VAULT/VAULT-LAB" # La tua base dir
BIN_DIR="$BASE_DIR/bin"
VAULT_DIR="$BASE_DIR/vault-lab"
VAULT_ADDR="http://127.0.0.1:8200" # Indirizzo predefinito di Vault

# --- FASE 0: PULIZIA AMBIENTE PRECEDENTE ---
echo "=================================================="
echo "PULIZIA COMPLETA AMBIENTE PRECEDENTE DI LABORATORIO"
echo "=================================================="

# Ferma tutti i processi Vault (potrebbe esserci un'altra istanza in ascolto)
echo "Fermo tutti i processi Vault in ascolto sulla porta 8200..."
lsof -ti:8200 | xargs -r kill >/dev/null 2>&1
sleep 1

# Cancella le directory di lavoro del laboratorio
echo "Cancello directory di lavoro precedenti..."
rm -rf "$VAULT_DIR"

# Ricrea le directory vuote
echo "Ricreo directory vuote..."
mkdir -p "$VAULT_DIR"
