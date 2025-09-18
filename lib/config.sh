#!/bin/bash
# lib/config.sh – variabili globali

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." &> /dev/null && pwd )"
BASE_DIR="$SCRIPT_DIR"

BIN_DIR="$SCRIPT_DIR/bin"
VAULT_DIR="$SCRIPT_DIR/vault-data"
CONSUL_DIR="$SCRIPT_DIR/consul-data"
VAULT_ADDR="http://127.0.0.1:8200"
CONSUL_ADDR="http://127.0.0.1:8500"
LAB_VAULT_PID_FILE="$VAULT_DIR/vault.pid"
LAB_CONSUL_PID_FILE="$CONSUL_DIR/consul.pid"
LAB_CONFIG_FILE="$SCRIPT_DIR/vault-lab-ctl.conf"
AUDIT_LOG_PATH="/dev/null"

CLUSTER_MODE=""
ENABLE_TLS=false
TLS_ENABLED_FROM_ARG=false
FORCE_CLEANUP_ON_START=false
VERBOSE_OUTPUT=false
BACKEND_TYPE_SET_VIA_ARG=false
BACKEND_TYPE="file"
