output "backend_config" {
  description = "Values for the root configuration's azurerm backend (and the TF_STATE_* variables in azure-pipelines.yml)"
  value = {
    resource_group_name  = module.rg.name
    storage_account_name = module.state_storage.sa_name
    container_name       = var.container_name
    key                  = var.state_key
  }
}

output "init_command" {
  description = "Command that connects the root configuration to this backend (run from the repo root after creating backend_override.tf)"
  value       = "terraform init -reconfigure -backend-config=resource_group_name=${module.rg.name} -backend-config=storage_account_name=${module.state_storage.sa_name} -backend-config=container_name=${var.container_name} -backend-config=key=${var.state_key}"
}
