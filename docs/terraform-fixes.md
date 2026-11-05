# Terraform Fix Instructions

These steps fix the issues listed in [terraform-review.md](terraform-review.md).

The input and output names below come from the module sources pinned in the code:

| Module | Ref | Inputs used | Outputs used |
|---|---|---|---|
| `resource-group` | `resource-group/v1.0.0` | `name`, `location`, `rg_tags` | `name`, `location`, `id` |
| `vnet` | `vnet/v1.0.0` | `vnet_name`, `vnet_address_space`, `vnet_tags`, `subnets`, `nsg_name`, `nsg_tags`, `nsg_rules` | `vnet_id`, `vnet_name`, `subnet_ids` (map of name → ID **string**), `nsg_id` |
| `virtual-machine` | `virtual-machine/v1.0.0` | `vm_name`, `subnet_id`, `vm_size`, `vm_admin_username`, `vm_admin_ssh_public_keys`, `vm_custom_data`, `vm_os_disk`, `vm_source_image`, `vm_tags` | `vm_id`, `vm_name`, `private_ip_address`, `nic_id` |

Work through the steps in order. Step 0 decides whether step 7 (state migration) applies to you.

---

## Step 0: Check whether state exists

`.gitignore` excludes `*.tfstate`, no backend is configured, and there's no `terraform.tfstate` in the repo directory. Find out where the state for the running cluster lives before changing anything:

```bash
terraform state list
```

- **Empty, or "No state file was found":** this is a fresh deployment. Skip step 7.
- **Lists resources such as `azurerm_resource_group.main`:** do step 7 **before** any `terraform apply`. Without it, the plan destroys the resource group and everything in it.

If the state is on another machine, copy it here or configure a remote backend first.

---

## Step 1: `main.tf` (providers)

Fixes issue 9. azurerm 4.x and later require `subscription_id`. The `local` and `null` providers used in `ansible.tf` also need to be declared.

```hcl
terraform {
  required_version = ">= 1.17"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.12" # the modules require >= 5.12, < 6.0
    }
    azapi = {
      source  = "azure/azapi" # needed by the virtual-machine module
      version = "~> 2.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
```

Delete the commented-out resource group block at the bottom of the file; it now lives in `rg.tf`.

Add to `variables.tf`:

```hcl
variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}
```

Set its value in `terraform.tfvars`, which is git-ignored, or export `ARM_SUBSCRIPTION_ID` and leave the variable out.

After step 8, **commit the new `.terraform.lock.hcl`**. It is not git-ignored and should stay in the repo.

---

## Step 2: `network.tf`

Fixes issues 3, 4 and 5.

### 2a: Fix the `vnet` module arguments

```hcl
module "vnet" {
  source              = "git::https://github.com/hamzaelouham/terraform-azurerm-modules.git//modules/vnet?ref=vnet/v1.0.0"
  vnet_name           = "vnet-${module.rg.name}"   # was: name
  vnet_address_space  = var.vnet_address_space    # was: address_space
  location            = module.rg.location
  resource_group_name = module.rg.name
  vnet_tags           = var.tags                  # was: tags

  subnets = {
    "snet-vm" = { address_prefixes = var.subnet_address_prefixes }
    # associate_nsg defaults to true, so the module attaches nsg-vm to this subnet
  }

  nsg_name = "nsg-vm"
  nsg_tags = var.tags

  nsg_rules = {
    AllowSSH = {
      priority               = 1001
      direction              = "Inbound"
      access                 = "Allow"
      protocol               = "Tcp"
      destination_port_range = "22"
      source_address_prefix  = var.allowed_ssh_source
    }
    AllowAllOutbound = {
      priority               = 1000
      direction              = "Outbound"
      access                 = "Allow"
      protocol               = "*"
      destination_port_range = "*"
      source_address_prefix  = "*"
    }
  }
}
```

### 2b: Fix the output references

`subnet_ids` is a map of plain ID strings, so drop the `.id`:

```hcl
resource "azurerm_subnet_nat_gateway_association" "main" {
  subnet_id      = module.vnet.subnet_ids["snet-vm"]   # was: ...["snet-vm"].id
  nat_gateway_id = azurerm_nat_gateway.main.id
}

resource "azurerm_virtual_network_peering" "peer_to_new" {
  # ...
  remote_virtual_network_id = module.vnet.vnet_id      # was: module.vnet.id
}

resource "azurerm_virtual_network_peering" "new_to_peer" {
  # ...
  virtual_network_name      = module.vnet.vnet_name    # was: module.vnet.name
}
```

### 2c: Delete the extra NSG association

Delete the whole `azurerm_subnet_network_security_group_association "main"` block at the end of `network.tf`. The module already creates this association as `subnet_nsg["snet-vm"]`, and Azure allows only one per subnet.

---

## Step 3: `vm.tf` (rewrite)

Fixes issues 1, 2 and 7.

The module creates its own NIC (`<vm_name>-nic`), so **delete both `azurerm_network_interface` resources** (`master` and `worker`). Replace the whole file with:

```hcl
locals {
  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))

  # Plain text: the module base64-encodes it itself
  cloud_init = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    username       = var.admin_username
    ssh_public_key = local.ssh_public_key
  })

  vm_image = {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  vm_os_disk = {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = var.os_disk_size_gb
  }
}

# =============================================================================
# Master Node
# =============================================================================
module "master" {
  source              = "git::https://github.com/hamzaelouham/terraform-azurerm-modules.git//modules/virtual-machine?ref=virtual-machine/v1.0.0"
  vm_name             = var.master_vm_name
  resource_group_name = module.rg.name
  location            = module.rg.location
  subnet_id           = module.vnet.subnet_ids["snet-vm"]
  vm_size             = var.master_vm_size

  vm_admin_username        = var.admin_username
  vm_admin_ssh_public_keys = [local.ssh_public_key]
  vm_custom_data           = local.cloud_init

  vm_source_image = local.vm_image
  vm_os_disk      = local.vm_os_disk

  vm_tags = merge(var.tags, { Role = "master" })
}

# =============================================================================
# Worker Nodes
# =============================================================================
module "worker" {
  source              = "git::https://github.com/hamzaelouham/terraform-azurerm-modules.git//modules/virtual-machine?ref=virtual-machine/v1.0.0"
  count               = var.worker_count
  vm_name             = "${var.worker_vm_name_prefix}-${count.index + 1}"
  resource_group_name = module.rg.name
  location            = module.rg.location
  subnet_id           = module.vnet.subnet_ids["snet-vm"]
  vm_size             = var.worker_vm_size

  vm_admin_username        = var.admin_username
  vm_admin_ssh_public_keys = [local.ssh_public_key]
  vm_custom_data           = local.cloud_init

  vm_source_image = local.vm_image
  vm_os_disk      = local.vm_os_disk

  vm_tags = merge(var.tags, { Role = "worker" })
}
```

Notes:
- `disable_password_authentication` isn't a module input. The module always disables password login for Linux.
- The module's defaults differ from the old VMs: trusted launch on, a system-assigned identity, boot diagnostics, and the OS disk named `<vm_name>-osdisk`. Set `vm_trusted_launch_enabled = false`, `vm_identity_type = null` or `vm_boot_diagnostics_enabled = false` if you don't want those. Either way, see step 7: the existing VMs get **replaced**.

---

## Step 4: `variables.tf`

Fixes issues 1 and 10.

1. **`admin_username`**: the module rejects `azureuser` as a reserved name. Change the default:
   ```hcl
   variable "admin_username" {
     description = "Admin username for the VMs"
     type        = string
     default     = "k8sadmin"
   }
   ```
   Any Ansible `group_vars`/`host_vars` that hard-code `azureuser` must change to match.

2. **`admin_password`**: delete the variable. Nothing uses it, and its default is a password committed to git. If that password was ever used anywhere, rotate it.

3. **`allowed_ssh_source`**: remove the `"*"` default so a value has to be chosen:
   ```hcl
   variable "allowed_ssh_source" {
     description = "Source CIDR allowed for SSH, e.g. the peered VNet range or your VPN range"
     type        = string
     # no default: set it in terraform.tfvars
   }
   ```
   The VMs have no public IP and are reached through the peered VNet, so the peer VNet's address range is a good value.

4. Add `subscription_id` (see step 1).

Update `terraform.tfvars.example` to match.

---

## Step 5: `outputs.tf`

Fixes issue 6. Replace every reference to a removed resource:

```hcl
output "resource_group_name" {
  description = "Name of the resource group"
  value       = module.rg.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = module.rg.location
}

output "master_vm_name" {
  description = "Name of the master VM"
  value       = module.master.vm_name
}

output "master_private_ip" {
  description = "Private IP address of the master node"
  value       = module.master.private_ip_address
}

output "worker_vm_names" {
  description = "Names of the worker VMs"
  value       = module.worker[*].vm_name
}

output "worker_private_ips" {
  description = "Private IP addresses of the worker nodes"
  value       = module.worker[*].private_ip_address
}

output "vnet_name" {
  description = "Name of the virtual network"
  value       = module.vnet.vnet_name
}

output "subnet_id" {
  description = "ID of the subnet"
  value       = module.vnet.subnet_ids["snet-vm"]
}

# nat_gateway_name, nat_gateway_public_ip and ansible_inventory_path: unchanged

output "ssh_master_command" {
  description = "SSH command to connect to the master node (requires VPN or peered VNet)"
  value       = "ssh ${var.admin_username}@${module.master.private_ip_address}"
}

output "ssh_worker_commands" {
  description = "SSH commands to connect to the worker nodes"
  value       = [for ip in module.worker[*].private_ip_address : "ssh ${var.admin_username}@${ip}"]
}
```

---

## Step 6: `ansible.tf`

Fixes issues 6, 7 and 10.

```hcl
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/inventory.tftpl", {
    master_ip            = module.master.private_ip_address
    worker_ips           = module.worker[*].private_ip_address
    ssh_user             = var.admin_username
    ssh_private_key_path = var.ssh_private_key_path
  })
  filename        = "${path.module}/ansible/inventory"
  file_permission = "0600"
}

resource "null_resource" "wait_for_vms" {
  depends_on = [module.master, module.worker]

  triggers = {
    vm_ids = join(",", concat([module.master.vm_id], module.worker[*].vm_id))
  }

  provisioner "local-exec" {
    command = "echo 'Waiting 60 seconds for VMs to boot...' && sleep 60"
  }
}

resource "null_resource" "run_ansible" {
  depends_on = [local_file.ansible_inventory, null_resource.wait_for_vms]

  # Rerun only when the VMs, the inventory or the k8s version change, not on every apply
  triggers = {
    vm_ids      = null_resource.wait_for_vms.triggers.vm_ids
    inventory   = local_file.ansible_inventory.content_sha256
    k8s_version = var.k8s_version
  }

  provisioner "local-exec" {
    command     = "ansible-playbook -i inventory k8s/setup/k8s-main.yaml -e k8s_version=${var.k8s_version}"
    working_dir = "${path.module}/ansible"
    environment = {
      ANSIBLE_HOST_KEY_CHECKING = "False"
    }
  }
}
```

> ⚠️ **Missing playbook (new finding):** the provisioner calls `k8s/k8s-main.yaml`, but commit `d29870f` deleted it, and `ansible/k8s/setup/` is empty. `run_ansible` fails until the playbooks are restored, for example with `git checkout c015689 -- ansible/k8s`. Point the `command` at wherever `k8s-main.yaml` ends up; the path above assumes `ansible/k8s/setup/`. Until then, add a `run_ansible` variable (`type = bool`, `default = false`) and set `count = var.run_ansible ? 1 : 0` on the resource, or remove the resource.

---

## Step 7: Migrate existing state

Fixes issue 8. **Skip this step if step 0 showed empty state.**

Create `moved.tf`:

```hcl
moved {
  from = azurerm_resource_group.main
  to   = module.rg.azurerm_resource_group.rg
}

moved {
  from = azurerm_virtual_network.main
  to   = module.vnet.azurerm_virtual_network.vnet
}

moved {
  from = azurerm_subnet.main
  to   = module.vnet.azurerm_subnet.subnet["snet-vm"]
}

moved {
  from = azurerm_network_security_group.main
  to   = module.vnet.azurerm_network_security_group.nsg
}

moved {
  from = azurerm_subnet_network_security_group_association.main
  to   = module.vnet.azurerm_subnet_network_security_group_association.subnet_nsg["snet-vm"]
}

# The old NSG defined its rules inline; the module manages each rule as a
# separate resource, so import them rather than letting Terraform recreate them.
import {
  to = module.vnet.azurerm_network_security_rule.rule["AllowSSH"]
  id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.Network/networkSecurityGroups/nsg-vm/securityRules/AllowSSH"
}

import {
  to = module.vnet.azurerm_network_security_rule.rule["AllowAllOutbound"]
  id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.Network/networkSecurityGroups/nsg-vm/securityRules/AllowAllOutbound"
}
```

**The VMs can't be migrated in place.** The module changes the NIC name (`nic-k8s-master` → `k8s-master-nic`), the OS disk name, the admin user and the security type, and each of these forces replacement. The master and workers will be **destroyed and recreated**, so the Kubernetes cluster has to be rebuilt by Ansible. Before applying:

1. Back up anything you need from the cluster (etcd snapshot, manifests, PV data).
2. Schedule downtime.
3. Run `terraform state rm azurerm_network_interface.master 'azurerm_network_interface.worker'` only if you want Terraform to *forget* the old NICs rather than delete them. Usually you should let it delete them, so they aren't left unused and billed.

Once a successful apply has run with `moved.tf` in place, the `moved` and `import` blocks can be kept or deleted.

---

## Step 8: Verify

```bash
terraform init -upgrade      # downloads modules + providers, writes .terraform.lock.hcl
terraform fmt -recursive
terraform validate           # must print "Success! The configuration is valid."
terraform plan -out tfplan
```

Check the plan before applying:

- [ ] `module.rg.azurerm_resource_group.rg` and `module.vnet.azurerm_virtual_network.vnet` show **"has moved"** or no change, **not** destroy (with existing state)
- [ ] No more than one `azurerm_subnet_network_security_group_association`
- [ ] Exactly 3 `azurerm_linux_virtual_machine` (1 master and 2 workers) and 3 NICs, with no extra top-level NICs
- [ ] `null_resource.run_ansible` doesn't show as replaced on a second `plan` straight after apply

Then:

```bash
terraform apply tfplan
git add .terraform.lock.hcl *.tf docs/
```

---

## Issue → step map

| # | Issue (from terraform-review.md) | Fixed in |
|---|---|---|
| 1 | VM modules written like resources / wrong inputs / reserved username / double base64 | Step 3, Step 4.1 |
| 2 | Self-referencing `network_interface_ids` | Step 3 |
| 3 | Bad NSG association reference / duplicate association | Step 2c |
| 4 | Wrong vnet module input names | Step 2a |
| 5 | Wrong vnet output names / `.id` on strings | Step 2b |
| 6 | `outputs.tf` / `ansible.tf` reference removed resources | Steps 5, 6 |
| 7 | Unattached NICs feed the Ansible inventory | Steps 3, 6 |
| 8 | No state migration → resource group/VNet destroyed | Step 7 |
| 9 | Unpinned providers, lock file deleted, `local`/`null` undeclared | Step 1 |
| 10 | Hard-coded password, SSH open to `*`, Ansible reruns on every apply | Steps 4, 6 |
| new | `run_ansible` points to a deleted playbook | Step 6 |
