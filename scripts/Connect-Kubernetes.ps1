[CmdletBinding()]
param([string]$ClusterId)

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$tf = Join-Path $projectDir '.tools\terraform\terraform.exe'
$yc = Join-Path $projectDir '.tools\yc\yc.exe'
$kubectl = Join-Path $projectDir '.tools\kubectl\kubectl.exe'
$profilePath = Join-Path $projectDir '.tools\yc\terraform.yaml'
$workspaceConfig = Join-Path $projectDir '.tools\kubeconfig-diplom'
$defaultConfig = Join-Path $env:USERPROFILE '.kube\config'

& (Join-Path $PSScriptRoot 'Import-Secrets.ps1') -Mode Infrastructure
$terraformDir = Join-Path $projectDir 'infrastructure\terraform'
if ([string]::IsNullOrWhiteSpace($ClusterId)) {
    $ClusterId = (& $tf "-chdir=$terraformDir" output -raw kubernetes_cluster_id | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw 'Cannot read the Managed Kubernetes cluster ID from Terraform.'
    }
}
if ($ClusterId -notmatch '^[a-z0-9]{20}$') {
    throw 'Expected a Managed Kubernetes cluster ID with 20 characters.'
}

& $yc --config $profilePath config set service-account-key $env:YC_SERVICE_ACCOUNT_KEY_FILE | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Cannot prepare CLI authentication.' }
& $yc --config $profilePath --no-browser managed-kubernetes cluster get-credentials --id $clusterId --external --kubeconfig $workspaceConfig --context-name diplom --force
if ($LASTEXITCODE -ne 0) { throw 'Cannot obtain the cluster connection configuration.' }

# Оставляем один контекст проекта и динамический вход через ключ аккаунта.
$generatedRaw = & $kubectl --kubeconfig $workspaceConfig config view --raw -o json
if ($LASTEXITCODE -ne 0) { throw 'Cannot read generated kubeconfig.' }
$generated = $generatedRaw | ConvertFrom-Json
$context = @($generated.contexts | Where-Object name -eq 'diplom')
if ($context.Count -ne 1) { throw 'Expected Kubernetes context was not generated.' }
$cluster = @($generated.clusters | Where-Object name -eq $context[0].context.cluster)
if ($cluster.Count -ne 1) { throw 'Expected Kubernetes cluster was not generated.' }
$userName = 'diplom-' + $clusterId
$config = @{
    apiVersion = 'v1'
    kind = 'Config'
    preferences = @{}
    clusters = $cluster
    contexts = @(@{ name = 'diplom'; context = @{ cluster = $cluster[0].name; user = $userName } })
    'current-context' = 'diplom'
    users = @(@{
        name = $userName
        user = @{
            exec = @{
                apiVersion = 'client.authentication.k8s.io/v1beta1'
                command = $yc
                args = @('--config', $profilePath, '--no-browser', 'managed-kubernetes', 'create-token')
                interactiveMode = 'Never'
                provideClusterInfo = $false
            }
        }
    })
}
[System.IO.File]::WriteAllText($workspaceConfig, ($config | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))

& $kubectl --kubeconfig $workspaceConfig --request-timeout=30s get --raw=/readyz
if ($LASTEXITCODE -ne 0) { throw 'Kubernetes API is not ready or access was denied.' }
Write-Host ''

# Существующие контексты пользователя сохраняются при объединении.
$previousKubeconfig = $env:KUBECONFIG
try {
    if (Test-Path -LiteralPath $defaultConfig) {
        $backupPath = Join-Path $projectDir ('.tools\kubeconfig-before-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Copy-Item -LiteralPath $defaultConfig -Destination $backupPath
        $env:KUBECONFIG = $workspaceConfig + [System.IO.Path]::PathSeparator + $defaultConfig
        $merged = & $kubectl config view --raw --flatten -o json
        if ($LASTEXITCODE -ne 0) { throw 'Cannot merge existing Kubernetes contexts.' }
        $mergedText = $merged | Out-String
    } else {
        $mergedText = [System.IO.File]::ReadAllText($workspaceConfig)
    }
    New-Item -ItemType Directory -Path (Split-Path $defaultConfig -Parent) -Force | Out-Null
    [System.IO.File]::WriteAllText($defaultConfig, $mergedText, [System.Text.UTF8Encoding]::new($false))
} finally {
    $env:KUBECONFIG = $previousKubeconfig
    $generatedRaw = $null
    $generated = $null
    $merged = $null
}

Write-Host 'Kubernetes context diplom is ready in the default user kubeconfig.'
