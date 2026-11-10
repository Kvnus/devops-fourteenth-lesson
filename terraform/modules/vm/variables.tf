variable "name" {
  description = "VM name (also used as default hostname)."
  type        = string
}

variable "zone" {
  description = "Availability zone, e.g. ru-central1-a."
  type        = string
}

variable "subnet_id" {
  description = "Subnet the VM is attached to. VMs in the same network see each other by internal IP."
  type        = string
}

variable "security_group_ids" {
  description = "Security groups for the network interface."
  type        = list(string)
  default     = []
}

variable "hostname" {
  description = "Hostname / internal DNS name. Defaults to name."
  type        = string
  default     = null
}

# ---- compute ----
variable "platform_id" {
  description = "standard-v1 | standard-v2 | standard-v3."
  type        = string
  default     = "standard-v3"
}

variable "cores" {
  type    = number
  default = 2
}

variable "memory" {
  description = "RAM in GB."
  type        = number
  default     = 2
}

variable "core_fraction" {
  description = "Guaranteed vCPU share in percent (v3: 20, 50, 100)."
  type        = number
  default     = 100
}

variable "preemptible" {
  description = "Preemptible VM (cheaper, may be stopped by the cloud, max 24h)."
  type        = bool
  default     = false
}

# ---- disk / image ----
variable "image_id" {
  description = "Boot image id. If null, the latest image of image_family is used."
  type        = string
  default     = null
}

variable "image_family" {
  description = "Public image family (used when image_id is null)."
  type        = string
  default     = "ubuntu-2204-lts"
}

variable "boot_disk_size" {
  description = "Boot disk size in GB."
  type        = number
  default     = 20
}

variable "boot_disk_type" {
  description = "network-hdd | network-ssd | network-ssd-nonreplicated."
  type        = string
  default     = "network-ssd"
}

# ---- network ----
variable "public_ip" {
  description = "Assign a public (NAT) IPv4 address."
  type        = bool
  default     = true
}

variable "nat_ip_address" {
  description = "Reserved static public address (yandex_vpc_address). null = ephemeral address."
  type        = string
  default     = null
}

# ---- access / init ----
variable "service_account_id" {
  description = "Service account attached to the VM (gives access to cloud APIs via metadata service)."
  type        = string
  default     = null
}

variable "ssh_user" {
  type    = string
  default = "ubuntu"
}

variable "ssh_public_key" {
  description = "Public SSH key content for ssh_user."
  type        = string
}

variable "user_data" {
  description = "cloud-init user-data (must start with #cloud-config)."
  type        = string
  default     = null
}

variable "extra_metadata" {
  description = "Additional metadata key/values."
  type        = map(string)
  default     = {}
}

variable "labels" {
  type    = map(string)
  default = {}
}
