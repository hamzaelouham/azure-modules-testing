# Each module call creates its own NIC in the subnet, so no separate
# azurerm_network_interface resources are needed.

module "master" {
  source = "git::https://github.com/hamzaelouham/terraform-azurerm-modules.git//modules/virtual-machine?ref=virtual-machine/v1.0.0"

  vm_name             = var.master_vm_name
  resource_group_name = module.rg.name
  location            = module.rg.location
  subnet_id           = local.subnet_id
  vm_size             = var.master_vm_size

  # Lets Ansible (and you) reach the cluster without the peered VNet.
  vm_public_ip_enabled = var.master_public_ip_enabled

  vm_admin_username        = var.admin_username
  vm_admin_ssh_public_keys = [local.admin_ssh_public_key]
  vm_custom_data           = local.cloud_init

  vm_source_image = local.vm_source_image
  vm_os_disk      = local.vm_os_disk

  vm_tags = merge(var.tags, {
    Role = "master"
  })
}

module "worker" {
  source   = "git::https://github.com/hamzaelouham/terraform-azurerm-modules.git//modules/virtual-machine?ref=virtual-machine/v1.0.0"
  for_each = local.worker_names

  vm_name             = each.key
  resource_group_name = module.rg.name
  location            = module.rg.location
  subnet_id           = local.subnet_id
  vm_size             = var.worker_vm_size

  vm_admin_username        = var.admin_username
  vm_admin_ssh_public_keys = [local.admin_ssh_public_key]
  vm_custom_data           = local.cloud_init

  vm_source_image = local.vm_source_image
  vm_os_disk      = local.vm_os_disk

  vm_tags = merge(var.tags, {
    Role = "worker"
  })
}
