#!/usr/bin/env bash

set -e  # Exit immediately if a command fails

# Colors for messages
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
RESET="\e[0m"

echo -e "${GREEN}🧹 Starting full Terraform cleanup...${RESET}"

# Confirm before proceeding
read -p "Are you sure you want to destroy all Terraform-managed resources and remove local files? (yes/[no]): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo -e "${YELLOW}Aborted by user.${RESET}"
  exit 0
fi

# Check for required Vault environment variables
if [[ -z "$VAULT_ADDR" || -z "$VAULT_TOKEN" ]]; then
  echo -e "${RED}❌ VAULT_ADDR and VAULT_TOKEN must be set before running this script.${RESET}"
  echo "Example:"
  echo "  export VAULT_ADDR=https://vault.example.com"
  echo "  export VAULT_TOKEN=hvs.xxxxx"
  exit 1
fi

# 1️⃣ Destroy Terraform-managed resources
echo -e "${YELLOW}➜ Destroying Terraform-managed resources...${RESET}"
terraform destroy -auto-approve

# 2️⃣ Clean up Terraform local files
echo -e "${YELLOW}➜ Removing local Terraform files...${RESET}"
rm -rf .terraform .terraform.lock.hcl tfplan terraform.tfstate terraform.tfstate.backup

echo -e "${GREEN}✅ All Terraform resources destroyed and local files removed!${RESET}"
