# Write a secret to 'secret/terraform-managed-secret'
resource "vault_kv_secret_v2" "terraform_managed_secret" {
  mount    = "secret"
  name     = "terraform-managed-secret"
  data_json = jsonencode({
    username = "tf_user"
    password = "supersecurepasswordfromterraform"
    env      = "dev"
  })
}

output "terraform_secret_path" {
  value = vault_kv_secret_v2.terraform_managed_secret.path
  description = "Path of the secret managed by Terraform."
}