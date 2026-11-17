locals {
  terraform_service_account_id = var.existing_terraform_service_account_id != null ? var.existing_terraform_service_account_id : yandex_iam_service_account.terraform[0].id
}

resource "yandex_iam_service_account" "terraform" {
  count = var.existing_terraform_service_account_id == null ? 1 : 0

  name        = "${var.project_name}-terraform"
  description = "Terraform for diploma infrastructure; no global administrator rights"
  folder_id   = var.folder_id
}

# Права расширяются только при появлении ресурсов следующих этапов.
resource "yandex_resourcemanager_folder_iam_member" "terraform_vpc" {
  folder_id = var.folder_id
  role      = "vpc.admin"
  member    = "serviceAccount:${local.terraform_service_account_id}"
}

resource "yandex_storage_bucket" "state" {
  bucket                = var.state_bucket_name
  folder_id             = var.folder_id
  default_storage_class = "STANDARD"
  max_size              = 1073741824
  force_destroy         = false

  anonymous_access_flags {
    read        = false
    list        = false
    config_read = false
  }

  versioning {
    enabled = true
  }

  # Проверка destroy/apply выполняется в ../terraform, а не в bootstrap.
  lifecycle {
    prevent_destroy = true
  }
}

# Доступ к одному бакету, а не ко всем бакетам каталога.
resource "yandex_storage_bucket_iam_binding" "state" {
  bucket  = yandex_storage_bucket.state.bucket
  role    = "storage.editor"
  members = ["serviceAccount:${local.terraform_service_account_id}"]
}
