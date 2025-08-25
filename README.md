zero-to-hashicorp-labs 🚀
=========================

======================

A collection of ready-to-use HashiCorp product laboratory environments, deployable with simple Bash scripts. This project is designed for developers, sysadmins, and anyone looking to explore or test HashiCorp's functionalities without the complexity of a manual, from-scratch configuration. It's your quick launchpad into the world of HashiCorp tools! 🌐

This repository currently includes:

-   **Vault Lab:** A single-instance HashiCorp Vault environment with flexible storage backend options (file or Consul).

HashiCorp Vault Lab (via `vault-lab-ctl.sh`)
--------------------------------------------

### Key Features ✨

The `vault-lab-ctl.sh` script automates the creation and management of a single-instance Vault environment with the following configurations:

-   **Flexible Backend Choice:** Choose between `file` (default) or `consul` as Vault's storage backend, with an interactive prompt at startup if the `--backend` argument is not explicitly provided. This allows you to explore different Vault persistence options. 🗄️

-   **Integrated Consul Environment (for 'consul' backend):** If you choose the `consul` backend, the script automatically downloads and sets up a single-node Consul server, bootstraps ACLs, and configures Vault to use it as its durable storage. 🌿

-   **Automated Vault Installation:** Automatically downloads and sets up the **latest stable Vault binary** (excluding Enterprise and Release Candidate versions). If a recent version is already present, it reuses it to save you time. ⏱️

-   **Robust Process Management:** The script tracks the Vault server's Process ID (PID) and the Consul server's PID (if used) for a more reliable and targeted shutdown. ✅

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

### How to Use the Vault Lab ▶️

Follow these simple steps to start and configure your Vault environment:

1.  **Clone the Repository**

    Open your terminal and clone the project:

    ```
    git clone https://github.com/marcogomiero/zero-to-hashicorp-labs.git # Update your repository URL if different
    cd zero-to-hashicorp-labs

    ```

2.  **Run the Control Script**

    The `vault-lab-ctl.sh` script is your main entry point. It will handle downloading Vault (and Consul if needed), starting it, initializing it, unsealing it, and configuring all secrets engines and authentication methods.

    ```
    ./vault-lab-ctl.sh [COMMAND] [OPTIONS]

    ```

    **Available Commands and Options for `vault-lab-ctl.sh`:**

    -   **`start`** (Default Command): Configures and starts the Vault lab.

        -   No options: Default behavior. The script will detect an existing Vault lab and ask for confirmation to clean it up. If no backend is specified, it will prompt interactively.

        -   `-c, --clean`: Forces a clean setup, removing any existing Vault data in `$VAULT_DIR` and Consul data in `$CONSUL_DIR` before starting, without prompting.

        -   `-b, --base-directory <path>`: Specify the base directory for the Vault lab. Overrides the default `BASE_DIR`.

    -   **`stop`**: Stops the running Vault and Consul (if applicable) servers gracefully.

    -   **`restart`**: Stops the Vault and Consul (if applicable) servers and then starts them again.

    -   **`reset`**: Restart Vault (and Consul if applicable) to original config.

    -   **`status`**: Checks and displays the current operational status of the Vault and Consul (if applicable) servers.

    -   **`cleanup`**: Removes all Vault and Consul (if applicable) lab data and stops any running instances.

    -   `-h, --help`: Displays the help message for the script, showing all commands and options.

    -   `-v, --verbose`: Enable verbose output for troubleshooting (currently not fully implemented).

    -   `--no-color`: Disables all colored output from the script. Useful when redirecting output to files.

    -   `--backend <type>`: Choose Vault storage backend: `file` (default) or `consul`. This option takes precedence over the saved configuration. This option is crucial and should be used with `start`, `stop`, `restart`, `status`, and `cleanup` to ensure correct management of the chosen backend (especially `consul`).

    **Script Behavior (when running `start`):**

    -   If it detects a previous Vault environment (`vault-lab/`), it will ask you if you want to clean it up and start from scratch (`y/N`).

        -   Answering `y` (or `Y`) will perform a complete cleanup of the environment, followed by a fresh setup.

        -   Answering `N` (or anything else) will attempt to restart Vault with existing data and unseal it if necessary (assuming keys are present). In this case, existing configurations will be reapplied idempotently.

    -   If no previous environment is detected, it proceeds with a fresh setup.

    -   The chosen backend type (`file` or `consul`) is saved in `$VAULT_DIR/vault-lab-ctl.conf` after a successful `start` command. Subsequent `stop`, `restart`, `status`, and `cleanup` commands will automatically use this saved backend type unless explicitly overridden with the `--backend` option.

3.  **Access Vault 🔐**

    After running `./vault-lab-ctl.sh start`, you will receive a very clear summary of access information directly in your terminal.

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

Version History 📜
------------------

This section tracks the main milestones and features introduced in different versions of the `zero-to-hashicorp-labs` project.

### Vault Lab (`vault-lab-ctl.sh`)

**v1.4.1 (Current)**
- Added `restart` command to vault-lab-ctl.sh:
  * Restarts Vault (and Consul if applicable) without reconfiguring
  * Automatically unseals Vault after restart
- Added `reset` command to vault-lab-ctl.sh:
  * Performs full cleanup and fresh start, restoring initial lab state
- Updated help output to include new commands
- Improved command dispatch logic to support restart/reset cleanly
- Introduced `vault-lab-smoketest.sh`:
  * Automated smoke tests for all key commands (start, restart, reset, cleanup)
  * Runs tests for both 'file' and 'consul' backends
  * Provides colored PASS/FAIL output and detailed logs
  * Includes summary of passed/failed tests

**v1.4.0 - Unified Control & Backend Persistence**

This version significantly enhances the lab environment management by consolidating all operations into a single control script (`vault-lab-ctl.sh`) and introducing persistent backend configuration.

-   **Unified Control Script:** All lab management commands (`start`, `stop`, `restart`, `status`, `cleanup`) are now integrated into a single `vault-lab-ctl.sh` script, simplifying usage and reducing script proliferation. This replaces the need for separate `setup-lab-vault.sh` and `stop.sh` scripts.

-   **Backend Persistence:** The chosen backend type (`file` or `consul`) is now saved to `$VAULT_DIR/vault-lab-ctl.conf` after a successful `start`. Subsequent commands (`stop`, `restart`, `status`, `cleanup`) will automatically use this saved backend, unless explicitly overridden with the `--backend` option. This eliminates the need to specify `--backend consul` for every command after the initial setup.

-   **Enhanced Interactive Prompt:** The `start` command now intelligently prompts for the backend type only if it's not provided via `--backend` and no previous configuration is saved.

-   **Improved Logging:** Added more explicit logging for backend type during management operations.

**v1.3.0 - Flexible Backend & Interactive Setup**

-   **Interactive Backend Selection:** Added an interactive prompt at startup to choose between `file` and `consul` as Vault's storage backend.

-   **Consul Backend Support:** Full integration for using HashiCorp Consul as Vault's durable storage backend, including automatic binary download, setup, and ACL bootstrapping for Consul.

-   **Enhanced Lab Cleanup:** Improved detection and interactive cleanup for pre-existing data from both Vault and Consul environments.

-   **Robust Process Management:** More reliable stopping routines for both Vault and Consul processes.

**v1.2.0 - Automated Prerequisite Management**

-   **Automatic Prerequisite Installation:** The script now checks for `curl`, `jq`, `unzip`, and `lsof` and offers to install them automatically using the system's package manager if missing.

-   **Cross-OS Compatibility Improvements:** Enhanced binary download logic for different operating systems (Linux, macOS, Windows/WSL).

**v1.1.0 - Automated Binary Download**

-   **Automatic Vault Binary Management:** Introduced logic to automatically download the latest stable Vault binary.

-   **Intelligent Updates:** The script now checks the local Vault binary version against the latest available release and only downloads/updates if necessary.

**v1.0.0 - Initial Release**

-   **Basic Vault Lab Setup:** First functional version providing an automated setup for a single-instance Vault lab.

-   **Pre-configuration:** Included automatic initialization, unsealing, basic secrets engine enablement (KV, PKI), authentication method setup (AppRole, Userpass), and test secret population.

-   **Essential Management:** Provided clear instructions and a separate script (`stop.sh`) for stopping and cleaning the lab environment.

Prerequisites 🛠️
-----------------

To run these scripts, the following tools are required on your system:

-   **bash**: The Bourne-Again SHell (already present on most Linux/WSL systems).

-   **curl**: A command-line tool for transferring data to or from a server.

-   **jq**: A command-line JSON processor, essential for extracting information from Vault/OpenBao APIs and HashiCorp's JSON responses.

-   **unzip**: Utility to extract `.zip` archives.

-   **lsof**: Utility to list open files and the processes using them (crucial for cleanly stopping Vault/OpenBao).

-   **terraform**: (Only for Vault lab if you plan to use Terraform examples, checked by `vault-lab-ctl.sh`).

-   **openssl**: (Only for OpenBao lab, checked by `bao-lab-ctl.sh`).

-   **Port 8200 free**: Ensure that port 8200 on your `127.0.0.1` (localhost) is not in use by other processes.

-   **Port 8500 free**: (Only for Vault lab with Consul backend) Ensure that port 8500 on your `127.0.0.1` (localhost) is not in use by other processes.

**Automatic Prerequisite Installation:** Both `vault-lab-ctl.sh` and `bao-lab-ctl.sh` scripts will automatically check for their respective prerequisites. If any are missing, they will **prompt you to install them** using your system's package manager (e.g., `apt`, `yum`, `brew`). You can choose to proceed with the automatic installation or install them manually.

**Manual Installation (e.g., on Debian/Ubuntu):** Should you prefer to install them manually, here's an example for Debian/Ubuntu based systems:

```
sudo apt update
sudo apt install -y curl jq unzip lsof openssl terraform

```

Directory Structure (After Setup) 🌳
------------------------------------

After running the control scripts, your `zero-to-hashicorp-labs` directory will have the following additional structure, which contains all the data and configurations for your labs:

```
zero-to-hashicorp-labs/
├── bin/
│   ├── vault                   # Downloaded Vault binary 📥
│   ├── consul                  # Downloaded Consul binary (if used by Vault lab) 📥
│   └── bao                     # Downloaded OpenBao binary 📥
├── vault-lab/                  # Working directory for Vault data, config, and keys
│   ├── config.hcl              # Vault server configuration file ⚙️
│   ├── vault.log               # Vault server logs 📄
│   ├── vault.pid               # File containing the PID of the running Vault server 🆔
│   ├── storage/                # Vault file storage directory (your data!) 📦
│   ├── root_token.txt          # The generated root token (or "root") for easy access 🗝️
│   ├── unseal_key.txt          # The unseal key for your Vault 🔓
│   ├── approle-policy.hcl      # HCL policy for AppRole 📜
│   ├── approle_role_id.txt     # Role ID for the 'web-application' AppRole 🆔
│   ├── approle_secret_id.txt   # Secret ID for the 'web-application' AppRole 🤫
│   └── vault-lab-ctl.conf      # Stores the last used backend type for persistence 💾
├── consul-lab/                 # Working directory for Consul data and config (if used by Vault lab)
│   ├── consul_config.hcl       # Consul server configuration file ⚙️
│   ├── consul.log              # Consul server logs 📄
│   ├── consul.pid              # File containing the PID of the running Consul server 🆔
│   ├── data/                   # Consul data directory 📦
│   └── acl_master_token.txt    # Consul ACL Master Token 🔑
├── bao-lab/                    # Working directory for OpenBao data, config, and keys
│   ├── config.hcl              # OpenBao server configuration file ⚙️
│   ├── bao.log                 # OpenBao server logs 📄
│   ├── bao.pid                 # File containing the PID of the running OpenBao server 🆔
│   ├── storage/                # OpenBao storage directory (your data!) 📦
│   ├── root_token.txt          # The generated root token (or "root") for easy access 🗝️
│   ├── unseal_key.txt          # The unseal key for your OpenBao 🔓
│   ├── approle-policy.hcl      # HCL policy for AppRole 📜
│   ├── approle_role_id.txt     # Role ID for the 'web-application' AppRole 🆔
│   └── approle_secret_id.txt   # Secret ID for the 'web-application' AppRole 🤫
├── vault-lab-ctl.sh            # Vault Lab unified control script ▶️
├── bao-lab-ctl.sh              # OpenBao Lab unified control script ▶️
└── README.md                   # This file you are reading! 📖

```

Disclaimer ⚠️
-------------

These scripts are exclusively for laboratory and testing purposes. **THEY MUST NOT BE USED IN PRODUCTION ENVIRONMENTS UNDER ANY CIRCUMSTANCE.** The default configurations (such as the root token set to "root", the absence of TLS by default, and audit to `/dev/null`) are designed for maximum simplicity and ease of use in a controlled environment and do not offer any security for a real HashiCorp Vault or OpenBao deployment. Use them responsibly! 😉