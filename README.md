zero-to-vault-lab

🚀 Project Overview
This project provides a comprehensive Bash script to rapidly deploy a fully functional HashiCorp Vault laboratory environment from scratch. Designed for developers, security professionals, and anyone looking to learn or experiment with Vault, this script automates the entire setup process, allowing you to focus on exploring Vault's capabilities rather than wrestling with configurations.

✨ Key Features
Our zero-to-vault-lab script offers:
	Automated Vault Installation: Downloads and sets up the latest stable (non-enterprise) version of the Vault binary.
	Single-Instance Lab Setup: Configures a ready-to-use, single-server Vault instance.
	Pre-initialized and Unsealed: Vault is automatically initialized and unsealed for immediate use.
	Common Secrets Engines Enabled: Includes popular secrets engines like KV v2 and PKI already configured.
	AppRole Authentication Setup: An example AppRole (web-application) is configured with a sample policy, Role ID, and Secret ID for quick testing.
	Userpass Authentication Example: Sets up a sample user (devuser/devpass) for basic authentication tests.
	Audit Device Enabled: An audit device is configured (defaulting to /dev/null for quiet lab use, but easily configurable to a file).
	Clear Output and Access Details: Provides all necessary information (Vault URL, Root Token, AppRole credentials) for immediate interaction.
	Clean Slate: Automatically cleans up previous lab environments to ensure a consistent setup every time.

This script significantly reduces the overhead of setting up a Vault instance, making it ideal for learning, prototyping, or quickly spinning up a temporary environment for testing Vault features and integrations.

🛠️ How to Use
Clone the repository:
Make the script executable:
Run the script:

The script will print all necessary information to access Vault (URL, Root Token, AppRole credentials) upon completion.

🤝 Contributing
Feel free to open issues to report bugs or suggest improvements. Pull requests are very welcome!

📄 License
This project is released under the . You are free to use, modify, and distribute this software for any purpose, provided that the original attribution is maintained.
