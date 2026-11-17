# The Kubernetes service controller creates the public Network Load Balancer.
resource "yandex_resourcemanager_folder_iam_member" "load_balancer" {
  folder_id = var.folder_id
  role      = "load-balancer.editor"
  member    = "serviceAccount:${local.terraform_service_account_id}"
}
