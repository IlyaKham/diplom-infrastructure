# Этап 4: фактическая проверка

Проверено 17 ноября 2026 года. Приложение и мониторинг развёрнуты в `diplom-k8s`.

## Публичные адреса

| Сервис | Адрес | Проверка |
| --- | --- | --- |
| Приложение | [http://46.243.210.163/](http://46.243.210.163/) | HTTP 200, версия `0.1.0` |
| Проверка приложения | [http://46.243.210.163/healthz](http://46.243.210.163/healthz) | HTTP 200, `ok` |
| Grafana | [http://46.243.210.163/grafana/](http://46.243.210.163/grafana/) | Страница входа HTTP 200, база `ok`, версия `13.3.1` |

Логин Grafana — `admin`; пароль задан владельцем в локальном `kubernetes/monitoring/secrets.local.ps1`. В отчёте и репозитории пароль не публикуется. Проверка входа выполнена через временный локальный туннель Kubernetes; после проверки туннель закрыт.

## Развёрнутые компоненты

| Компонент | Результат |
| --- | --- |
| Traefik | Две реплики Ready, chart `42.4.0`, приложение `v3.7.18` |
| nginx-приложение | Две реплики Ready в a/d, приватный образ закреплён digest |
| kube-prometheus-stack | Chart `93.3.1`, оператор `v0.95.2` |
| Prometheus | `v3.16.0`, под 2/2 Ready на `diplom-worker-igon` |
| Grafana | `13.3.1`, под 3/3 Ready на `diplom-worker-ejyg` |
| Alertmanager | `v0.35.0`, под 2/2 Ready на `diplom-worker-acez` |
| kube-state-metrics и оператор | По одной готовой реплике |
| node-exporter | Три готовых пода, по одному на каждом узле |

Все 12 подов диплома находятся в Running/Ready и имеют нулевое число перезапусков. Штатные системные поды остаются работоспособны. Загрузка Alertmanager из `quay.io` на новый узел сначала завершилась сетевым таймаутом; повторная загрузка прошла, окончательная проверка выполнена после Ready.

Фактическое использование памяти узлов при проверке: 50%, 58%, 66% доступной Kubernetes памяти; CPU около 4%. Новых PVC и дисков не создавалось.

## Метрики и дашборды

Полный `Test-Platform.ps1` успешно выполнен в Windows PowerShell 5.1:

- Prometheus возвращает три `kube_node_info` и три `node_uname_info`.
- Запрос скорости CPU возвращает 54 временных ряда с данными.
- Все 22 scrape targets имеют `health=up`.
- Вход Grafana проверен с локальными учётными данными.
- Health datasource `prometheus` возвращает `OK`.
- Запрос через proxy datasource Grafana возвращает три узла Kubernetes.
- Найдено 25 дашбордов, в том числе 16 Kubernetes-дашбордов.

Дашборды автоматически восстановлены из конфигураций чарта. Значения метрик относятся к реальному кластеру, а не к демонстрационному источнику.

## Балансировщик и Terraform

Один внешний Network Load Balancer, ID `enpv4hbqdvcohvkhpc0j`, статус `ACTIVE`. Target group `enp6sbsvfbp2musub4hm` содержит три узла в a/d/e, все `HEALTHY`. Обработчик TCP 80 направляет трафик на NodePort 30080. Облачное имя с префиксом `k8s-` сгенерировано контроллером Kubernetes автоматически.

Роль `load-balancer.editor` назначена существующему единственному облачному аккаунту `diplom-terraform` через bootstrap: `1 added, 0 changed, 0 destroyed`. В Kubernetes чарты создают собственные внутренние ServiceAccount для RBAC; это не дополнительные сервисные аккаунты Yandex Cloud.

Группа рабочих узлов обновлена Terraform: `0 added, 1 changed, 0 destroyed`; вместо диапазона NodePort 30000–32767 разрешён только 30080. Ограничения API двумя собственными `/32` сохранены. После применения оба Terraform-модуля проверены с кодом 0, `No changes`. В основном state по-прежнему 12 ресурсов; балансировщиком и его target group управляет Service Kubernetes.

## Материалы отчёта

- [Итоговые результаты](evidence/04-monitoring-results.txt).
- [Автоматическая проверка HTTP, метрик и Grafana](evidence/14-platform-test.log).
- [Поды после завершения установки](evidence/15-platform-pods.log).
- [Использование ресурсов узлов](evidence/16-platform-node-usage.log).
- [Helm-релизы](evidence/17-platform-helm.json).
- [Структурированный результат и список дашбордов](evidence/18-platform-verification.json).
- [Применение сетевого ограничения](evidence/19-platform-security.log).
- [Финальный план основного модуля](evidence/20-platform-terraform-plan.log).
- [Финальный план bootstrap](evidence/21-platform-bootstrap-plan.log).
- [Параметры балансировщика](evidence/22-platform-load-balancer.json) и [целевые узлы](evidence/23-platform-targets.json).
- [Галерея шести скриншотов Grafana](04-gallery.md), выполненных владельцем.
- [Памятка по остальным скриншотам](04-screenshots.md).

Приложение, мониторинг и ручное воспроизведение этапа проверены. Автоматический Terraform pipeline, сборка по коммитам и развёртывание по тегам остаются для этапа 5 GitHub Actions. Репозитории пока локальные, удалённые GitHub-проекты не подключены.
