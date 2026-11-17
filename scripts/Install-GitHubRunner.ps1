[CmdletBinding()]
param(
    [ValidatePattern('^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
    [string]$ApplicationRepositoryUrl = 'https://github.com/IlyaKham/diplom-app',
    [string]$Context = 'diplom'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $repoRoot
$configuration = Join-Path $repoRoot 'kubernetes/actions-runner'
$kubectl = Join-Path $workspaceRoot '.tools/kubectl/kubectl.exe'
$helm = Join-Path $workspaceRoot '.tools/helm/windows-amd64/helm.exe'
$cache = Join-Path $repoRoot '.tools'
$chartDirectory = Join-Path $cache 'charts'
$env:HELM_CONFIG_HOME = Join-Path $cache 'helm/config'
$env:HELM_CACHE_HOME = Join-Path $cache 'helm/cache'
$env:HELM_DATA_HOME = Join-Path $cache 'helm/data'
New-Item -ItemType Directory -Path $chartDirectory -Force | Out-Null

try { . (Join-Path $configuration 'secrets.local.ps1') } catch { throw 'Cannot read the local GitHub runner token file.' }
try {
    if ([string]::IsNullOrWhiteSpace($env:GITHUB_RUNNER_PAT) -or $env:GITHUB_RUNNER_PAT -like 'REPLACE_*') {
        throw 'Enter the repository-scoped GitHub token in the local runner secrets file first.'
    }
    $chartResponse = Get-Content (Join-Path $configuration 'charts.lock.json') -Raw | ConvertFrom-Json
    $charts = @($chartResponse)
    foreach ($chart in $charts) {
        $archive = Join-Path $chartDirectory ($chart.name + '-' + $chart.version + '.tgz')
        if (-not (Test-Path -LiteralPath $archive)) {
            & $helm pull ($chart.repository + '/' + $chart.name) --version $chart.version --destination $chartDirectory
            if ($LASTEXITCODE -ne 0) { throw ('Cannot download chart: ' + $chart.name) }
        }
        if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $chart.sha256) {
            throw ('Chart checksum mismatch: ' + $chart.name)
        }
    }

    & $kubectl --context $Context apply -f (Join-Path $configuration 'namespaces.yaml')
    if ($LASTEXITCODE -ne 0) { throw 'Runner namespace creation failed.' }
    & $kubectl --context $Context apply -f (Join-Path $configuration 'rbac.yaml')
    if ($LASTEXITCODE -ne 0) { throw 'Runner RBAC creation failed.' }
    $secret = @{
        apiVersion='v1'; kind='Secret'; type='Opaque'
        metadata=@{name='diplom-github-auth';namespace='diplom-actions-runners'}
        data=@{github_token=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($env:GITHUB_RUNNER_PAT))}
    }
    $secret | ConvertTo-Json -Depth 4 -Compress | & $kubectl --context $Context apply --server-side --field-manager=diplom-actions -f -
    if ($LASTEXITCODE -ne 0) { throw 'Runner token Secret creation failed.' }

    $controllerChart = Join-Path $chartDirectory 'gha-runner-scale-set-controller-0.15.1.tgz'
    & $helm upgrade --install diplom-arc $controllerChart --namespace diplom-actions-system --kube-context $Context `
        -f (Join-Path $configuration 'controller.values.yaml') --wait --timeout 8m --history-max 3
    if ($LASTEXITCODE -ne 0) { throw 'Actions Runner Controller installation failed.' }

    $runnerChart = Join-Path $chartDirectory 'gha-runner-scale-set-0.15.1.tgz'
    & $helm upgrade --install diplom-deploy $runnerChart --namespace diplom-actions-runners --kube-context $Context `
        -f (Join-Path $configuration 'runner.values.yaml') --set-string "githubConfigUrl=$ApplicationRepositoryUrl" `
        --wait --timeout 8m --history-max 3
    if ($LASTEXITCODE -ne 0) { throw 'Runner scale set installation failed.' }

    & $kubectl --context $Context -n diplom-actions-system get pods
    if ($LASTEXITCODE -ne 0) { throw 'Controller status check failed.' }
    & $kubectl --context $Context -n diplom-actions-runners get autoscalingrunnersets
    if ($LASTEXITCODE -ne 0) { throw 'Runner scale set status check failed.' }
    Write-Host 'Runner scale set installed. The release workflow uses runs-on: diplom-deploy.'
} finally {
    $secret = $null
    Remove-Item Env:GITHUB_RUNNER_PAT -ErrorAction SilentlyContinue
}
