#!/usr/bin/env bash

set -e  # Exit immediately if a command fails

# Colors for messages
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
RESET="\e[0m"

echo -e "${GREEN}🚀 Starting Terraform bootstrap...${RESET}"

# Check for required Vault environment variables
if [[ -z "$VAULT_ADDR" || -z "$VAULT_TOKEN" ]]; then
  echo -e "${RED}❌ VAULT_ADDR and VAULT_TOKEN must be set before running this script.${RESET}"
  echo "Example:"
  echo "  export VAULT_ADDR=https://vault.example.com"
  echo "  export VAULT_TOKEN=hvs.xxxxx"
  exit 1
fi

# 1️⃣ Initialize Terraform
echo -e "${YELLOW}➜ Initializing Terraform...${RESET}"
terraform init

# 2️⃣ Generate execution plan
echo -e "${YELLOW}➜ Generating Terraform plan...${RESET}"
terraform plan -out=tfplan

# 3️⃣ Apply the plan
echo -e "${YELLOW}➜ Applying Terraform plan...${RESET}"
terraform apply "tfplan"

echo -e "${GREEN}✅ Terraform completed successfully!${RESET}"
