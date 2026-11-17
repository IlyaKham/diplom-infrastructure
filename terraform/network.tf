resource "yandex_vpc_network" "main" {
  name        = "${var.project_name}-network"
  description = "Diploma VPC for a regional Managed Kubernetes cluster"
  folder_id   = var.folder_id
  labels = {
    project    = var.project_name
    managed-by = "terraform"
  }
}

resource "yandex_vpc_subnet" "main" {
  for_each = var.subnets

  name           = "${var.project_name}-${each.key}"
  description    = "Managed Kubernetes subnet in ${each.key}"
  folder_id      = var.folder_id
  zone           = each.key
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = [each.value]
  labels = {
    project    = var.project_name
    managed-by = "terraform"
  }
}
