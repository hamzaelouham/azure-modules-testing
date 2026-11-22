output "ansible_inventory_path" {
  description = "Path to the generated Ansible inventory file"
  value       = local_file.ansible_inventory.filename
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = module.keyvault.kv_name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = module.keyvault.kv_uri
}

output "master_private_ip" {
  description = "Private IP address of the master node"
  value       = module.master.private_ip_address
}

output "master_public_ip" {
  description = "Public IP address of the master node, or null when master_public_ip_enabled is false"
  value       = module.master.public_ip_address
}

output "master_vm_name" {
  description = "Name of the master VM"
  value       = module.master.vm_name
}

output "nat_gateway_name" {
  description = "Name of the NAT Gateway"
  value       = azurerm_nat_gateway.main.name
}

output "nat_gateway_public_ip" {
  description = "Public IP address of the NAT Gateway (used for outbound internet)"
  value       = azurerm_public_ip.nat.ip_address
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = module.rg.location
}

output "resource_group_name" {
  description = "Name of the resource group"
  value       = module.rg.name
}

output "ssh_master_command" {
  description = "SSH command for the master node (public IP when enabled, otherwise the private IP from the peered VNet)"
  value       = "ssh -i ${var.ssh_private_key_path} ${var.admin_username}@${local.master_ssh_host}"
}

output "ssh_worker_commands" {
  description = "SSH commands for the worker nodes, keyed by VM name (jumping through the master when it has a public IP)"
  value = {
    for name, worker in module.worker :
    name => var.master_public_ip_enabled ? "ssh -i ${var.ssh_private_key_path} -J ${var.admin_username}@${local.master_ssh_host} ${var.admin_username}@${worker.private_ip_address}" : "ssh -i ${var.ssh_private_key_path} ${var.admin_username}@${worker.private_ip_address}"
  }
}

output "subnet_id" {
  description = "ID of the VM subnet"
  value       = local.subnet_id
}

output "vnet_id" {
  description = "ID of the virtual network"
  value       = module.vnet.vnet_id
}

output "vnet_name" {
  description = "Name of the virtual network"
  value       = module.vnet.vnet_name
}

output "worker_private_ips" {
  description = "Private IP addresses of the worker nodes, keyed by VM name"
  value       = { for name, worker in module.worker : name => worker.private_ip_address }
}

output "worker_vm_names" {
  description = "Names of the worker VMs"
  value       = [for worker in values(module.worker) : worker.vm_name]
}
