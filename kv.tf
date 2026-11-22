module "keyvault" {
  source              = "git::https://github.com/hamzaelouham/terraform-azurerm-modules.git//modules/key-vault?ref=key-vault/v1.0.0"
  kv_name             = "keyvault-${module.rg.name}"
  location            = var.location
  resource_group_name = module.rg.name
  kv_sku_name         = var.kv_sku_name
  kv_tags             = var.tags

}
