# Azure DevOps pipeline

`azure-pipelines.yml` runs three stages:

| Stage | Runs on | What it does |
|---|---|---|
| Validate | PRs and pushes to `main` | `terraform fmt -check`, `init -backend=false`, `validate` |
| Plan | PRs and pushes to `main` | `terraform plan` against remote state; on `main` it publishes the plan as an artifact |
| Apply | pushes to `main` only | waits for approval on the `k8s-test` environment, then applies the saved plan (this also runs the Ansible playbooks) |

`run_ansible` has a `timestamp()` trigger, so every plan has changes and every push to `main` asks for approval.

## One-time setup

### 1. Remote state (not done yet)

The pipeline keeps state in an Azure Storage blob. It writes `backend_override.tf` (gitignored) at run time, so local runs still use local state.

Create the storage account. The name must be globally unique, 3-24 lowercase letters and digits:

```bash
az group create -n rg-tfstate -l eastus2
az storage account create -n <account> -g rg-tfstate -l eastus2 --sku Standard_LRS --min-tls-version TLS1_2 --allow-blob-public-access false
az storage container create -n tfstate --account-name <account> --auth-mode login
```

Set `TF_STATE_STORAGE_ACCOUNT` in `azure-pipelines.yml` to `<account>`.

**Migrate your local state before the first pipeline run.** Local state already tracks `module.rg.azurerm_resource_group.rg`. Without the migration the pipeline starts from empty state and fails because `k8s-cluster` already exists.

```bash
cat > backend_override.tf <<'EOF'
terraform {
  backend "azurerm" {}
}
EOF
terraform init -migrate-state \
  -backend-config=resource_group_name=rg-tfstate \
  -backend-config=storage_account_name=<account> \
  -backend-config=container_name=tfstate \
  -backend-config=key=azure-modules-testing.tfstate
```

### 2. Service connection

Project settings > Service connections > New > Azure Resource Manager > **Workload identity federation (automatic)**. Scope it to the subscription and name it `azure-k8s-test`, or change `azureServiceConnection` in the pipeline to match.

The identity needs:
- **Contributor** on the subscription, to create the `k8s-cluster` resource group.
- Access to the state storage account. Contributor on `rg-tfstate` is enough, because the backend reads the account key.

### 3. SSH key pair as secure files

Pipelines > Library > Secure files: upload the key pair that Ansible uses to log in to the VMs.

- `k8s-ssh-key` (private key)
- `k8s-ssh-key.pub` (public key)

Authorize the pipeline to use both files. If you use a different key from your local `~/.ssh/id_ed25519`, the next apply replaces the VMs, because `custom_data` changes.

### 4. Approval gate

Pipelines > Environments > New environment `k8s-test` (no resources). Then open it and go to ⋮ > Approvals and checks > **Approvals**, and add yourself.

### 5. Create the pipeline

Pipelines > New pipeline > GitHub > `hamzaelouham/azure-modules-testing` > Existing YAML > `/azure-pipelines.yml`.

## Notes

- Commit `.terraform.lock.hcl` so CI uses the same provider versions you use locally. The plan stage also publishes it with the plan, so Apply always matches Plan.
- PRs from forks can't read secure files or the service connection, so their Plan stage fails. Only Validate is meaningful for them.
