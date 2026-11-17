# Этап 4: мониторинг и развёртывание

Конфигурации находятся в `kubernetes/`. Используется `kube-prometheus-stack` из официального сообщества Prometheus: он объединяет компоненты kube-prometheus, включая Prometheus Operator, Prometheus, Grafana, Alertmanager, kube-state-metrics и node-exporter. Helm chart закреплён на `93.3.1`, оператор — `v0.95.2`.

Для общего HTTP-входа используется официальный Traefik chart `42.4.0`, Traefik `v3.7.18`. Архивы обоих чартов закреплены SHA256 в `kubernetes/charts.lock.json` и проверяются перед установкой. Совместимость проверена Helm с Kubernetes `1.35.1`.

## Схема

```text
Интернет, HTTP :80
        |
Yandex Network Load Balancer (один IP)
        |
Traefik, NodePort 30080, две реплики
        |-- /          -> diplom-app:80 -> nginx:8080, две реплики
        |-- /grafana/  -> diplom-grafana:80
                                  |
                         Prometheus (ClusterIP)
                          |-- kubelet / cAdvisor
                          |-- kube-state-metrics
                          |-- node-exporter на каждом из трёх узлов
                          |-- API Kubernetes и компоненты мониторинга
                                  |
                         Alertmanager (ClusterIP)
```

Приложение и Grafana доступны по HTTP 80. Prometheus, Alertmanager и панель управления Traefik наружу не публикуются. Ограничение Kubernetes API собственными IP сохраняется.

## Балансировщик и права

Проверены квоты Network Load Balancer: два балансировщика, занято ноль до начала установки; целевых групп 100, занято ноль. Достаточно одного нового балансировщика и одной группы для трёх узлов.

Первые события Service показали `PermissionDenied` при создании балансировщика. В bootstrap добавлено назначение `load-balancer.editor` существующему аккаунту `diplom-terraform`. Уже имеющаяся роль `vpc.admin` обеспечивает необходимую работу с публичными адресами. Универсальные `admin/editor` не назначаются.

Балансировщиком управляет Kubernetes Service `diplom-ingress`, созданный Helm. Он не дублируется отдельным Terraform-ресурсом. Terraform управляет правами, сетью и группами безопасности; разрешён только NodePort 30080 вместо полного диапазона 30000–32767.

## Пароль и данные

Владелец самостоятельно задаёт пароль Grafana в `kubernetes/monitoring/secrets.local.ps1`; шаблон — `secrets.example.ps1`. Локальный файл исключён из Git. Пароль передаётся в Kubernetes Secret через stdin без значения в аргументах процессов и без сохранения заполненного манифеста. Helm хранит только ссылку на Secret.

Дисковые квоты уже заняты загрузочными дисками. Для учебного мониторинга выбраны `emptyDir` без новых дисков: Prometheus сохраняет до суток истории, объём блоков ограничен 1 GB, временный том — 2 ГиБ. При пересоздании пода его история сбрасывается. Дашборды и datasource Grafana восстанавливаются из ConfigMap; локальные пользовательские изменения не сохраняются. Alertmanager установлен с локальным получателем `null`; уведомления во внешние каналы не настраивались.

HTTP используется в соответствии с ТЗ. Для эксплуатации за пределами учебной работы следует настроить HTTPS и постоянное хранилище.

## Воспроизведение и проверка

[Инструкция и команды](../kubernetes/README.md). Скрипт `Deploy-Platform.ps1` выполняет установку, `Test-Platform.ps1` проверяет HTTP, Prometheus, datasource и дашборды. Проверка с паролем Grafana выполняется через временный локальный туннель Kubernetes API; после проверки он закрывается.

Фактический результат: [проверка в облаке](04-cloud-validation.md), [чек-лист](04-checklist.md). Все компоненты готовы; Prometheus видит три узла и 22 доступные цели, Grafana — 25 дашбордов. Автоматизация Terraform в GitHub и обязательные скриншоты её pipeline относятся к следующему этапу CI/CD.
