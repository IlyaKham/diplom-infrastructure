# Скриншоты для отчёта: этап 2

Делай снимки после завершения проверки: мастер Healthy/Running, три рабочих узла Ready. Сохраняй изображения в `infrastructure/docs/screenshots/`.

| Что показать | Что должно читаться | Имя файла |
| --- | --- | --- |
| Managed Kubernetes → `diplom-k8s` | Статус, версия, региональное размещение мастера в a/d/e | `07-kubernetes-cluster.png` |
| Группы узлов | Три группы `diplom-workers-ru-central1-a/d/e`, в каждой один узел | `08-kubernetes-node-groups.png` |
| Параметры рабочих ВМ | Прерываемость, 2 vCPU, 4 ГиБ RAM, доля CPU 20%; диск 64 ГиБ | `09-worker-resources.png` |
| Сеть | Три подсети диплома в a/d/e; подсеть e имеет CIDR `10.40.0.0/24` | `10-network-ade.png` |
| Результат kubectl | Три строки Ready и системные поды без ошибок | `11-kubectl.png` |
| Terraform | Завершённое создание и финальный `No changes` | `12-kubernetes-terraform.png` |

Квоты можно показать дополнительным снимком: HDD 64 ГиБ в a/d и SSD 64 ГиБ в e. Размещение a/d/e и разные типы дисков — результат проверки доступных квот, а не отступление от требования трёх зон.

## Команды для своего терминала

Из папки проекта после настройки доступа:

```powershell
.\.tools\kubectl\kubectl.exe config current-context
.\.tools\kubectl\kubectl.exe get nodes -o wide
.\.tools\kubectl\kubectl.exe get pods --all-namespaces
```

Для показа извлечённых реальных результатов после завершения этапа:

```powershell
Get-Content -Encoding UTF8 .\infrastructure\docs\evidence\02-kubernetes-results.txt
```

Файл с результатами формируется после фактической проверки. Скриншоты не должны содержать JSON-ключ, секреты, OAuth/IAM-токены или полный kubeconfig.

Не запускай `terraform destroy` для получения новых скриншотов: теперь основная конфигурация включает платный кластер и рабочие узлы. Результаты цикла удаления/создания сети первого этапа уже сохранены.
