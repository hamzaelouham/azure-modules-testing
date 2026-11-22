# Remote state storage for the root configuration (replaces scripts/bootstrap-azure.sh).
# This configuration keeps its own state locally: it creates the backend, so it
# cannot store its state in it. Resource providers (Compute, Network, Storage)
# are registered automatically by the azurerm provider.

data "azurerm_subscription" "current" {}

module "rg" {
  source = "git::https://github.com/hamzaelouham/terraform-azurerm-modules.git//modules/resource-group?ref=resource-group/v1.1.0"

  name     = var.resource_group_name
  location = var.location
  rg_tags  = var.tags
}

module "state_storage" {
  source = "git::https://github.com/hamzaelouham/terraform-azurerm-modules.git//modules/storage-account?ref=storage-account/v1.0.0"

  sa_name             = var.storage_account_name
  resource_group_name = module.rg.name
  location            = module.rg.location

  sa_containers = {
    (var.container_name) = {}
  }

  # Versioning and soft delete let a bad apply's state be restored.
  sa_blob_properties = {
    versioning_enabled              = true
    delete_retention_days           = var.state_retention_days
    container_delete_retention_days = var.state_retention_days
  }

  # The azurerm backend authenticates with the account key, and the pipeline's
  # hosted agents have no fixed IPs, so keys stay on and the network stays open.
  sa_shared_access_key_enabled = true
  sa_network_rules             = null

  sa_tags = var.tags
}

# Lets the Azure DevOps service connection create the cluster and read the state.
resource "azurerm_role_assignment" "pipeline" {
  count = var.pipeline_principal_id == null ? 0 : 1

  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = var.pipeline_principal_id
  principal_type       = "ServicePrincipal"
}
