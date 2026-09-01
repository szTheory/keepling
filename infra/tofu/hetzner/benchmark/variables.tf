variable "location" {
  type = string
  validation {
    condition     = var.location == "nbg1"
    error_message = "the approved benchmark location is nbg1"
  }
}

variable "hcloud_endpoint" {
  description = "Optional private transport endpoint used only when the runtime cannot reach the provider directly."
  type        = string
  default     = null
  nullable    = true
}

variable "server_type" {
  type = string
  validation {
    condition     = var.server_type == "cx33"
    error_message = "the approved benchmark type is cx33"
  }
}

variable "server_image_id" {
  type = string
  validation {
    condition     = can(regex("^[1-9][0-9]*$", var.server_image_id))
    error_message = "server_image_id must be an immutable numeric image ID"
  }
}

variable "ssh_public_key" {
  type      = string
  sensitive = true
  validation {
    condition     = can(regex("^(ssh-ed25519|ecdsa-sha2-nistp256|ssh-rsa) [A-Za-z0-9+/]+={0,3}( .*)?$", trimspace(var.ssh_public_key)))
    error_message = "ssh_public_key must contain one supported public key"
  }
}

variable "admin_source_cidr" {
  type      = string
  sensitive = true
  validation {
    condition     = can(cidrnetmask(var.admin_source_cidr)) && var.admin_source_cidr != "0.0.0.0/0" && var.admin_source_cidr != "::/0"
    error_message = "admin_source_cidr must be one bounded network"
  }
}

variable "replacement_run_id" {
  type = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{7,39}$", var.replacement_run_id))
    error_message = "replacement_run_id must be 8-40 lowercase letters, digits, or hyphens"
  }
}

variable "data_volume_size_gb" {
  type    = number
  default = 160
  validation {
    condition     = var.data_volume_size_gb == 160
    error_message = "the approved benchmark volume is exactly 160 GB"
  }
}
