# Enable AppRole auth method if not already enabled (idempotent)
resource "vault_mount" "approle_auth" {
  path = "approle"
  type = "approle"
  description = "AppRole authentication method managed by Terraform."
}

# Create an AppRole named 'terraform-approle'
resource "vault_approle_auth_backend_role" "terraform_approle" {
  role_name = "terraform-approle"
  token_ttl = 3600
  token_max_ttl = 7200
  token_policies = ["default", vault_policy.terraform_read_policy.name] # Attach the policy defined in policy.tf
  bind_secret_id = true # Allow secret ID to be bound
  secret_id_num_uses = 1 # Allow secret ID to be used once
  secret_id_ttl = 300
}

# Read the Role ID of the 'terraform-approle'
data "vault_approle_auth_backend_role_id" "terraform_approle_id" {
  role_name = vault_approle_auth_backend_role.terraform_approle.role_name
}

# Generate a Secret ID for the 'terraform-approle'
resource "vault_approle_auth_backend_secret_id" "terraform_approle_secret" {
  role_name = vault_approle_auth_backend_role.terraform_approle.role_name
  cidr_list = ["0.0.0.0/0"] # For lab purposes, allow from any IP
}

output "terraform_approle_role_name" {
  value = vault_approle_auth_backend_role.terraform_approle.role_name
  description = "Name of the Terraform-managed AppRole."
}

output "terraform_approle_role_id" {
  value = data.vault_approle_auth_backend_role_id.terraform_approle_id.role_id
  description = "Role ID for the Terraform-managed AppRole."
}

output "terraform_approle_secret_id" {
  value     = vault_approle_auth_backend_secret_id.terraform_approle_secret.secret_id
  sensitive = true
  description = "Secret ID for the Terraform-managed AppRole. This should be handled with care."
}