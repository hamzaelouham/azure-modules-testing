# Terraform review: all `*.tf` files

Date: 2026-11-05. Scope: `main.tf`, `rg.tf`, `network.tf`, `vm.tf`, `ansible.tf`, `outputs.tf` and `variables.tf` as they are in the working tree, uncommitted changes included.

**Verdict: the configuration is not valid.** `terraform validate` stops at "Module not installed" because `terraform init` has not been run for the new git modules. Even after init, it would fail on the issues below. I checked them by hand against the module sources cached in `.terraform/modules/master/modules/{resource-group,vnet,virtual-machine}`.

## Blocking errors (validate or plan fails)

### 1. `vm.tf` modules `master` and `worker` (lines 21-61 and 84-125) use the `azurerm_linux_virtual_machine` resource schema, not the module's interface
- Nested blocks are not allowed inside a `module` block. `admin_ssh_key`, `os_disk` and `source_image_reference` each cause an "Unsupported block type" error.
- These arguments do not exist on the module: `name`, `size`, `admin_username`, `network_interface_ids`, `disable_password_authentication`, `custom_data` and `tags`. The module's names are `vm_name`, `vm_size`, `vm_admin_username`, `vm_admin_ssh_public_keys`, `vm_os_disk`, `vm_source_image`, `vm_custom_data` and `vm_tags`.
- Two required inputs are missing: `subnet_id` and `vm_name`.
- `network_interface_ids = [module.master.azurerm_network_interface.nic.id]` refers to the module from inside itself, which is a cycle. Module internals are also not addressable from outside. The module creates its own NIC and exposes it only as `nic_id`.
- The module's validation rejects `admin_username = "azureuser"`, which is the default in `variables.tf`, because it is on the module's reserved-name list.
- `custom_data = base64encode(...)`: the module already base64-encodes `vm_custom_data`, so passing an encoded value would encode it twice. Pass the plain `templatefile(...)` output.

### 2. `network.tf` module `vnet` (lines 3-39) uses the wrong argument names
- `name`, `address_space` and `tags` are not module inputs. They should be `vnet_name`, `vnet_address_space` and `vnet_tags`. Without them the required `vnet_name` and `vnet_address_space` are missing.

### 3. Module outputs are referenced with the wrong names and shapes
- `module.vnet.subnet_ids` is a `map(string)` of IDs, so `module.vnet.subnet_ids["snet-vm"].id` fails with "Unsupported attribute". This happens in `network.tf:75`, `vm.tf:13` and `vm.tf:76`. Use `module.vnet.subnet_ids["snet-vm"]`.
- `module.vnet.id` (`network.tf:89`) and `module.vnet.name` (`network.tf:95`) do not exist. The outputs are `vnet_id` and `vnet_name`.

### 4. `network.tf:99-102` has a broken NSG association that should be removed
- `azurerm_subnet.module.vnet...` is not a valid reference.
- `azurerm_network_security_group.main` was deleted along with `security.tf`.
- The vnet module already associates its NSG with every subnet (`associate_nsg` defaults to `true`). A second association on the same subnet would conflict even if the references were fixed. Delete this block.

### 5. `outputs.tf` and `ansible.tf` still reference resources that were removed
- `outputs.tf:4,9` use `azurerm_resource_group.main`, which is now commented out. Use `module.rg.name` and `module.rg.location`.
- `outputs.tf:15,26` and `ansible.tf:17,18,25,26` use `azurerm_linux_virtual_machine.master` and `.worker`. Use `module.master.vm_name`, `module.worker[*].vm_name` and the module references in `depends_on`.
- `outputs.tf:37` uses `azurerm_virtual_network.main`. Use `module.vnet.vnet_name`.
- `outputs.tf:43` uses `azurerm_subnet.main`. Use `module.vnet.subnet_ids["snet-vm"]`.

## Logic and operational issues

### 6. The NICs at the root of `vm.tf` are orphaned, so the Ansible inventory and outputs point at the wrong IPs
`azurerm_network_interface.master` and `.worker` (`vm.tf:6-18`, `vm.tf:68-81`) are no longer attached to any VM, because the module creates its own NIC from `subnet_id`. `ansible.tf:8-9` and `outputs.tf:20,31,59,65` read IPs from these unattached NICs. Every Ansible run and SSH command would therefore target addresses that no VM answers on. Delete the root NICs and use `module.master.private_ip_address` and `module.worker[*].private_ip_address`.

### 7. There are no `moved` blocks, so `apply` would destroy and recreate all infrastructure
Every resource changed address: `azurerm_resource_group.main` moves to `module.rg.azurerm_resource_group.rg`, the VNet, subnet and NSG move into `module.vnet`, and the VMs move into the modules. With an existing state, `plan` destroys the resource group, the VNet and both VMs, along with the running Kubernetes cluster, and recreates them. Add `moved {}` blocks, or use `terraform state mv`. The VM module may manage VMs under a different internal address (for example with `count` or `for_each`), so check that before writing the `moved` blocks.

### 8. The major provider upgrade and the deleted lock file leave providers unpinned
`azurerm` jumps from `~> 3.0` to `>= 5.12, < 6.0` across two major versions with breaking schema changes, and `.terraform.lock.hcl` was deleted. Providers will float on the next `init`, which makes builds non-reproducible. Run `terraform init -upgrade`, commit the regenerated lock file, and review the state upgrade.

### 9. Providers used in `ansible.tf` are not declared
`local_file` (`hashicorp/local`) and `null_resource` (`hashicorp/null`) are not listed in `required_providers` in `main.tf`. Without the lock file they resolve to whatever version is latest. Pin them, or switch to the built-in `terraform_data` in place of `null_resource`.

## Security and cleanup (existing issues, not introduced by this change)

### 10. Insecure defaults in `variables.tf`
- `admin_password` (line 66) has a hard-coded default of `Password123!@#`. It is also unused, because password authentication is disabled. Remove it.
- `allowed_ssh_source` (line 93) defaults to `"*"`, which opens SSH to the internet if a public IP is ever attached.
- `ansible.tf:43`: `triggers = { always_run = timestamp() }` reruns the whole Kubernetes playbook on every `apply`.
- `terraform.tfvars.example` uses `vm_name` and `vm_size`, which are not declared variables (Terraform warns about them), and contains the example password `YourSecureP@ssw0rd!`.
