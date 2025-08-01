zero-to-vault-lab 🚀
====================

A ready-to-use HashiCorp Vault laboratory environment, deployable with a simple Bash script. This project is designed for developers, sysadmins, and anyone looking to explore or test Vault's functionalities without the complexity of a manual, from-scratch configuration. It's your quick launchpad into the world of Vault! 🌐

Key Features ✨
--------------

This script automates the creation of a single-instance Vault environment with the following configurations:

-   **Flexible Backend Choice:** Choose between `file` (default) or `consul` as Vault's storage backend, with an interactive prompt at startup if `--backend` argument is not explicitly provided. This allows you to explore different Vault persistence options. 🗄️

-   **Integrated Consul Environment (for 'consul' backend):** If you choose the `consul` backend, the script automatically downloads and sets up a single-node Consul server, bootstraps ACLs, and configures Vault to use it as its durable storage. 🌿

-   **Automated Vault Installation:** Automatically downloads and sets up the **latest stable Vault binary** (excluding Enterprise and Release Candidate versions). If a recent version is already present, it reuses it to save you time. ⏱️

-   **Robust Process Management:** The setup script tracks the Vault server's Process ID (PID) and the Consul server's PID (if used) for a more reliable and targeted shutdown. ✅

-   **Pre-configured Environment:**

    -   Vault is initialized and "unsealed" automatically. No need to worry about unseal keys (for the lab, of course!).

    -   The Root Token is conveniently set to "root" (⚠️ **for laboratory purposes only, never use in production!** ⚠️).

-   **Common Secrets Engines Enabled:**

    -   KV v2 enabled on `/secret` and `/kv` paths. Perfect for your first secrets! 🔑

    -   PKI (Public Key Infrastructure) enabled on the `/pki` path, with an extended maximum lease TTL. Ready for certificate management. 🛡️

-   **Pre-configured Authentication Methods:**

    -   **AppRole:** Enabled and configured with an example role (`web-application`), policy (`my-app-policy`), and initial credentials (Role ID and Secret ID). Ideal for simulating application access. 🤖

    -   **Userpass:** Enabled with an example user (`devuser` / `devpass`) and `default` policy. For quick access with username and password. 👥

-   **Audit Device:** A file type audit device is enabled, with logs directed to `/dev/null` by default (configurable). You can see what's happening in your Vault. 📝

-   **Test Secrets:** Some example secrets are populated to facilitate initial testing and let you start experimenting with Vault right away. 🧪

-   **Clear Output:** Upon setup completion, the script provides all essential information to access and interact with your Vault environment (URL, token, AppRole credentials, example commands). If using Consul, it also provides Consul UI and ACL token details. No searching, everything at your fingertips! 📋

-   **Flexible Output:** Supports colored terminal output by default, but can be disabled for scripting or logging purposes. 🌈

Version History 📜
------------------

This section tracks the main milestones and features introduced in different versions of the zero-to-vault-lab script.

**v1.3.0 - Flexible Backend & Interactive Setup (Current)**

Interactive Backend Selection: Added an interactive prompt at startup to choose between file and consul as Vault's storage backend.

Consul Backend Support: Full integration for using HashiCorp Consul as Vault's durable storage backend, including automatic binary download, setup, and ACL bootstrapping for Consul.

Enhanced Lab Cleanup: Improved detection and interactive cleanup for pre-existing data from both Vault and Consul environments.

Robust Process Management: More reliable stopping routines for both Vault and Consul processes.

**v1.2.0 - Automated Prerequisite Management**

Automatic Prerequisite Installation: The script now checks for curl, jq, unzip, and lsof and offers to install them automatically using the system's package manager if missing.

Cross-OS Compatibility Improvements: Enhanced binary download logic for different operating systems (Linux, macOS, Windows/WSL).

**v1.1.0 - Automated Binary Download**

Automatic Vault Binary Management: Introduced logic to automatically download the latest stable Vault binary.

Intelligent Updates: The script now checks the local Vault binary version against the latest available release and only downloads/updates if necessary.

**v1.0.0 - Initial Release**

Basic Vault Lab Setup: First functional version providing an automated setup for a single-instance Vault lab.

Pre-configuration: Included automatic initialization, unsealing, basic secrets engine enablement (KV, PKI), authentication method setup (AppRole, Userpass), and test secret population.

Essential Management: Provided clear instructions and a separate script (stop.sh) for stopping and cleaning the lab environment.

Prerequisites 🛠️
-----------------

To run this script, the following tools are required on your system:

-   **bash**: The Bourne-Again SHell (already present on most Linux/WSL systems).

-   **curl**: A command-line tool for transferring data to or from a server.

-   **jq**: A command-line JSON processor, essential for extracting information from Vault's APIs and HashiCorp's JSON responses.

-   **unzip**: Utility to extract `.zip` archives.

-   **lsof**: Utility to list open files and the processes using them (crucial for cleanly stopping Vault).

-   **Port 8200 free**: Ensure that port 8200 on your `127.0.0.1` (localhost) is not in use by other processes.

**Automatic Prerequisite Installation:** The `setup-lab-vault.sh` script will automatically check for these prerequisites. If any are missing, it will **prompt you to install them** using your system's package manager (e.g., `apt`, `yum`, `brew`). You can choose to proceed with the automatic installation or install them manually.

**Manual Installation (e.g., on Debian/Ubuntu):** Should you prefer to install them manually, here's an example for Debian/Ubuntu based systems:

```
sudo apt update
sudo apt install -y curl jq unzip lsof
```

How to Use the Vault Lab ▶️
---------------------------

Follow these simple steps to start and configure your Vault environment:

1.  **Clone the Repository**

    Open your terminal and clone the project:

    ```
    git clone https://github.com/marcogomiero/zero-to-vault-lab.git
    cd zero-to-vault-lab
    ```

2.  **Run the Setup Script**

    The `setup-lab-vault.sh` script is your starting point. It will handle downloading Vault (if needed), starting it, initializing it, unsealing it, and configuring all secrets engines and authentication methods.

    ```
    ./setup-lab-vault.sh [OPTIONS]
    ```

    **Available Options for `setup-lab-vault.sh`:**

    -   No option: Default behavior. The script will detect an existing Vault lab and ask for confirmation to clean it up.

    -   `-c, --clean`: Forces a clean setup, removing any existing Vault data in `$VAULT_DIR` before starting, without prompting.

    -   `--no-color`: Disables all colored output from the script. Useful when redirecting output to files.

    -   `-h, --help`: Displays the help message for the script.

    **Script Behavior:**

    -   If it detects a previous Vault environment (`vault-lab/`), it will ask you if you want to clean it up and start from scratch (`y/N`).

        -   Answering `y` (or `Y`) will perform a complete cleanup of the environment, followed by a fresh setup.

        -   Answering `N` (or anything else) will attempt to restart Vault with existing data and unseal it if necessary (assuming keys are present). In this case, existing configurations will be reapplied idempotently.

    -   If no previous environment is detected, it proceeds with a fresh setup.

3.  **Access Vault 🔐**

    After running `setup-lab-vault.sh`, you will receive a very clear summary of access information directly in your terminal.

    **From CLI (Command Line Interface):** To configure your shell and interact with Vault, copy and paste the commands suggested by the script's final output. They will be similar to these:

    ```
    export VAULT_ADDR="http://127.0.0.1:8200"
    export VAULT_TOKEN="root"
    ```

    Once environment variables are set, you can use the `vault` command to interact with your instance. For example:

    ```
    vault status
    vault kv get secret/test-secret
    ```

    **From UI (User Interface):** Open your favorite browser and navigate to: `http://127.0.0.1:8200`. Use "root" as the token to log in to the graphical Vault interface. Easy, right? ✨

    **Troubleshooting & Logs:** If Vault fails to start or behave as expected, check the detailed logs at: `$VAULT_DIR/vault.log`.

Cleaning Up the Lab Environment 🧹
----------------------------------

When you're done experimenting, you can easily stop Vault and (optionally) remove all lab data using the `stop.sh` script.

```
./stop-vault.sh [OPTIONS]
```

**Available Options:**

-   No option: Stops Vault and prompts for confirmation before deleting lab data and configuration (`y/N`).

-   `-f, --force`: Stops Vault and forces a complete data cleanup without asking for any confirmation. Useful for automation or if you know exactly what you want to do.

-   `--no-color`: Disables all colored output from the script.

-   `-h, --help`: Displays this help message and exits the script.

**Examples:**

```
./stop-vault.sh            # Stops Vault and prompts for cleanup confirmation
./stop-vault.sh --force    # Stops Vault and deletes everything without asking
./stop-vault.sh --no-color # Stops Vault with plain text output
./stop-vault.sh -h         # Displays the script's help message
```

Using Terraform with this Lab (Optional) 🚀

This lab environment can be easily managed and extended using HashiCorp Terraform, the industry standard for Infrastructure as Code (IaC). After deploying and initializing Vault using setup-lab-vault.sh, you can use the provided Terraform configurations to create and manage Vault resources automatically.

* * * * *

1.  Install Terraform

Ensure Terraform is installed on your system.\
The setup-lab-vault.sh script checks for it and prompts for installation if missing.\
Alternatively, you can download Terraform from the official HashiCorp website or use your system's package manager.

* * * * *

1.  Explore Terraform Examples

Navigate to the terraform-examples/ directory in this project. This directory contains ready-to-use Terraform configurations for Vault.

* * * * *

1.  Authenticate Terraform to Vault

Terraform needs to connect and authenticate to Vault.\
For this lab, export VAULT_ADDR and VAULT_TOKEN as environment variables in your shell:

export VAULT_ADDR="<http://127.0.0.1:8200>"\
export VAULT_TOKEN="root" # or use the root token generated by setup-lab-vault.sh

* * * * *

1.  Run Terraform with Automation Scripts

We provide ready-made scripts to simplify Terraform usage.

Initialize, plan, and apply changes by running:

./run-terraform.sh

This script runs:

-   terraform init

-   terraform plan

-   terraform apply

Destroy all resources and clean up local files by running:

./destroy-terraform.sh

This script runs:

-   terraform destroy -auto-approve

-   Removes .terraform/, lock files, state files, and plan files.

* * * * *

Example Terraform Configurations Included

-   main.tf: Configures the Vault provider and creates a new KV v2 secrets engine (lab-secrets/).

-   policy.tf: Defines a Vault policy (terraform-read-policy) with read permissions.

-   secrets.tf: (Optional) Creates a sample secret in Vault.

-   approle.tf: Configures a new AppRole (terraform-approle) and generates its Role ID and Secret ID.

* * * * *

Flow Diagram: End-to-End Workflow

┌─────────────────────────┐\
│ Run setup-lab-vault.sh │\
│ - Deploy Vault server │\
│ - Initialize & unseal │\
│ - Get root token │\
└─────────────┬───────────┘\
│\
▼\
┌─────────────────────────┐\
│ Export Vault env vars │\
│ VAULT_ADDR + VAULT_TOKEN│\
└─────────────┬───────────┘\
│\
▼\
┌─────────────────────────┐\
│ Run run-terraform.sh │\
│ - terraform init │\
│ - terraform plan │\
│ - terraform apply │\
└─────────────┬───────────┘\
│\
▼\
┌─────────────────────────┐\
│ Lab ready! │\
│ - KV secrets engine │\
│ - Policies & AppRoles │\
└─────────────┬───────────┘\
│\
▼\
┌─────────────────────────┐\
│ Run destroy-terraform.sh│\
│ - terraform destroy │\
│ - Cleanup files │\
└─────────────────────────┘

Directory Structure (After Setup) 🌳
------------------------------------

After running the setup script, your `zero-to-vault-lab` directory will have the following additional structure, which contains all the data and configurations for your Vault lab:

```
zero-to-vault-lab/
├── bin/
│   └── vault                   # Downloaded Vault binary 📥
├── vault-lab/
│   ├── config.hcl              # Vault server configuration file ⚙️
│   ├── vault.log               # Vault server logs 📄
│   ├── vault.pid               # File containing the PID of the running Vault server 🆔
│   ├── storage/                # Vault storage directory (your data!) 📦
│   ├── root_token.txt          # The generated root token (or "root") for easy access 🗝️
│   ├── unseal_key.txt          # The unseal key for your Vault 🔓
│   ├── approle-policy.hcl      # HCL policy for AppRole 📜
│   ├── approle_role_id.txt     # Role ID for the 'web-application' AppRole 🆔
│   └── approle_secret_id.txt   # Secret ID for the 'web-application' AppRole 🤫
├── setup-lab-vault.sh          # Lab setup script (starts everything!) ▶️
└── stop.sh                     # Lab stop and cleanup script (stops and cleans) 🛑
└── README.md                   # This file you are reading! 📖
```

Disclaimer ⚠️
-------------

This script is exclusively for laboratory and testing purposes. **IT MUST NOT BE USED IN PRODUCTION ENVIRONMENTS UNDER ANY CIRCUMSTANCE.** The default configurations (such as the root token set to "root", the absence of TLS by default, and audit to `/dev/null`) are designed for maximum simplicity and ease of use in a controlled environment and do not offer any security for a real HashiCorp Vault deployment. Use it responsibly! 😉
