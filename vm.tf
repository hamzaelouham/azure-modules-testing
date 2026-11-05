# =============================================================================
# Master Node
# =============================================================================

# Network Interface for Master
resource "azurerm_network_interface" "master" {
  name                = "nic-${var.master_vm_name}"
  location            = module.rg.location
  resource_group_name = module.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = module.vnet.subnet_ids["snet-vm"].id
    private_ip_address_allocation = "Dynamic"
  }

  tags = var.tags
}


locals {
  admin_ssh_key = trimspace(file(pathexpand(var.ssh_public_key_path)))

  custom_data = base64encode(templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    username       = var.admin_username
    ssh_public_key = file(var.ssh_public_key_path)
  }))

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

# Master VM
module "master" {
  source              = "git::https://github.com/hamzaelouham/terraform-azurerm-modules.git//modules/virtual-machine?ref=virtual-machine/v1.0.0"
  vm_name             = var.master_vm_name
  resource_group_name = module.rg.name
  location            = module.rg.location
  vm_size             = var.master_vm_size
  vm_admin_username   = var.admin_username

  network_interface_ids = [
    module.master.azurerm_network_interface.nic.id
  ]

  disable_password_authentication = true

  vm_tags = merge(var.tags, {
    Role = "master"
  })
}

# =============================================================================
# Worker Nodes
# =============================================================================

# Network Interfaces for Workers
resource "azurerm_network_interface" "worker" {
  count               = var.worker_count
  name                = "nic-${var.worker_vm_name_prefix}-${count.index + 1}"
  location            = module.rg.location
  resource_group_name = module.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = module.vnet.subnet_ids["snet-vm"].id
    private_ip_address_allocation = "Dynamic"
  }

  tags = var.tags
}


# Worker VMs
module "worker" {
  source              = "git::https://github.com/hamzaelouham/terraform-azurerm-modules.git//modules/virtual-machine?ref=virtual-machine/v1.0.0"
  count               = var.worker_count
  vm_name             = "${var.worker_vm_name_prefix}-${count.index + 1}"
  resource_group_name = module.rg.name
  location            = module.rg.location
  vm_size             = var.worker_vm_size
  vm_admin_username   = var.admin_username

  network_interface_ids = [
    module.worker[count.index].azurerm_network_interface.nic.id
  ]

  disable_password_authentication = true



  vm_tags = merge(var.tags, {
    Role = "worker"
  })
}
