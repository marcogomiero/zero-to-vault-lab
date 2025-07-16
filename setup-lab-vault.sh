#!/bin/bash

# Script per configurare un ambiente Vault di laboratorio pronto all'uso.
# - Una singola istanza Vault.
# - Già inizializzata e sbloccata.
# - Root token impostato a "root".
# - Alcuni secrets engine comuni abilitati.
# - AppRole abilitato e configurato con un esempio.
# - Audit Device abilitato.
# - Scarica automaticamente l'ultima versione di Vault (escludendo solo le versioni enterprise).
# - Messaggistica migliorata per chiarezza sul processo di download/aggiornamento.

# --- Configurazione Globale ---
BASE_DIR="/mnt/c/Users/gomiero1/PycharmProjects/PythonProject/zero-to-vault-lab" # La tua base dir
BIN_DIR="$BASE_DIR/bin"
VAULT_DIR="$BASE_DIR/vault-lab"
VAULT_ADDR="http://127.0.0.1:8200" # Indirizzo predefinito di Vault
LAB_VAULT_PID="" # Variabile globale per il PID di Vault

# Percorso per l'Audit Log (percorso predefinito per il laboratorio è /dev/null)
# Per abilitare l'audit su un file reale, cambiare questa variabile. Esempio:
# AUDIT_LOG_PATH="$VAULT_DIR/vault_audit.log"
AUDIT_LOG_PATH="/dev/null"

# --- Funzione: Download o aggiornamento del binario Vault ---
download_latest_vault_binary() {
    local bin_dir="$1"
    local platform="linux_amd64"
    local vault_exe="$bin_dir/vault"
    local temp_dir=$(mktemp -d)
    local success=1

    echo "=================================================="
    echo "GESTIONE BINARIO VAULT: CONTROLLO E SCARICAMENTO"
    echo "=================================================="

    local missing_deps=false
    if ! command -v jq &> /dev/null; then
        echo "ATTENZIONE: 'jq' non trovato. Si prega di installarlo (es. 'sudo apt install jq')."
        missing_deps=true
    fi
    if ! command -v curl &> /dev/null; then
        echo "ATTENZIONE: 'curl' non trovato. Si prega di installarlo (es. 'sudo apt install curl')."
        missing_deps=true
    fi
    if ! command -v unzip &> /dev/null; then
        echo "ATTENZIONE: 'unzip' non trovato. Si prega di installarlo (es. 'sudo apt install unzip')."
        missing_deps=true
    fi

    if [ "$missing_deps" = true ]; then
        echo "Impossibile procedere con il download automatico a causa di dipendenze mancanti."
        rm -rf "$temp_dir"
        return 1
    fi

    local vault_releases_json
    vault_releases_json=$(curl -s "https://releases.hashicorp.com/vault/index.json")

    if [ -z "$vault_releases_json" ]; then
        echo "Errore: 'curl' non ha ricevuto dati dalla URL di HashiCorp. Controllare la connessione internet o l'URL: https://releases.hashicorp.com/vault/index.json"
        rm -rf "$temp_dir"
        return 1
    fi

    local latest_version
    latest_version=$(echo "$vault_releases_json" | \
                     tr -d '\r' | \
                     jq -r '.versions | to_entries | .[] | select(.key | contains("ent") | not) | .value.version' | \
                     sort -V | tail -n 1)

    if [ -z "$latest_version" ]; then
        echo "Errore: Impossibile determinare l'ultima versione di Vault. La struttura JSON potrebbe essere cambiata o nessun match trovato."
        rm -rf "$temp_dir"
        return 1
    fi

    echo "Ultima versione disponibile (incluse eventuali release candidate): $latest_version"

    if [ -f "$vault_exe" ]; then
        local current_version
        current_version=$("$vault_exe" version -short 2>/dev/null | awk '{print $2}')
        current_version=${current_version#v}

        if [ "$current_version" == "$latest_version" ]; then
            echo "Il binario Vault corrente (v$current_version) è già l'ultima versione disponibile."
            echo "Nessun download o aggiornamento necessario. Verrà usato il binario esistente."
            rm -rf "$temp_dir"
            return 0
        else
            echo "Il binario Vault corrente è v$current_version. L'ultima versione disponibile è v$latest_version."
            echo "Procedo con l'aggiornamento..."
        fi
    else
        echo "Nessun binario Vault trovato in $bin_dir. Procedo con lo scaricamento dell'ultima versione."
    fi

    local download_url="https://releases.hashicorp.com/vault/${latest_version}/vault_${latest_version}_${platform}.zip"
    local zip_file="$temp_dir/vault.zip"

    echo "Scaricando Vault v$latest_version per $platform da $download_url..."
    if ! curl -fsSL -o "$zip_file" "$download_url"; then
        echo "Errore: Fallito lo scaricamento di Vault da $download_url."
        rm -rf "$temp_dir"
        return 1
    fi

    echo "Estrazione del binario..."
    if ! unzip -o "$zip_file" -d "$temp_dir" >/dev/null; then
        echo "Errore: Fallita l'estrazione del file zip."
        rm -rf "$temp_dir"
        return 1
    fi

    if [ -f "$temp_dir/vault" ]; then
        echo "Spostamento e configurazione del nuovo binario Vault in $bin_dir..."
        mkdir -p "$bin_dir"
        mv "$temp_dir/vault" "$vault_exe"
        chmod +x "$vault_exe"
        success=0
        echo "Vault v$latest_version scaricato e configurato con successo."
    else
        echo "Errore: Binario 'vault' non trovato nell'archivio estratto."
    fi

    rm -rf "$temp_dir"
    return $success
}

# --- Funzione: Attendi che Vault sia UP e risponda alle API ---
wait_for_vault_up() {
  local addr=$1
  local timeout=30 # Tempo massimo di attesa in secondi
  local elapsed=0

  echo "Attesa che Vault sia in ascolto su $addr..."
  while [[ $elapsed -lt $timeout ]]; do
    if curl -s -o /dev/null -w "%{http_code}" "$addr/v1/sys/seal-status" | grep -q "200"; then
      echo "Vault è in ascolto e risponde alle API dopo $elapsed secondi."
      return 0
    fi
    sleep 1
    echo -n "."
    ((elapsed++))
  done
  echo -e "\nVault non è diventato raggiungibile dopo $timeout secondi. Controllare i log ($VAULT_DIR/vault.log)."
  exit 1
}

# --- Funzione: Pulisci ambiente precedente ---
cleanup_previous_environment() {
    echo "=================================================="
    echo "PULIZIA COMPLETA AMBIENTE PRECEDENTE DI LABORATORIO"
    echo "=================================================="

    echo "Fermo tutti i processi Vault in ascolto sulla porta 8200..."
    lsof -ti:8200 | xargs -r kill >/dev/null 2>&1
    sleep 1

    echo "Cancello directory di lavoro precedenti..."
    rm -rf "$VAULT_DIR"

    echo "Ricreo directory vuote..."
    mkdir -p "$VAULT_DIR"
}

# --- Funzione: Configura e avvia Vault ---
# --- Funzione: Configura e avvia Vault ---
configure_and_start_vault() {
    echo -e "\n=================================================="
    echo "CONFIGURAZIONE VAULT DI LABORATORIO (ISTANZA SINGOLA)"
    echo "=================================================="

    echo "Configurazione del file di Vault..."
    cat > "$VAULT_DIR/config.hcl" <<EOF
storage "file" {
  path = "$VAULT_DIR/storage"
}

listener "tcp" {
  address     = "127.0.0.1:8200"
  tls_disable = 1
}

api_addr = "http://127.0.0.1:8200"
cluster_addr = "http://127.0.0.1:8201"
ui = true
EOF

    echo "Avvio Vault server in background..."
    "$BIN_DIR/vault" server -config="$VAULT_DIR/config.hcl" > "$VAULT_DIR/vault.log" 2>&1 &
    LAB_VAULT_PID=$!
    echo "PID Vault server: $LAB_VAULT_PID"

    # Nuova chiamata alla funzione di attesa
    wait_for_vault_up "$VAULT_ADDR"
}

# --- Funzione: Attendi che Vault sia UNSEALED e pronto ---
wait_for_unseal_ready() {
  local addr=$1
  local timeout=30
  local elapsed=0

  echo "Attesa che Vault sia completamente sbloccato e operativo per le API..."
  while [[ $elapsed -lt $timeout ]]; do
    status_output=$("$BIN_DIR/vault" status -address=$addr 2>/dev/null)
    if echo "$status_output" | grep -q "Sealed.*false"; then
      echo "Vault è sbloccato e operativo dopo $elapsed secondi."
      return 0
    fi
    sleep 1
    echo -n "."
    ((elapsed++))
  done
  echo -e "\nVault non è diventato operativo dopo $timeout secondi. Controllare i log."
  exit 1
}


# --- Funzione: Inizializza e sblocca Vault ---
initialize_and_unseal_vault() {
    echo -e "\nInizializzo Vault..."
    export VAULT_ADDR="$VAULT_ADDR"
    local INIT_OUTPUT
    INIT_OUTPUT=$("$BIN_DIR/vault" operator init -key-shares=1 -key-threshold=1 -format=json)

    local ROOT_TOKEN_VAULT
    ROOT_TOKEN_VAULT=$(echo "$INIT_OUTPUT" | jq -r '.root_token')
    local UNSEAL_KEY_VAULT
    UNSEAL_KEY_VAULT=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[0]')

    echo "$ROOT_TOKEN_VAULT" > "$VAULT_DIR/root_token.txt"
    echo "$UNSEAL_KEY_VAULT" > "$VAULT_DIR/unseal_key.txt"

    echo "Vault inizializzato."

    echo "Eseguo l'unseal del Vault con la chiave generata..."
    "$BIN_DIR/vault" operator unseal "$UNSEAL_KEY_VAULT"
    echo "Vault sbloccato."

    wait_for_unseal_ready "$VAULT_ADDR"

    echo "Imposto il root token a 'root' (solo per laboratorio, non per produzione!)..."
    export VAULT_TOKEN="$ROOT_TOKEN_VAULT"
    "$BIN_DIR/vault" token create -id="root" -policy="root" -no-default-policy -display-name="laboratory-root" >/dev/null

    echo "root" > "$VAULT_DIR/root_token.txt"
    export VAULT_TOKEN="root"
}


# --- Funzione: Configura AppRole ---
configure_approle() {
    echo -e "\nAbilito e configuro Auth Method AppRole..."

    echo " - Abilito Auth Method 'approle' a 'approle/'"
    "$BIN_DIR/vault" auth enable approle

    cat > "$VAULT_DIR/approle-policy.hcl" <<EOF
path "secret/my-app/*" {
  capabilities = ["read", "list"]
}
path "secret/other-data" {
  capabilities = ["read"]
}
EOF

    echo " - Creo policy 'my-app-policy' per AppRole..."
    "$BIN_DIR/vault" policy write my-app-policy "$VAULT_DIR/approle-policy.hcl"

    echo " - Creo ruolo AppRole 'web-application'..."
    "$BIN_DIR/vault" write auth/approle/role/web-application \
        token_policies="default,my-app-policy" \
        token_ttl="1h" \
        token_max_ttl="24h"

    local ROLE_ID
    ROLE_ID=$("$BIN_DIR/vault" read -field=role_id auth/approle/role/web-application/role-id)
    echo "   Role ID per 'web-application': $ROLE_ID (salvato in $VAULT_DIR/approle_role_id.txt)"
    echo "$ROLE_ID" > "$VAULT_DIR/approle_role_id.txt"

    local SECRET_ID
    SECRET_ID=$("$BIN_DIR/vault" write -f -field=secret_id auth/approle/role/web-application/secret-id)
    echo "   Secret ID per 'web-application': $SECRET_ID (salvato in $VAULT_DIR/approle_secret_id.txt)"
    echo "$SECRET_ID" > "$VAULT_DIR/approle_secret_id.txt"

    echo "Configurazione AppRole completata per il ruolo 'web-application'."
}


# --- Funzione: Configura Audit Device (usa la variabile globale AUDIT_LOG_PATH) ---
configure_audit_device() {
    echo -e "\nAbilito e configuro un Audit Device..."
    echo " - Abilito audit device su file a '$AUDIT_LOG_PATH'"
    "$BIN_DIR/vault" audit enable file file_path="$AUDIT_LOG_PATH"

    echo "Audit Device configurato. I log saranno scritti in $AUDIT_LOG_PATH"
}


# --- Funzione: Abilita e configura funzionalità comuni ---
configure_vault_features() {
    echo -e "\nAbilito e configuro funzionalità comuni..."

    echo " - Abilito secrets engine KV v2 a 'secret/'"
    "$BIN_DIR/vault" secrets enable -path=secret kv-v2

    echo " - Abilito secrets engine PKI a 'pki/'"
    "$BIN_DIR/vault" secrets enable pki
    "$BIN_DIR/vault" secrets tune -max-lease-ttl=87600h pki

    echo " - Abilito Auth Method 'userpass' a 'userpass/'"
    "$BIN_DIR/vault" auth enable userpass

    echo " - Creo utente di esempio 'devuser' con password 'devpass'"
    "$BIN_DIR/vault" write auth/userpass/users/devuser password=devpass policies=default

    configure_approle
    configure_audit_device
}


# --- Funzione: Mostra informazioni finali ---
display_final_info() {
    echo -e "\n=================================================="
    echo "VAULT DI LABORATORIO PRONTO ALL'USO!"
    echo "=================================================="

    echo -e "\nDETTAGLI ACCESSO PRINCIPALI:"
    echo "URL: $VAULT_ADDR"
    echo "Root Token: root (salvato anche in $VAULT_DIR/root_token.txt)"
    echo "Utente di esempio: devuser / devpass (con policy 'default')"

    echo -e "\nDETTAGLI APPROLE 'web-application':"
    echo "Role ID: $(cat "$VAULT_DIR/approle_role_id.txt")"
    echo "Secret ID: $(cat "$VAULT_DIR/approle_secret_id.txt")"

    echo -e "\nStato attuale del Vault:"
    "$BIN_DIR/vault" status

    echo -e "\nPer accedere a Vault UI/CLI, usa:"
    echo "export VAULT_ADDR=$VAULT_ADDR"
    echo "export VAULT_TOKEN=root"
    echo "Oppure accedi alla UI all'indirizzo sopra e usa 'root' come token."

    echo -e "\nPer testare l'autenticazione AppRole:"
    echo "export VAULT_ADDR=$VAULT_ADDR"
    echo "vault write auth/approle/login role_id=\"$(cat "$VAULT_DIR/approle_role_id.txt")\" secret_id=\"$(cat "$VAULT_DIR/approle_secret_id.txt")\""
    echo "Ricorda che il Secret ID è monouso per le nuove creazioni, ma questo token è valido per il login."

    echo -e "\nPer fermare il server: kill $LAB_VAULT_PID"
    echo "O per fermare tutti i Vault in esecuzione: pkill -f \"vault server\""

    echo -e "\nBuon divertimento con Vault!"
}


# --- Flusso Principale dello Script ---
main() {
    cleanup_previous_environment

    mkdir -p "$BIN_DIR"
    if download_latest_vault_binary "$BIN_DIR" "linux_amd64"; then
        echo "Il binario Vault è pronto per l'uso."
    else
        echo "La gestione automatica del binario Vault non è riuscita completamente."
        if [ -f "$BIN_DIR/vault" ]; then
            echo "Verrà utilizzato il binario Vault esistente in $BIN_DIR/vault."
        else
            echo "ERRORE FATALE: Nessun binario Vault disponibile. Scarica manualmente il binario desiderato e posizionalo in $BIN_DIR/vault."
            exit 1
        fi
    fi
    echo "=================================================="

    configure_and_start_vault
    initialize_and_unseal_vault
    configure_vault_features
    display_final_info
}

# Esegui la funzione principale
main
