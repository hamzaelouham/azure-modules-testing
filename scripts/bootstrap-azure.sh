#!/usr/bin/env bash
# One-time Azure setup for the Azure DevOps pipeline. Safe to re-run: every
# step checks what already exists first.
#
#   1. Registers the Compute, Network and Storage resource providers
#   2. Creates the Terraform state resource group, storage account and container
#   3. Gives the service connection's identity Contributor on the subscription
#   4. (--migrate)          Moves the local Terraform state into the storage account
#   5. (--update-pipeline)  Writes the storage account name into azure-pipelines.yml
#   6. Prints the regional vCPU quota against what the cluster needs
#
# Run it logged in (`az login`) as an Owner of the subscription, from the repo root:
#   scripts/bootstrap-azure.sh --sp <service-connection-app-or-object-id> --migrate --update-pipeline
#
# Find the service connection's identity in Azure DevOps: Project settings >
# Service connections > <connection> > "Manage service connection roles" (or the
# app ID shown under "Manage App registration").
set -euo pipefail

LOCATION=eastus2
STATE_RG=rg-tfstate
STORAGE_ACCOUNT=""
CONTAINER=tfstate
STATE_KEY=azure-modules-testing.tfstate
SP=""
MIGRATE=false
UPDATE_PIPELINE=false
PIPELINE_FILE=azure-pipelines.yml

usage() {
  sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'
  cat <<EOF
Options:
  --sp ID                 Service connection's app ID or object ID (required)
  --location REGION       Region for the state storage (default: $LOCATION)
  --state-rg NAME         State resource group (default: $STATE_RG)
  --storage-account NAME  State storage account. Default: the one already set in
                          $PIPELINE_FILE, else a new random tfstateXXXXXXXX
  --container NAME        Blob container (default: $CONTAINER)
  --key NAME              State blob name (default: $STATE_KEY)
  --migrate               Migrate local state into the storage account
  --update-pipeline       Set TF_STATE_STORAGE_ACCOUNT in $PIPELINE_FILE
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sp) SP="$2"; shift 2 ;;
    --location) LOCATION="$2"; shift 2 ;;
    --state-rg) STATE_RG="$2"; shift 2 ;;
    --storage-account) STORAGE_ACCOUNT="$2"; shift 2 ;;
    --container) CONTAINER="$2"; shift 2 ;;
    --key) STATE_KEY="$2"; shift 2 ;;
    --migrate) MIGRATE=true; shift ;;
    --update-pipeline) UPDATE_PIPELINE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[[ -n "$SP" ]] || { echo "--sp is required" >&2; usage >&2; exit 1; }
cd "$(dirname "$0")/.."

step() { printf '\n==> %s\n' "$*"; }

SUB=$(az account show --query id -o tsv)
step "Subscription: $(az account show --query name -o tsv) ($SUB)"

# --- 1. Resource providers ---------------------------------------------------
step "Resource providers"
for ns in Microsoft.Compute Microsoft.Network Microsoft.Storage; do
  state=$(az provider show -n "$ns" --query registrationState -o tsv)
  if [[ "$state" == Registered ]]; then
    echo "$ns: already registered"
  else
    echo "$ns: registering (can take a few minutes)..."
    az provider register -n "$ns" --wait -o none
  fi
done

# --- 2. State storage --------------------------------------------------------
step "State storage"
if [[ -z "$STORAGE_ACCOUNT" && -f "$PIPELINE_FILE" ]]; then
  current=$(sed -n 's/^ *TF_STATE_STORAGE_ACCOUNT: *//p' "$PIPELINE_FILE")
  [[ -n "$current" && "$current" != CHANGE_ME ]] && STORAGE_ACCOUNT="$current"
fi
[[ -n "$STORAGE_ACCOUNT" ]] || STORAGE_ACCOUNT="tfstate$(openssl rand -hex 4)"

if [[ $(az group exists -n "$STATE_RG") == true ]]; then
  echo "Resource group $STATE_RG: exists"
else
  echo "Resource group $STATE_RG: creating"
  az group create -n "$STATE_RG" -l "$LOCATION" --tags ManagedBy=bootstrap-azure.sh Purpose=terraform-state -o none
fi

if az storage account show -n "$STORAGE_ACCOUNT" -g "$STATE_RG" -o none 2>/dev/null; then
  echo "Storage account $STORAGE_ACCOUNT: exists"
else
  avail=$(az storage account check-name -n "$STORAGE_ACCOUNT" --query nameAvailable -o tsv)
  [[ "$avail" == true ]] || { echo "Storage account name $STORAGE_ACCOUNT is taken or invalid (3-24 lowercase letters/digits, globally unique)" >&2; exit 1; }
  echo "Storage account $STORAGE_ACCOUNT: creating"
  az storage account create -n "$STORAGE_ACCOUNT" -g "$STATE_RG" -l "$LOCATION" \
    --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 \
    --allow-blob-public-access false -o none
fi
# Versioning keeps earlier state versions, so a bad apply can be rolled back.
az storage account blob-service-properties update -n "$STORAGE_ACCOUNT" -g "$STATE_RG" --enable-versioning true -o none

KEY=$(az storage account keys list -n "$STORAGE_ACCOUNT" -g "$STATE_RG" --query "[0].value" -o tsv)
if [[ $(az storage container exists -n "$CONTAINER" --account-name "$STORAGE_ACCOUNT" --account-key "$KEY" --query exists -o tsv) == true ]]; then
  echo "Container $CONTAINER: exists"
else
  echo "Container $CONTAINER: creating"
  az storage container create -n "$CONTAINER" --account-name "$STORAGE_ACCOUNT" --account-key "$KEY" -o none
fi

# --- 3. Service connection role ----------------------------------------------
step "Service connection identity"
SP_OBJECT_ID=$(az ad sp show --id "$SP" --query id -o tsv)
echo "$(az ad sp show --id "$SP" --query displayName -o tsv) (object ID $SP_OBJECT_ID)"
if [[ -n $(az role assignment list --assignee "$SP_OBJECT_ID" --role Contributor --scope "/subscriptions/$SUB" --query "[?scope=='/subscriptions/$SUB'].id" -o tsv) ]]; then
  echo "Contributor on the subscription: already assigned"
else
  echo "Contributor on the subscription: assigning"
  az role assignment create --assignee-object-id "$SP_OBJECT_ID" --assignee-principal-type ServicePrincipal \
    --role Contributor --scope "/subscriptions/$SUB" -o none
fi

# --- 4. State migration ------------------------------------------------------
if $MIGRATE; then
  step "Migrating local state"
  if [[ -s terraform.tfstate ]]; then
    backup="terraform.tfstate.pre-migration.$(date +%Y%m%d%H%M%S)"
    cp terraform.tfstate "$backup"
    echo "Local state backed up to $backup (gitignored)"
  else
    echo "No local state file; this only connects the working directory to the remote backend"
  fi
  # *_override.tf is gitignored, so this stays local; CI writes its own.
  printf 'terraform {\n  backend "azurerm" {}\n}\n' > backend_override.tf
  terraform init -migrate-state -force-copy -input=false \
    -backend-config="resource_group_name=$STATE_RG" \
    -backend-config="storage_account_name=$STORAGE_ACCOUNT" \
    -backend-config="container_name=$CONTAINER" \
    -backend-config="key=$STATE_KEY" >/dev/null
  echo "Resources in remote state:"
  terraform state list | sed 's/^/  /'
fi

# --- 5. Pipeline file --------------------------------------------------------
if $UPDATE_PIPELINE; then
  step "Updating $PIPELINE_FILE"
  sed -i -E \
    -e "s/^( *TF_STATE_RESOURCE_GROUP: ).*/\1$STATE_RG/" \
    -e "s/^( *TF_STATE_STORAGE_ACCOUNT: ).*/\1$STORAGE_ACCOUNT/" \
    -e "s/^( *TF_STATE_CONTAINER: ).*/\1$CONTAINER/" \
    -e "s/^( *TF_STATE_KEY: ).*/\1$STATE_KEY/" \
    "$PIPELINE_FILE"
  git diff --quiet -- "$PIPELINE_FILE" && echo "Already up to date" || echo "Changed; commit and push it"
fi

# --- 6. vCPU quota -----------------------------------------------------------
step "vCPU quota in the cluster's region"
# The cluster's region is var.location in variables.tf, e.g. "East US 2" -> eastus2.
vm_region=$(sed -n '/variable "location"/,/^}/s/.*default *= *"\(.*\)"/\1/p' variables.tf | tr -d ' ' | tr '[:upper:]' '[:lower:]')
workers=$(sed -n '/variable "worker_count"/,/^}/s/.*default *= *\([0-9]*\).*/\1/p' variables.tf)
needed=$(( (1 + workers) * 2 ))  # Standard_B2s = 2 vCPUs
limit=$(az vm list-usage -l "$vm_region" --query "[?name.value=='cores'].limit | [0]" -o tsv)
used=$(az vm list-usage -l "$vm_region" --query "[?name.value=='cores'].currentValue | [0]" -o tsv)
echo "$vm_region: $used of $limit vCPUs in use; the cluster needs $needed (1 master + $workers workers, Standard_B2s)"
if (( used + needed > limit )); then
  echo "WARNING: not enough quota; apply will fail. Lower worker_count or raise the quota (Free Trial is capped at 4)."
fi

step "Done"
cat <<EOF
State backend:
  resource_group_name  = $STATE_RG
  storage_account_name = $STORAGE_ACCOUNT
  container_name       = $CONTAINER
  key                  = $STATE_KEY
EOF
