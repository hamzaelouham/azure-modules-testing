# =============================================================================
# Virtual Network, subnet and NSG
# =============================================================================

module "vnet" {
  source = "git::https://github.com/hamzaelouham/terraform-azurerm-modules.git//modules/vnet?ref=vnet/v1.0.0"

  vnet_name           = "vnet-${module.rg.name}"
  resource_group_name = module.rg.name
  location            = module.rg.location
  vnet_address_space  = var.vnet_address_space
  vnet_tags           = var.tags

  subnets = {
    (local.subnet_name) = {
      address_prefixes = var.subnet_address_prefixes
    }
  }

  # The module associates this NSG with every subnet.
  nsg_name = "nsg-vm"
  nsg_tags = var.tags

  nsg_rules = {
    AllowSSH = {
      priority               = 1001
      direction              = "Inbound"
      access                 = "Allow"
      protocol               = "Tcp"
      destination_port_range = "22"
      source_address_prefix  = local.ssh_source_address_prefix
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
}

# =============================================================================
# NAT Gateway (outbound internet for the VMs, which have no public IP)
# =============================================================================

resource "azurerm_public_ip" "nat" {
  name                = "pip-nat-gateway"
  location            = module.rg.location
  resource_group_name = module.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = [var.nat_gateway_zone]

  tags = var.tags
}

resource "azurerm_nat_gateway" "main" {
  name                    = "nat-gateway"
  location                = module.rg.location
  resource_group_name     = module.rg.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  zones                   = [var.nat_gateway_zone] # must match the public IP's zone

  tags = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.main.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "main" {
  subnet_id      = local.subnet_id
  nat_gateway_id = azurerm_nat_gateway.main.id
}

# =============================================================================
# Peering with the existing VNet
# =============================================================================

data "azurerm_virtual_network" "peer" {
  name                = var.peer_vnet_name
  resource_group_name = var.peer_vnet_resource_group
}

resource "azurerm_virtual_network_peering" "peer_to_new" {
  name                      = "peer-to-${module.vnet.vnet_name}"
  resource_group_name       = var.peer_vnet_resource_group
  virtual_network_name      = data.azurerm_virtual_network.peer.name
  remote_virtual_network_id = module.vnet.vnet_id

  lifecycle {
    precondition {
      condition = alltrue([
        for prefix in var.vnet_address_space :
        !contains(data.azurerm_virtual_network.peer.address_space, prefix)
      ])
      error_message = "vnet_address_space overlaps the peer VNet (${join(", ", data.azurerm_virtual_network.peer.address_space)}). Peered VNets need distinct address ranges."
    }
  }
}

resource "azurerm_virtual_network_peering" "new_to_peer" {
  name                      = "peer-to-${data.azurerm_virtual_network.peer.name}"
  resource_group_name       = module.rg.name
  virtual_network_name      = module.vnet.vnet_name
  remote_virtual_network_id = data.azurerm_virtual_network.peer.id
}
