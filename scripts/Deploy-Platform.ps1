[CmdletBinding()]
param(
    [ValidateSet('All', 'Base', 'Monitoring')]
    [string]$Part = 'All',
    [string]$Context = 'diplom',
    [string]$KubectlPath,
    [string]$HelmPath,
    [string]$ApplicationImage
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $repoRoot
$cacheRoot = Join-Path $repoRoot '.tools'
$chartDirectory = Join-Path $cacheRoot 'charts'
New-Item -ItemType Directory -Path $chartDirectory -Force | Out-Null
if (-not $KubectlPath) {
    $KubectlPath = Join-Path $workspaceRoot '.tools/kubectl/kubectl.exe'
    if (-not (Test-Path -LiteralPath $KubectlPath)) { $KubectlPath = 'kubectl' }
}
if (-not $HelmPath) {
    $HelmPath = Join-Path $workspaceRoot '.tools/helm/windows-amd64/helm.exe'
    if (-not (Test-Path -LiteralPath $HelmPath)) { $HelmPath = 'helm' }
}
$env:HELM_CONFIG_HOME = Join-Path $cacheRoot 'helm/config'
$env:HELM_CACHE_HOME = Join-Path $cacheRoot 'helm/cache'
$env:HELM_DATA_HOME = Join-Path $cacheRoot 'helm/data'
$charts = Get-Content (Join-Path $repoRoot 'kubernetes/charts.lock.json') -Raw | ConvertFrom-Json

function Get-PinnedChart($Chart) {
    $archive = Join-Path $chartDirectory ($Chart.name + '-' + $Chart.version + '.tgz')
    if (-not (Test-Path -LiteralPath $archive)) {
        & $HelmPath pull $Chart.name --repo $Chart.repository --version $Chart.version --destination $chartDirectory
        if ($LASTEXITCODE -ne 0) { throw ('Chart download failed: ' + $Chart.name) }
    }
    $actualHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $Chart.sha256) { throw ('Chart checksum mismatch: ' + $Chart.name) }
    return $archive
}

function Get-PublicAddress {
    for ($attempt = 0; $attempt -lt 72; $attempt++) {
        $serviceJson = & $KubectlPath --context $Context --request-timeout=30s -n diplom-ingress get service diplom-ingress -o json
        if ($LASTEXITCODE -ne 0) { throw 'Cannot read the ingress service.' }
        $service = $serviceJson | ConvertFrom-Json
        $address = @($service.status.loadBalancer.ingress | Where-Object ip | Select-Object -ExpandProperty ip)
        if ($address.Count -gt 0) { return $address[0] }
        if ($attempt % 6 -eq 0) { Write-Host 'Waiting for the public LoadBalancer address...' }
        Start-Sleep -Seconds 5
    }
    throw 'The public LoadBalancer did not receive an address in six minutes.'
}

& $KubectlPath --context $Context --request-timeout=30s get --raw=/readyz
if ($LASTEXITCODE -ne 0) { throw 'Kubernetes API is unavailable.' }
Write-Host ''

if ($Part -in @('All', 'Base')) {
    $ingressChart = Get-PinnedChart $charts.traefik
    & $KubectlPath --context $Context apply -f (Join-Path $repoRoot 'kubernetes/namespaces.yaml')
    if ($LASTEXITCODE -ne 0) { throw 'Namespace deployment failed.' }
    $existingDeploymentJson = & $KubectlPath --context $Context -n diplom-app get deployment diplom-app --ignore-not-found -o json
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the current application release.' }
    if (-not $ApplicationImage -and $existingDeploymentJson) {
        $existingDeployment = $existingDeploymentJson | ConvertFrom-Json
        $ApplicationImage = @($existingDeployment.spec.template.spec.containers | Where-Object name -eq nginx)[0].image
    }
    $applicationJson = & $KubectlPath --context $Context create --dry-run=client -k (Join-Path $repoRoot 'kubernetes/application') -o json
    if ($LASTEXITCODE -ne 0) { throw 'Cannot render the application manifest.' }
    $applicationManifest = $applicationJson | ConvertFrom-Json
    if ($ApplicationImage) {
        if ($ApplicationImage -notmatch '^cr\.yandex/[a-z0-9]{20}/diplom-app@sha256:[a-f0-9]{64}$') {
            throw 'ApplicationImage must be an immutable diplom-app digest in Yandex Container Registry.'
        }
        $deploymentManifest = @($applicationManifest.items | Where-Object { $_.kind -eq 'Deployment' -and $_.metadata.name -eq 'diplom-app' })
        if ($deploymentManifest.Count -ne 1) { throw 'Expected one application Deployment.' }
        @($deploymentManifest[0].spec.template.spec.containers | Where-Object name -eq nginx)[0].image = $ApplicationImage
    }
    $applicationJson = $applicationManifest | ConvertTo-Json -Depth 30
    $applicationJson | & $KubectlPath --context $Context apply --dry-run=server -f -
    if ($LASTEXITCODE -ne 0) { throw 'Application server validation failed.' }
    & $HelmPath upgrade --install diplom-ingress $ingressChart --namespace diplom-ingress `
        --kube-context $Context -f (Join-Path $repoRoot 'kubernetes/ingress/values.yaml') `
        --wait --timeout 8m --history-max 3
    if ($LASTEXITCODE -ne 0) { throw 'Ingress installation failed; inspect its pods and events.' }
    # Preserve a release deployed by Actions when reapplying platform settings.
    $applicationJson | & $KubectlPath --context $Context apply -f -
    if ($LASTEXITCODE -ne 0) { throw 'Application deployment failed.' }
    & $KubectlPath --context $Context -n diplom-app rollout status deployment/diplom-app --timeout=300s
    if ($LASTEXITCODE -ne 0) { throw 'Application rollout failed.' }
}

$publicAddress = Get-PublicAddress
$parsedAddress = $null
if (-not [Net.IPAddress]::TryParse($publicAddress, [ref]$parsedAddress) -or
    $parsedAddress.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
    throw 'Expected an IPv4 LoadBalancer address.'
}
$applicationUrl = "http://$publicAddress/"
$grafanaUrl = "http://$publicAddress/grafana/"

if ($Part -in @('All', 'Monitoring')) {
    $secretsPath = Join-Path $repoRoot 'kubernetes/monitoring/secrets.local.ps1'
    try { . $secretsPath } catch { throw 'Cannot load local Grafana credentials. Check the local file syntax.' }
    try {
        if ([string]::IsNullOrWhiteSpace($env:GRAFANA_ADMIN_USER) -or
            [string]::IsNullOrWhiteSpace($env:GRAFANA_ADMIN_PASSWORD) -or
            $env:GRAFANA_ADMIN_PASSWORD -like 'REPLACE_*' -or
            $env:GRAFANA_ADMIN_PASSWORD.Length -lt 12) {
            throw 'Fill the local Grafana credentials first; use a unique password of at least 12 characters.'
        }
        $monitoringChart = Get-PinnedChart $charts.monitoring
        $secret = @{
            apiVersion = 'v1'
            kind = 'Secret'
            metadata = @{ name = 'diplom-grafana-admin'; namespace = 'diplom-monitoring' }
            type = 'Opaque'
            data = @{
                'admin-user' = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($env:GRAFANA_ADMIN_USER))
                'admin-password' = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($env:GRAFANA_ADMIN_PASSWORD))
            }
        }
        # stdin avoids putting credentials in process arguments or a manifest file.
        # Server-side apply avoids storing a last-applied annotation with secret data.
        $secret | ConvertTo-Json -Depth 5 -Compress | & $KubectlPath --context $Context apply --server-side --field-manager=diplom-monitoring -f -
        if ($LASTEXITCODE -ne 0) { throw 'Grafana secret creation failed.' }

        $endpointValues = Join-Path $cacheRoot 'monitoring-endpoint.values.yaml'
        $endpointYaml = "grafana:`n  grafana.ini:`n    server:`n      domain: '$publicAddress'`n      root_url: '$grafanaUrl'`n"
        [IO.File]::WriteAllText($endpointValues, $endpointYaml, [Text.UTF8Encoding]::new($false))
        & $HelmPath upgrade --install diplom-monitoring $monitoringChart --namespace diplom-monitoring `
            --kube-context $Context -f (Join-Path $repoRoot 'kubernetes/monitoring/values.yaml') -f $endpointValues `
            --wait --timeout 8m --history-max 3
        if ($LASTEXITCODE -ne 0) { throw 'Monitoring installation failed; inspect its pods and events.' }
        & $KubectlPath --context $Context apply -f (Join-Path $repoRoot 'kubernetes/monitoring/ingress.yaml')
        if ($LASTEXITCODE -ne 0) { throw 'Grafana ingress deployment failed.' }
        & $KubectlPath --context $Context -n diplom-monitoring rollout status statefulset/prometheus-diplom-monitoring-prometheus --timeout=300s
        if ($LASTEXITCODE -ne 0) { throw 'Prometheus rollout failed.' }
        & $KubectlPath --context $Context -n diplom-monitoring rollout status statefulset/alertmanager-diplom-monitoring-alertmanager --timeout=300s
        if ($LASTEXITCODE -ne 0) { throw 'Alertmanager rollout failed.' }
    } finally {
        $secret = $null
        Remove-Item Env:GRAFANA_ADMIN_PASSWORD -ErrorAction SilentlyContinue
        Remove-Item Env:GRAFANA_ADMIN_USER -ErrorAction SilentlyContinue
    }
}

@{ application = $applicationUrl; grafana = $grafanaUrl; ingress_ip = $publicAddress } |
    ConvertTo-Json | Set-Content (Join-Path $cacheRoot 'platform-endpoints.json') -Encoding UTF8
Write-Host "Application: $applicationUrl"
if ($Part -ne 'Base') { Write-Host "Grafana: $grafanaUrl" }
