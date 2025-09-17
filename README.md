Zero-to-Vault-Lab 🚀
--------------------

Your entire **HashiCorp Vault** playground, built from nothing in minutes.\
Run **one command** and watch the script pull the latest binaries, wire up TLS, enable auto-unseal, and spin up a multi-node Vault + Consul cluster that's ready for real testing.

### 🌟 Why It's Awesome

-   **Self-assembling environment** -- downloads and configures every required binary and dependency automatically.

-   **Multi-cluster capable** -- launch a full 3-node Vault cluster with Consul backend for high-availability scenarios, or stick to a single node for quick tests.

-   **Secure by default** -- TLS certificates and auto-unseal handled transparently.

-   **Break it & rebuild it** -- policies, auth methods, secret engines... experiment freely, then reset with one command.

-   **Batteries included** -- KV v2, PKI, Userpass and AppRole authentication pre-enabled so you can focus on learning, not bootstrapping.

### ⚡ Quick Start

`git clone https://github.com/your-repo/zero-to-vault-lab.git
cd zero-to-vault-lab
./vault-lab-ctl.sh start` 

That's it. The script fetches everything, configures Vault and Consul, and gives you credentials on the console.

### 🧩 Key Features

| Feature | What You Get |
| --- | --- |
| **Single or Multi Mode** | Choose a simple single node or a 3-node Vault cluster backed by Consul. |
| **One-line lifecycle** | `start`, `stop`, `restart`, `reset`, `cleanup`, `status`, and an interactive `shell` with VAULT_TOKEN pre-set. |
| **Backup & Restore** | Full-state hot and cold backups with SHA256 verification, export/import for easy sharing. |
| **Pre-configured Auth** | Userpass test user (`devuser/devpass`) and AppRole with ready Role ID/Secret ID. |
| **Secrets Engines Ready** | KV v2 and PKI enabled automatically. |

### 🚀 Try the Cluster Mode

`./vault-lab-ctl.sh start --cluster multi`

This starts:

-   **1 Consul server**

-   **3 Vault nodes** (ports 8200/8201/8202)

-   Automatic initialization and unseal across all nodes.

Access Vault at **<https://localhost:8200>** and Consul at **<http://localhost:8500>**.

### 🏗️ Learn More

Full documentation, architecture diagrams, and advanced scenarios (multi-cluster topologies, custom policies, and integration examples) are available in the project wiki.