resource "yandex_vpc_network" "this" {
  name   = "${var.name}-net"
  labels = var.labels
}

resource "yandex_vpc_subnet" "this" {
  name           = "${var.name}-subnet-${var.zone}"
  zone           = var.zone
  network_id     = yandex_vpc_network.this.id
  v4_cidr_blocks = [var.cidr]
  labels         = var.labels
}

resource "yandex_vpc_security_group" "this" {
  name       = "${var.name}-sg"
  network_id = yandex_vpc_network.this.id
  labels     = var.labels

  # VMs that share this group talk to each other on any port.
  ingress {
    description       = "intra-group"
    protocol          = "ANY"
    predefined_target = "self_security_group"
  }

  ingress {
    description    = "ssh"
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = var.ssh_allowed_cidrs
  }

  dynamic "ingress" {
    for_each = toset([for p in var.app_ports : tostring(p)])
    content {
      description    = "app ${ingress.value}"
      protocol       = "TCP"
      port           = tonumber(ingress.value)
      v4_cidr_blocks = var.app_allowed_cidrs
    }
  }

  egress {
    description    = "all outbound"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}
