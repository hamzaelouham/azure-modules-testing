variable "admin_username" {
  description = "Admin username for the VMs (Azure-reserved names such as admin, root or azureuser are rejected)"
  type        = string
  default     = "k8sadmin"
}

variable "allowed_ssh_source" {
  description = "Source allowed to reach SSH on the VMs: \"*\" (any), a CIDR block, or null for the peer VNet's first address range (needs peering_enabled)"
  type        = string
  default     = "*"

  validation {
    condition     = var.allowed_ssh_source == null || var.allowed_ssh_source == "*" || can(cidrhost(coalesce(var.allowed_ssh_source, "-"), 0))
    error_message = "allowed_ssh_source must be \"*\", a CIDR block such as \"10.0.0.0/16\", or null."
  }

  validation {
    condition     = var.allowed_ssh_source != null || var.peering_enabled
    error_message = "allowed_ssh_source can only be null when peering_enabled is true."
  }
}

variable "k8s_version" {
  description = "Kubernetes minor version to install, e.g. \"1.35\""
  type        = string
  default     = "1.35"

  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.k8s_version))
    error_message = "k8s_version must be a Kubernetes minor version such as \"1.35\"."
  }
}

variable "kv_purge_protection_enabled" {
  description = "Block purging of the Key Vault until the retention period ends. Cannot be turned off once enabled."
  type        = bool
  default     = false
}

variable "kv_sku_name" {
  description = "SKU of the Key Vault: \"standard\" or \"premium\""
  type        = string
  default     = "standard"
}

variable "kv_soft_delete_retention_days" {
  description = "Days a deleted Key Vault is kept before it can be purged (7-90)"
  type        = number
  default     = 7
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus2"
}

variable "master_public_ip_enabled" {
  description = "Give the master a public IP so it (and the workers, through it) can be reached without the peered VNet"
  type        = bool
  default     = true
}

variable "master_vm_name" {
  description = "Name of the Kubernetes master node"
  type        = string
  default     = "k8s-master"
}

variable "master_vm_size" {
  description = "Size of the master VM (kubeadm needs at least 2 vCPUs and 2 GB RAM)"
  type        = string
  default     = "Standard_D2ls_v7"
}

variable "nat_gateway_zone" {
  description = "Availability zone for the NAT Gateway and its public IP"
  type        = string
  default     = "1"

  validation {
    condition     = contains(["1", "2", "3"], var.nat_gateway_zone)
    error_message = "nat_gateway_zone must be \"1\", \"2\" or \"3\"."
  }
}

variable "os_disk_size_gb" {
  description = "Size of the OS disk in GB"
  type        = number
  default     = 30

  validation {
    condition     = var.os_disk_size_gb >= 30 && floor(var.os_disk_size_gb) == var.os_disk_size_gb
    error_message = "os_disk_size_gb must be a whole number of at least 30 (the Ubuntu image size)."
  }
}

variable "os_disk_storage_account_type" {
  description = "Storage type of the OS disks"
  type        = string
  default     = "StandardSSD_LRS"

  validation {
    condition     = contains(["Standard_LRS", "StandardSSD_LRS", "Premium_LRS", "StandardSSD_ZRS", "Premium_ZRS"], var.os_disk_storage_account_type)
    error_message = "os_disk_storage_account_type must be Standard_LRS, StandardSSD_LRS, Premium_LRS, StandardSSD_ZRS or Premium_ZRS."
  }
}

variable "peer_vnet_name" {
  description = "Name of the existing VNet to peer with"
  type        = string
  default     = "devopsVM-vnet"
}

variable "peer_vnet_resource_group" {
  description = "Resource group of the existing VNet to peer with"
  type        = string
  default     = "devops-group"
}

variable "peering_enabled" {
  description = "Peer the cluster VNet with the existing VNet named by peer_vnet_name and peer_vnet_resource_group"
  type        = bool
  default     = false
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "k8s-cluster"
}

variable "ssh_private_key_path" {
  description = "Path to the SSH private key Ansible uses; must match ssh_public_key_path"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key installed on the VMs"
  type        = string
  default     = "~/.ssh/id_rsa.pub"

  validation {
    condition     = fileexists(pathexpand(var.ssh_public_key_path)) && can(regex("^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp(256|384|521)) ", file(pathexpand(var.ssh_public_key_path))))
    error_message = "ssh_public_key_path must point to an existing OpenSSH public key (ssh-rsa, ssh-ed25519 or ecdsa-sha2-*), e.g. one created with ssh-keygen -t ed25519."
  }
}

variable "subnet_address_prefixes" {
  description = "Address prefixes for the VM subnet; must fall inside vnet_address_space"
  type        = list(string)
  default     = ["10.1.1.0/24"]
}

variable "subscription_id" {
  description = "Azure subscription ID. Null uses the ARM_SUBSCRIPTION_ID environment variable."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "Development"
    ManagedBy   = "Terraform"
    Project     = "Kubernetes"
  }
}

variable "vnet_address_space" {
  description = "Address space for the virtual network; must not overlap the peer VNet when peering_enabled is true"
  type        = list(string)
  default     = ["10.1.0.0/16"]
}

variable "worker_count" {
  description = "Number of Kubernetes worker nodes"
  type        = number
  default     = 1 # Free Trial caps each region at 4 vCPUs: master + 1 worker (2 vCPUs each)

  validation {
    condition     = var.worker_count >= 1 && floor(var.worker_count) == var.worker_count
    error_message = "worker_count must be a whole number of at least 1."
  }
}

variable "worker_vm_name_prefix" {
  description = "Prefix for worker node names; workers are named <prefix>-1, <prefix>-2, ..."
  type        = string
  default     = "k8s-worker"
}

variable "worker_vm_size" {
  description = "Size of the worker VMs"
  type        = string
  default     = "Standard_D2ls_v7"
}
