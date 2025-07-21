zero-to-vault-lab 🚀
====================

A ready-to-use HashiCorp Vault laboratory environment, deployable with a simple Bash script. This project is designed for developers, sysadmins, and anyone looking to explore or test Vault's functionalities without the complexity of a manual, from-scratch configuration. It's your quick launchpad into the world of Vault! 🌐

Key Features ✨
--------------

This script automates the creation of a single-instance Vault environment with the following configurations:

-   **Automated Vault Installation:** Automatically downloads and sets up the **latest stable Vault binary** (excluding Enterprise and Release Candidate versions). If a recent version is already present, it reuses it to save you time. ⏱️

-   **Robust Process Management:** The setup script tracks the Vault server's Process ID (PID) for a more reliable and targeted shutdown. ✅

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

-   **Clear Output:** Upon setup completion, the script provides all essential information to access and interact with your Vault environment (URL, token, AppRole credentials, example commands). No searching, everything at your fingertips! 📋

-   **Flexible Output:** Supports colored terminal output by default, but can be disabled for scripting or logging purposes. 🌈

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

Wait! There is more!
--------------------

### `setup-vault-with-consul.sh` (Updated & Optimized - Vault with Consul Storage, Fully Self-Contained)

This script is the **enhanced and optimized version and super-beta** for deploying a complete Vault environment integrated with Consul. It's a **single, self-contained shell script** that fully manages the deployment of **both Consul (running as a development agent) and Vault (configured to use Consul for its backend storage)**. This script builds upon the original approach by adding significant robustness and convenience features.

**Key Features & Improvements:**

* **Self-Contained Binaries:** Automatically downloads and sets up the correct `vault` and `consul` binaries for your operating system and architecture. You **do not** need to install these tools globally beforehand.
* **Portable Lab Environment:** All configuration files, data, logs, and downloaded binaries are neatly placed within a dedicated subdirectory (`zero-to-vault-lab_data`) in the same folder where you execute the script. This ensures a clean system and makes cleanup extremely easy.
* **Robust Startup Checks:** Includes intelligent waiting mechanisms to ensure both Consul and Vault services are fully up and running and responsive before proceeding with Vault's initialization and unsealing. This significantly enhances the reliability of the setup process.
* **Automatic Cleanup:** Features an integrated `trap` cleanup mechanism. This function automatically attempts to stop running Consul and Vault processes when the script exits (even on errors). It also offers to remove all generated data (configuration, data, and downloaded binaries) from the `zero-to-vault-lab_data` directory, allowing for effortless environment resets.
* **Pure Monoshell:** Runs entirely within your current shell session, without relying on `systemctl` or making permanent modifications to your global system configurations, ensuring maximum portability.
