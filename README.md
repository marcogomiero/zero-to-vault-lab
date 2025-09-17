Zero-to-Vault-Lab
=================

**Your entire Vault playground, built from nothing in minutes.**\
Run a single command and watch the script pull the latest binaries, wire up TLS, enable auto-unseal, and spin up a **multi-cluster Vault + Consul lab** that's ready for real testing.

Why It's Awesome
----------------

-   **Self-assembling environment** -- downloads and configures every required binary and dependency automatically.

-   **Multi-cluster capable** -- create multiple Vault clusters for advanced scenarios with zero manual setup.

-   **Secure by default** -- TLS certificates and auto-unseal handled behind the scenes.

-   **Built for experimentation** -- policies, auth methods, secret engines... break it, rebuild it, repeat.

Quick Start
-----------

`git clone https://github.com/your-repo/zero-to-vault-lab.git
cd zero-to-vault-lab
./vault-lab-ctl.sh start`

That single command fetches everything and brings the lab online.\
Open **<https://localhost:8200>** to start exploring.

Learn More
----------

Full documentation, architecture diagrams, and advanced scenarios are in the **[project wiki](https://github.com/marcogomiero/zero-to-vault-lab/wiki)**.