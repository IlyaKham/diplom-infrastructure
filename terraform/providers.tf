# Авторизованный ключ сервисного аккаунта указывается через
# YC_SERVICE_ACCOUNT_KEY_FILE. В исходном коде секретов нет.
provider "yandex" {
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
}
