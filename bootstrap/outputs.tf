output "terraform_service_account_id" {
  description = "Сервисный аккаунт основной конфигурации Terraform."
  value       = local.terraform_service_account_id
}

output "state_service_account_id" {
  description = "Тот же аккаунт Terraform используется для S3 backend. Для него владелец создаёт статический ключ."
  value       = local.terraform_service_account_id
}

output "state_bucket_name" {
  description = "Имя для terraform/backend.hcl."
  value       = yandex_storage_bucket.state.bucket
}
