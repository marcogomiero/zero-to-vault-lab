HashiCorp Vault Lab 🚀
----------------------

A full laboratory environment for HashiCorp Vault, deployable with a single Bash script.\
Perfect for exploring, testing, or developing with Vault without the headache of a manual setup.

The goal is simple: **one command** to get a running, configured, and ready-to-use Vault environment for your experiments.

* * * * *

### ✨ **New: Multi-Node Vault Cluster**

You can now start the lab in **single-node** or **multi-node** mode.

-   **Single Mode** -- one Vault server with either a File or Consul backend.

-   **Cluster Mode** -- a **3-node Vault cluster** automatically configured with a shared **Consul backend** for real high-availability testing.

When you run `./vault-lab-ctl.sh start` the script **first asks for the cluster mode**.\
If you select `multi`, the backend is automatically set to **Consul**, three Vault nodes are launched, and they are initialized and unsealed as a cluster.\
You'll get a single Consul instance and three Vault API endpoints (`8200`, `8201`, `8202`) ready for HA experiments.

* * * * *

✨ Quick Start
-------------

Run these three commands:

`# 1. Clone the repository
git clone https://github.com/marcogomiero/zero-to-vault-lab.git

# 2. Change into the directory
cd zero-to-vault-lab

# 3. Start the lab
./vault-lab-ctl.sh start`

The script checks dependencies, downloads the latest Vault and Consul binaries, starts the servers, and prints all credentials you need.

* * * * *

📜 Key Features
---------------

-   **Automated Setup** -- verifies prerequisites (curl, jq, unzip, lsof) and installs them if missing. Downloads and updates the latest Vault and Consul.

-   **Flexible Backend** -- choose File or Consul for single mode.\
    *If you select multi-node, Consul is enforced automatically.*

-   **New Multi-Node Cluster** -- optional 3-node Vault cluster with a shared Consul backend for true HA testing.

-   **Pre-Configured & Ready**

    -   Vault initialized and unsealed automatically

    -   KV v2 (`secret/`) and PKI (`pki/`) engines enabled

    -   Userpass and AppRole authentication set up

    -   Example secret at `secret/test-secret`

-   **Backup & Restore System** -- full state preservation with metadata, export/import, and SHA256 integrity checks.

* * * * *

⚙️ Lab Management Commands
--------------------------

| Command | Options | Description |
| --- | --- | --- |
| **start** | `--backend`, `--cluster`, `--clean` | Starts and configures the environment. Prompts for cluster mode first. Forces `--backend consul` when `--cluster multi` is chosen. |
| **stop** |  | Stops Vault and Consul processes. |
| **restart** |  | Restarts processes and unseals Vault again without data loss. |
| **status** |  | Shows running/stopped and sealed/unsealed status. |
| **reset** | `--backend`, `--cluster` | Destroys all data and starts fresh. |
| **cleanup** |  | Stops all processes and deletes all lab files and folders. |
| **shell** |  | Opens an interactive shell with `VAULT_ADDR` and `VAULT_TOKEN` set. |

### Backup & Restore

| Command | Description |
| --- | --- |
| `backup [name] [description]` | Create a backup of the current lab state. |
| `restore <name> [--force]` | Restore from a specific backup. |
| `list-backups` | Show all backups with metadata. |
| `delete-backup <name> [--force]` | Delete a specific backup. |
| `export-backup <name> [path]` | Export a backup to a compressed tar.gz file. |
| `import-backup <path> [name]` | Import a backup from a tar.gz file. |

* * * * *

💡 Example Multi-Node Start
---------------------------

`# Three Vault nodes + Consul
./vault-lab-ctl.sh start --cluster multi`

You will see three Vault endpoints:

-   <http://127.0.0.1:8200>

-   <http://127.0.0.1:8201>

-   <http://127.0.0.1:8202>

Consul UI will be available at:

-   <http://127.0.0.1:8500>

* * * * *

💾 Backup & Restore Highlights
------------------------------

-   Hot or cold backups with full Vault/Consul state.

-   Integrity verification with SHA256.

-   Automatic timestamp names or custom names.

-   Export/import for easy sharing.

* * * * *

🛠️ Prerequisites
-----------------

-   bash

-   curl

-   jq

-   unzip

-   lsof

The script checks and installs anything missing.\
Ensure ports **8200** (Vault) and **8500** (Consul) are free.

* * * * *

🌳 Directory Structure After Setup
----------------------------------

`zero-to-hashicorp-labs/
├── bin/               # Vault and Consul binaries
├── vault-data/        # Vault data, logs, tokens
├── consul-data/       # Consul data (if used)
├── backups/           # Backups
├── lib/               # Script libraries
├── vault-lab-ctl.sh   # Control script
└── README.md`

* * * * *

🚀 Typical Workflows
--------------------

-   **Single Node Lab** -- fast experiments with a simple file or Consul backend.

-   **3-Node Cluster** -- simulate production-style HA with Consul backend.

-   **Policy & Auth Testing** -- create and test Vault policies safely.

-   **Integration Testing** -- validate your application against a realistic Vault cluster.

-   **Backup & Recovery** -- practice disaster recovery using built-in backup/restore.

* * * * *

⚠️ Disclaimer
-------------

This project is **for lab and development use only**.\
It is intentionally insecure to maximize ease of use. **Never run in production**.