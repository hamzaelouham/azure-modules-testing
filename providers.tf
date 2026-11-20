provider "azurerm" {
  features {}

  # Null falls back to the ARM_SUBSCRIPTION_ID environment variable.
  subscription_id = var.subscription_id
}
