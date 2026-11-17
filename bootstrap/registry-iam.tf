# Stage 3: create the registry and push/pull images with the same service account.
resource "yandex_resourcemanager_folder_iam_member" "container_registry" {
  folder_id = var.folder_id
  role      = "container-registry.editor"
  member    = "serviceAccount:${local.terraform_service_account_id}"
}
