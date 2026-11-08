variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
  default     = ""

}


# Resource Group
variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "k8s-cluster"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "East US 2"
}

# Network
variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.1.0.0/16"]
}

variable "subnet_address_prefixes" {
  description = "Address prefixes for the subnet"
  type        = list(string)
  default     = ["10.1.1.0/24"]
}

# Master Node Configuration
variable "master_vm_name" {
  description = "Name of the Kubernetes master node"
  type        = string
  default     = "k8s-master"
}

variable "master_vm_size" {
  description = "Size of the master VM"
  type        = string
  default     = "Standard_D2ls_v7"
}

# Worker Node Configuration
variable "worker_count" {
  description = "Number of Kubernetes worker nodes"
  type        = number
  default     = 1 # Free Trial caps each region at 4 vCPUs: master + 1 worker (Standard_B2s, 2 vCPUs each)
}

variable "worker_vm_name_prefix" {
  description = "Prefix for worker node names"
  type        = string
  default     = "k8s-worker"
}

variable "worker_vm_size" {
  description = "Size of the worker VMs"
  type        = string
  default     = "Standard_D2ls_v7"
}

# Common VM Configuration
variable "admin_username" {
  description = "Admin username for the VMs"
  type        = string
  default     = "k8sadmin"
}


variable "os_disk_size_gb" {
  description = "Size of the OS disk in GB"
  type        = number
  default     = 30
}

# SSH Key for Ansible
variable "ssh_public_key_path" {
  description = "Path to SSH public key for Ansible access"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key for Ansible access"
  type        = string
  default     = "~/.ssh/id_rsa"
}

# Security
variable "allowed_ssh_source" {
  description = "Source IP/CIDR allowed for SSH access"
  type        = string
  default     = "*"
}

# Kubernetes
variable "k8s_version" {
  description = "Kubernetes version to install"
  type        = string
  default     = "1.30"
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "Development"
    ManagedBy   = "Terraform"
    Project     = "Kubernetes"
  }
}
