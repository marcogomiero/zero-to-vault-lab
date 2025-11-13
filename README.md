ZERO-TO-VAULT-LAB

Zero-to-Vault-Lab gives you a fully operational HashiCorp Vault environment in the time it takes to inhale. One script, one command, and you're standing inside a complete Vault playground with everything wired, initialized, and ready to break.

This isn't a long setup guide or a pile of YAMLs. It's a living, self-building lab.

Fast. Disposable. Repeatable. And strangely fun.

* * * * *

WHAT MAKES IT SPECIAL

It's one file. A single, surgical control script that does everything: downloads binaries, creates directories, spins up Vault and Consul, generates certificates, configures engines, and unseals for you.

It's self-assembling. You can clone the repository on a blank machine and still get a full Vault+Consul stack with no external dependencies and no "manual setup" ritual.

It grows with you. Start with a simple single-node Vault using the file backend, or go straight to a full 3-node cluster backed by Consul. Everything is wired automatically.

It behaves like production. TLS certificates, SANs, CA generation, HTTPS endpoints, proper validation --- all included at no extra effort.

It forgives. Destroy the lab, reset it, rebuild it, test strange configurations, break the cluster on purpose. The script is designed to take a hit and come back smiling.

It ships batteries. KV v2, Transit, PKI, AppRole, Userpass, a demo Database engine --- everything you'd want to explore Vault's capabilities right out of the gate.

And then there's Ephemeral Mode. A mode for people who want speed above all else: the entire lab is created in a temporary system directory, runs from RAM, and vanishes cleanly on stop. No clutter, no cleanup, no leftovers.

* * * * *

QUICK START

Clone the repo and start a single-node Vault:\
./vault-lab-ctl.sh start

Or jump directly into a disposable in-memory lab:\
./vault-lab-ctl.sh --ephemeral start

Instant Vault, zero persistence, zero questions asked. Perfect for demos, experiments, or just playing.

* * * * *

TLS MODE

Need HTTPS everywhere? Add --tls and the script creates a private CA, signs all Vault/Consul certificates, configures SANs, and serves endpoints on secure ports.

./vault-lab-ctl.sh --tls start

You get real certificates, real CA files, and real validation. Great for anyone studying mTLS, PKI workflows, or Vault in production-style conditions.

* * * * *

FEATURES AT A GLANCE

Single-file architecture\
Automated binary download\
Single-node or multi-node cluster setups\
File or Consul backend\
Optional TLS with full certificate chain\
Interactive shell with exported environment variables\
Backup and restore (persistent mode)\
Ephemeral Mode for pure in-memory labs\
Pre-configured secrets engines and auth methods\
Clean lifecycle commands: start, stop, restart, reset, cleanup, status

* * * * *

ADVANCED SCENARIOS

Spin up a full 3-node Vault HA cluster with Consul and TLS:\
./vault-lab-ctl.sh --cluster multi --backend consul --tls start

Take snapshots of your lab, export them, import them elsewhere, or restore them later --- ideal for teaching, testing, or simulating upgrades.

Use the Transit or PKI engine immediately, generate dynamic credentials, or explore AppRole flows with the preconfigured roles the script creates.

Drop into an interactive shell:\
./vault-lab-ctl.sh shell

You'll find VAULT_ADDR, VAULT_TOKEN, PATH and CA variables already set.

* * * * *

EPHEMERAL MODE

This mode deserves its own spotlight.

./vault-lab-ctl.sh --ephemeral start

No prompts.\
No persistent folders.\
No lingering files.\
No cleanup required.

Vault, Consul, TLS assets, logs, PIDs --- everything lives under a randomly generated runtime directory and disappears when you stop the lab.

It feels like spinning up a mini-cluster inside RAM. Because that's exactly what it is.

Use it when you want to experiment without consequences. When you want to learn Vault by breaking things. Or when you need a clean environment immediately, without touching the project tree.

* * * * *

TROUBLESHOOTING

If something feels off, the status command gives you a clear picture of what's running.\
TLS issues? The CA and certificates are generated fresh each time, and SANs are correct out of the box.\
Service not responding? Check port usage or view live logs directly in the runtime directory.

Vault sealed? The script handles unseal automatically, but you can always unseal manually using the generated key when running in persistent mode.

* * * * *

ARCHITECTURE OVERVIEW

The lab supports multiple configurations:

- Single node with file backend\
- Single node with Consul backend\
- Multi-node Vault cluster with Consul\
- TLS or non-TLS mode\
- Persistent mode with filesystem storage\
- Ephemeral mode with everything in RAM

Each configuration enables the same set of auth methods and secrets engines so you can get to the good stuff immediately.

* * * * *

LEARN MORE

This lab is not meant to be static. It's a place to explore dynamic secrets, encryption-as-a-service, identity models, PKI lifecycles, HA behavior, token flows, and operational patterns.

Clone it. Launch it. Break it. Rebuild it.\
Vault makes more sense when you can take it apart safely --- and now you can.