# Скриншоты этапа 4

Сохраняй в `infrastructure/docs/screenshots/` после завершения проверок.

| Снимок | Что должно читаться | Файл |
| --- | --- | --- |
| Публичная страница приложения | HTTP-адрес балансировщика и версия приложения | `16-application-http.png` |
| Grafana: Kubernetes / Compute Resources / Cluster | Графики CPU/RAM и данные работающего кластера | `17-grafana-cluster.png` |
| Grafana: Node Exporter / Nodes | Один из трёх узлов, графики CPU/RAM/диска | `18-grafana-node.png` |
| Состояние Kubernetes | Приложение, Prometheus, Grafana, Alertmanager и три node-exporter Running/Ready | `19-platform-pods.png` |
| Helm-релизы | `diplom-ingress` и `diplom-monitoring`, статус deployed, закреплённые версии | `20-helm-releases.png` |

Пароль Grafana вводится владельцем. На снимках не должно быть файла секретов, токенов, ключей или вывода содержимого Secret.

Команды из корня рабочего каталога для собственного терминала:

```powershell
.\.tools\kubectl\kubectl.exe --context diplom -n diplom-app get pods -o wide
.\.tools\kubectl\kubectl.exe --context diplom -n diplom-monitoring get pods -o wide
.\.tools\helm\windows-amd64\helm.exe list --all-namespaces --kube-context diplom
```

Для повторного показа сохранённых фактических результатов после готовности этапа:

```powershell
Get-Content -Encoding UTF8 .\infrastructure\docs\evidence\04-monitoring-results.txt
```

Графики CPU требуют нескольких точек измерения: при свежем запуске подожди несколько минут и выбери диапазон Last 15 minutes. Скриншоты GitHub Actions pipeline будут сделаны отдельно на этапе 5.
