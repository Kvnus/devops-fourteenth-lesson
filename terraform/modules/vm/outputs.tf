output "id" {
  value = yandex_compute_instance.this.id
}

output "name" {
  value = yandex_compute_instance.this.name
}

output "fqdn" {
  description = "Internal DNS name."
  value       = yandex_compute_instance.this.fqdn
}

output "internal_ip" {
  value = yandex_compute_instance.this.network_interface[0].ip_address
}

output "public_ip" {
  value = yandex_compute_instance.this.network_interface[0].nat_ip_address
}

output "ssh_user" {
  value = var.ssh_user
}
