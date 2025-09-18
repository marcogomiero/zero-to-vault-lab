#!/bin/bash
# lib/tls.sh
# Funzioni per la generazione automatica di certificati TLS per il lab Vault

# --- Configuration ---
TLS_DIR="$SCRIPT_DIR/tls"
CA_DIR="$TLS_DIR/ca"
CERTS_DIR="$TLS_DIR/certs"
CA_KEY="$CA_DIR/ca-key.pem"
CA_CERT="$CA_DIR/ca-cert.pem"
CA_CONFIG="$CA_DIR/ca-config.json"
CA_CSR="$CA_DIR/ca-csr.json"

# --- TLS Management Functions ---

check_tls_prerequisites() {
    # Usa OpenSSL che è universalmente disponibile
    if ! command -v openssl &> /dev/null; then
        log ERROR "OpenSSL is required but not found. Please install OpenSSL."
    fi
    log INFO "TLS prerequisites satisfied (OpenSSL available)."
}

generate_ca_certificate() {
    log INFO "Generating Certificate Authority (CA) with OpenSSL..."
    mkdir -p "$CA_DIR"

    # Genera CA se non esiste
    if [ ! -f "$CA_CERT" ] || [ ! -f "$CA_KEY" ]; then
        log INFO "Creating CA private key..."
        openssl genrsa -out "$CA_KEY" 2048 || log ERROR "Failed to generate CA private key"

        log INFO "Creating CA certificate..."
        openssl req -new -x509 -key "$CA_KEY" -sha256 -days 3650 -out "$CA_CERT" \
            -subj "/C=IT/ST=Virtual/L=Lab/O=Vault Lab/CN=Vault Lab CA" \
            || log ERROR "Failed to generate CA certificate"

        log INFO "CA certificate generated: $CA_CERT"
    else
        log INFO "CA certificate already exists, reusing."
    fi

    # Verifica che i file CA esistano
    if [ ! -f "$CA_CERT" ] || [ ! -f "$CA_KEY" ]; then
        log ERROR "CA certificate or key missing after generation"
    fi
}

generate_vault_certificate() {
    local node_name="${1:-vault-server}"
    local node_ip="${2:-127.0.0.1}"
    local additional_sans="${3:-}"

    log INFO "Generating TLS certificate for Vault node: $node_name"
    mkdir -p "$CERTS_DIR"

    local cert_file="$CERTS_DIR/${node_name}.pem"
    local key_file="$CERTS_DIR/${node_name}-key.pem"
    local csr_file="$CERTS_DIR/${node_name}.csr"

    if [ ! -f "$cert_file" ] || [ ! -f "$key_file" ]; then
        # Genera chiave privata
        openssl genrsa -out "$key_file" 2048 || log ERROR "Failed to generate private key for $node_name"

        # Crea CSR
        openssl req -new -key "$key_file" -out "$csr_file" \
            -subj "/C=IT/ST=Virtual/L=Lab/O=Vault Lab/CN=$node_name" \
            || log ERROR "Failed to generate CSR for $node_name"

        # Crea config per Subject Alternative Names
        local san_config="$CERTS_DIR/${node_name}.conf"
        cat > "$san_config" <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req

[req_distinguished_name]

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = $node_name
IP.1 = 127.0.0.1
IP.2 = $node_ip
EOF

        # Aggiungi SAN aggiuntivi se specificati
        if [ -n "$additional_sans" ]; then
            echo "# Additional SANs" >> "$san_config"
            echo "$additional_sans" >> "$san_config"
        fi

        # Genera certificato firmato dalla CA
        openssl x509 -req -in "$csr_file" -CA "$CA_CERT" -CAkey "$CA_KEY" \
            -CAcreateserial -out "$cert_file" -days 365 \
            -extensions v3_req -extfile "$san_config" \
            || log ERROR "Failed to generate certificate for $node_name"

        # Cleanup
        rm -f "$csr_file" "$san_config"

        log INFO "Vault certificate generated: $cert_file"
    else
        log INFO "Vault certificate already exists for $node_name, reusing."
    fi

    # Restituisci i percorsi dei file
    echo "CERT_FILE=$cert_file"
    echo "KEY_FILE=$key_file"
}

generate_consul_certificate() {
    local node_name="${1:-consul-server}"
    local node_ip="${2:-127.0.0.1}"

    log INFO "Generating TLS certificate for Consul node: $node_name"
    mkdir -p "$CERTS_DIR"

    local cert_file="$CERTS_DIR/${node_name}.pem"
    local key_file="$CERTS_DIR/${node_name}-key.pem"
    local csr_file="$CERTS_DIR/${node_name}.csr"

    if [ ! -f "$cert_file" ] || [ ! -f "$key_file" ]; then
        # Genera chiave privata
        openssl genrsa -out "$key_file" 2048 || log ERROR "Failed to generate private key for $node_name"

        # Crea CSR
        openssl req -new -key "$key_file" -out "$csr_file" \
            -subj "/C=IT/ST=Virtual/L=Lab/O=Vault Lab/CN=$node_name" \
            || log ERROR "Failed to generate CSR for $node_name"

        # Crea config per SAN
        cat > "$CERTS_DIR/${node_name}.conf" <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req

[req_distinguished_name]

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = $node_name
IP.1 = 127.0.0.1
IP.2 = $node_ip
EOF

        # Genera certificato firmato dalla CA
        openssl x509 -req -in "$csr_file" -CA "$CA_CERT" -CAkey "$CA_KEY" \
            -CAcreateserial -out "$cert_file" -days 365 \
            -extensions v3_req -extfile "$CERTS_DIR/${node_name}.conf" \
            || log ERROR "Failed to generate certificate for $node_name"

        # Cleanup
        rm -f "$csr_file" "$CERTS_DIR/${node_name}.conf"

        log INFO "Consul certificate generated: $cert_file"
    else
        log INFO "Consul certificate already exists for $node_name, reusing."
    fi

    echo "CERT_FILE=$cert_file"
    echo "KEY_FILE=$key_file"
}

setup_tls_infrastructure() {
    log INFO "SETTING UP TLS INFRASTRUCTURE"

    check_tls_prerequisites
    generate_ca_certificate

    # Genera certificati per Vault
    if [ "$CLUSTER_MODE" = "multi" ]; then
        for i in 1 2 3; do
            generate_vault_certificate "vault-node$i" "127.0.0.1"
        done
    else
        generate_vault_certificate "vault-server" "127.0.0.1"
    fi

    # Genera certificati per Consul se necessario
    if [ "$BACKEND_TYPE" == "consul" ]; then
        generate_consul_certificate "consul-server" "127.0.0.1"
    fi

    log INFO "TLS infrastructure setup completed."
}

verify_certificate() {
    local cert_file="$1"
    local service_name="$2"

    if [ ! -f "$cert_file" ]; then
        log ERROR "Certificate file not found: $cert_file"
        return 1
    fi

    log INFO "Verifying certificate for $service_name..."

    # Verifica validità del certificato
    if ! openssl x509 -in "$cert_file" -text -noout >/dev/null 2>&1; then
        log ERROR "Invalid certificate format: $cert_file"
        return 1
    fi

    # Verifica data di scadenza
    local expiry_date=$(openssl x509 -in "$cert_file" -enddate -noout | cut -d= -f2)
    local expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$expiry_date" +%s 2>/dev/null || echo "0")
    local current_epoch=$(date +%s)

    if [ "$expiry_epoch" -le "$current_epoch" ]; then
        log WARN "Certificate for $service_name has expired or expires soon: $expiry_date"
        return 1
    fi

    local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
    log INFO "Certificate for $service_name is valid for $days_until_expiry more days."

    return 0
}

cleanup_expired_certificates() {
    log INFO "Checking for expired certificates..."

    local expired_found=false
    for cert_file in "$CERTS_DIR"/*.pem; do
        if [ -f "$cert_file" ] && [[ "$cert_file" != *"-key.pem" ]]; then
            local service_name=$(basename "$cert_file" .pem)
            if ! verify_certificate "$cert_file" "$service_name"; then
                log INFO "Removing expired certificate: $cert_file"
                rm -f "$cert_file" "${cert_file%-*}-key.pem"
                expired_found=true
            fi
        fi
    done

    if [ "$expired_found" = true ]; then
        log INFO "Expired certificates removed. Run setup again to regenerate."
    else
        log INFO "No expired certificates found."
    fi
}

# --- Integration functions to modify existing Vault/Consul configs ---

configure_vault_with_tls() {
    local node_name="${1:-vault-server}"
    local port="${2:-8200}"
    local cluster_port="${3:-8201}"

    setup_tls_infrastructure

    local storage_config=""
    if [ "$BACKEND_TYPE" == "file" ]; then
        mkdir -p "$VAULT_DIR/storage"
        storage_config="storage \"file\" { path = \"$VAULT_DIR/storage\" }"
    elif [ "$BACKEND_TYPE" == "consul" ]; then
        local consul_token=$(cat "$CONSUL_DIR/acl_master_token.txt" 2>/dev/null)
        if [ -z "$consul_token" ]; then
            log ERROR "Consul ACL token not found. Start Consul first."
        fi
        storage_config="storage \"consul\" {
            address = \"127.0.0.1:8500\"
            path = \"vault/\"
            token = \"$consul_token\"
            scheme = \"https\"
            tls_ca_file = \"$CA_CERT\"
        }"
    fi

    cat > "$VAULT_DIR/config.hcl" <<EOF
$storage_config
listener "tcp" {
  address       = "127.0.0.1:$port"
  tls_cert_file = "$CERTS_DIR/${node_name}.pem"
  tls_key_file  = "$CERTS_DIR/${node_name}-key.pem"
  tls_ca_file   = "$CA_CERT"
}
api_addr = "https://127.0.0.1:$port"
cluster_addr = "https://127.0.0.1:$cluster_port"
ui = true
EOF

    # Aggiorna le variabili globali per usare HTTPS
    VAULT_ADDR="https://127.0.0.1:$port"
    export VAULT_CACERT="$CA_CERT"
    export VAULT_ADDR="$VAULT_ADDR"
}

configure_consul_with_tls() {
    setup_tls_infrastructure

    cat > "$CONSUL_DIR/consul_config.hcl" <<EOF
datacenter = "dc1"
data_dir = "$CONSUL_DIR/data"
server = true
bootstrap_expect = 1
client_addr = "0.0.0.0"
ui_config {
  enabled = true
}
ports {
    http = -1
    https = 8500
}
ca_file = "$CA_CERT"
cert_file = "$CERTS_DIR/consul-server.pem"
key_file = "$CERTS_DIR/consul-server-key.pem"
verify_incoming = false
verify_outgoing = false
verify_server_hostname = false
acl = {
  enabled = true
  default_policy = "deny"
  enable_token_persistence = true
}
EOF

    # Aggiorna CONSUL_ADDR per usare HTTPS
    CONSUL_ADDR="https://127.0.0.1:8500"
    export CONSUL_CACERT="$CA_CERT"
}

configure_consul_with_tls_simple() {
    setup_tls_infrastructure

    cat > "$CONSUL_DIR/consul_config.hcl" <<EOF
datacenter = "dc1"
data_dir = "$CONSUL_DIR/data"
server = true
bootstrap_expect = 1
client_addr = "0.0.0.0"
ui_config {
  enabled = true
}
ports {
    https = 8500
}
ca_file = "$CA_CERT"
cert_file = "$CERTS_DIR/consul-server.pem"
key_file = "$CERTS_DIR/consul-server-key.pem"
acl = {
  enabled = true
  default_policy = "deny"
  enable_token_persistence = true
}
EOF

    CONSUL_ADDR="https://127.0.0.1:8500"
    export CONSUL_CACERT="$CA_CERT"
}