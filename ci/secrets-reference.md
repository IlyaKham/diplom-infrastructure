# GitHub Actions Secrets

Значения заполняет владелец в Settings → Secrets and variables → Actions → Secrets каждого репозитория. Этот файл содержит только названия и источники значений. Ключи, пароли и токены в Git не добавляются.

| Репозиторий | Secret | Что вставить самостоятельно |
| --- | --- | --- |
| Инфраструктура | `YC_SERVICE_ACCOUNT_KEY` | Полное содержимое существующего авторизованного JSON-ключа `infrastructure/secrets/terraform-sa-key.json` |
| Инфраструктура | `AWS_ACCESS_KEY_ID` | Идентификатор существующего статического S3-ключа из `infrastructure/secrets.local.ps1` |
| Инфраструктура | `AWS_SECRET_ACCESS_KEY` | Секретная часть того же статического S3-ключа |
| Инфраструктура | `API_ALLOWED_CIDRS` | JSON-массив двух существующих `/32` из локального `terraform.tfvars`: `["FIRST_IP/32","SECOND_IP/32"]` |
| Приложение | `YC_SERVICE_ACCOUNT_KEY` | Тот же авторизованный JSON-ключ аккаунта `diplom-terraform` |

Используются существующие ключи одного облачного аккаунта. Временный токен владельца `YC_TOKEN` и пароль Grafana в GitHub не нужны. Основной Terraform workflow применяет только модуль `terraform/`; bootstrap проверяется локально/в validate и применяется владельцем отдельно при изменении прав.

Несекретные Variables перечислены в `variables.example.json`; их можно настроить отдельно от Secrets.

Для runner нужен отдельный fine-grained GitHub PAT с доступом только к репозиторию приложения и разрешением `Administration: Read and write`. Он нужен контроллеру для регистрации временных исполнителей. Владелец вводит его только в локальный `kubernetes/actions-runner/secrets.local.ps1`; установщик передаёт токен в Secret Kubernetes через stdin. В Secrets приложения этот PAT не размещается.
