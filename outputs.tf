# Resource Group
output "resource_group_name" {
  description = "Name of the resource group"
  value       = module.rg.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = module.rg.location
}

# Master Node Outputs
output "master_vm_name" {
  description = "Name of the master VM"
  value       = module.master.azurerm_linux_virtual_machine.vm.name
}

output "master_private_ip" {
  description = "Private IP address of the master node"
  value       = module.master.azurerm_network_interface.nic.private_ip_address
}

# Worker Node Outputs
output "worker_vm_names" {
  description = "Names of the worker VMs"
  value       = module.worker[*].azurerm_linux_virtual_machine.vm.name
}

output "worker_private_ips" {
  description = "Private IP addresses of the worker nodes"
  value       = module.worker[*].azurerm_network_interface.nic.private_ip_address
}

# Network Outputs
output "vnet_name" {
  description = "Name of the virtual network"
  value       = module.vnet.name
}

output "subnet_id" {
  description = "ID of the subnet"
  value       = module.vnet.subnet_ids["snet-vm"].id
}

# NAT Gateway Outputs
output "nat_gateway_name" {
  description = "Name of the NAT Gateway"
  value       = module.nat_gateway.name
}

output "nat_gateway_public_ip" {
  description = "Public IP address of the NAT Gateway (used for outbound internet)"
  value       = module.nat_gateway.public_ip_address
}

# Connection Info
output "ssh_master_command" {
  description = "SSH command to connect to the master node (requires VPN or Bastion)"
  value       = "ssh ${var.admin_username}@${module.master.azurerm_network_interface.nic.private_ip_address}"
}

output "ssh_worker_commands" {
  description = "SSH commands to connect to the worker nodes"
  value = [
    for ip in module.worker[*].azurerm_network_interface.nic.private_ip_address :
    "ssh ${var.admin_username}@${ip}"
  ]
}

# Ansible Inventory Path
output "ansible_inventory_path" {
  description = "Path to the generated Ansible inventory file"
  value       = local_file.ansible_inventory.filename
}
