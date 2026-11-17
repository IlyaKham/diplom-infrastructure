# Диплом DevOps: Yandex Cloud и GitHub Actions

[Отчёт по всем этапам со скриншотами](REPORT.md)

- [Приложение](http://46.243.210.163/) — релиз `v1.0.0`.
- [Grafana](http://46.243.210.163/grafana/) — логин `admin`, пароль передаётся преподавателю отдельно.
- [Исходники приложения и Dockerfile](https://github.com/IlyaKham/diplom-app).

## Реализация

| Каталог | Назначение |
| --- | --- |
| `bootstrap/` | Аккаунт, профильные права и закрытый бакет Terraform state; отдельный локальный state |
| `terraform/` | VPC, три подсети, региональный Kubernetes, прерываемые рабочие группы и Container Registry; S3 backend |
| `kubernetes/` | Манифесты приложения, настройки Traefik, мониторинга и временных Actions runners |
| `.github/workflows/terraform.yml` | Проверка обоих модулей и автоматические plan/apply основного модуля при push в main |
| `ci/prepare-terraform.sh` | Подготовка временных credentials, tfvars и backend внутри задания Actions |
| `docs/screenshots/` | Оригинальные снимки для отчёта |

Terraform 1.14.0, Yandex provider 0.248.0. Версии и контрольные суммы Helm-чартов указаны в `kubernetes/charts.lock.json` и `kubernetes/actions-runner/charts.lock.json`.

## Параметры и секреты

Для нового развёртывания нужны заполненные локальные копии `bootstrap/terraform.tfvars.example`, `terraform/terraform.tfvars.example` и `terraform/backend.hcl.example`. Bootstrap выполняется с временным `YC_TOKEN` владельца каталога. Для основного модуля используются `YC_SERVICE_ACCOUNT_KEY_FILE`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` одного аккаунта диплома.

В Actions инфраструктуры заданы Secrets `YC_SERVICE_ACCOUNT_KEY`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `API_ALLOWED_CIDRS` (JSON-массив собственных IPv4 /32); Variables перечислены в `ci/variables.example.json`. В приложении нужны Secret `YC_SERVICE_ACCOUNT_KEY` и Variables `YC_REGISTRY_ID`, `APPLICATION_URL`.

Мониторинг использует существующий Kubernetes Secret `diplom-grafana-admin` с ключами `admin-user` и `admin-password`. ARC использует `diplom-github-auth` в namespace `diplom-actions-runners`, ключ `github_token`: fine-grained PAT только для репозитория приложения с Administration: Read and write. Значения вводит владелец; в Git они не хранятся.

Helm-релизы: `diplom-ingress` (Traefik 42.4.0), `diplom-monitoring` (kube-prometheus-stack 93.3.1), `diplom-arc` и `diplom-deploy` (ARC 0.15.1). Для них используются соответствующие `values.yaml`. Приложение применяется через `kubectl apply -k kubernetes/application`. В манифесте закреплён проверенный digest v1.0.0; последующие релизы обновляет workflow приложения.

При пересоздании балансировщика нужно обновить IP Grafana в `kubernetes/monitoring/values.yaml` и Variable `APPLICATION_URL`. Пароль Grafana, облачные ключи, локальные tfvars, backend, kubeconfig и state исключены из Git. Вспомогательные PowerShell-скрипты и промежуточные журналы удалены из актуального состава проекта.
