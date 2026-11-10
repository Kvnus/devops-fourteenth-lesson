output "registry_id" {
  value = yandex_container_registry.this.id
}

output "image" {
  value = local.image
}

output "build_public_ip" {
  value = module.build.public_ip
}

output "build_internal_ip" {
  value = module.build.internal_ip
}

output "prod_public_ip" {
  value = module.prod.public_ip
}

output "prod_internal_ip" {
  value = module.prod.internal_ip
}

output "app_url" {
  value = "http://${module.prod.public_ip}:${var.app_port}/"
}

output "ssh_build" {
  value = "ssh ${var.ssh_user}@${module.build.public_ip}"
}

output "ssh_prod" {
  value = "ssh ${var.ssh_user}@${module.prod.public_ip}"
}
