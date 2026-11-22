terraform {
  backend "azurerm" {

    resource_group_name  = "rg-tfstate"
    storage_account_name = "tfstate9498a810"
    container_name       = "tfstate"
    key                  = "azure-modules-testing.tfstate"
  }

}
