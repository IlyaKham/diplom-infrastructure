variable "service_account_id" {
  description = "ID единого аккаунта diplom-terraform из bootstrap output."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{20}$", var.service_account_id))
    error_message = "Укажи ID сервисного аккаунта Terraform (20 символов)."
  }
}

variable "kubernetes_version" {
  description = "Минорная версия из yc managed-kubernetes list-versions, канал STABLE."
  type        = string
  default     = "1.35"

  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "Версия задаётся как 1.35 и должна поддерживаться Yandex Cloud."
  }
}

variable "api_allowed_cidrs" {
  description = "Внешние IPv4 CIDR администраторов, которым доступен Kubernetes API."
  type        = list(string)

  validation {
    condition     = length(var.api_allowed_cidrs) > 0 && alltrue([for cidr in var.api_allowed_cidrs : can(cidrnetmask(cidr))])
    error_message = "Укажи хотя бы один IPv4 CIDR для доступа к Kubernetes API."
  }
}

variable "worker_platform_id" {
  description = "Платформа рабочих узлов."
  type        = string
  default     = "standard-v3"
}

variable "worker_memory_gb" {
  description = "Память одного рабочего узла; 4 ГиБ оставляют место для мониторинга."
  type        = number
  default     = 4

  validation {
    condition     = var.worker_memory_gb >= 2 && floor(var.worker_memory_gb) == var.worker_memory_gb
    error_message = "Память узла должна быть целым числом не меньше 2 ГиБ."
  }
}

variable "worker_core_fraction" {
  description = "Гарантированная доля двух vCPU: 20% для экономии учебного бюджета."
  type        = number
  default     = 20

  validation {
    condition     = contains([20, 100], var.worker_core_fraction)
    error_message = "Для этой конфигурации выбери долю CPU 20 или 100 процентов."
  }
}

variable "worker_disk_types" {
  description = "Переопределения дисков по зонам; в остальных зонах используется network-hdd."
  type        = map(string)
  default = {
    ru-central1-e = "network-ssd"
  }

  validation {
    condition     = alltrue([for disk_type in values(var.worker_disk_types) : contains(["network-hdd", "network-ssd"], disk_type)])
    error_message = "Поддерживаются диски network-hdd и network-ssd."
  }
}
