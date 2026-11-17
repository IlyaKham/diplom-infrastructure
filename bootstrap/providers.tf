# Bootstrap использует временный IAM-токен владельца каталога из YC_TOKEN.
# Токен не записывается в конфигурацию и не передаётся как Terraform variable.
provider "yandex" {
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
}
