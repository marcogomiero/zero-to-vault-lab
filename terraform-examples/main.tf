# Configure the Vault Provider
# Assumes VAULT_ADDR and VAULT_TOKEN are set as environment variables
# export VAULT_ADDR="http://127.0.0.1:8200"
# export VAULT_TOKEN="root"

provider "vault" {
  address = getenv("VAULT_ADDR")
  token   = getenv("VAULT_TOKEN")
}

# Ensure the 'secret' KV v2 engine is enabled (idempotent)
resource "vault_mount" "kv2_secret" {
  path        = "secret"
  type        = "kv"
  description = "KV V2 secret engine for general secrets"
  options = {
    version = "2"
  }
}

# Ensure the 'kv' KV v2 engine is enabled (idempotent)
resource "vault_mount" "kv2_kv" {
  path        = "kv"
  type        = "kv"
  description = "KV V2 secret engine for general key-value secrets"
  options = {
    version = "2"
  }
}