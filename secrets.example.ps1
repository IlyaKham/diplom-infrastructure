# Скопируй этот файл в secrets.local.ps1 в этой же папке.
# Значения вводит владелец облака. Не отправляй их в чат и не добавляй в Git.

# Для однократного bootstrap: временный IAM-токен владельца каталога.
# Получи самостоятельно из корня проекта после входа в yc:
# & .\.tools\yc\yc.exe --config .tools/yc/config.yaml iam create-token
$env:YC_TOKEN = '' # ВСТАВЬ IAM-ТОКЕН ДЛЯ BOOTSTRAP

# Для основной инфраструктуры: абсолютный путь к JSON авторизованного ключа
# аккаунта diplom-terraform. Сам JSON храни в infrastructure/secrets/.
$env:YC_SERVICE_ACCOUNT_KEY_FILE = Join-Path $PSScriptRoot 'secrets\terraform-sa-key.json'

# Для S3 backend: статический ключ того же аккаунта diplom-terraform.
$env:AWS_ACCESS_KEY_ID = ''     # ВСТАВЬ ИДЕНТИФИКАТОР СТАТИЧЕСКОГО КЛЮЧА
$env:AWS_SECRET_ACCESS_KEY = '' # ВСТАВЬ СЕКРЕТНУЮ ЧАСТЬ СТАТИЧЕСКОГО КЛЮЧА
