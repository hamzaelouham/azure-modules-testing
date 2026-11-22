output "ansible_inventory_path" {
  description = "Path to the generated Ansible inventory file"
  value       = local_file.ansible_inventory.filename
}

output "master_private_ip" {
  description = "Private IP address of the master node"
  value       = module.master.private_ip_address
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
  description = "SSH command for the master node (reachable from the peered VNet)"
  value       = "ssh -i ${var.ssh_private_key_path} ${var.admin_username}@${module.master.private_ip_address}"
}

output "ssh_worker_commands" {
  description = "SSH commands for the worker nodes, keyed by VM name"
  value = {
    for name, worker in module.worker :
    name => "ssh -i ${var.ssh_private_key_path} ${var.admin_username}@${worker.private_ip_address}"
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
