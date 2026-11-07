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
  value       = module.master.vm_name
}

output "master_public_ip" {
  description = "Public IP address of the master node"
  value       = module.master.public_ip_address
}

output "master_private_ip" {
  description = "Private IP address of the master node"
  value       = module.master.private_ip_address
}

# Worker Node Outputs
output "worker_vm_names" {
  description = "Names of the worker VMs"
  value       = module.worker[*].vm_name
}

output "worker_private_ips" {
  description = "Private IP addresses of the worker nodes"
  value       = module.worker[*].private_ip_address
}

# Network Outputs
output "vnet_name" {
  description = "Name of the virtual network"
  value       = module.vnet.vnet_name
}

output "subnet_id" {
  description = "ID of the subnet"
  value       = module.vnet.subnet_ids["snet-vm"]
}

# NAT Gateway Outputs
output "nat_gateway_name" {
  description = "Name of the NAT Gateway"
  value       = azurerm_nat_gateway.main.name
}

output "nat_gateway_public_ip" {
  description = "Public IP address of the NAT Gateway (used for outbound internet)"
  value       = azurerm_public_ip.nat.ip_address
}

# Connection Info
output "ssh_master_command" {
  description = "SSH command to connect to the master node"
  value       = "ssh ${var.admin_username}@${module.master.public_ip_address}"
}

output "ssh_worker_commands" {
  description = "SSH commands to connect to the worker nodes (jumping through the master)"
  value = [
    for ip in module.worker[*].private_ip_address :
    "ssh -J ${var.admin_username}@${module.master.public_ip_address} ${var.admin_username}@${ip}"
  ]
}

# Ansible Inventory Path
output "ansible_inventory_path" {
  description = "Path to the generated Ansible inventory file"
  value       = local_file.ansible_inventory.filename
}
