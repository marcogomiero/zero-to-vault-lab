HashiCorp Vault Lab 🚀
======================

This repository provides a laboratory environment for **HashiCorp Vault**, deployable with a single, simple Bash script. It's designed for anyone looking to explore, test, or develop with Vault without the complexity of a manual setup.

The goal is simple: one command to get a running, configured, and ready-to-use Vault instance for your experiments.

* * * * *

✨ Quick Start
-------------

To launch the lab, open a terminal and run these three commands:

```
# 1. Clone the repository
git clone https://github.com/marcogomiero/zero-to-hashicorp-labs.git

# 2. Change into the directory
cd zero-to-hashicorp-labs

# 3. Start the lab!
./vault-lab-ctl.sh start
```

The script will handle everything: it will check for dependencies, download the necessary binaries, start the servers, and provide you with all the credentials you need to get started.

* * * * *

📜 Key Features
---------------

The lab managed by `vault-lab-ctl.sh` is not just a running process, but a pre-configured environment designed to be immediately useful.

-   **Automated Setup**: The script checks for prerequisites (`curl`, `jq`, etc.) and offers to install them. It automatically downloads and updates the latest versions of Vault and Consul.
-   **Flexible Backend**: You can choose between a **file** backend (simple and fast) or a **Consul** instance (more similar to a real-world scenario). If you don't specify a backend, you will be prompted interactively on the first run.
-   **Pre-configured & Ready-to-Use**:
    -   Vault is automatically **initialized** and **unsealed**.
    -   The most common secrets engines are enabled: **KV v2** (at `secret/`) and **PKI** (at `pki/`).
    -   Two authentication methods are configured:
        -   **Userpass**: with a test user `devuser` / `devpass`.
        -   **AppRole**: with a `web-application` role and its initial credentials (Role ID and Secret ID).
    -   An example secret is created at `secret/test-secret` for your initial tests.
-   **Backup & Restore System**: Save and restore your lab configurations with full state preservation, metadata tracking, and sharing capabilities.

* * * * *

⚙️ Lab Management (Commands)
----------------------------

Use the `vault-lab-ctl.sh` script to manage the entire lifecycle of your test environment.

### Core Commands

| Command | Options | Description |
| --- | --- | --- |
| **`start`** | `--backend`, `--clean` | **(Default)** Starts and configures the environment. Asks for confirmation if a lab already exists. |
| **`stop`** |  | Stops the Vault and Consul (if active) processes. |
| **`restart`** |  | Restarts the processes and unseals Vault again. Does not delete data. |
| **`status`** |  | Shows the current status of the processes (running/stopped, sealed/unsealed). |
| **`reset`** | `--backend` | **Destructive action.** Deletes all data and starts over from a clean configuration. |
| **`cleanup`** |  | **Destructive action.** Stops all processes and deletes all lab files and folders. |
| **`shell`** |  | Opens an interactive shell with environment variables (`VAULT_ADDR`, `VAULT_TOKEN`) already set. |

### Backup & Restore Commands

| Command | Description |
| --- | --- |
| **`backup [name] [description]`** | Create a backup of the current lab state. If no name is provided, generates a timestamp-based name. |
| **`restore <name> [--force]`** | Restore from a specific backup. Use `--force` to skip confirmation prompts. |
| **`list-backups`** | Display all available backups with metadata (date, backend type, size). |
| **`delete-backup <name> [--force]`** | Delete a specific backup. Use `--force` to skip confirmation. |
| **`export-backup <name> [path]`** | Export a backup to a compressed tar.gz file for sharing or archiving. |
| **`import-backup <path> [name]`** | Import a backup from a tar.gz file. Optionally specify a new name. |

### Options

| Option | Values | Description |
| --- | --- | --- |
| **`--backend`** | `file` | `consul` | Select storage backend |
| **`--clean`** |  | Used with `start`, forces a lab cleanup without asking for confirmation |
| **`--verbose`** |  | Enables debug logs for more detailed troubleshooting |
| **`--no-color`** |  | Disables colored output, useful for logging or integration with other scripts |
| **`--help`** |  | Displays the help message with all commands and options |

* * * * *

💾 Backup & Restore System
--------------------------

The backup system allows you to save, restore, and share lab configurations with complete state preservation.

### Basic Usage

bash

```
# Create a backup with automatic naming
./vault-lab-ctl.sh backup

# Create a named backup with description
./vault-lab-ctl.sh backup my-working-setup "KV and PKI configured"

# List all available backups
./vault-lab-ctl.sh list-backups

# Restore from a backup
./vault-lab-ctl.sh restore my-working-setup

# Export backup for sharing
./vault-lab-ctl.sh export-backup my-working-setup ./my-config.tar.gz

# Import shared backup
./vault-lab-ctl.sh import-backup ./received-config.tar.gz team-config
```

### What Gets Backed Up

**Hot Backups** (lab running):

-   All Vault data files and configuration
-   API-exported policies, auth methods, and secrets engines
-   Consul data and KV store (if using consul backend)
-   Lab configuration and credentials

**Cold Backups** (lab stopped):

-   All data files and configurations
-   Lab state and credentials

### Backup Features

-   **Integrity Verification**: SHA256 checksums ensure backup integrity
-   **Rich Metadata**: Tracks creation date, backend type, versions, and descriptions
-   **Smart Naming**: Automatic timestamp-based names or custom names
-   **Export/Import**: Share configurations via compressed archives
-   **Safety Checks**: Confirmation prompts for destructive operations

### Example Workflow

bash

```
# Start with a clean lab
./vault-lab-ctl.sh start

# Configure your policies and secrets
./vault-lab-ctl.sh shell
vault policy write my-policy - <<EOF
path "secret/data/myapp/*" {
  capabilities = ["read", "list"]
}
EOF

# Save your working configuration
./vault-lab-ctl.sh backup production-ready "Configured policies and auth"

# Later, quickly restore to this state
./vault-lab-ctl.sh restore production-ready
```

* * * * *

✅ What to Expect (Example Output)
---------------------------------

After running the `start` (or `restart`) command, you will receive a clear summary with all the information needed to start using the lab.

```
--- ACCESS DETAILS ---
  🔗 Vault UI: http://127.0.0.1:8200 (Accessible from WSL)
  🔑 Vault Root Token: hvs.xxxxxxxxxxxxxxxx
  ---
  🔗 Consul UI: http://172.27.184.124:8500 (Accessible from your Windows browser)
  🔑 Consul ACL Token: a1b2c3d4-e5f6-.... (Use this to log in to the UI)

--- EXAMPLE USAGE ---
  Run the built-in shell for a pre-configured environment:
    ./vault-lab-ctl.sh shell

  Test User (userpass):
    Username: devuser
    Password: devpass

  AppRole Credentials (for 'web-application' role):
    Role ID:   e9d29b1b-....
    Secret ID: 6a9f3d9e-....

  Example CLI Commands (run inside the lab shell):
    # Read the example secret
    vault kv get secret/test-secret

    # To use the consul CLI, export the token:
    export CONSUL_HTTP_TOKEN="a1b2c3d4-e5f6-...."
    consul members
```

* * * * *

🛠️ Prerequisites
-----------------

To run the script, the following tools are required. Don't worry, the script will check for them and offer to install any that are missing.

-   `bash`
-   `curl`
-   `jq`
-   `unzip`
-   `lsof`

Please also ensure that ports **8200** (for Vault) and **8500** (for Consul, if used) are available.

* * * * *

🌳 Directory Structure (After Setup)
------------------------------------

After startup, the following directories will be created to hold the binaries, data, and configurations.

```
zero-to-hashicorp-labs/
├── bin/
│   ├── vault                   # Vault binary
│   └── consul                  # Consul binary (if used)
├── vault-data/                 # Vault data (logs, tokens, keys, storage...)
├── consul-data/                # Consul data (logs, tokens, storage...)
├── backups/                    # Backup storage directory
│   ├── backup_20240115_103000/ # Example timestamped backup
│   └── my-working-setup/       # Example named backup
├── lib/                        # Internal script libraries
├── vault-lab-ctl.sh            # The control script
└── README.md                   # This file
```

* * * * *

🚀 Common Use Cases
-------------------

### Development Scenarios

**API Development**: Use the pre-configured AppRole for testing application authentication flows.

**Policy Testing**: Create and test complex Vault policies in a safe environment.

**Secrets Management**: Experiment with different secrets engines and rotation strategies.

### Learning & Training

**Vault Fundamentals**: Learn Vault concepts with a pre-configured, working environment.

**Configuration Management**: Practice Vault configuration without fear of breaking production.

**Team Training**: Share identical lab environments using the export/import feature.

### Experimentation

**Feature Testing**: Quickly test new Vault features or configuration approaches.

**Integration Testing**: Test Vault integration with your applications in a controlled environment.

**Backup & Recovery**: Practice disaster recovery scenarios with the backup/restore system.

* * * * *

⚠️ Disclaimer
-------------

This script is intended **exclusively for lab, development, and testing purposes**. **IT MUST NOT BE USED IN PRODUCTION ENVIRONMENTS.** The default configurations are intentionally insecure to maximize ease of use in a controlled environment.