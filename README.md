-----

```
zero-to-vault-lab 🚀

---

A ready-to-use HashiCorp Vault laboratory environment, deployable with a simple Bash script. This project is designed for developers, sysadmins, and anyone looking to explore or test Vault's functionalities without the complexity of a manual, from-scratch configuration. It's your quick launchpad into the world of Vault! 🌐

---

Key Features ✨

This script automates the creation of a single-instance Vault environment with the following configurations:

* Automated Vault Installation: Automatically downloads and sets up the latest Vault binary (excluding Enterprise versions). If a recent version is already present, it reuses it to save you time. ⏱️
* Pre-configured Environment:
    * Vault is initialized and "unsealed" automatically. No need to worry about unseal keys (for the lab, of course!).
    * The Root Token is conveniently set to "root" (⚠️ for laboratory purposes only, never use in production! ⚠️).
* Common Secrets Engines Enabled:
    * KV v2 enabled on /secret and /kv paths. Perfect for your first secrets! 🔑
    * PKI (Public Key Infrastructure) enabled on the /pki path, with an extended maximum lease TTL. Ready for certificate management. 🛡️
* Pre-configured Authentication Methods:
    * AppRole: Enabled and configured with an example role (web-application), policy (my-app-policy), and initial credentials (Role ID and Secret ID). Ideal for simulating application access. 🤖
    * Userpass: Enabled with an example user (devuser / devpass) and default policy. For quick access with username and password. 👥
* Audit Device: A file type audit device is enabled, with logs directed to /dev/null by default (configurable). You can see what's happening in your Vault. 📝
* Test Secrets: Some example secrets are populated to facilitate initial testing and let you start experimenting with Vault right away. 🧪
* Clear Output: Upon setup completion, the script provides all essential information to access and interact with your Vault environment (URL, token, AppRole credentials, example commands). No searching, everything at your fingertips! 📋

---

Prerequisites 🛠️

To run this script, ensure you have the following tools installed on your system:

* bash: The Bourne-Again SHell (already present on most Linux/WSL systems).
* curl: A command-line tool for transferring data to or from a server.
* jq: A command-line JSON processor, essential for extracting information from Vault's APIs and HashiCorp's JSON responses.
* unzip: Utility to extract .zip archives.
* lsof: Utility to list open files and the processes using them (crucial for cleanly stopping Vault).
* Port 8200 free: Ensure that port 8200 on your 127.0.0.1 (localhost) is not in use by other processes.

Installing Prerequisites (e.g., on Debian/Ubuntu):
sudo apt update
sudo apt install -y curl jq unzip lsof

How to Use the Vault Lab ▶️

Follow these simple steps to start and configure your Vault environment:

1. Clone the Repository

Open your terminal and clone the project:

git clone https://github.com/marcogomiero/zero-to-vault-lab.git
cd zero-to-vault-lab

2. Run the Start Script

The start-vault.sh script is your starting point. It will handle downloading Vault (if needed), starting it, initializing it, unsealing it, and configuring all secrets engines and authentication methods.

./start-vault.sh

Script Behavior:

* If it detects a previous Vault environment (vault-lab/), it will ask you if you want to clean it up and start from scratch (y/N).
    * Answering y (or Y) will perform a complete cleanup of the environment, followed by a fresh setup.
    * Answering N (or anything else) will attempt to restart Vault with existing data and unseal it if necessary (assuming keys are present). In this case, additional configurations (new engines, AppRoles, etc.) will not be automatically reapplied, preserving the previous state.

3. Access Vault 🔐

After running start-vault.sh, you will receive a very clear summary of access information directly in your terminal.

From CLI (Command Line Interface):
To configure your shell and interact with Vault, copy and paste the commands suggested by the script's final output. They will be similar to these:
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="root"
Once environment variables are set, you can use the vault command to interact with your instance. For example:
vault status
vault kv get secret/test-secret

From UI (User Interface):
Open your favorite browser and navigate to: http://127.0.0.1:8200.
Use "root" as the token to log in to the graphical Vault interface. Easy, right? ✨

---

Cleaning Up the Lab Environment 🧹

When you're done experimenting, you can easily stop Vault and (optionally) remove all lab data using the stop-vault.sh script.

./stop-vault.sh [OPTIONS]

Available Options:

* No option: Stops Vault and prompts for confirmation before deleting lab data and configuration (y/N).
* -f, --force: Stops Vault and forces a complete data cleanup without asking for any confirmation. Useful for automation or if you know exactly what you want to do.
* -h, --help: Displays this help message and exits the script.

Examples:

./stop-vault.sh          # Stops Vault and prompts for cleanup confirmation
./stop-vault.sh --force  # Stops Vault and deletes everything without asking
./stop-vault.sh -h       # Displays the script's help message

---

Directory Structure (After Setup) 🌳

After running the startup script, your zero-to-vault-lab directory will have the following additional structure, which contains all the data and configurations for your Vault lab:

zero-to-vault-lab/
├── bin/
│   └── vault                   # Downloaded Vault binary 📥
├── vault-lab/
│   ├── config.hcl              # Vault server configuration file ⚙️
│   ├── vault.log               # Vault server logs 📄
│   ├── storage/                # Vault storage directory (your data!) 📦
│   ├── root_token.txt          # The generated root token (or "root") for easy access 🗝️
│   ├── unseal_key.txt          # The unseal key for your Vault 🔓
│   ├── approle-policy.hcl      # HCL policy for AppRole 📜
│   ├── approle_role_id.txt     # Role ID for the 'web-application' AppRole 🆔
│   └── approle_secret_id.txt   # Secret ID for the 'web-application' AppRole 🤫
├── start-vault.sh              # Lab startup script (starts everything!) ▶️
└── stop-vault.sh               # Lab stop and cleanup script (stops and cleans) 🛑
└── README.md                   # This file you are reading! 📖

---

Disclaimer ⚠️

This script is exclusively for laboratory and testing purposes. IT MUST NOT BE USED IN PRODUCTION ENVIRONMENTS UNDER ANY CIRCUMSTANCE. The default configurations (such as the root token set to "root", the absence of TLS by default, and audit to /dev/null) are designed for maximum simplicity and ease of use in a controlled environment and do not offer any security for a real HashiCorp Vault deployment. Use it responsibly! 😉

---
```