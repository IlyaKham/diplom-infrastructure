# Дипломная работа по курсу «DevOps-инженер» --- "Хамуро ИА"

Я развернул приложение и мониторинг в Yandex Managed Service for Kubernetes и настроил автоматизацию через GitHub Actions.

| Результат | Ссылка |
| --- | --- |
| Terraform | [diplom-infrastructure](https://github.com/IlyaKham/diplom-infrastructure) |
| Приложение, Dockerfile, Kubernetes и Helm | [diplom-app](https://github.com/IlyaKham/diplom-app) |

Адреса приложения и Grafana, а также данные для входа я передаю преподавателю лично.

## 1. Облачная инфраструктура

Я разделил Terraform на два корневых модуля. В `bootstrap/` создал аккаунт `diplom-terraform`, назначил профильные права без универсальных `admin`/`editor` и подготовил закрытый версионируемый S3-бакет. В `terraform/` описал основную инфраструктуру с удалённым state и блокировкой в этом бакете.

Я использовал Terraform 1.14.0 и Yandex provider 0.248.0. Версии и контрольные суммы зависимостей зафиксировал в конфигурациях и lock-файлах.

Я создал VPC `diplom-network` и подсети в зонах a/d/e: `10.10.0.0/24`, `10.30.0.0/24`, `10.40.0.0/24`. До создания Kubernetes проверил удаление и повторное создание сети через `destroy/apply`. Существующее имя бакета `diploma-tfstate-bbe2400261af` сохранил; ключ состояния — `diploma/infrastructure.tfstate`.

<details>
<summary>Скриншоты: ресурсы, state и сеть</summary>

![Ресурсы каталога Yandex Cloud](https://github.com/IlyaKham/diplom-infrastructure/releases/download/report-assets-2026-11-17/01-cloud-resources.png)

![Terraform state в Object Storage](https://github.com/IlyaKham/diplom-infrastructure/releases/download/report-assets-2026-11-17/02-terraform-state-bucket.png)

![Сеть и подсети в трёх зонах](https://github.com/IlyaKham/diplom-infrastructure/releases/download/report-assets-2026-11-17/10-network-ade.png)

</details>

## 2. Kubernetes

Я создал региональный кластер `diplom-k8s` с размещением мастера в a/d/e и тремя прерываемыми рабочими узлами, по одному в каждой зоне. Каждый узел имеет 2 vCPU, долю CPU 20%, 4 ГиБ RAM и диск 64 ГиБ. Выбор зон и типов дисков согласовал с доступными квотами облака.

Я настроил kubeconfig и проверил три Ready-узла и выполнение `kubectl get pods --all-namespaces`. Кластер использует Kubernetes 1.35; манифесты находятся в [репозитории приложения](https://github.com/IlyaKham/diplom-app/tree/main/kubernetes).

<details>
<summary>Скриншот: работающий кластер</summary>

![Кластер и работающие поды](https://github.com/IlyaKham/diplom-infrastructure/releases/download/report-assets-2026-11-17/07-kubernetes-cluster.png)

</details>

## 3. Тестовое приложение

Я подготовил отдельный репозиторий со статической страницей, конфигурацией nginx и собственным Dockerfile. Базовый nginx 1.30.6-alpine закрепил по digest. Контейнер запускается с UID 101 на порту 8080, без дополнительных Linux capabilities, с файловой системой только для чтения и временным `/tmp`.

Через Terraform я создал приватный Yandex Container Registry. Первый образ опубликовал как `0.1.0`, затем настроил автоматическую публикацию из Actions. Проверил HTTP, `/healthz`, `/version.json`, стили, JavaScript и ответ 404. Версия, SHA коммита и время сборки включены в JSON и метаданные образа.

![Первый образ приложения в Container Registry](https://github.com/IlyaKham/diplom-infrastructure/releases/download/report-assets-2026-11-17/13-container-registry.png)

## 4. Мониторинг и доступ к приложению

Я установил kube-prometheus-stack: Prometheus, Grafana, Alertmanager, kube-state-metrics и node-exporter на каждом узле. Проверил 22 доступные цели сбора метрик и 25 дашбордов, включая 16 Kubernetes-дашбордов. Grafana получает реальные метрики трёх узлов.

Я развернул две реплики приложения и две реплики Traefik. Один внешний балансировщик принимает HTTP на порту 80 и направляет трафик на NodePort 30080: `/` открывает приложение, `/grafana/` — Grafana. Все три узла целевой группы прошли проверки доступности. Prometheus и Alertmanager доступны внутри кластера.

Для учебного стенда я использовал временные тома без дополнительных дисков: история Prometheus хранится до суток и теряется при пересоздании пода. Дашборды и настройки компонентов восстанавливаются из конфигураций.

<details>
<summary>Скриншоты: Grafana и балансировщик</summary>

![Метрики кластера: CPU и память](https://github.com/IlyaKham/diplom-infrastructure/releases/download/report-assets-2026-11-17/17-grafana-cluster.png)

![Метрики кластера: память и сеть](https://github.com/IlyaKham/diplom-infrastructure/releases/download/report-assets-2026-11-17/17-grafana-cluster-details.png)

![Ресурсы подов выбранного узла](https://github.com/IlyaKham/diplom-infrastructure/releases/download/report-assets-2026-11-17/18-grafana-node-pods.png)

![Память подов выбранного узла](https://github.com/IlyaKham/diplom-infrastructure/releases/download/report-assets-2026-11-17/18-grafana-node-pods-memory.png)

![Node Exporter: CPU и память](https://github.com/IlyaKham/diplom-infrastructure/releases/download/report-assets-2026-11-17/18-grafana-node.png)

![Node Exporter: диски и сеть](https://github.com/IlyaKham/diplom-infrastructure/releases/download/report-assets-2026-11-17/18-grafana-node-details.png)

![Активный внешний балансировщик](https://github.com/IlyaKham/diplom-infrastructure/releases/download/report-assets-2026-11-17/21-load-balancer.png)

</details>

## 5. CI/CD

Я настроил GitHub Actions, разрешённый заданием. В инфраструктурном репозитории каждый push в `main` запускает проверку обоих Terraform-модулей и автоматические plan/apply основного модуля. В [успешном запуске 44099861686](https://github.com/IlyaKham/diplom-infrastructure/actions/runs/44099861686) план подтвердил соответствие облака конфигурации, apply завершился с `0 added, 0 changed, 0 destroyed`.

В репозитории приложения каждый push запускает сборку, проверку и публикацию образа с тегом `sha-<SHA>`. Это проверено [запуском 44098787782](https://github.com/IlyaKham/diplom-app/actions/runs/44098787782). Создание тега `v1.0.0` запустило сборку с соответствующей версией, публикацию и автоматический деплой по digest: [запуск 44100761404](https://github.com/IlyaKham/diplom-app/actions/runs/44100761404).

Для деплоя я установил Actions Runner Controller. Временный runner создаётся внутри Kubernetes на одно задание и удаляется после него. Он использует внутренний API и ограниченный RBAC для Deployment приложения, поэтому внешний API не требуется открывать для GitHub. Доступ подов приложения и runner к метаданным узла заблокирован NetworkPolicy.

<details>
<summary>Скриншоты: Terraform pipeline и релиз приложения</summary>

![Terraform plan: No changes](https://github.com/IlyaKham/diplom-infrastructure/releases/download/report-assets-2026-11-17/23-github-terraform-plan.png)

![Успешные сборка, публикация и деплой v1.0.0](https://github.com/IlyaKham/diplom-infrastructure/releases/download/report-assets-2026-11-17/25-github-release.png)

</details>

После деплоя я проверил две доступные реплики и публичный `/version.json`: версия `v1.0.0`, ревизия `d13e00cccd4bfb50f598475b16b95d9c40c7fc65`. Опубликованный и развёрнутый digest совпадают:

```text
cr.yandex/crp85lbhbo07ldt2oj0c/diplom-app:v1.0.0
cr.yandex/crp85lbhbo07ldt2oj0c/diplom-app@sha256:3e2d086d30d4a3069ca115ef5acfc253c7d1e199c6a3c848c17637203d7fbc81
```

На снимке registry показан первоначальный образ `0.1.0`, на снимке Actions — последующий релиз `v1.0.0`.

