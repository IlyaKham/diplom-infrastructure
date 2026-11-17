[CmdletBinding()]
param(
    [string]$Context = 'diplom',
    [string]$KubectlPath,
    [int]$GrafanaLocalPort = 13000
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$cacheRoot = Join-Path $repoRoot '.tools'
if (-not $KubectlPath) {
    $KubectlPath = Join-Path (Split-Path -Parent $repoRoot) '.tools/kubectl/kubectl.exe'
    if (-not (Test-Path -LiteralPath $KubectlPath)) { $KubectlPath = (Get-Command kubectl).Source }
}

function Get-KubernetesJson([string[]]$Arguments) {
    $json = & $KubectlPath --context $Context --request-timeout=30s @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'A Kubernetes verification request failed.' }
    return ($json | ConvertFrom-Json)
}

function Get-PrometheusResult([string]$Query) {
    $uri = '/api/v1/namespaces/diplom-monitoring/services/http:diplom-monitoring-prometheus:9090/proxy/api/v1/query?query=' + [Uri]::EscapeDataString($Query)
    $response = Get-KubernetesJson @('get', '--raw', $uri)
    if ($response.status -ne 'success') { throw 'Prometheus query failed.' }
    return $response.data.result
}

$service = Get-KubernetesJson @('-n', 'diplom-ingress', 'get', 'service', 'diplom-ingress', '-o', 'json')
$address = @($service.status.loadBalancer.ingress | Where-Object ip)[0].ip
if (-not $address) { throw 'The LoadBalancer has no public address.' }
$baseUrl = "http://$address"
$page = Invoke-WebRequest "$baseUrl/" -UseBasicParsing -TimeoutSec 15
if ($page.StatusCode -ne 200 -or $page.Content -notmatch '<title>Diplom') { throw 'Public application page failed.' }
$appHealth = Invoke-RestMethod "$baseUrl/healthz" -TimeoutSec 15
if ($appHealth.Trim() -ne 'ok') { throw 'Public application health failed.' }
$version = Invoke-RestMethod "$baseUrl/version.json" -TimeoutSec 15
Write-Host "PASS public application HTTP 80: version $($version.version)"

$grafanaHealth = Invoke-RestMethod "$baseUrl/grafana/api/health" -TimeoutSec 15
if ($grafanaHealth.database -ne 'ok') { throw 'Public Grafana health failed.' }
$loginPage = Invoke-WebRequest "$baseUrl/grafana/login" -UseBasicParsing -TimeoutSec 15
if ($loginPage.StatusCode -ne 200 -or $loginPage.Content -notmatch 'Grafana') { throw 'Grafana login page failed.' }
Write-Host "PASS public Grafana HTTP 80: database ok, version $($grafanaHealth.version)"

$app = Get-KubernetesJson @('-n', 'diplom-app', 'get', 'deployment', 'diplom-app', '-o', 'json')
if ($app.status.availableReplicas -ne 2) { throw 'Expected two available application replicas.' }
$exporters = Get-KubernetesJson @('-n', 'diplom-monitoring', 'get', 'daemonset', 'diplom-node-exporter', '-o', 'json')
if ($exporters.status.numberReady -ne 3) { throw 'Expected three ready node exporters.' }

# Wait for enough scrapes to verify both inventory and CPU rate queries.
$nodeCount = 0
$exporterCount = 0
$cpuSeries = 0
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    $nodes = @(Get-PrometheusResult 'count(kube_node_info)')
    $nodeMetrics = @(Get-PrometheusResult 'count(node_uname_info)')
    $cpu = @(Get-PrometheusResult 'count(rate(container_cpu_usage_seconds_total{container!="",pod!=""}[2m]))')
    if ($nodes.Count -gt 0) { $nodeCount = [int]$nodes[0].value[1] }
    if ($nodeMetrics.Count -gt 0) { $exporterCount = [int]$nodeMetrics[0].value[1] }
    if ($cpu.Count -gt 0) { $cpuSeries = [int]$cpu[0].value[1] }
    if ($nodeCount -eq 3 -and $exporterCount -eq 3 -and $cpuSeries -gt 0) { break }
    Start-Sleep -Seconds 5
}
if ($nodeCount -ne 3 -or $exporterCount -ne 3 -or $cpuSeries -lt 1) { throw 'Cluster metric queries have insufficient data.' }
$targets = Get-KubernetesJson @('get', '--raw', '/api/v1/namespaces/diplom-monitoring/services/http:diplom-monitoring-prometheus:9090/proxy/api/v1/targets')
$activeTargets = @($targets.data.activeTargets)
$downTargets = @($activeTargets | Where-Object health -ne 'up')
if ($downTargets.Count -gt 0) {
    $downTargets | Select-Object scrapePool,health,lastError | ConvertTo-Json -Depth 3 | Write-Host
    throw 'Prometheus has unhealthy scrape targets.'
}
Write-Host "PASS Prometheus: $nodeCount Kubernetes nodes, $exporterCount node exporters, $cpuSeries CPU series, $($activeTargets.Count) healthy targets"

$forward = $null
try {
    try { . (Join-Path $repoRoot 'kubernetes/monitoring/secrets.local.ps1') } catch { throw 'Cannot load local Grafana credentials.' }
    if (-not $env:GRAFANA_ADMIN_PASSWORD -or $env:GRAFANA_ADMIN_PASSWORD -like 'REPLACE_*') { throw 'Fill the local Grafana credentials.' }
    $forwardArguments = @('--context', $Context, '-n', 'diplom-monitoring', 'port-forward', 'service/diplom-grafana', "${GrafanaLocalPort}:80", '--address', '127.0.0.1')
    $forward = Start-Process -FilePath $KubectlPath -ArgumentList $forwardArguments -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $cacheRoot 'grafana-forward.log') `
        -RedirectStandardError (Join-Path $cacheRoot 'grafana-forward-error.log') -PassThru
    $localUrl = "http://127.0.0.1:$GrafanaLocalPort/grafana"
    $tunnelReady = $false
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        if ($forward.HasExited) { throw 'The Grafana verification tunnel exited.' }
        try {
            $health = Invoke-RestMethod "$localUrl/api/health" -TimeoutSec 2
            if ($health.database -eq 'ok') { $tunnelReady = $true; break }
        } catch { Start-Sleep -Milliseconds 500 }
    }
    if (-not $tunnelReady) { throw 'The local Grafana tunnel is unavailable.' }
    if ($forward.HasExited) { throw 'The Grafana tunnel exited before authentication.' }
    $forwardLog = Get-Content (Join-Path $cacheRoot 'grafana-forward.log') -Raw
    if ($forwardLog -notmatch ("Forwarding from 127\.0\.0\.1:" + $GrafanaLocalPort + ' ->')) {
        throw 'The verification tunnel did not bind its expected local port.'
    }

    $basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($env:GRAFANA_ADMIN_USER + ':' + $env:GRAFANA_ADMIN_PASSWORD))
    $headers = @{ Authorization = 'Basic ' + $basic }
    # Windows PowerShell returns a REST JSON array as one pipeline object.
    $searchResponse = Invoke-RestMethod "$localUrl/api/search?type=dash-db&limit=200" -Headers $headers -TimeoutSec 20
    $dashboards = @($searchResponse)
    $kubernetesDashboards = @($dashboards | Where-Object title -like 'Kubernetes / *')
    if ($kubernetesDashboards.Count -lt 3) { throw 'Expected provisioned Kubernetes dashboards.' }
    $datasourceHealth = Invoke-RestMethod "$localUrl/api/datasources/uid/prometheus/health" -Headers $headers -TimeoutSec 20
    if ($datasourceHealth.status -ne 'OK') { throw 'Grafana cannot query Prometheus.' }
    $grafanaQuery = Invoke-RestMethod "$localUrl/api/datasources/proxy/uid/prometheus/api/v1/query?query=count%28kube_node_info%29" -Headers $headers -TimeoutSec 20
    if ($grafanaQuery.status -ne 'success' -or [int]$grafanaQuery.data.result[0].value[1] -ne 3) { throw 'Grafana datasource query failed.' }
    Write-Host "PASS Grafana login, Prometheus datasource and $($dashboards.Count) dashboards ($($kubernetesDashboards.Count) Kubernetes dashboards)"

    $report = [ordered]@{
        verified_at_utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        status = 'healthy'
        application_url = "$baseUrl/"
        application_version = $version.version
        application_available_replicas = $app.status.availableReplicas
        grafana_url = "$baseUrl/grafana/"
        grafana_version = $grafanaHealth.version
        grafana_login_verified = $true
        prometheus_datasource_verified = $true
        kubernetes_nodes = $nodeCount
        node_exporters = $exporterCount
        cpu_metric_series = $cpuSeries
        prometheus_healthy_targets = $activeTargets.Count
        prometheus_unhealthy_targets = $downTargets.Count
        dashboard_count = $dashboards.Count
        kubernetes_dashboard_count = $kubernetesDashboards.Count
        dashboards = @($dashboards | Select-Object title,uid)
    }
    $report | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $cacheRoot 'platform-verification.json') -Encoding UTF8
} finally {
    if ($forward -and -not $forward.HasExited) { $forward.Kill(); $forward.WaitForExit() }
    $headers = $null
    $basic = $null
    Remove-Item Env:GRAFANA_ADMIN_PASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:GRAFANA_ADMIN_USER -ErrorAction SilentlyContinue
}
Write-Host 'All platform checks passed; the verification tunnel is closed.'
