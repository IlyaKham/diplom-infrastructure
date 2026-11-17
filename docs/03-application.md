# Этап 3: приложение и Container Registry

Выбран Yandex Container Registry. Terraform-ресурс `yandex_container_registry.application` находится в `terraform/registry.tf`; состояние реестра хранится в существующем S3 backend основной инфраструктуры.

Фактически создан 17 ноября 2026 года: ID `crp85lbhbo07ldt2oj0c`. Загружен и повторно скачан образ `cr.yandex/crp85lbhbo07ldt2oj0c/diplom-app:0.1.0`, digest `sha256:a8ddcb81bd996cd1c8a70a0ee6b91661986666116f9e62309989f6e9c5f373d9`. Опубликованный образ проверен в Windows PowerShell 5.1. Результат и версия находятся в `application/docs/validation.md` отдельного репозитория приложения; [чек-лист](03-checklist.md).

API облака подтверждает статус реестра `ACTIVE` и соответствие тега `0.1.0` указанному digest. Публичных IAM bindings нет. Оба модуля проверены финальным `terraform plan -detailed-exitcode`: код 0, `No changes`. В основном удалённом state — 12 ресурсов. [Фактические результаты](evidence/03-application-results.txt), [создание реестра](evidence/11-registry-create.log), [финальный план](evidence/12-registry-final-plan.log), [план bootstrap](evidence/13-registry-bootstrap-plan.log).

Реестр называется `diplom-registry`, репозиторий образа — `diplom-app`. Доступ приватный, публичных IAM bindings нет. Приложение находится в отдельном каталоге/локальном Git-репозитории `application`, вне репозитория инфраструктуры.

## Права одного сервисного аккаунта

В `bootstrap/registry-iam.tf` добавлена только профильная роль `container-registry.editor` на каталог для существующего `diplom-terraform`. Она нужна Terraform для создания реестра и включает операции загрузки/скачивания образов. Новый сервисный аккаунт и новые ключи не создаются. Узлы Kubernetes уже используют этот же аккаунт и смогут скачивать приватный образ.

Роль назначается при применении bootstrap от имени владельца каталога. Основной Terraform по-прежнему работает через авторизованный ключ аккаунта диплома. Ключи и S3 credentials находятся только в локальных исключённых из Git файлах.

## Воспроизведение

1. Применить bootstrap с временным IAM-токеном владельца, как в инструкции первого этапа. План добавляет одну роль и не меняет аккаунт/бакет.
2. Подготовить окружение: `. .\infrastructure\scripts\Import-Secrets.ps1 -Mode Infrastructure`.
3. Выполнить план и применение основного модуля. Для перехода с этапа 2 ожидается только один новый реестр, без изменения сети и Kubernetes.
4. Получить ID: `.\.tools\terraform\terraform.exe '-chdir=infrastructure/terraform' output -raw container_registry_id`.
5. Собрать, проверить и опубликовать приложение по его README. Именованный профиль `.tools/yc/terraform.yaml` уже настроен на существующий ключ.

Основной модуль возвращает также `application_image_repository` — адрес без тега. Сборка образа выполняется средствами Docker, а не Terraform; реестр создаётся Terraform, как требует ТЗ.

## Проверка и отчёт

Сохраняем реальные журналы создания реестра, сборки, проверки и загрузки образа. Для скриншотов:

| Что показать | Имя файла в `docs/screenshots/` |
| --- | --- |
| Container Registry → `diplom-registry`, репозиторий `diplom-app`, тег и digest | `13-container-registry.png` |
| Собственный Dockerfile и успешная сборка | `14-application-build.png` |
| Локальная страница и версия сборки внизу | `15-application-local.png` |

Скриншоты сохраняются отдельно от текстовых журналов. Для просмотра страницы используй команду preview из README приложения. Не показывай JSON-ключи, временные токены, локальный файл секретов или конфигурацию входа Docker.

## Источники

- [Ресурс Terraform Container Registry](https://yandex.cloud/ru/docs/terraform/resources/container_registry).
- [Профильные роли Container Registry](https://yandex.cloud/ru/docs/container-registry/security/index).
- [Вход Docker с IAM-токеном](https://yandex.cloud/ru/docs/container-registry/operations/authentication).

После публикации образа следующим этапом будут мониторинг и развёртывание приложения. До этого приложение работает только при локальном запуске Docker.
