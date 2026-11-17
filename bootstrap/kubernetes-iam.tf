# Права для второго этапа. Универсальные admin/editor не используются.
resource "yandex_resourcemanager_folder_iam_member" "kubernetes" {
  for_each = toset([
    "k8s.editor",
    "k8s.clusters.agent",
    "k8s.cluster-api.cluster-admin",
  ])

  folder_id = var.folder_id
  role      = each.value
  member    = "serviceAccount:${local.terraform_service_account_id}"
}

# Аккаунт Terraform может назначать на кластер и узлы только самого себя.
resource "yandex_iam_service_account_iam_binding" "kubernetes_self_use" {
  service_account_id = local.terraform_service_account_id
  role               = "iam.serviceAccounts.user"
  members            = ["serviceAccount:${local.terraform_service_account_id}"]
}
