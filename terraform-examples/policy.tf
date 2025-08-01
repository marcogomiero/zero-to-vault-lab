# Define a Vault policy named 'terraform-read-policy'
resource "vault_policy" "terraform_read_policy" {
  name = "terraform-read-policy"
  policy = <<EOT
path "secret/data/terraform-managed-secret" {
  capabilities = ["read"]
}

path "kv/data/terraform-approle-secret" {
  capabilities = ["read"]
}
EOT
}

output "terraform_read_policy_name" {
  value = vault_policy.terraform_read_policy.name
  description = "Name of the Terraform-managed read policy."
}