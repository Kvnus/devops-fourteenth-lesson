data "yandex_compute_image" "this" {
  count  = var.image_id == null ? 1 : 0
  family = var.image_family
}

locals {
  image_id = var.image_id != null ? var.image_id : data.yandex_compute_image.this[0].id

  metadata = merge(
    { ssh-keys = "${var.ssh_user}:${trimspace(var.ssh_public_key)}" },
    var.user_data == null ? {} : { user-data = var.user_data },
    var.extra_metadata,
  )
}

resource "yandex_compute_instance" "this" {
  name                      = var.name
  hostname                  = coalesce(var.hostname, var.name)
  zone                      = var.zone
  platform_id               = var.platform_id
  service_account_id        = var.service_account_id
  allow_stopping_for_update = true
  labels                    = var.labels

  resources {
    cores         = var.cores
    memory        = var.memory
    core_fraction = var.core_fraction
  }

  scheduling_policy {
    preemptible = var.preemptible
  }

  boot_disk {
    initialize_params {
      image_id = local.image_id
      size     = var.boot_disk_size
      type     = var.boot_disk_type
    }
  }

  network_interface {
    subnet_id          = var.subnet_id
    nat                = var.public_ip
    nat_ip_address     = var.public_ip ? var.nat_ip_address : null
    security_group_ids = var.security_group_ids
  }

  metadata = local.metadata
}
