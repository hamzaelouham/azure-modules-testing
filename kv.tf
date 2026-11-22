# =============================================================================
# Key Vault
# =============================================================================

data "azurerm_client_config" "current" {}

# Test-friendly settings: short soft-delete retention and no purge protection so
# the vault can be destroyed and recreated, and an access policy (not RBAC) for
# the identity running Terraform, because the pipeline's Contributor role
# cannot create role assignments.
module "keyvault" {
  source = "git::https://github.com/hamzaelouham/terraform-azurerm-modules.git//modules/key-vault?ref=key-vault/v1.0.0"

  kv_name             = local.kv_name
  resource_group_name = module.rg.name
  location            = module.rg.location
  kv_sku_name         = var.kv_sku_name

  kv_purge_protection_enabled   = var.kv_purge_protection_enabled
  kv_soft_delete_retention_days = var.kv_soft_delete_retention_days

  kv_rbac_authorization_enabled = false
  kv_access_policies = {
    terraform = {
      object_id          = data.azurerm_client_config.current.object_id
      secret_permissions = ["Get", "List", "Set", "Delete", "Recover", "Purge"]
    }
  }

  kv_network_acls = {
    default_action = "Allow"
  }

  kv_tags = var.tags
}
