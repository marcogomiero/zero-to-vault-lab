resource "vault_approle_auth_backend_role" "terraform_approle" {
  role_name          = "terraform-approle"
  token_ttl          = 3600
  token_max_ttl      = 7200
  token_policies     = ["default", "terraform-read-policy"]
  bind_secret_id     = true
  secret_id_num_uses = 1
  secret_id_ttl      = 600
}

resource "vault_approle_auth_backend_role_secret_id" "terraform_approle_secret" {
  role_name = vault_approle_auth_backend_role.terraform_approle.role_name
  cidr_list = ["0.0.0.0/0"] # Solo per laboratorio
}

output "terraform_approle_role_id" {
  value = vault_approle_auth_backend_role.terraform_approle.role_id
}

output "terraform_approle_secret_id" {
  value     = vault_approle_auth_backend_role_secret_id.terraform_approle_secret.secret_id
  sensitive = true
}
