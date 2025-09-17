Zero-to-Vault-Lab 🚀
====================

Your entire **HashiCorp Vault** playground, built from nothing in minutes.\
Run **one command** and watch the script pull the latest binaries, wire up TLS, enable auto-unseal, and spin up a multi-node Vault + Consul cluster that's ready for real testing.

🌟 Why It's Awesome
-------------------

-   **Self-assembling environment** -- downloads and configures every required binary and dependency automatically.
-   **Multi-cluster capable** -- launch a full 3-node Vault cluster with Consul backend for high-availability scenarios, or stick to a single node for quick tests.
-   **Secure by default** -- automatic TLS certificate generation with CA, encrypted connections, and auto-unseal handled transparently.
-   **Break it & rebuild it** -- policies, auth methods, secret engines... experiment freely, then reset with one command.
-   **Batteries included** -- KV v2, PKI, Transit and Database engines pre-enabled so you can focus on learning, not bootstrapping.
-   **Enterprise-ready patterns** -- backup/restore, certificate management, multi-backend support for realistic testing scenarios.

⚡ Quick Start
-------------

```
git clone https://github.com/your-repo/zero-to-vault-lab.git
cd zero-to-vault-lab
./vault-lab-ctl.sh start

```

That's it. The script fetches everything, configures Vault and Consul, and prints all credentials you need.

🔒 TLS-First Security
---------------------

```
# Start with automatic TLS encryption
./vault-lab-ctl.sh --tls start

# Or enable interactively when prompted
./vault-lab-ctl.sh start
# -> Enable TLS/SSL encryption? (y/N): y

```

**What you get with TLS:**

-   Self-signed CA certificate for the lab environment
-   Individual certificates for each Vault and Consul node
-   HTTPS endpoints (https://127.0.0.1:8200, https://127.0.0.1:8500)
-   Proper certificate validation and Subject Alternative Names
-   Certificate backup/restore in lab snapshots

**Trust the lab CA:**

```
# Linux
sudo cp tls/ca/ca-cert.pem /usr/local/share/ca-certificates/vault-lab-ca.crt
sudo update-ca-certificates

# macOS
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain tls/ca/ca-cert.pem

# Windows
# Import tls/ca/ca-cert.pem via certmgr.msc into Trusted Root Certification Authorities

```

🧩 Key Features
---------------

| Feature | What You Get |
| --- | --- |
| **Single or Multi Mode** | Choose a simple single node or a 3-node Vault cluster backed by Consul. |
| **TLS Encryption** | Automatic certificate generation, HTTPS endpoints, proper certificate validation. |
| **Flexible Backends** | File storage for simplicity or Consul for distributed scenarios. |
| **One-line lifecycle** | `start`, `stop`, `restart`, `reset`, `cleanup`, `status`, and an interactive `shell` with VAULT_TOKEN pre-set. |
| **Backup & Restore** | Full-state hot and cold backups with SHA256 verification, export/import for easy sharing. |
| **Pre-configured Auth** | Userpass test user (`devuser/devpass`) and AppRole with ready Role ID/Secret ID. |
| **Secrets Engines Ready** | KV v2, PKI, **Transit** (encryption as a service), and **Database (SQLite demo)** enabled automatically. |

🚀 Advanced Usage
-----------------

### Multi-Node Cluster with TLS

```
./vault-lab-ctl.sh --cluster multi --backend consul --tls start

```

This starts:

-   **1 Consul server** with TLS and ACL
-   **3 Vault nodes** (ports 8200/8201/8202) with individual certificates
-   Automatic initialization and unseal across all nodes
-   Full HTTPS communication between components

Access Vault at **https://localhost:8200** and Consul at **https://localhost:8500**.

### Backup and Restore Operations

```
# Create a named backup of current state
./vault-lab-ctl.sh backup my-config "Working KV setup with TLS"

# List all available backups
./vault-lab-ctl.sh list-backups

# Restore from backup (preserves TLS settings)
./vault-lab-ctl.sh restore my-config

# Export backup for sharing
./vault-lab-ctl.sh export-backup my-config ./my-backup.tar.gz

# Import backup from file
./vault-lab-ctl.sh import-backup ./my-backup.tar.gz imported-config

```

### Interactive Shell

```
./vault-lab-ctl.sh shell
# Environment pre-configured with:
# - VAULT_ADDR set to correct endpoint (HTTP/HTTPS)
# - VAULT_TOKEN set to root token
# - VAULT_CACERT set for TLS mode
# - PATH includes vault and consul binaries

```

🔐 Demo Engines Out of the Box
------------------------------

-   **KV v2** -- Standard key/value secrets at `secret/`
-   **PKI** -- Issue and manage certificates with 10-year max TTL
-   **Transit** -- Encryption-as-a-service with pre-created key `lab-key`

    ```
    vault write transit/encrypt/lab-key plaintext=$(base64 <<< "hello")

    ```

-   **Database (SQLite)** -- Dynamic credentials using `sqlite-database-plugin`

    ```
    vault read database/creds/demo-role  # Generate demo creds with 1h TTL

    ```

-   **Authentication Methods** -- Userpass and AppRole pre-configured with policies

🛠️ Command Reference
---------------------

```
# Lifecycle management
./vault-lab-ctl.sh start                    # Start lab environment
./vault-lab-ctl.sh stop                     # Stop all services
./vault-lab-ctl.sh restart                  # Restart and unseal
./vault-lab-ctl.sh reset                    # Full reset and restart
./vault-lab-ctl.sh status                   # Check service status
./vault-lab-ctl.sh cleanup                  # Clean all data

# Configuration options
./vault-lab-ctl.sh --tls start              # Force TLS encryption
./vault-lab-ctl.sh --cluster multi start    # Multi-node cluster
./vault-lab-ctl.sh --backend consul start   # Use Consul backend
./vault-lab-ctl.sh --clean start            # Force cleanup before start
./vault-lab-ctl.sh --verbose start          # Detailed output

# Backup operations
./vault-lab-ctl.sh backup [name] [description]
./vault-lab-ctl.sh restore <name> [--force]
./vault-lab-ctl.sh list-backups
./vault-lab-ctl.sh delete-backup <name> [--force]
./vault-lab-ctl.sh export-backup <name> [path]
./vault-lab-ctl.sh import-backup <path> [name]

# Utility
./vault-lab-ctl.sh shell                    # Interactive shell with env
./vault-lab-ctl.sh --help                   # Full help and examples

```

📁 Directory Structure
----------------------

```
zero-to-vault-lab-v2/
├── vault-lab-ctl.sh           # Main script
├── lib/                       # Modular functions
│   ├── common.sh              # Utilities and logging
│   ├── dependencies.sh        # Binary management
│   ├── vault.sh               # Vault configuration
│   ├── consul.sh              # Consul management
│   ├── tls.sh                 # Certificate operations
│   ├── backup.sh              # Backup/restore logic
│   └── lifecycle.sh           # Main workflow
├── bin/                       # Downloaded binaries
├── vault-data/                # Vault storage and config
├── consul-data/               # Consul data and logs
├── tls/                       # Certificate authority and certs
│   ├── ca/                    # CA certificate and key
│   └── certs/                 # Service certificates
└── backups/                   # Lab state snapshots

```

🔍 Troubleshooting
------------------

**TLS Certificate Issues:**

-   Certificates are auto-generated with proper SAN entries for localhost/127.0.0.1
-   Import the CA certificate to avoid browser warnings
-   Check certificate validity: `openssl x509 -in tls/ca/ca-cert.pem -text -noout`

**Service Connection Issues:**

-   Verify ports 8200 (Vault) and 8500 (Consul) are available
-   Check service logs: `tail -f vault-data/vault.log` or `tail -f consul-data/consul.log`
-   Use `./vault-lab-ctl.sh status` for service health overview

**Vault Sealed State:**

-   Script handles unsealing automatically, but check `vault-data/unseal_key.txt` exists
-   Manual unseal: `vault operator unseal $(cat vault-data/unseal_key.txt)`

🏗️ Architecture
----------------

The lab environment supports multiple deployment patterns:

-   **Single Node + File Backend** -- Simplest setup for learning basics
-   **Single Node + Consul Backend** -- Introduces Consul concepts
-   **Multi-Node + Consul Backend** -- Full HA cluster simulation
-   **Any combination with TLS** -- Production-like encrypted communication

All configurations include the same rich set of pre-configured authentication methods, policies, and secrets engines for immediate hands-on learning.

📚 Learn More
-------------

This lab environment provides a foundation for exploring advanced Vault concepts including dynamic secrets, certificate management, encryption-as-a-service, and high availability patterns.

The modular design makes it easy to extend with additional authentication backends, secrets engines, or integration scenarios for your specific learning objectives.