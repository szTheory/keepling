variable "location" {
  description = "Hetzner location selected by the measured replacement rehearsal."
  type        = string

  validation {
    condition     = var.location == "nbg1"
    error_message = "the measured Phase 2 replacement boundary is the location name nbg1."
  }
}

variable "hcloud_endpoint" {
  description = "Optional private transport endpoint used only when the runtime cannot reach the provider directly."
  type        = string
  default     = null
  nullable    = true
}

variable "server_type" {
  description = "Measured x86 Hetzner server type selected before apply."
  type        = string

  validation {
    condition     = can(regex("^(cx|cpx|ccx)[0-9]+$", var.server_type))
    error_message = "server_type must be an x86 CX, CPX, or CCX type selected by the replacement benchmark."
  }
}

variable "target_architecture" {
  description = "Architecture of the tested OCI artifact and selected server."
  type        = string
  default     = "x86_64"

  validation {
    condition     = var.target_architecture == "x86_64"
    error_message = "the Phase 2 reference target is the measured x86_64 path."
  }
}

variable "server_image_id" {
  description = "Immutable numeric Hetzner image ID; aliases such as ubuntu-24.04 are refused."
  type        = string

  validation {
    condition     = can(regex("^[1-9][0-9]*$", var.server_image_id))
    error_message = "server_image_id must be an immutable numeric provider image ID."
  }
}

variable "server_image_os_family" {
  description = "OS family belonging to the immutable image ID; cloud-init is bounded to this package/runtime contract."
  type        = string
  default     = "ubuntu-24.04"

  validation {
    condition     = var.server_image_os_family == "ubuntu-24.04"
    error_message = "the bootstrap contract requires an immutable Ubuntu 24.04 image ID."
  }
}

variable "tested_oci_digest" {
  description = "Exact application artifact proven by the deployment verifier."
  type        = string

  validation {
    condition     = can(regex("^sha256:[0-9a-f]{64}$", var.tested_oci_digest))
    error_message = "tested_oci_digest must be a lowercase sha256 digest, never a mutable tag."
  }
}

variable "ssh_public_key" {
  description = "Public half of the exact replacement-run SSH identity."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^(ssh-ed25519|ecdsa-sha2-nistp256|ssh-rsa) [A-Za-z0-9+/]+={0,3}( .*)?$", trimspace(var.ssh_public_key)))
    error_message = "ssh_public_key must contain one supported OpenSSH public key."
  }
}

variable "replacement_run_id" {
  description = "Non-secret bounded identifier used to prove resource ownership."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{7,39}$", var.replacement_run_id))
    error_message = "replacement_run_id must be 8-40 lowercase letters, digits, or hyphens."
  }
}

variable "admin_source_cidrs" {
  description = "Exact operator networks allowed to reach SSH."
  type        = set(string)

  validation {
    condition = length(var.admin_source_cidrs) > 0 && alltrue([
      for cidr in var.admin_source_cidrs : can(cidrnetmask(cidr))
    ]) && !contains(var.admin_source_cidrs, "0.0.0.0/0") && !contains(var.admin_source_cidrs, "::/0")
    error_message = "admin_source_cidrs must contain valid bounded CIDRs and must not expose SSH globally."
  }
}

variable "data_volume_size_gb" {
  description = "Empty attached storage allocation; canonical data enters it only through the admitted restore."
  type        = number
  default     = 160

  validation {
    condition     = var.data_volume_size_gb >= 80 && var.data_volume_size_gb <= 1024 && floor(var.data_volume_size_gb) == var.data_volume_size_gb
    error_message = "data_volume_size_gb must be a whole number between 80 and 1024."
  }
}

variable "network_cidr" {
  description = "Private network range owned by the replacement run."
  type        = string
  default     = "10.77.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.network_cidr)) && !can(regex("^0\\.", var.network_cidr))
    error_message = "network_cidr must be a valid non-default private CIDR."
  }
}

variable "subnet_cidr" {
  description = "Private server subnet within network_cidr."
  type        = string
  default     = "10.77.1.0/24"

  validation {
    condition     = can(cidrnetmask(var.subnet_cidr))
    error_message = "subnet_cidr must be a valid CIDR."
  }
}
