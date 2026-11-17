output "kubernetes_cluster_id" {
  description = "ID регионального Managed Kubernetes."
  value       = yandex_kubernetes_cluster.main.id
}

output "kubernetes_endpoint" {
  description = "Внешний HTTPS endpoint Kubernetes API."
  value       = yandex_kubernetes_cluster.main.master[0].external_v4_endpoint
}

output "kubernetes_node_group_ids" {
  description = "Три рабочие группы, по одной в каждой зоне."
  value       = { for zone, group in yandex_kubernetes_node_group.workers : zone => group.id }
}
