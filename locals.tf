locals {
  subnet_name = "snet-vm"
  subnet_id   = module.vnet.subnet_ids[local.subnet_name]

  # SSH is limited to the peered VNet unless allowed_ssh_source is set.
  ssh_source_address_prefix = coalesce(var.allowed_ssh_source, data.azurerm_virtual_network.peer.address_space[0])

  admin_ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))

  # Plain text: the virtual-machine module base64-encodes vm_custom_data itself.
  cloud_init = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    username       = var.admin_username
    ssh_public_key = local.admin_ssh_public_key
  })

  vm_os_disk = {
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_storage_account_type
    disk_size_gb         = var.os_disk_size_gb
  }

  vm_source_image = {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  # Stable keys, so changing worker_count adds or removes only the last workers.
  worker_names = toset([for i in range(1, var.worker_count + 1) : "${var.worker_vm_name_prefix}-${i}"])
}
