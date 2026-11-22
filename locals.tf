locals {
  subnet_name = "snet-vm"
  subnet_id   = module.vnet.subnet_ids[local.subnet_name]

  # Null falls back to the peered VNet's range (validation requires peering then).
  ssh_source_address_prefix = coalesce(var.allowed_ssh_source, one(data.azurerm_virtual_network.peer[*].address_space[0]))

  # Globally unique, 3-24 characters: "kv-" + up to 14 name characters + "-" + 6-character hash.
  kv_name = format(
    "kv-%s-%s",
    substr(replace(lower(var.resource_group_name), "/[^a-z0-9]/", ""), 0, 14),
    substr(sha1("${data.azurerm_client_config.current.subscription_id}/${var.resource_group_name}"), 0, 6),
  )

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

  master_ssh_host = coalesce(module.master.public_ip_address, module.master.private_ip_address)

  # Stable keys, so changing worker_count adds or removes only the last workers.
  worker_names = toset([for i in range(1, var.worker_count + 1) : "${var.worker_vm_name_prefix}-${i}"])
}
