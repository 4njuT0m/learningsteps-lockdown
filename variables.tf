variable "prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "learningsteps"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "westeurope"
}

variable "vm_admin_username" {
  description = "Admin username for the VM"
  type        = string
  default     = "azureuser"
}

variable "vm_admin_ssh_key" {
  description = "SSH public key for VM access"
  type        = string
}

variable "db_admin_username" {
  description = "Administrator username for PostgreSQL"
  type        = string
  default     = "psqladmin"
}

variable "db_admin_password" {
  description = "Administrator password for PostgreSQL"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "Name of the application database"
  type        = string
  default     = "learning_journal"
}

variable "admin_source_ip" {
  description = "Public IPv4 address (CIDR, e.g. 203.0.113.10/32) allowed to reach SSH on port 22. Get it with: curl -s -4 ifconfig.me"
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_source_ip, 0)) && !contains(["*", "0.0.0.0/0", "Internet", "Any"], var.admin_source_ip)
    error_message = "admin_source_ip must be a single IPv4 CIDR such as 203.0.113.10/32, never * or 0.0.0.0/0."
  }
}
