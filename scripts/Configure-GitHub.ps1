[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
    [string]$InfrastructureRepository = 'IlyaKham/diplom-infrastructure',
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
    [string]$ApplicationRepository = 'IlyaKham/diplom-app'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$gh = (Get-Command gh -ErrorAction Stop).Source
$variables = Get-Content (Join-Path $repoRoot 'ci/variables.example.json') -Raw | ConvertFrom-Json

function Set-PrivateSecret([string]$Repository, [string]$Name, [string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { throw ('Empty local value for ' + $Name) }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $gh
    $start.Arguments = 'secret set ' + $Name + ' --repo ' + $Repository
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    [void]$process.Start()
    $outputTask = $process.StandardOutput.ReadToEndAsync()
    $errorTask = $process.StandardError.ReadToEndAsync()
    # Write without adding a newline to scalar S3 credentials.
    $process.StandardInput.Write($Value)
    $process.StandardInput.Close()
    $process.WaitForExit()
    [void]$outputTask.Result
    [void]$errorTask.Result
    if ($process.ExitCode -ne 0) { throw ('GitHub secret update failed: ' + $Repository + ' / ' + $Name) }
    $process.Dispose()
    Write-Host ('Configured encrypted Secret: ' + $Repository + ' / ' + $Name)
}

foreach ($repository in @($InfrastructureRepository, $ApplicationRepository)) {
    $metadataJson = & $gh repo view $repository --json nameWithOwner,viewerPermission
    if ($LASTEXITCODE -ne 0) { throw ('Cannot access GitHub repository: ' + $repository) }
    $metadata = $metadataJson | ConvertFrom-Json
    if ($metadata.viewerPermission -ne 'ADMIN') { throw ('Repository administrator permission required: ' + $repository) }
}

& (Join-Path $PSScriptRoot 'Import-Secrets.ps1') -Mode Infrastructure
try {
    $keyJson = [IO.File]::ReadAllText($env:YC_SERVICE_ACCOUNT_KEY_FILE)
    $key = $keyJson | ConvertFrom-Json
    if ($key.service_account_id -ne $variables.infrastructure.YC_SERVICE_ACCOUNT_ID) { throw 'The key belongs to another cloud account.' }

    $tfvarsPath = Join-Path $repoRoot 'terraform/terraform.tfvars'
    $tfvars = [IO.File]::ReadAllText($tfvarsPath)
    $match = [regex]::Match($tfvars, '(?ms)^\s*api_allowed_cidrs\s*=\s*\[(.*?)\]')
    if (-not $match.Success) { throw 'Cannot find the existing administrator CIDR array in local terraform.tfvars.' }
    $cidrMatches = [regex]::Matches($match.Groups[1].Value, '"(?<cidr>\d{1,3}(?:\.\d{1,3}){3}/32)"')
    $cidrs = @($cidrMatches | ForEach-Object { $_.Groups['cidr'].Value })
    if ($cidrs.Count -ne 2) { throw 'Expected the two existing administrator /32 addresses.' }
    $cidrsJson = ConvertTo-Json -InputObject $cidrs -Compress

    Set-PrivateSecret $InfrastructureRepository 'YC_SERVICE_ACCOUNT_KEY' $keyJson
    Set-PrivateSecret $InfrastructureRepository 'AWS_ACCESS_KEY_ID' $env:AWS_ACCESS_KEY_ID
    Set-PrivateSecret $InfrastructureRepository 'AWS_SECRET_ACCESS_KEY' $env:AWS_SECRET_ACCESS_KEY
    Set-PrivateSecret $InfrastructureRepository 'API_ALLOWED_CIDRS' $cidrsJson
    Set-PrivateSecret $ApplicationRepository 'YC_SERVICE_ACCOUNT_KEY' $keyJson

    foreach ($entry in @(@{ Repository=$InfrastructureRepository; Values=$variables.infrastructure }, @{ Repository=$ApplicationRepository; Values=$variables.application })) {
        foreach ($property in $entry.Values.PSObject.Properties) {
            & $gh variable set $property.Name --repo $entry.Repository --body ([string]$property.Value)
            if ($LASTEXITCODE -ne 0) { throw ('GitHub variable update failed: ' + $property.Name) }
            Write-Host ('Configured Variable: ' + $entry.Repository + ' / ' + $property.Name)
        }
    }
    Write-Host 'GitHub Actions settings are ready. Source code has not been pushed.'
} finally {
    $keyJson = $null
    $key = $null
    $tfvars = $null
    $cidrsJson = $null
    Remove-Item Env:AWS_ACCESS_KEY_ID -ErrorAction SilentlyContinue
    Remove-Item Env:AWS_SECRET_ACCESS_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:YC_SERVICE_ACCOUNT_KEY_FILE -ErrorAction SilentlyContinue
}
