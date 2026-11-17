resource "yandex_vpc_security_group" "kubernetes_internal" {
  name        = "${var.project_name}-k8s-internal"
  description = "Managed Kubernetes internal traffic and load balancer health checks"
  network_id  = yandex_vpc_network.main.id
  labels = {
    project    = var.project_name
    managed-by = "terraform"
  }

  ingress {
    description       = "Master and workers within this security group"
    protocol          = "ANY"
    from_port         = 0
    to_port           = 65535
    predefined_target = "self_security_group"
  }

  ingress {
    description       = "Yandex Network Load Balancer health checks"
    protocol          = "TCP"
    from_port         = 0
    to_port           = 65535
    predefined_target = "loadbalancer_healthchecks"
  }

  ingress {
    description    = "ICMP diagnostics from private cloud networks"
    protocol       = "ICMP"
    v4_cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }

  egress {
    description    = "Cloud APIs, DNS, NTP and container registries"
    protocol       = "ANY"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "kubernetes_api" {
  name        = "${var.project_name}-k8s-api"
  description = "Kubernetes API from configured administrator IPv4 ranges"
  network_id  = yandex_vpc_network.main.id
  labels = {
    project    = var.project_name
    managed-by = "terraform"
  }

  ingress {
    protocol       = "TCP"
    port           = 443
    v4_cidr_blocks = var.api_allowed_cidrs
  }

  ingress {
    protocol       = "TCP"
    port           = 6443
    v4_cidr_blocks = var.api_allowed_cidrs
  }
}

resource "yandex_vpc_security_group" "kubernetes_workers" {
  name        = "${var.project_name}-k8s-workers"
  description = "Pod and service traffic; HTTP ingress NodePort 30080"
  network_id  = yandex_vpc_network.main.id
  labels = {
    project    = var.project_name
    managed-by = "terraform"
  }

  ingress {
    protocol       = "ANY"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["10.96.0.0/16", "10.112.0.0/16"]
  }

  ingress {
    description    = "HTTP ingress behind the public LoadBalancer"
    protocol       = "TCP"
    port           = 30080
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}
