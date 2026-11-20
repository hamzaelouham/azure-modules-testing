# Terraform review: all `*.tf` files

Date: 2026-11-05 (second pass). Scope: `main.tf`, `rg.tf`, `network.tf`, `vm.tf`, `ansible.tf`, `outputs.tf`, `variables.tf` and the local `terraform.tfvars`, as they are in the working tree, uncommitted `vm.tf` changes included.

**Verdict: the configuration is still not valid.** `terraform init` has now been run (modules are in `.terraform/modules`, `.terraform.lock.hcl` is regenerated), so `terraform validate` runs and reports 15 errors. More errors would follow at `plan`. Module interfaces were checked against the cached sources in `.terraform/modules/{rg,vnet,master}/modules/...`.

## What the last change fixed

- `rg.tf` and the `vnet` module call now use the right input names (`name`/`location`/`rg_tags`, `vnet_name`/`vnet_address_space`/`vnet_tags`).
- `vm.tf`: the `master` and `worker` module calls now use `vm_name`, `vm_size`, `vm_admin_username`, `vm_tags` and pass `subnet_id`. The self-referencing `network_interface_ids` and the unsupported nested blocks are gone.
- `main.tf` declares `azapi`, `local` and `null`, and sets `subscription_id`. The lock file pins azurerm 5.12.0, azapi 2.13.0, local 2.9.1, null 3.3.2.
- `admin_username` defaults to `k8sadmin` (no longer the reserved `azureuser`), and `admin_password` was removed.
- `outputs.tf` uses `module.rg.name` / `module.rg.location`.
- The playbooks exist again under `ansible/k8s/setup/`.

## Blocking errors (validate or plan fails)

### 1. `vm.tf:52,90` passes the subnet ID correctly, but `network.tf:76`, `vm.tf:13,72` and `outputs.tf:42` still append `.id`
`module.vnet.subnet_ids` is `map(string)`. `module.vnet.subnet_ids["snet-vm"].id` is accepted by `validate` (the value is unknown) but fails at `plan` with "Unsupported attribute" / "Can't access attributes on a primitive-typed value (string)". Use `module.vnet.subnet_ids["snet-vm"]`.

### 2. Module internals are referenced from outside the module
`module.master.azurerm_network_interface.nic.private_ip_address` and `module.master.azurerm_linux_virtual_machine.vm.name` (and the `module.worker[*]` forms) are not addressable. Affected lines: `ansible.tf:8-9`, `outputs.tf:15,20,26,31,59,65`. Use the module outputs `vm_name`, `private_ip_address`, `vm_id`, `nic_id`.

### 3. `network.tf:90,96` use vnet outputs that do not exist
`module.vnet.id` and `module.vnet.name` must be `module.vnet.vnet_id` and `module.vnet.vnet_name`. `outputs.tf:37` has the same problem.

### 4. `network.tf:100-103` is a broken, duplicate NSG association
`azurerm_subnet.module.vnet...` is not a valid reference and `azurerm_network_security_group.main` no longer exists. The vnet module already associates `nsg-vm` with every subnet (`associate_nsg` defaults to `true`), and Azure allows one NSG per subnet. Delete the block.

### 5. `outputs.tf:48,53` reference an undeclared `module.nat_gateway`
The NAT gateway is a plain resource in `network.tf`. Use `azurerm_nat_gateway.main.name` and `azurerm_public_ip.nat.ip_address`.

## Functional bugs (plan succeeds, deployment is wrong)

### 6. The VM modules get no SSH key, so the VMs cannot be created or reached
`vm.tf` builds `local.admin_ssh_key` but never passes `vm_admin_ssh_public_keys`. The module forces `disable_password_authentication = true` on Linux and has no precondition for an empty key list, so Azure rejects the VM at apply ("Linux VMs with password authentication disabled require an SSH key"). Pass `vm_admin_ssh_public_keys = [local.admin_ssh_key]`.

### 7. All the locals in `vm.tf:21-41` are dead, so the VMs silently get module defaults
`custom_data`, `vm_os_disk` and `source_image_reference` are not wired to `vm_custom_data`, `vm_os_disk` and `vm_source_image`. Result: Ubuntu 24.04 (`ubuntu-24_04-lts/server`) instead of 22.04, a `StandardSSD_LRS` OS disk at the image default size instead of `Standard_LRS`/`os_disk_size_gb`, and no cloud-init (the passwordless-sudo user in `templates/cloud-init.yaml.tftpl` is never created). `os_disk_size_gb` is now an unused variable. When wiring `custom_data`, drop the `base64encode()`: the module encodes `vm_custom_data` itself, so it would be double-encoded.

### 8. Orphan NICs in `vm.tf:6-18,64-77`
The module creates its own NIC (`<vm_name>-nic`) from `subnet_id`. `azurerm_network_interface.master` and `.worker` are attached to nothing: they take three IPs from `snet-vm` and are billed for nothing. Delete them.

### 9. `local terraform.tfvars` overrides the VNet range back to `10.0.0.0/16`
`variables.tf` defaults to `10.1.0.0/16` / `10.1.1.0/24` (changed in `ede9c8d` for the peering, and the running cluster in `ansible/hosts` is on `10.1.1.x`). `terraform.tfvars` sets `10.0.0.0/16` / `10.0.1.0/24`, which is also Azure's default for portal-created VNets such as `devopsVM-vnet`. Overlapping address spaces make both peerings fail, and the range change forces the VNet and subnet to be replaced. The same file also moves `location` to `westeurope` and renames the VMs (`vm-master`, `vm-worker-N`) and the resource group, each of which forces replacement of an existing deployment. Remove those overrides or confirm a fresh deployment is intended.

### 10. `ansible.tf:41` runs a playbook path that no longer exists
The playbooks moved to `ansible/k8s/setup/`, so `k8s/k8s-main.yaml` must be `k8s/setup/k8s-main.yaml`.

## Operational issues

### 11. No state migration (`moved` blocks)
Every resource changed address (resource group, VNet, subnet and NSG into modules, VMs into the VM module). With existing state, `plan` destroys and recreates the resource group and everything in it. See [terraform-fixes.md](terraform-fixes.md) step 7.

### 12. Ansible reruns on every apply; the boot wait runs only once
`run_ansible` uses `triggers = { always_run = timestamp() }`, so the whole Kubernetes playbook runs on every `apply`, including applies that only change tags. `wait_for_vms` has no triggers, so it never runs again when VMs are replaced, and Ansible then races the boot. Trigger both on the VM IDs (and `run_ansible` also on the inventory hash and `k8s_version`).

### 13. Module defaults differ from the old VMs
Trusted launch, a system-assigned identity and boot diagnostics are on by default. Existing VMs are replaced (NIC and OS disk names change), so the cluster must be rebuilt.

## Security and cleanup

- `allowed_ssh_source` defaults to `"*"` in both `variables.tf:98` and `terraform.tfvars:23`. The VMs have no public IP today, but any public IP added later is open to the internet on 22. Set it to the peer VNet range.
- `ssh_private_key_path` defaults to `~/.ssh/id_rsa`, while `ansible/hosts` uses `~/.ssh/ansible_id`. The generated inventory uses the Terraform variable, so make sure the pair matches the public key that ends up on the VMs.
- Host key checking is disabled in both `ansible.tf:44` and `templates/inventory.tftpl`.
- `subscription_id` defaults to `""`. azurerm 4+ requires a subscription; with `""` it falls back to `ARM_SUBSCRIPTION_ID` and fails if that is unset. Remove the default or document the env var.
- `terraform.tfvars` still carries leftover comments from the deleted `terraform.tfvars.example` ("Copy this to terraform.tfvars", the password-rule comment).
- `azurerm_public_ip.nat` is pinned to zone `1` while `azurerm_nat_gateway.main` has no zone. Put both in the same zone, or remove `zones` from the public IP.
- `network.tf:18` has a stale commented `# vnet_tags` line (it is set on line 39), and `vm.tf` mixes `file(pathexpand(...))` and `file(...)` for the same key: use `local.admin_ssh_key` everywhere.
