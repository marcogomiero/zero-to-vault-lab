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

-   **Instant Vault** (single or multi node)

-   **Automatic TLS** (private CA, SANs, signed certs)

-   **Consul optional** (file or Consul backend)

-   **Preconfigured engines** (KV v2, Transit, PKI, Database, Userpass, AppRole)

-   **Plugin Mode** to extend the lab

-   **Ephemeral Mode** --- a RAM-only Vault that leaves zero traces

No YAML. No Docker. No Terraform.\
Just a script.

* * * * *

🏁 **Quick Start**
------------------

Start a Vault lab:

`./vault-lab-ctl.sh start`

Start with TLS:

`./vault-lab-ctl.sh --tls start`

Start a **disposable**, in-memory Vault:

`./vault-lab-ctl.sh --ephemeral start`

Stop:

`./vault-lab-ctl.sh stop`

Reset the lab:

`./vault-lab-ctl.sh reset`

* * * * *

🔥 **Ephemeral Mode --- a killer feature**
----------------------------------------

Ephemeral Mode creates a full Vault+Consul environment that **lives entirely in RAM**\
and **vanishes** cleanly when you stop it.

-   No persistent folders

-   No secret leftovers

-   No cleanup required

-   No pollution of your project directory

-   Perfect for demos, workshops, conference talks, or chaos testing

It feels like spinning up a **temporary Vault universe** --- built in seconds, erased instantly.

`./vault-lab-ctl.sh --ephemeral start`

This alone makes the lab dramatically more flexible than traditional Vault examples.

* * * * *

🔧 **Plugin Mode**
------------------

Drop any `*.sh` file in:

`plugins/`

Example:

`on_after_start() {
    log INFO "[demo] Vault has started!"
}`

Plugins are automatically:

-   discovered

-   sourced

-   ordered

-   connected to lifecycle hooks

This turns the lab into a **framework** instead of a monolithic script.

* * * * *

🔐 **What comes preconfigured**
-------------------------------

You get a usable Vault from second zero.

-   KV v2 (`secret/`)

-   Transit (`transit/`)

-   PKI (`pki/`)

-   Userpass + AppRole ready for testing

-   Database engine (demo config)

-   Audit device (file or /dev/null)

-   Shell mode with VAULT_ADDR and VAULT_TOKEN exported

* * * * *

📦 **Features at a glance**
---------------------------

-   Single-file architecture

-   Automatic binary download

-   Single-node or multi-node cluster

-   File or Consul backend

-   Optional TLS with full CA chain

-   Backup & restore

-   Full lifecycle: start, stop, restart, reset, cleanup, status

-   Ephemeral Mode (RAM-only)

-   Plugin Mode

-   Works on Linux, macOS, Windows/WSL

* * * * *

🧠 **Use it for**
-----------------

-   Learning Vault

-   Teaching Vault workshops

-   PKI, Transit, AppRole experiments

-   HA simulations

-   Break/fix exercises

-   Building custom modules via Plugin Mode

-   Demo environments for talks & trainings

* * * * *

🌍 **Zero friction. Zero excuses. Zero to Vault.**
--------------------------------------------------