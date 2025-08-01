terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = ">= 3.23.0"
    }
  }
}

# Provider Vault
# Prende VAULT_ADDR e VAULT_TOKEN dalle variabili d'ambiente.
provider "vault" {
  # Se necessario, puoi sovrascrivere manualmente:
  # address = "https://vault.example.com"
}