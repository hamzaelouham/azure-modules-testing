terraform {
  required_version = ">= 1.17"

  required_providers {
    azapi = {
      source  = "azure/azapi" # required by the virtual-machine module
      version = "~> 2.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.12" # the modules require >= 5.12, < 6.0
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}
