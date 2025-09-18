#!/bin/bash
# Main entrypoint – deploy a local HashiCorp Vault lab environment.

# Consenti override da ambiente, default “latest”
VAULT_VERSION="${VAULT_VERSION:-latest}"
CONSUL_VERSION="${CONSUL_VERSION:-latest}"

# Calcola directory del progetto (un livello sopra a questo file)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Carica variabili e funzioni comuni
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/dependencies.sh"
source "$SCRIPT_DIR/lib/consul.sh"
source "$SCRIPT_DIR/lib/vault.sh"
source "$SCRIPT_DIR/lib/backup.sh"
source "$SCRIPT_DIR/lib/tls.sh"
source "$SCRIPT_DIR/lib/lifecycle.sh"

# Passa il controllo alla funzione main (definita in lifecycle.sh)
main "$@"
