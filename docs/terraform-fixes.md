# Terraform Fix Instructions

These steps fix the issues listed in [terraform-review.md](terraform-review.md).

The input and output names below come from the module sources pinned in the code:

| Module | Ref | Inputs used | Outputs used |
|---|---|---|---|
| `resource-group` | `resource-group/v1.0.0` | `name`, `location`, `rg_tags` | `name`, `location`, `id` |
| `vnet` | `vnet/v1.0.0` | `vnet_name`, `vnet_address_space`, `vnet_tags`, `subnets`, `nsg_name`, `nsg_tags`, `nsg_rules` | `vnet_id`, `vnet_name`, `subnet_ids` (map of name → ID **string**), `nsg_id` |
| `virtual-machine` | `virtual-machine/v1.0.0` | `vm_name`, `subnet_id`, `vm_size`, `vm_admin_username`, `vm_admin_ssh_public_keys`, `vm_custom_data`, `vm_os_disk`, `vm_source_image`, `vm_tags` | `vm_id`, `vm_name`, `private_ip_address`, `nic_id` |

Work through the steps in order. Step 0 decides whether step 7 (state migration) applies to you.

**Status (2026-11-05, second pass):** step 1 is done, step 2a is done, step 4.1 and 4.2 are done, steps 2b and 2c (`network.tf`), 5 (`outputs.tf`) and 6 (`ansible.tf`) are done, `terraform validate` passes, and the VM modules already pass `vm_name`, `vm_size`, `vm_admin_username`, `subnet_id` and `vm_tags`. `terraform init` has been run. The steps below are updated to cover only what is still open, plus the new findings (NAT outputs, VNet range override in `terraform.tfvars`, missing SSH key).

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

## Step 1: `main.tf` (providers) — done

Already applied; kept for reference. The regenerated `.terraform.lock.hcl` (azurerm 5.12.0, azapi 2.13.0, local 2.9.1, null 3.3.2) is untracked: **commit it**. azurerm 4.x and later require `subscription_id`. The `local` and `null` providers used in `ansible.tf` also need to be declared.

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

`variables.tf` declares `subscription_id` with `default = ""`. Remove the default so a missing value fails at plan time instead of at provider configuration:

```hcl
variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}
```

Set its value in `terraform.tfvars`, which is git-ignored, or export `ARM_SUBSCRIPTION_ID` and leave the variable out.

After step 8, **commit the new `.terraform.lock.hcl`**. It is not git-ignored and should stay in the repo.

---

## Step 2: `network.tf` and `terraform.tfvars`

Fixes review issues 1, 3, 4 and 9.

### 2a: Fix the `vnet` module arguments — done

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

### 2b: Fix the output references — done

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

The same `.id` must also be dropped in `outputs.tf:42` (step 5). While here, either add `zones = ["1"]` to `azurerm_nat_gateway.main` or remove `zones` from `azurerm_public_ip.nat`, so the gateway and its public IP are in the same zone. The two `.id` uses in `vm.tf` go away with the root NICs in step 3.

### 2c: Delete the extra NSG association — done

Delete the whole `azurerm_subnet_network_security_group_association "main"` block at the end of `network.tf`. The module already creates this association as `subnet_nsg["snet-vm"]`, and Azure allows only one per subnet.

### 2d: Stop `terraform.tfvars` from overriding the VNet range

The local `terraform.tfvars` sets `vnet_address_space = ["10.0.0.0/16"]` and `subnet_address_prefixes = ["10.0.1.0/24"]`. The defaults are `10.1.x` on purpose: the peered `devopsVM-vnet` is very likely on Azure's default `10.0.0.0/16`, and peering fails on overlapping ranges. Delete those two lines (and, for an existing deployment, the `location`, `resource_group_name`, `master_vm_name` and `worker_vm_name_prefix` overrides, which each force replacement). Check the peer range with:

```bash
az network vnet show -g devops-group -n devopsVM-vnet --query addressSpace.addressPrefixes
```

Also delete the leftover comments copied from the old `.example` file ("Copy this to terraform.tfvars", the password rule).

---

## Step 3: `vm.tf` (rewrite)

Fixes review issues 1, 6, 7 and 8.

What is still missing in the current `vm.tf`: the root NICs are orphaned (the module creates its own `<vm_name>-nic`), and the locals are never passed to the modules, so the VMs get **no SSH key** (Azure rejects the VM, because password login is disabled), no cloud-init, the module's Ubuntu 24.04 image and a default-size `StandardSSD_LRS` disk. **Delete both `azurerm_network_interface` resources** (`master` and `worker`) and replace the whole file with:

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

Fixes the security items in the review. Items 1 and 2 are done.

1. **`admin_username`** (done): the module rejects `azureuser` as a reserved name. The default is now:
   ```hcl
   variable "admin_username" {
     description = "Admin username for the VMs"
     type        = string
     default     = "k8sadmin"
   }
   ```
   Any Ansible `group_vars`/`host_vars` that hard-code `azureuser` must change to match.

2. **`admin_password`** (done): delete the variable. Nothing uses it, and its default is a password committed to git. If that password was ever used anywhere, rotate it.

3. **`allowed_ssh_source`**: remove the `"*"` default so a value has to be chosen:
   ```hcl
   variable "allowed_ssh_source" {
     description = "Source CIDR allowed for SSH, e.g. the peered VNet range or your VPN range"
     type        = string
     # no default: set it in terraform.tfvars
   }
   ```
   The VMs have no public IP and are reached through the peered VNet, so the peer VNet's address range is a good value.

4. Remove the `""` default from `subscription_id` (see step 1).

5. Check that `ssh_private_key_path` is the private half of `ssh_public_key_path`. The old `ansible/hosts` used `~/.ssh/ansible_id`, while the defaults are `~/.ssh/id_rsa{,.pub}`.

`terraform.tfvars.example` was deleted. If you want an example file again, recreate it from `terraform.tfvars` without real values (`.gitignore` already allows `*.tfvars.example`).

---

## Step 5: `outputs.tf` — done

Fixes review issues 1, 2, 3 and 5. `resource_group_name` and `resource_group_location` are already fixed. Replace every other reference to module internals or removed resources:

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

# There is no module.nat_gateway: the NAT gateway is a plain resource in network.tf
output "nat_gateway_name" {
  description = "Name of the NAT Gateway"
  value       = azurerm_nat_gateway.main.name
}

output "nat_gateway_public_ip" {
  description = "Public IP address of the NAT Gateway (used for outbound internet)"
  value       = azurerm_public_ip.nat.ip_address
}

# ansible_inventory_path: unchanged

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

## Step 6: `ansible.tf` — done

Fixes review issues 2, 10 and 12.

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

The playbooks are back under `ansible/k8s/setup/` (`k8s-main.yaml`, `os-setup.yaml`, `containerd-setup.yaml`, `kube-setup.yaml`, `cluster-setup.yaml`), so the provisioner path must change from `k8s/k8s-main.yaml` to `k8s/setup/k8s-main.yaml` as shown. `depends_on` on `local_file.ansible_inventory` is dropped because the module references already create the dependency.

---

## Step 7: Migrate existing state

Fixes review issue 11. **Skip this step if step 0 showed empty state.**

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
| 1 | `.id` on `subnet_ids` string values | Steps 2b, 3, 5 |
| 2 | Module internals (`module.x.azurerm_...`) referenced from outside | Steps 5, 6 |
| 3 | `module.vnet.id` / `module.vnet.name` don't exist | Steps 2b, 5 |
| 4 | Broken, duplicate NSG association | Step 2c |
| 5 | Undeclared `module.nat_gateway` in outputs | Step 5 |
| 6 | No SSH key passed to the VM modules | Step 3 |
| 7 | Dead locals: no cloud-init, wrong image and OS disk | Step 3 |
| 8 | Orphan root NICs | Step 3 |
| 9 | `terraform.tfvars` overrides the VNet range to `10.0.0.0/16` (peering overlap) | Step 2d |
| 10 | Playbook path `k8s/k8s-main.yaml` moved to `k8s/setup/` | Step 6 |
| 11 | No state migration | Step 7 |
| 12 | Ansible reruns on every apply; boot wait runs once | Step 6 |
| 13 | Module defaults (trusted launch, identity, boot diagnostics) | Step 3 notes |
| — | `allowed_ssh_source = "*"`, `subscription_id = ""`, key-path mismatch | Step 4 |
