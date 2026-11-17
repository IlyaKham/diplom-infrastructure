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
  description = "Тот же префикс, что в bootstrap."
  type        = string
  default     = "diplom"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,19}$", var.project_name))
    error_message = "Префикс: 2–20 символов, строчные латинские буквы, цифры и дефис; начинается с буквы."
  }
}

variable "subnets" {
  description = "Три зоны и непересекающиеся подсети будущего регионального кластера."
  type        = map(string)
  default = {
    ru-central1-a = "10.10.0.0/24"
    ru-central1-e = "10.40.0.0/24"
    ru-central1-d = "10.30.0.0/24"
  }

  validation {
    condition     = length(var.subnets) == 3 && alltrue([for zone, cidr in var.subnets : contains(["ru-central1-a", "ru-central1-b", "ru-central1-d", "ru-central1-e"], zone) && can(cidrnetmask(cidr))])
    error_message = "Нужны три разные зоны ru-central1 и корректные IPv4 CIDR."
  }
}
