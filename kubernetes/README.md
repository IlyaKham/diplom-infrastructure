# Приложение и мониторинг

В каталоге находятся манифесты приложения, настройки официальных Helm-чартов и закреплённые версии с SHA256 в `charts.lock.json`.

| Компонент | Размещение | Доступ |
| --- | --- | --- |
| Traefik, две реплики | `diplom-ingress` | Один публичный LoadBalancer, HTTP 80 → NodePort 30080 |
| nginx, две реплики | `diplom-app` | `/` через общий балансировщик |
| Grafana | `diplom-monitoring` | `/grafana/` через общий балансировщик; требуется вход |
| Prometheus, Alertmanager | `diplom-monitoring` | Только внутри Kubernetes |
| kube-state-metrics | `diplom-monitoring` | Состояние объектов Kubernetes |
| node-exporter, по одному на узел | `diplom-monitoring` | Метрики узлов |

Traefik обслуживает стандартные Kubernetes Ingress. Сертификат и DNS-имя для обязательного HTTP-доступа из ТЗ не требуются. Prometheus, Alertmanager и панель управления Traefik не публикуются наружу. Для проверки Grafana с учётными данными скрипт использует локальный туннель через защищённое Kubernetes API.

Приложение запускается по digest приватного образа Container Registry. Доступ к образу узлы получают через уже назначенный сервисный аккаунт `diplom-terraform`; копировать облачный JSON-ключ в Kubernetes не требуется. У приложения нет токена Kubernetes API, процесс работает без root, корневая файловая система доступна только для чтения.

## Развёртывание

Нужны настроенный контекст `diplom`, kubectl 1.35.x и Helm 3.19.x. Подготовленные инструменты скрипт находит в `.tools` общего рабочего каталога; для другого размещения можно передать `-KubectlPath` и `-HelmPath`.

1. Скопировать `monitoring/secrets.example.ps1` в `monitoring/secrets.local.ps1`, если локального файла ещё нет.
2. Владелец самостоятельно задаёт в локальном файле уникальный пароль Grafana; пароль в Git и чат не передаётся.
3. Применить Terraform основного модуля: группа рабочих узлов должна разрешать NodePort 30080 и проверки балансировщика.
4. Из корня общего рабочего каталога выполнить:

```powershell
.\infrastructure\scripts\Deploy-Platform.ps1
.\infrastructure\scripts\Test-Platform.ps1
```

При отдельном checkout инфраструктуры команды начинаются с `.\scripts\`. Для поэтапного выполнения есть `-Part Base` (Traefik и приложение) и `-Part Monitoring` (мониторинг после готовности Base).

При повторном применении Base сохраняет текущий digest приложения, установленный релизным workflow. При первом создании используется стартовый образ из манифеста. Для явного выбора другой версии передай `-ApplicationImage` с полным адресом `cr.yandex/.../diplom-app@sha256:...`.

Скрипт сверяет архивы Helm с SHA256, выполняет серверную проверку приложения и ждёт готовности компонентов. Адрес балансировщика берётся из Service; Grafana `root_url` автоматически получает актуальный IP и `/grafana/`. Локальные кэш, адреса и результаты находятся в исключённом из Git `infrastructure/.tools/`.

Пароль передаётся в Secret через stdin и server-side apply, без записи заполненного манифеста на диск и без значения в аргументах процессов. Helm использует ссылку на готовый Secret. Повторное применение использует тот же локальный пароль. Для смены пароля уже работающего пользователя Grafana нужен отдельный сброс пароля: изменение одного bootstrap Secret не меняет пароль в существующей базе Grafana.

## Хранение и ресурсы

Подобраны небольшие запросы CPU/RAM для трёх узлов по 4 ГиБ. Prometheus хранит до суток истории и до 1 GB блоков, `emptyDir` ограничен 2 ГиБ. У Grafana и Alertmanager также временное хранилище. Это учебный вариант без новых платных дисков: текущие дисковые квоты заняты загрузочными дисками узлов.

После пересоздания соответствующего пода история метрик, локальные изменения Grafana и silences Alertmanager теряются. Дашборды, datasource и правила восстанавливаются из конфигураций; пароль начального администратора — из Secret. Для сохранения истории нужно отдельно согласовать и увеличить дисковые квоты, затем включить PVC.

Поскольку мастер управляется Yandex Cloud, сборщики scheduler/controller-manager/etcd/kube-proxy и соответствующие правила отключены: их закрытые endpoints не доступны внутри пользовательского кластера. Метрики API Kubernetes, kubelet/cAdvisor, kube-state-metrics, узлов и самого стека остаются включены.

## Проверка

`Test-Platform.ps1` проверяет публичный HTTP, метрики трёх узлов, две реплики приложения, доступность scrape targets, связь Grafana с Prometheus и наличие Kubernetes-дашбордов. Вход для проверки выполняется через локальный port-forward; после проверки туннель закрывается. Пароль и заголовки авторизации в журналы не сохраняются.

После установки открой `/grafana/`, войди с локальными данными и выбери дашборды `Kubernetes / Compute Resources / Cluster`, `Kubernetes / Compute Resources / Namespace (Pods)` и `Node Exporter / Nodes`. Для графиков CPU после свежего запуска может потребоваться несколько минут данных.

Требование автоматического Terraform pipeline выполняется на следующем этапе GitLab CI/CD. Его работа и скриншоты ещё не подтверждены.

## Удаление ресурсов после защиты

Сначала удалить Helm-релиз `diplom-ingress` и дождаться удаления его LoadBalancer в Yandex Cloud; затем удалить мониторинг, приложение и пространства имён диплома. После этого выполнять `terraform destroy` основного модуля. Не удалять вручную балансировщик, пока его Service существует: Kubernetes создаст его снова. Bootstrap с защищённым бакетом состояния уничтожать вместе с основным модулем нельзя.

## Источники

- [kube-prometheus-stack: состав и установка](https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/README.md).
- [Официальный Helm chart Traefik](https://github.com/traefik/traefik-helm-chart).
- [Service LoadBalancer в Yandex Managed Kubernetes](https://yandex.cloud/ru/docs/managed-kubernetes/operations/create-load-balancer).
- [Настройки Grafana и serve_from_sub_path](https://grafana.com/docs/grafana/latest/setup-grafana/configure-grafana/).
