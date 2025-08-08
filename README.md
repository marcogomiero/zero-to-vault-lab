Zero to Vault Lab
=================

A ready-to-use **HashiCorp Vault** and **OpenBao** lab environment for development and testing.\
Supports quick setup, backend selection (file or Consul for Vault), automated configuration, and full cleanup.

* * * * *

Features
--------

### Vault Lab

-   Start, stop, restart, status, and cleanup commands.

-   Choose backend at startup:

    -   **file** (default)

    -   **consul**

-   Automatic Vault binary management (download latest if not found).

-   Self-signed TLS certificate generation.

-   Automatic initialization and unseal for lab purposes.

-   Pre-configured secrets engines:

    -   KV v2 (`secret/` and `kv/`)

    -   PKI (`pki/`)

-   Pre-configured auth methods:

    -   Userpass (`devuser/devpass`)

    -   AppRole (role: `web-application` with stored RoleID/SecretID).

-   Example policy (`dev-policy`) applied to test users.

-   Audit device enabled (`/dev/null`).

### Bao Lab

-   Same structure as Vault Lab (commands, TLS, initialization, unseal).

-   No Consul backend (file storage only).

-   Pre-configured secrets engines, auth methods, example user, and AppRole role.

-   Example policy and audit device.

-   Fully aligned with Vault Lab workflow.

* * * * *

**New in v1.4.1 --- Unified Control Scrip [BETA]t**
------------------------------------------

-   Single entry point script for both Vault and Bao.

-   Interactive menu at launch:

    -   Choose **Vault** or **Bao**.

    -   If Vault → choose **file** or **consul** backend.

-   Instance detection:

    -   Detects if Vault, Consul, or Bao is already running.

    -   Prompts to either:

        -   Continue with the current instance.

        -   Clean up and start fresh.

-   Maintains all original subcommand features (`start`, `stop`, `status`, `restart`, `cleanup`).

-   Full English code comments and console messages.

* * * * *

Requirements
------------

-   **Linux** or WSL (Windows Subsystem for Linux)

-   Installed:

    -   `curl`, `jq`, `unzip`, `tar`, `lsof`, `openssl`

    -   `consul` binary if using Consul backend

-   Internet connection for first run (to fetch binaries).

* * * * *

Usage
-----

### 1\. Launch the unified control script:

`./lab-ctl.sh`

-   Follow the interactive prompts to select Vault/Bao and backend.

-   If instances are running, choose whether to clean up or continue.

### 2\. Direct usage (Vault or Bao specific):

`./vault-lab-ctl.sh --backend file start
./vault-lab-ctl.sh --backend consul start
./bao-lab-ctl.sh start`

### 3\. Commands available:

-   `start` --- launches and configures the lab instance

-   `status` --- shows current server status

-   `restart` --- restarts the server

-   `stop` --- stops the server

-   `cleanup` --- removes all lab data and certificates

* * * * *

Example Outputs
---------------

### Vault start (file backend):

`[INFO] Starting Vault with file backend...
[INFO] Vault is listening and responding after 10 seconds. ✅
...
[INFO] Vault is UNSEALED and READY. 🎉`

### Bao start:

`[INFO] Starting OpenBao server...
[INFO] OpenBao is UNSEALED and READY. 🎉`

* * * * *

Cleanup
-------

To remove **all** lab data:

`./vault-lab-ctl.sh cleanup
./bao-lab-ctl.sh cleanup`

Or from the unified script, choose cleanup when prompted.

* * * * *

Security Notes
--------------

-   This lab saves **root tokens** and **unseal keys** in plain text for convenience --- do **NOT** use in production.

-   TLS uses self-signed certificates --- browsers and CLI will need to skip verification.

* * * * *

Release History
---------------

-   **v1.4.0** --- Unified Vault/Bao control script with interactive menu, instance detection, and backend selection.

-   **v1.3.x** --- Flexible backend selection, improved cleanup routines, Consul backend integration.

-   **v1.2.x** --- Enhanced process management, TLS automation, AppRole and Userpass configuration.

-   **v1.0.0** --- Initial release with Vault Lab setup.