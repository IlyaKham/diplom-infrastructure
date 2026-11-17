[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ycPath = Join-Path $projectDir '.tools\yc\yc.exe'
$configPath = Join-Path $projectDir '.tools\yc\config.yaml'
$resultPath = Join-Path $projectDir '.tools\yc\login-result.json'

function Set-LocalParameter {
    param([string]$Path, [string]$Name, [string]$Value)

    $content = [System.IO.File]::ReadAllText($Path)
    $pattern = '(?m)^\s*' + [regex]::Escape($Name) + '\s*=\s*"[^"\r\n]*"'
    if (-not [regex]::IsMatch($content, $pattern)) {
        throw "Parameter $Name is missing in the local configuration."
    }
    $replacement = $Name + ' = "' + $Value + '"'
    $content = [regex]::Replace($content, $pattern, $replacement)
    [System.IO.File]::WriteAllText($Path, $content, [System.Text.UTF8Encoding]::new($false))
}

try {
    if (-not (Test-Path -LiteralPath $ycPath)) {
        throw 'Local Yandex Cloud CLI was not found.'
    }

    Write-Host 'Вход в Yandex Cloud для дипломного проекта.' -ForegroundColor Cyan
    Write-Host 'Введи данные входа самостоятельно. Выбери облако и каталог диплома.'
    Write-Host 'На этом шаге облачные ресурсы не создаются.'
    & $ycPath --config $configPath init
    if ($LASTEXITCODE -ne 0) {
        throw 'Yandex Cloud login did not complete successfully.'
    }

    $cloudId = (& $ycPath --config $configPath config get cloud-id | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $cloudId -notmatch '^[a-z0-9]{20}$') {
        throw 'Choose a cloud in the Yandex Cloud CLI profile.'
    }
    $folderId = (& $ycPath --config $configPath config get folder-id | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $folderId -notmatch '^[a-z0-9]{20}$') {
        throw 'Choose a diploma folder in the Yandex Cloud CLI profile.'
    }

    $bootstrapPath = Join-Path $projectDir 'infrastructure\bootstrap\terraform.tfvars'
    $infraPath = Join-Path $projectDir 'infrastructure\terraform\terraform.tfvars'
    $backendPath = Join-Path $projectDir 'infrastructure\terraform\backend.hcl'
    $bootstrapText = [System.IO.File]::ReadAllText($bootstrapPath)
    $existingAccount = [regex]::Match($bootstrapText, '(?m)^\s*existing_terraform_service_account_id\s*=\s*([^\r\n#]+)')
    if ($existingAccount.Success -and $existingAccount.Groups[1].Value.Trim() -ne 'null') {
        throw 'The configuration must use a new diploma service account (null).'
    }

    $bucketMatch = [regex]::Match($bootstrapText, '(?m)^\s*state_bucket_name\s*=\s*"([^"\r\n]+)"')
    if (-not $bucketMatch.Success) {
        throw 'state_bucket_name is missing in the bootstrap configuration.'
    }
    $bucketName = $bucketMatch.Groups[1].Value
    if ($bucketName -match '^(REPLACE|replace-)') {
        $bucketName = 'diplom-tfstate-' + [guid]::NewGuid().ToString('N').Substring(0, 12)
    }

    foreach ($path in @($bootstrapPath, $infraPath)) {
        Set-LocalParameter -Path $path -Name 'cloud_id' -Value $cloudId
        Set-LocalParameter -Path $path -Name 'folder_id' -Value $folderId
    }
    Set-LocalParameter -Path $bootstrapPath -Name 'state_bucket_name' -Value $bucketName
    Set-LocalParameter -Path $backendPath -Name 'bucket' -Value $bucketName

    @{ status = 'ready'; cloud_id = $cloudId; folder_id = $folderId; bucket_name = $bucketName } |
        ConvertTo-Json | Set-Content -LiteralPath $resultPath -Encoding utf8

    Write-Host 'Вход выполнен. Параметры облака и каталога сохранены в проекте.' -ForegroundColor Green
    Write-Host 'Аккаунты и бакет ещё не создавались. Вернись в чат и напиши: готово.'
} catch {
    @{ status = 'failed' } | ConvertTo-Json | Set-Content -LiteralPath $resultPath -Encoding utf8
    Write-Host 'Вход или подготовка параметров не завершены. Сообщи в чате, на каком шаге остановились.' -ForegroundColor Yellow
    Write-Host 'Не отправляй токены или ключи.'
    Write-Error $_
}
