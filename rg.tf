module "rg" {
  source   = "git::https://github.com/hamzaelouham/terraform-azurerm-modules.git//modules/resource-group?ref=resource-group/v1.0.0"
  name     = var.resource_group_name
  location = var.location
  rg_tags  = var.tags
}