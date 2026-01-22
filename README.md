🔐 Zero to Vault Lab
====================

From zero to a working HashiCorp Vault lab in minutes.\
No TLS. No cloud. No production illusions. Just learning.

* * * * *

🚀 What is this?

Zero to Vault Lab is an ephemeral and opinionated HashiCorp Vault playground.\
It is designed for DevOps engineers, DevSecOps beginners and developers who are curious about security but don't want to fight complexity on day one.

The goal is simple: spin up a *real* Vault instance locally, experiment with authentication methods, policies and secrets, and then destroy everything cleanly when you are done.

No prior Vault experience is required.

* * * * *

🧠 Why this lab exists

Vault is powerful, but it can also be intimidating.\
Between TLS, clustering, cloud integrations and production-grade setups, it is easy to lose sight of the core concepts.

This lab exists to remove friction.\
There is no manual configuration, no TLS ceremony, no cloud dependency and no leftover state.\
You run a script, you get a working Vault, and you learn by doing.

* * * * *

⚡ Quick Start (60 seconds)

You only need a Linux environment (or WSL) with a standard shell toolchain available: bash, curl, jq and unzip. Docker is not required.

To start the lab:

git clone <https://github.com/marcogomiero/zero-to-vault-lab.git>\
cd zero-to-vault-lab\
./vault-lab-ctl.sh start

On startup, the script checks online for the latest *stable* Vault release.\
If the check or the download fails for any reason, it safely falls back to the local Vault binary.

At the end of the command you immediately get the Vault address, the root token, and the UI ready at:

<http://127.0.0.1:8200>

* * * * *

🎬 Demo

The demo is intentionally short and terminal-focused.

What you see is a simple, realistic flow: the lab is started, the UI is accessed, authentication methods are bootstrapped, a demo user logs in, and finally everything is stopped and cleaned up.

The idea is to show the full lifecycle without distractions.

* * * * *

🧪 What gets bootstrapped

When you run:

./vault-lab-ctl.sh bootstrap

the lab configures a minimal but meaningful Vault setup.

Two secrets engines are enabled: a KV v2 engine for generic secrets and the transit engine for cryptographic operations.\
Two authentication methods are configured: AppRole and userpass.\
A demo user is created with username "demo" and password "demo", along with policies that allow read and write access to secrets under kv/demo/* and read access to health endpoints.

The bootstrap process is idempotent and safe to run multiple times.

* * * * *

🖥️ Available commands

The control script exposes a small, explicit set of commands:

start\
Starts a fresh ephemeral Vault lab.

restart\
Destroys the current lab and recreates it from scratch.

bootstrap\
Configures secrets engines, authentication methods, users and demo data.

status\
Shows the current Vault status.

env\
Prints the environment variable exports needed to use the Vault CLI.

stop\
Stops Vault and removes all lab data.

--help\
Shows inline help.

* * * * *

🔐 Authentication examples

The root token is printed automatically after start or bootstrap and can be used directly with the Vault CLI:

vault login <root-token>

To test userpass authentication with the demo user, make sure you are not authenticated as root:

unset VAULT_TOKEN\
rm -f ~/.vault-token\
vault login -method=userpass username=demo password=demo

It is important to note that the Vault CLI persists tokens in ~/.vault-token.\
Unsetting VAULT_TOKEN alone may not be enough.

* * * * *

🧹 Cleanup philosophy

This lab is ephemeral by design.

Running:

./vault-lab-ctl.sh stop

kills all Vault processes, frees port 8200 and removes all temporary lab directories under /tmp.\
No state is left behind.

* * * * *

🎯 Learning goals

After using this lab, you should have a clear understanding of what Vault actually does, how authentication methods differ, how policies control access, how secrets engines behave, and how to interact with Vault through both the CLI and the UI.

This is not a mock environment.\
It is a real Vault instance, with training wheels.

* * * * *

🛑 What this is NOT

This project is not production-ready, not secure by default, not TLS-enabled and not cloud-integrated.\
It is a learning lab, not a blueprint.

* * * * *

📦 Roadmap (maybe)

Future improvements may include an HA setup backed by Consul, a Docker-based version, CI via GitHub Actions, published documentation pages and more advanced bootstrap profiles.

* * * * *

🤝 Contributing

Pull requests are welcome, especially for documentation, diagrams, examples and educational improvements.

The guiding principles are simple: keep it simple, keep it didactic, keep it honest.