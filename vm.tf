locals {
  admin_ssh_key = trimspace(file(pathexpand(var.ssh_public_key_path)))

  # Plain text: the virtual-machine module base64-encodes it.
  custom_data = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    username       = var.admin_username
    ssh_public_key = local.admin_ssh_key
  })

  vm_os_disk = {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference = {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}

# =============================================================================
# Master Node
# =============================================================================

# The module creates the NIC itself and always disables password auth on Linux.
module "master" {
  source              = "git::https://github.com/hamzaelouham/terraform-azurerm-modules.git//modules/virtual-machine?ref=virtual-machine/v1.0.0"
  vm_name             = var.master_vm_name
  resource_group_name = module.rg.name
  location            = module.rg.location
  subnet_id           = module.vnet.subnet_ids["snet-vm"]
  vm_size             = var.master_vm_size
  vm_admin_username   = var.admin_username

  # Public IP so Ansible can reach the master; workers are reached through it.
  vm_public_ip_enabled = true

  vm_admin_ssh_public_keys = [local.admin_ssh_key]
  vm_custom_data           = local.custom_data
  vm_os_disk               = local.vm_os_disk
  vm_source_image          = local.source_image_reference

  vm_tags = merge(var.tags, {
    Role = "master"
  })
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
  vm_admin_username   = var.admin_username

  vm_admin_ssh_public_keys = [local.admin_ssh_key]
  vm_custom_data           = local.custom_data
  vm_os_disk               = local.vm_os_disk
  vm_source_image          = local.source_image_reference

  vm_tags = merge(var.tags, {
    Role = "worker"
  })
}
