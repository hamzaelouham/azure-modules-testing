# Virtual Network

module "vnet" {
  source    = "git::https://github.com/hamzaelouham/terraform-azurerm-modules.git//modules/vnet?ref=vnet/v1.0.0"
  vnet_name = "vnet-${module.rg.name}"

  vnet_address_space  = var.vnet_address_space
  location            = module.rg.location
  resource_group_name = module.rg.name

  # Subnet for VM
  subnets = {
    "snet-vm" = { address_prefixes = var.subnet_address_prefixes }
  }

  nsg_name = "nsg-vm"
  nsg_tags = var.tags
  # vnet_tags = var.tags   # if your VNet has tags

  nsg_rules = {
    AllowSSH = {
      priority               = 1001
      direction              = "Inbound"
      access                 = "Allow"
      protocol               = "Tcp"
      destination_port_range = "22"
      source_address_prefix  = var.allowed_ssh_source
    }
    AllowAllOutbound = {
      priority               = 1000
      direction              = "Outbound"
      access                 = "Allow"
      protocol               = "*"
      destination_port_range = "*"
      source_address_prefix  = "*"
    }
  }

  vnet_tags = var.tags
}




# Public IP for NAT Gateway (Standard SKU required)
resource "azurerm_public_ip" "nat" {
  name                = "pip-nat-gateway"
  location            = module.rg.location
  resource_group_name = module.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1"]

  tags = var.tags
}

# NAT Gateway
resource "azurerm_nat_gateway" "main" {
  name                    = "nat-gateway"
  location                = module.rg.location
  resource_group_name     = module.rg.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10

  tags = var.tags
}

# Associate Public IP with NAT Gateway
resource "azurerm_nat_gateway_public_ip_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.main.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

# Associate NAT Gateway with Subnet
resource "azurerm_subnet_nat_gateway_association" "main" {
  subnet_id      = module.vnet.subnet_ids["snet-vm"].id
  nat_gateway_id = azurerm_nat_gateway.main.id
}

# Peering with existing VNet
data "azurerm_virtual_network" "peer" {
  name                = var.peer_vnet_name
  resource_group_name = var.peer_vnet_resource_group
}

resource "azurerm_virtual_network_peering" "peer_to_new" {
  name                      = "peer-to-new"
  resource_group_name       = var.peer_vnet_resource_group
  virtual_network_name      = data.azurerm_virtual_network.peer.name
  remote_virtual_network_id = module.vnet.id
}

resource "azurerm_virtual_network_peering" "new_to_peer" {
  name                      = "new-to-peer"
  resource_group_name       = module.rg.name
  virtual_network_name      = module.vnet.name
  remote_virtual_network_id = data.azurerm_virtual_network.peer.id
}

resource "azurerm_subnet_network_security_group_association" "main" {
  subnet_id                 = azurerm_subnet.module.vnet.subnet_ids["snet-vm"].id
  network_security_group_id = azurerm_network_security_group.main.id
}
