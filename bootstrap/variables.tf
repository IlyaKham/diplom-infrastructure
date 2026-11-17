variable "cloud_id" {
  description = "Идентификатор облака Yandex Cloud."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{20}$", var.cloud_id))
    error_message = "Укажи настоящий cloud_id из консоли Yandex Cloud (20 символов)."
  }
}

variable "folder_id" {
  description = "Идентификатор выделенного каталога диплома."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{20}$", var.folder_id))
    error_message = "Укажи настоящий folder_id из консоли Yandex Cloud (20 символов)."
  }
}

variable "project_name" {
  description = "Короткий префикс имён ресурсов."
  type        = string
  default     = "diplom"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,19}$", var.project_name))
    error_message = "Префикс: 2–20 символов, строчные латинские буквы, цифры и дефис; начинается с буквы."
  }
}

variable "existing_terraform_service_account_id" {
  description = "ID существующего аккаунта Terraform. null — создать отдельный аккаунт через Terraform."
  type        = string
  default     = null

  validation {
    condition     = var.existing_terraform_service_account_id == null ? true : can(regex("^[a-z0-9]{20}$", var.existing_terraform_service_account_id))
    error_message = "Укажи ID существующего сервисного аккаунта (20 символов) или null."
  }
}

variable "state_bucket_name" {
  description = "Глобально уникальное имя бакета Terraform state."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.state_bucket_name)) && !startswith(var.state_bucket_name, "replace-")
    error_message = "Задай уникальное имя бакета: 3–63 символа, строчные латинские буквы, цифры и дефис."
  }
}
