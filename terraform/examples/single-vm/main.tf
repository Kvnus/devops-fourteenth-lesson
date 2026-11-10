# Example: reuse the modules for any other scenario (e.g. a single web VM).
terraform {
  required_version = ">= 1.3"
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = ">= 0.120"
    }
  }
}

variable "cloud_id" { type = string }
variable "folder_id" { type = string }
variable "zone" {
  type    = string
  default = "ru-central1-a"
}
variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

provider "yandex" {
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
  zone      = var.zone
}

module "network" {
  source    = "../../modules/network"
  name      = "example"
  zone      = var.zone
  app_ports = [80, 443]
}

# Two VMs from the same module: they share a subnet + security group,
# so they reach each other via internal IPs / internal DNS (<name>.ru-central1.internal).
module "web" {
  count  = 2
  source = "../../modules/vm"

  name               = "web-${count.index + 1}"
  zone               = var.zone
  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
  cores              = 2
  memory             = 2
  core_fraction      = 20
  preemptible        = true
  ssh_public_key     = file(pathexpand(var.ssh_public_key_path))

  user_data = <<-EOT
    #cloud-config
    package_update: true
    packages: [nginx]
  EOT
}

output "public_ips" {
  value = module.web[*].public_ip
}

output "internal_ips" {
  value = module.web[*].internal_ip
}
