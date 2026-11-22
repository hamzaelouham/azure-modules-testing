variable "container_name" {
  description = "Blob container that holds the state files"
  type        = string
  default     = "tfstate"
}

variable "location" {
  description = "Azure region for the state storage"
  type        = string
  default     = "eastus2"
}

variable "pipeline_principal_id" {
  description = "Object ID of the Azure DevOps service connection's service principal, given Contributor on the subscription. Null skips the role assignment."
  type        = string
  default     = null

  validation {
    condition     = var.pipeline_principal_id == null || can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", coalesce(var.pipeline_principal_id, "-")))
    error_message = "pipeline_principal_id must be a GUID (the service principal's object ID, not its app ID)."
  }
}

variable "resource_group_name" {
  description = "Resource group for the state storage"
  type        = string
  default     = "rg-tfstate"
}

variable "state_key" {
  description = "Blob name of the root configuration's state file"
  type        = string
  default     = "azure-modules-testing.tfstate"
}

variable "state_retention_days" {
  description = "Days deleted state blobs and containers are kept (1-365)"
  type        = number
  default     = 7
}

variable "storage_account_name" {
  description = "Globally unique storage account name (3-24 lowercase letters and digits); must match TF_STATE_STORAGE_ACCOUNT in azure-pipelines.yml"
  type        = string
  default     = "tfstate9498a810"
}

variable "subscription_id" {
  description = "Azure subscription ID. Null uses the ARM_SUBSCRIPTION_ID environment variable."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to the state resources"
  type        = map(string)
  default = {
    ManagedBy = "Terraform"
    Purpose   = "terraform-state"
  }
}
