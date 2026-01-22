🔐 Zero to Vault Lab
====================

> **From zero to a working HashiCorp Vault lab in minutes.**\
> No TLS. No cloud. No excuses. Just learning.

* * * * *

🚀 What is this?
----------------

**Zero to Vault Lab** is an **ephemeral, opinionated Vault playground** designed for:

-   DevOps engineers

-   DevSecOps beginners

-   Security-curious developers

It lets you **spin up a real Vault instance locally**, explore authentication methods, policies and secrets, and then **destroy everything cleanly**.

No prior Vault experience required.

* * * * *

🧠 Why this lab exists
----------------------

Vault is powerful --- and intimidating.

This project exists to remove friction:

-   ❌ no manual config

-   ❌ no TLS ceremony

-   ❌ no cloud dependency

-   ❌ no leftover state

Just run a script, get a Vault, learn by doing.

* * * * *

⚡ Quick Start (60 seconds)
--------------------------

### Requirements

-   Linux / WSL

-   `bash`, `curl`, `jq`, `unzip`

-   No Docker required

### Start the lab

`git clone https://github.com/marcogomiero/zero-to-vault-lab.git
cd zero-to-vault-lab
./vault-lab-ctl-dev.sh start`

You'll immediately get:

-   Vault address

-   Root token

-   UI ready at `http://127.0.0.1:8200`

* * * * *

🎬 Demo
-------------

**What happens here:**

1.  Start the lab

2.  Login via UI

3.  Bootstrap auth methods

4.  Login with a demo user

5.  Stop and clean everything

> 📌 *GIF is intentionally short and terminal-focused.*

*(I'll tell you below how to record it cleanly)*

* * * * *

🧪 What gets bootstrapped
-------------------------

Running:

`./vault-lab-ctl-dev.sh bootstrap`

Configures:

-   🔑 **Secrets engines**

    -   `kv-v2`

    -   `transit`

-   🔐 **Auth methods**

    -   `approle`

    -   `userpass`

-   👤 **Demo user**

    -   username: `demo`

    -   password: `demo`

-   📜 **Policies**

    -   read/write access to `kv/demo/*`

    -   health check access

Everything is **idempotent** and safe to re-run.

* * * * *

🖥️ Available Commands
----------------------

| Command | Description |
| --- | --- |
| `start` | Start a fresh ephemeral Vault lab |
| `restart` | Destroy and recreate the lab |
| `bootstrap` | Configure engines, auth, users |
| `status` | Show Vault status |
| `shell` | Open a shell with Vault env vars set |
| `stop` | Stop Vault and remove all data |
| `--help` | Show inline help |

* * * * *

🔐 Authentication examples
--------------------------

### Root token

Printed automatically after `start` or `bootstrap`.

`vault login <root-token>`

### Userpass (demo)

`vault login -method=userpass username=demo password=demo`

* * * * *

🧹 Cleanup philosophy
---------------------

This lab is **ephemeral by design**.

Running:

`./vault-lab-ctl-dev.sh stop`

Will:

-   kill all Vault processes

-   free port 8200

-   remove all `/tmp/vault-lab-*` directories

No leftovers. Ever.

* * * * *

🎯 Learning goals
-----------------

After using this lab, you should understand:

-   what Vault *actually* does

-   how auth methods differ

-   how policies control access

-   how secrets engines behave

-   how to interact via CLI and UI

This is **not a mock**.\
It's a **real Vault** with training wheels.

* * * * *

🛑 What this is NOT
-------------------

-   ❌ Production ready

-   ❌ Secure by default

-   ❌ TLS-enabled

-   ❌ Cloud-integrated

This is a **learning lab**, not a blueprint.

* * * * *

📦 Roadmap (maybe)
------------------

-   Consul backend / HA mode

-   Docker-based version

-   GitHub Actions CI

-   GitHub Pages docs

-   Advanced bootstrap profiles

* * * * *

🤝 Contributing
---------------

PRs welcome, especially for:

-   documentation

-   diagrams

-   examples

-   educational improvements

Keep it **simple**, **didactic**, **honest**.