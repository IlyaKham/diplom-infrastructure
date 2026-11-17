# Этап 5: GitHub Actions

По уточнению владельца от 17 ноября 2026 года вместо GitLab CI используется разрешённый ТЗ GitHub Actions. Исходное задание сохранено без изменений.

Репозитории:

- [IlyaKham/diplom-infrastructure](https://github.com/IlyaKham/diplom-infrastructure).
- [IlyaKham/diplom-app](https://github.com/IlyaKham/diplom-app).

## Terraform

Workflow `.github/workflows/terraform.yml` проверяет оба модуля при pull request и запускает plan/apply основного модуля при каждом push в `main`. Применение автоматическое, без ручного подтверждения. Bootstrap управляет аккаунтом, бакетом и правами и применяется владельцем отдельно; его конфигурация также проходит validate.

Состояние основного модуля остаётся в существующем S3 bucket. Workflow не создаёт отдельное состояние. План хранится только во временной папке задания и применяется в том же job; state, plan и заполненные файлы credentials не загружаются в artifacts.

Изменения `main` применяются последовательно: `concurrency`, `cancel-in-progress: false`, `queue: max`. В очереди допускается до 100 запусков. Дополнительно используется блокировка S3 backend. Перед применением checkout получает актуальный `main`, чтобы ожидавший запуск не вернул устаревшую конфигурацию.

## Сборка приложения

Workflow приложения запускается при каждом push ветки или тега:

1. Собирает linux/amd64 из собственного Dockerfile с версией, SHA коммита и временем сборки.
2. Проверяет HTTP, healthz, JSON версии, CSS/JS, 404, UID и файловую систему только для чтения.
3. Входит в Yandex Container Registry существующим сервисным аккаунтом и публикует проверенный образ.
4. Записывает digest результата в output и summary задания.

Обычный коммит получает тег `sha-<полный SHA>`. Релизный тег, например `v1.0.0`, получает соответствующий тег образа и OCI version label. Тег релиза должен иметь вид `vX.Y.Z` или `vX.Y.Z-rc.1`. Сборка обычного коммита не изменяет приложение в кластере.

## Деплой релиза

После успешной публикации релизного образа job `deploy` автоматически обновляет только Deployment `diplom-app` по digest, ждёт rollout и проверяет публичный `/version.json`: версия и SHA должны совпасть с релизом.

Сборка и Terraform выполняются на GitHub-hosted Ubuntu 24.04. Деплой выполняет временный runner внутри Kubernetes, поскольку внешний Kubernetes API ограничен собственными IP. Глобально открывать API не требуется.

Для runner используется официальный Actions Runner Controller `0.15.1`, архивы чартов закреплены SHA256; образ runner `2.338.2` закреплён digest. Контроллер и listener работают постоянно, рабочий под создаётся только для задания и удаляется после него. `minRunners=0`, `maxRunners=1`. Новые ВМ, балансировщики и диски не создаются; Docker-in-Docker и привилегированные контейнеры не используются.

Runner использует внутренний ServiceAccount Kubernetes. RBAC разрешает get/watch/patch/update только Deployment `diplom-app` и просмотр подов его namespace. Прав на Secrets и другие namespaces у job нет. Долгоживущий GitHub PAT хранится отдельно в Kubernetes Secret для регистрации исполнителей; облачные ключи на deploy runner не передаются.

NetworkPolicy запрещает подам runner и приложения обращаться к адресу метаданных ВМ `169.254.169.254`, чтобы они не получали облачную учётную запись узла через metadata service. Доступ к GitHub и внутреннему Kubernetes API сохраняется.

## Настройка владельцем

[Таблица Secrets и Variables](../ci/secrets-reference.md). Владелец заполняет значения сам. Подготовленный `Configure-GitHub.ps1` передаёт существующие локальные ключи в зашифрованные Secrets через stdin, без значений в аргументах процессов или выводе. Список названий Secrets доступен для проверки, значения из GitHub обратно не читаются.

```powershell
.\infrastructure\scripts\Configure-GitHub.ps1
.\infrastructure\scripts\Install-GitHubRunner.ps1
```

Второй скрипт использует локальный `kubernetes/actions-runner/secrets.local.ps1`. Для него нужен fine-grained PAT только для `diplom-app`, с `Administration: Read and write`. Токен не сохраняется в репозиторий и не передаётся в чат.

При повторном применении `Deploy-Platform.ps1` сохраняется текущий digest приложения. Обновление настроек платформы не возвращает релиз на стартовый образ `0.1.0`.

## Доказательства

Локально проверены синтаксис workflow и Bash-скриптов, версия для обычного коммита и релизного тега, параметры Helm, инструменты официального runner и ограничения RBAC.

Используется `actionlint 1.7.12`. Его схема пока не знает новое поле `concurrency.queue`; игнорируется только соответствующая диагностика. Поддержка `queue: max` проверена по текущей официальной документации GitHub. Остальные проверки actionlint пройдены.

Полная приёмка требует реальных запусков Actions: Terraform на main, сборка по коммиту, сборка и деплой по тегу. Их ссылки, digest, новый SHA приложения и скриншоты добавляются после выполнения, а не подменяются локальными тестами.

## Источники

- [Workflow concurrency и очередь](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency).
- [Официальный Actions Runner Controller](https://docs.github.com/en/actions/how-tos/manage-runners/use-actions-runner-controller/deploy-runner-scale-sets).
- [Авторизация контроллера GitHub](https://docs.github.com/en/actions/how-tos/manage-runners/use-actions-runner-controller/authenticate-to-the-api).
- [GitHub CLI: шифрование Secrets до отправки](https://cli.github.com/manual/gh_secret_set).
