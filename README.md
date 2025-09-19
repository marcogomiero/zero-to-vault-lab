**ZERO-TO-VAULT-LAB**

Your entire **HashiCorp Vault** playground, built from nothing in minutes.\
Run one command and the script pulls the latest binaries, wires up TLS, enables auto-unseal, and spins up a multi-node Vault + Consul cluster ready for testing.

* * * * *

**WHY IT'S AWESOME**

- **Single-file convenience** -- everything lives in `vault-lab-ctl.sh`.\
- **Self-assembling** -- downloads and configures all binaries and dependencies automatically.\
- **Multi-cluster capable** -- 3-node Vault cluster with Consul backend or a single node for quick tests.\
- **Secure by default** -- automatic TLS certificates, encrypted connections, auto-unseal.\
- **Break it & rebuild it** -- experiment freely, reset with one command.\
- **Batteries included** -- KV v2, PKI, Transit and Database engines pre-enabled.\
- **Enterprise-ready** -- backup/restore, certificate management, multi-backend support.

* * * * *

**QUICK START**

`git clone https://github.com/your-repo/zero-to-vault-lab.git
cd zero-to-vault-lab
./vault-lab-ctl.sh start      (single node, file backend, no TLS)`

* * * * *

**TLS-FIRST SECURITY**

Start with automatic TLS:\
`./vault-lab-ctl.sh --tls start`

Enable interactively:\
`./vault-lab-ctl.sh start` → answer **y** when asked "Enable TLS/SSL encryption?"

**What TLS gives you**

- Self-signed CA certificate\
- Individual certificates for each Vault and Consul node\
- HTTPS endpoints: **<https://127.0.0.1:8200>** and **<https://127.0.0.1:8500>**\
- Proper certificate validation and SANs\
- Certificate backup/restore in lab snapshots

Trust the lab CA:\
Linux: `sudo cp tls/ca/ca-cert.pem /usr/local/share/ca-certificates/vault-lab-ca.crt && sudo update-ca-certificates`\
macOS: `sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain tls/ca/ca-cert.pem`\
Windows: import `tls/ca/ca-cert.pem` into **Trusted Root Certification Authorities**.

* * * * *

**KEY FEATURES**

| Feature | What you get |
| --- | --- |
| **Single/Multi Mode** | Single node or full 3-node Vault cluster backed by Consul |
| **TLS Encryption** | Automatic certificates, HTTPS endpoints, full validation |
| **Flexible Backends** | File storage for simplicity or Consul for distributed scenarios |
| **One-line lifecycle** | start / stop / restart / reset / cleanup / status, plus interactive shell |
| **Backup & Restore** | Full-state backups with SHA256 verification, easy export/import |
| **Pre-configured Auth** | Userpass test user and AppRole with ready Role ID/Secret ID |
| **Secrets Engines** | KV v2, PKI, Transit, and Database (SQLite demo) pre-enabled |

* * * * *

**ADVANCED USAGE**

Multi-Node Cluster with TLS:\
`./vault-lab-ctl.sh --cluster multi --backend consul --tls start`

Starts:\
- 1 Consul server with TLS and ACL\
- 3 Vault nodes (ports 8200/8201/8202) with individual certificates\
- Automatic initialization and unseal\
- Full HTTPS communication

Backup & Restore:

```
./vault-lab-ctl.sh backup my-config "Working KV setup with TLS"
./vault-lab-ctl.sh list-backups
./vault-lab-ctl.sh restore my-config
./vault-lab-ctl.sh export-backup my-config ./my-backup.tar.gz
./vault-lab-ctl.sh import-backup ./my-backup.tar.gz imported-config
```

Interactive Shell (environment pre-configured)

`
./vault-lab-ctl.sh shell
`

Environment variables set automatically:
  VAULT_ADDR
  VAULT_TOKEN
  VAULT_CACERT
  PATH

* * * * *

**DEMO ENGINES OUT OF THE BOX**

- **KV v2** -- key/value secrets at `secret/`\
- **PKI** -- issue and manage certificates with 10-year max TTL\
- **Transit** -- encryption-as-a-service\
  `vault write transit/encrypt/lab-key plaintext=$(base64 <<< "hello")`\
- **Database (SQLite)** -- dynamic credentials\
  `vault read database/creds/demo-role`\
- **Authentication** -- Userpass and AppRole pre-configured with policies

* * * * *

**COMMAND REFERENCE**

Lifecycle

```
./vault-lab-ctl.sh start      # start lab
./vault-lab-ctl.sh stop       # stop services
./vault-lab-ctl.sh restart    # restart and unseal
./vault-lab-ctl.sh reset      # full reset and restart
./vault-lab-ctl.sh status     # check service status
./vault-lab-ctl.sh cleanup    # clean all data
```

Configuration Options

```
./vault-lab-ctl.sh --tls start
./vault-lab-ctl.sh --cluster multi start
./vault-lab-ctl.sh --backend consul start
./vault-lab-ctl.sh --clean start
./vault-lab-ctl.sh --verbose start
```

Backup Operations

```
./vault-lab-ctl.sh backup [name] [description]
./vault-lab-ctl.sh restore <name> [--force]
./vault-lab-ctl.sh list-backups
./vault-lab-ctl.sh delete-backup <name> [--force]
./vault-lab-ctl.sh export-backup <name> [path]
./vault-lab-ctl.sh import-backup <path> [name]
```

* * * * *

**DIRECTORY STRUCTURE**

```
zero-to-vault-lab/
├─ vault-lab-ctl.sh      single all-in-one script
├─ bin/                  downloaded binaries
├─ vault-data/           Vault storage and config
├─ consul-data/          Consul data and logs
├─ tls/                  certificate authority and certs
└─ backups/              lab state snapshots
```

* * * * *

**TROUBLESHOOTING**

TLS Certificate Issues\
- Certificates auto-generated with proper SAN entries for localhost/127.0.0.1\
- Import the CA certificate to avoid browser warnings\
- Check validity: `openssl x509 -in tls/ca/ca-cert.pem -text -noout`

Service Connection Issues\
- Verify ports 8200 (Vault) and 8500 (Consul) are available\
- Logs: `tail -f vault-data/vault.log` or `tail -f consul-data/consul.log`\
- Use `./vault-lab-ctl.sh status` for service health

Vault Sealed State\
- Script handles unsealing automatically, but ensure `vault-data/unseal_key.txt` exists\
- Manual unseal: `vault operator unseal $(cat vault-data/unseal_key.txt)`

* * * * *

**ARCHITECTURE**

- Single Node + File Backend -- simplest setup\
- Single Node + Consul Backend -- introduces Consul concepts\
- Multi-Node + Consul Backend -- full HA cluster simulation\
- Any combination with TLS -- production-like encrypted communication

All configurations include the same set of pre-configured authentication methods, policies, and secrets engines for immediate hands-on learning.

* * * * *

**LEARN MORE**

Explore dynamic secrets, certificate management, encryption-as-a-service, and high availability patterns.\
Clone. Run. Break it. Rebuild it.