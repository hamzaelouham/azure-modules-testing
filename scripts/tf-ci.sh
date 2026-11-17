#!/usr/bin/env bash
# Runs Terraform in Azure Pipelines against the remote state backend.
# Call it from an AzureCLI@2 task with addSpnToEnvironment: true and a
# workload identity federation service connection, e.g.:  tf-ci.sh plan -out=tfplan
set -euo pipefail

: "${TF_STATE_RESOURCE_GROUP:?}" "${TF_STATE_STORAGE_ACCOUNT:?}" "${TF_STATE_CONTAINER:?}" "${TF_STATE_KEY:?}"

# Credentials from the service connection (set by addSpnToEnvironment).
# azurerm, azapi and the azurerm backend all read these.
export ARM_USE_OIDC=true
export ARM_CLIENT_ID="${servicePrincipalId:?run inside AzureCLI@2 with addSpnToEnvironment: true}"
export ARM_TENANT_ID="${tenantId:?}"
export ARM_OIDC_TOKEN="${idToken:?the service connection must use workload identity federation}"
ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
export ARM_SUBSCRIPTION_ID
export TF_IN_AUTOMATION=true TF_INPUT=0

# Remote backend only in CI; local runs keep their local state.
# *_override.tf is gitignored.
cat > backend_override.tf <<'EOF'
terraform {
  backend "azurerm" {}
}
EOF

terraform init -input=false \
  -backend-config="resource_group_name=${TF_STATE_RESOURCE_GROUP}" \
  -backend-config="storage_account_name=${TF_STATE_STORAGE_ACCOUNT}" \
  -backend-config="container_name=${TF_STATE_CONTAINER}" \
  -backend-config="key=${TF_STATE_KEY}"

terraform "$@"
