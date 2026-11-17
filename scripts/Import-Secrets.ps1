[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Bootstrap', 'Infrastructure')]
    [string]$Mode
)

$ErrorActionPreference = 'Stop'
$configPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'secrets.local.ps1'
if (-not (Test-Path -LiteralPath $configPath)) {
    throw 'Сначала создай и заполни infrastructure/secrets.local.ps1 по шаблону.'
}

. $configPath

if ($Mode -eq 'Bootstrap') {
    if ([string]::IsNullOrWhiteSpace($env:YC_TOKEN)) {
        throw 'Заполни YC_TOKEN в локальном файле секретов.'
    }
    Remove-Item Env:YC_SERVICE_ACCOUNT_KEY_FILE -ErrorAction SilentlyContinue
    Remove-Item Env:AWS_ACCESS_KEY_ID -ErrorAction SilentlyContinue
    Remove-Item Env:AWS_SECRET_ACCESS_KEY -ErrorAction SilentlyContinue
} else {
    Remove-Item Env:YC_TOKEN -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($env:YC_SERVICE_ACCOUNT_KEY_FILE) -or
        -not (Test-Path -LiteralPath $env:YC_SERVICE_ACCOUNT_KEY_FILE -PathType Leaf)) {
        throw 'Укажи существующий JSON ключ аккаунта Terraform в YC_SERVICE_ACCOUNT_KEY_FILE.'
    }
    if ([string]::IsNullOrWhiteSpace($env:AWS_ACCESS_KEY_ID) -or
        [string]::IsNullOrWhiteSpace($env:AWS_SECRET_ACCESS_KEY)) {
        throw 'Заполни обе части статического S3-ключа в локальном файле секретов.'
    }
}

Write-Host "Окружение $Mode подготовлено. Значения секретов не выводятся."
