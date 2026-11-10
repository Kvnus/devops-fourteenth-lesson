locals {
  labels = {
    project = var.name_prefix
    managed = "terraform"
  }
  ssh_public_key = file(pathexpand(var.ssh_public_key_path))

  image_name = "${yandex_container_registry.this.id}/${var.name_prefix}"
  image_tag  = substr(data.archive_file.src.output_md5, 0, 12)
  image      = "cr.yandex/${local.image_name}:${local.image_tag}"
}

# ---------------------------------------------------------------- network
module "network" {
  source            = "./modules/network"
  name              = var.name_prefix
  zone              = var.zone
  ssh_allowed_cidrs = var.ssh_allowed_cidrs
  app_ports         = [var.app_port]
  labels            = local.labels
}

# ----------------------------------------- artifact repository (native)
resource "yandex_container_registry" "this" {
  name      = "${var.name_prefix}-registry"
  folder_id = var.folder_id
  labels    = local.labels
}

resource "yandex_iam_service_account" "build" {
  name = "${var.name_prefix}-build-sa"
}

resource "yandex_iam_service_account" "prod" {
  name = "${var.name_prefix}-prod-sa"
}

resource "yandex_container_registry_iam_binding" "pusher" {
  registry_id = yandex_container_registry.this.id
  role        = "container-registry.images.pusher"
  members     = ["serviceAccount:${yandex_iam_service_account.build.id}"]
}

resource "yandex_container_registry_iam_binding" "puller" {
  registry_id = yandex_container_registry.this.id
  role        = "container-registry.images.puller"
  members     = ["serviceAccount:${yandex_iam_service_account.prod.id}"]
}

# ------------------------------------------------------------ build VM
module "build" {
  source = "./modules/vm"

  name               = "${var.name_prefix}-build"
  zone               = var.zone
  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
  cores              = var.build_vm.cores
  memory             = var.build_vm.memory
  core_fraction      = var.build_vm.core_fraction
  boot_disk_size     = var.build_vm.disk_size
  preemptible        = var.build_vm.preemptible
  public_ip          = true
  service_account_id = yandex_iam_service_account.build.id
  ssh_user           = var.ssh_user
  ssh_public_key     = local.ssh_public_key
  labels             = merge(local.labels, { role = "build" })

  user_data = templatefile("${path.module}/templates/cloud-init.yaml.tpl", {
    role           = "build"
    extra_packages = ["unzip"]
    app_port       = var.app_port
  })
}

# Zip the project and ship it to the build VM, build the Docker image there
# and push it to Yandex Container Registry.
data "archive_file" "src" {
  type        = "zip"
  source_dir  = var.app_source_dir
  output_path = "${path.module}/app-src.zip"
  excludes    = ["terraform", "docs", "target", ".git", ".idea"]
}

resource "null_resource" "build" {
  triggers = {
    image = local.image
    vm    = module.build.id
  }

  depends_on = [yandex_container_registry_iam_binding.pusher]

  connection {
    type        = "ssh"
    host        = module.build.public_ip
    user        = var.ssh_user
    private_key = file(pathexpand(var.ssh_private_key_path))
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = ["cloud-init status --wait || true"]
  }

  provisioner "file" {
    source      = data.archive_file.src.output_path
    destination = "/tmp/app-src.zip"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "rm -rf ~/src && mkdir ~/src && unzip -q /tmp/app-src.zip -d ~/src",
      "sudo yc-registry-login",
      "cd ~/src && sudo docker build -t ${local.image} -t cr.yandex/${local.image_name}:latest .",
      "sudo docker push ${local.image}",
      "sudo docker push cr.yandex/${local.image_name}:latest",
    ]
  }
}

# ------------------------------------------------------------- prod VM
resource "yandex_vpc_address" "prod" {
  name = "${var.name_prefix}-prod-ip"
  external_ipv4_address {
    zone_id = var.zone
  }
}

module "prod" {
  source = "./modules/vm"

  name               = "${var.name_prefix}-prod"
  zone               = var.zone
  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
  cores              = var.prod_vm.cores
  memory             = var.prod_vm.memory
  core_fraction      = var.prod_vm.core_fraction
  boot_disk_size     = var.prod_vm.disk_size
  preemptible        = var.prod_vm.preemptible
  public_ip          = true
  nat_ip_address     = yandex_vpc_address.prod.external_ipv4_address[0].address
  service_account_id = yandex_iam_service_account.prod.id
  ssh_user           = var.ssh_user
  ssh_public_key     = local.ssh_public_key
  labels             = merge(local.labels, { role = "prod" })

  user_data = templatefile("${path.module}/templates/cloud-init.yaml.tpl", {
    role           = "prod"
    extra_packages = []
    app_port       = var.app_port
  })
}

# Starts / updates the app on prod once the image has been pushed.
resource "null_resource" "deploy" {
  triggers = {
    image = local.image
    vm    = module.prod.id
  }

  depends_on = [null_resource.build, yandex_container_registry_iam_binding.puller]

  connection {
    type        = "ssh"
    host        = module.prod.public_ip
    user        = var.ssh_user
    private_key = file(pathexpand(var.ssh_private_key_path))
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait || true",
      "sudo deploy-app ${local.image}",
      "for i in $(seq 1 30); do curl -sf http://localhost:${var.app_port}/ && exit 0; sleep 2; done; echo 'app did not start'; sudo docker logs app; exit 1",
    ]
  }
}
