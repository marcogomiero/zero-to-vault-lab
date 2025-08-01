terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = ">= 3.23.0"
    }
  }
}

provider "vault" {
  # Usa VAULT_ADDR e VAULT_TOKEN dalle variabili d'ambiente
}

# Esempio: Creiamo un nuovo KV v2 store chiamato 'lab-secrets'
resource "vault_mount" "kv2_lab" {
  path        = "lab-secrets"
  type        = "kv"
  description = "KV V2 secret engine for lab examples"
  options = {
    version = "2"
  }
}