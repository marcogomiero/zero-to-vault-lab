**ZERO-TO-VAULT-LAB**
=====================

A full HashiCorp Vault environment in **one command**.

Spin up a complete Vault playground --- single-node or HA with Consul --- in seconds.\
TLS, PKI, Transit, AppRole, Userpass, audit, and batteries included.\
Build, break, reset, repeat.\
No setup. No clutter. No fear.

* * * * *

🚀 **Why this exists**
----------------------

Because learning Vault shouldn't feel like assembling a server room.

This project gives you:

-   **Instant Vault** (single or multi-node)

-   **Automatic TLS** (private CA, SANs, signed certs)

-   **Consul optional** (file or Consul backend)

-   **Preconfigured engines** (KV v2, Transit, PKI, Database, Userpass, AppRole)

-   **Plugin Mode** to extend the lab with custom hooks

-   **Ephemeral Mode** --- a RAM-only Vault that leaves zero traces

-   **CI/CD Mode** --- fully automated, zero prompts

-   **Interactive Mode** --- full control over every setting

No YAML. No Docker. No Terraform.\
Just a script.

* * * * *

🎯 **Quick Start**
------------------

**CI/CD Mode (default, automated)**

`./vault-lab-ctl.sh start`

This will run with: ephemeral mode, single-node, file backend, TLS enabled.

**Interactive Mode (full control)**

`./vault-lab-ctl.sh --interactive start`

Get prompted for cluster mode, backend type, and TLS settings.

**Quick presets**

Start with Ephemeral mode (single node, file backend, no TLS):

`./vault-lab-ctl.sh --ephemeral start`

Start with TLS enabled (requires --interactive for other options):

`./vault-lab-ctl.sh --tls --interactive start`

Multi-node cluster with Consul:

`./vault-lab-ctl.sh --cluster multi --backend consul --interactive start`

Stop the lab:

`./vault-lab-ctl.sh stop`

Reset everything:

`./vault-lab-ctl.sh reset`

* * * * *

🔥 **Ephemeral Mode**
--------------------

Ephemeral Mode creates a full Vault+Consul environment that **lives entirely in RAM** and **vanishes** cleanly when you stop it.

-   No persistent folders

-   No secret leftovers

-   No cleanup required

-   No pollution of your project directory

-   Perfect for demos, workshops, conference talks, or chaos testing

When using `--ephemeral`, the script automatically uses:

-   Single-node cluster mode

-   File backend (in /tmp)

-   No TLS by default

`./vault-lab-ctl.sh --ephemeral start`

After running, all data disappears when you stop the lab:

`./vault-lab-ctl.sh stop`

This alone makes the lab dramatically more flexible than traditional Vault examples.

* * * * *

🔧 **Plugin Mode & Hooks**
---------------------------

Turn the lab into a **framework** by adding custom plugins.

Drop any `*.sh` file in:

`plugins/`

Plugins are automatically discovered and sourced before the lab starts.

Available hooks you can implement in your plugins:

-   `on_after_start()` --- runs after Vault and Consul are ready

-   `on_before_stop()` --- runs before Vault shuts down

-   `on_after_reset()` --- runs after reset is complete

Example plugin (`plugins/my-demo.sh`):

```bash
on_after_start() {
    log INFO "[my-demo] Vault started. Setting up demo..."
    vault auth enable userpass
    vault write auth/userpass/users/demo password="demo123"
}
```

Plugins have full access to:

-   Environment variables: `VAULT_ADDR`, `VAULT_TOKEN`, `CONSUL_ADDR`

-   Logging functions: `log_info()`, `log_warn()`, `log_error()`

-   Vault CLI (in `$BIN_DIR/vault`)

* * * * *

📋 **Command Reference**
------------------------

| Command | Description |
|---------|-------------|
| `start` | Start the Vault lab with current settings |
| `stop` | Stop Vault and Consul (keeps data) |
| `restart` | Stop and start the lab |
| `reset` | Stop and completely reset all data |
| `status` | Show lab status and running processes |
| `cleanup` | Remove all lab directories |
| `shell` | Open an interactive shell with `VAULT_ADDR`, `VAULT_TOKEN` exported |

* * * * *

🎛️ **Flags & Options**
-----------------------

| Flag | Description |
|------|-------------|
| `-h, --help` | Show help message |
| `-v` | Verbose output (debug logging) |
| `-c` | Force cleanup on start |
| `--interactive` | Enable interactive prompts (default: CI/CD mode) |
| `--ephemeral` | Enable ephemeral/RAM-only mode |
| `--tls` | Enable TLS encryption for Vault/Consul |
| `--cluster <single\|multi>` | Set cluster mode (single-node or HA) |
| `--backend <file\|consul>` | Set storage backend |
| `--no-color` | Disable colored output |

Examples:

`./vault-lab-ctl.sh --interactive --tls --cluster multi start`

`./vault-lab-ctl.sh -v --ephemeral start`

`./vault-lab-ctl.sh --backend consul --interactive start`

* * * * *

🔐 **Operating Modes**
-----------------------

**CI/CD Mode (default)**

When you run `./vault-lab-ctl.sh start` without `--interactive`:

-   Ephemeral mode is ON

-   Single-node cluster

-   File backend

-   TLS enabled

-   No prompts, fully automated

Ideal for automated tests, GitHub Actions, GitLab CI, etc.

**Interactive Mode**

When you run `./vault-lab-ctl.sh --interactive start`:

-   You're prompted for cluster mode (single/multi)

-   You're prompted for backend type (file/consul)

-   You're prompted for TLS (enabled/disabled)

-   Full control over every setting

Ideal for learning, experimentation, and development.

* * * * *

📝 **What comes preconfigured**
-------------------------------

Every Vault instance is ready to use immediately:

-   KV v2 (`secret/`) --- secret storage

-   Transit (`transit/`) --- encryption as a service

-   PKI (`pki/`) --- certificate management

-   Userpass + AppRole --- authentication methods

-   Database engine (demo config)

-   Audit device (logs to `/dev/null` by default)

-   Full `vault` CLI access via `./vault-lab-ctl.sh shell`

* * * * *

📦 **Features at a glance**
---------------------------

-   Single-file architecture

-   Automatic binary download and platform detection

-   Single-node or multi-node (HA) clusters

-   File backend or Consul backend

-   Optional TLS with full CA chain and signed certs

-   Prerequisite auto-detection and installation prompts

-   Full lifecycle control: start, stop, restart, reset, cleanup, status

-   **Ephemeral Mode** (RAM-only, zero traces)

-   **CI/CD Mode** (fully automated)

-   **Interactive Mode** (full user control)

-   **Plugin Mode** with lifecycle hooks

-   Shell access with pre-configured environment

-   Port validation and process cleanup

-   Works on Linux, macOS, Windows/WSL

* * * * *

🧠 **Use it for**
-----------------

-   Learning Vault from the ground up

-   Teaching workshops and training sessions

-   PKI, Transit, AppRole experiments

-   HA cluster simulations

-   Break/fix exercises

-   Building and testing custom automations via Plugin Mode

-   Demo environments for talks and conferences

-   CI/CD integration and automated testing

-   One-time ephemeral sandboxes

* * * * *

🌟 **Zero friction. Zero excuses. Zero to Vault.**
--------------------------------------------------