resource "yandex_kubernetes_cluster" "main" {
  name                     = "${var.project_name}-k8s"
  description              = "Regional Kubernetes master and preemptible workers in three zones"
  folder_id                = var.folder_id
  network_id               = yandex_vpc_network.main.id
  service_account_id       = var.service_account_id
  node_service_account_id  = var.service_account_id
  release_channel          = "STABLE"
  network_policy_provider  = "CALICO"
  cluster_ipv4_ranges      = ["10.96.0.0/16"]
  service_ipv4_range       = "10.112.0.0/16"
  node_ipv4_cidr_mask_size = 24
  labels = {
    project    = var.project_name
    managed-by = "terraform"
  }

  master {
    version   = var.kubernetes_version
    public_ip = true
    security_group_ids = [
      yandex_vpc_security_group.kubernetes_internal.id,
      yandex_vpc_security_group.kubernetes_api.id,
    ]

    # Три master_location создают региональный, отказоустойчивый мастер.
    dynamic "master_location" {
      for_each = yandex_vpc_subnet.main
      content {
        zone      = master_location.key
        subnet_id = master_location.value.id
      }
    }

    maintenance_policy {
      auto_upgrade = true
      maintenance_window {
        start_time = "01:00"
        duration   = "3h"
      }
    }

    # Метрики развёртываются на этапе мониторинга; платные журналы пока выключены.
    master_logging {
      enabled = false
    }
  }

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
}

resource "yandex_kubernetes_node_group" "workers" {
  for_each = yandex_vpc_subnet.main

  cluster_id  = yandex_kubernetes_cluster.main.id
  name        = "${var.project_name}-workers-${each.key}"
  description = "One preemptible worker in ${each.key}"
  version     = var.kubernetes_version
  labels = {
    project    = var.project_name
    managed-by = "terraform"
  }
  node_labels = {
    project = var.project_name
  }

  instance_template {
    name        = "${var.project_name}-worker-{instance.short_id}"
    platform_id = var.worker_platform_id
    labels = {
      project    = var.project_name
      managed-by = "terraform"
    }

    resources {
      cores         = 2
      memory        = var.worker_memory_gb
      core_fraction = var.worker_core_fraction
    }

    boot_disk {
      type = lookup(var.worker_disk_types, each.key, "network-hdd")
      size = 64
    }

    network_interface {
      ipv4       = true
      nat        = true
      subnet_ids = [each.value.id]
      security_group_ids = [
        yandex_vpc_security_group.kubernetes_internal.id,
        yandex_vpc_security_group.kubernetes_workers.id,
      ]
    }

    scheduling_policy {
      preemptible = true
    }

    container_runtime {
      type = "containerd"
    }
  }

  scale_policy {
    fixed_scale {
      size = 1
    }
  }

  allocation_policy {
    location {
      zone = each.key
    }
  }

  deploy_policy {
    max_expansion   = 0
    max_unavailable = 1
  }

  maintenance_policy {
    auto_upgrade = true
    auto_repair  = true
    maintenance_window {
      start_time = "01:00"
      duration   = "3h"
    }
  }

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
}
