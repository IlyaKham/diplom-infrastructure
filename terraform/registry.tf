resource "yandex_container_registry" "application" {
  name      = "${var.project_name}-registry"
  folder_id = var.folder_id

  labels = {
    project = var.project_name
    purpose = "application-images"
  }
}

output "container_registry_id" {
  description = "ID of the private application image registry."
  value       = yandex_container_registry.application.id
}

output "application_image_repository" {
  description = "Application image repository without a tag."
  value       = "cr.yandex/${yandex_container_registry.application.id}/diplom-app"
}
