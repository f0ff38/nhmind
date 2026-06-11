variable "selectel_account_id" {
  description = "Selectel account number (domain_name)."
  type        = string
}

variable "selectel_project_id" {
  description = "Cloud platform project ID (32 hex chars)."
  type        = string
}

variable "selectel_service_user" {
  description = "Service user name with member role on the project."
  type        = string
  sensitive   = true
}

variable "selectel_service_password" {
  description = "Service user password."
  type        = string
  sensitive   = true
}

variable "selectel_region" {
  description = "OpenStack pool, e.g. ru-3 (derived from availability zone in CI)."
  type        = string
}

variable "availability_zone" {
  description = "Pool segment for VM and volume, e.g. ru-3a."
  type        = string
}

variable "deploy_ssh_public_key" {
  description = "OpenSSH public key for deploy user and instance keypair."
  type        = string
  sensitive   = true
}

variable "flavor_id" {
  description = "Selectel flavor ID for the relay VM (pool-specific). Empty = auto-pick 2 vCPU / 2048 MB / disk 0 (lexicographically first name if several match)."
  type        = string
  default     = ""
}

variable "image_name" {
  description = "Ubuntu image name in the public catalog."
  type        = string
  default     = "Ubuntu 24.04 LTS 64-bit"
}

variable "boot_volume_size_gb" {
  description = "Boot network volume size in GB."
  type        = number
  default     = 20
}

variable "private_subnet_cidr" {
  description = "CIDR for the relay private subnet."
  type        = string
  default     = "10.10.42.0/24"
}

variable "server_name" {
  description = "Cloud server display name."
  type        = string
  default     = "nhmind-relay"
}
