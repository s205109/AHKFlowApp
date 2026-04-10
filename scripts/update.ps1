<#
.SYNOPSIS
    Updates AHKFlowApp to the latest release by pulling the newest container image.

.DESCRIPTION
    Reads the saved deployment config from scripts/.env.{environment}, fetches the
    latest container image tag from GHCR, sets it on the App Service, and health-checks.

.PARAMETER Environment
    Target environment: 'test' or 'prod'. Prompts if not provided.

.EXAMPLE
    .\update.ps1
    .\update.ps1 -Environment test
#>
[CmdletBinding()]
param(
    [ValidateSet('test', 'prod')]
    [string]$Environment
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step([string]$Message) { Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Write-Success([string]$Message) { Write-Host "  ✓ $Message" -ForegroundColor Green }
function Write-Fail([string]$Message) { Write-Host "`n  ✗ $Message" -ForegroundColor Red }

# Load saved config
if (-not $Environment) {
    $Environment = Read-Host "  Environment [test/prod] (default: test)"
    if ([string]::IsNullOrWhiteSpace($Environment)) { $Environment = 'test' }
}

$EnvFile = Join-Path $PSScriptRoot ".env.$Environment"
if (-not (Test-Path $EnvFile)) {
    Write-Fail "Config file not found: $EnvFile"
    Write-Host "  Run .\deploy.ps1 -Environment $Environment first." -ForegroundColor Yellow
    exit 1
}

$config = @{}
Get-Content $EnvFile | Where-Object { $_ -match '^\s*[^#]' -and $_ -match '=' } | ForEach-Object {
    $parts = $_ -split '=', 2
    $config[$parts[0].Trim()] = $parts[1].Trim()
}

$ResourceGroup    = $config['RESOURCE_GROUP']
$AppServiceName   = $config['APP_SERVICE_NAME']
$GitHubOrgRepo    = $config['GITHUB_ORG_REPO']
$AppHostname      = $config['APP_SERVICE_HOSTNAME']

Write-Step "Updating AHKFlowApp ($Environment)..."

# Verify az login
$null = az account show 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Not logged into Azure. Run: az login"
    exit 1
}
Write-Success "Azure login verified"

# Fetch the latest image tag from GHCR
$Owner = $GitHubOrgRepo -split '/' | Select-Object -First 1
$ImageName = "ghcr.io/${Owner}/ahkflowapp-api"
$Tag = "latest-${Environment}"
$ImageRef = "${ImageName}:${Tag}"

Write-Host "  Image: $ImageRef"

# Set the container image on the App Service
Write-Host "  Setting container image on App Service..."
az webapp config container set `
    --name $AppServiceName `
    --resource-group $ResourceGroup `
    --container-image-name $ImageRef `
    --container-registry-url "https://ghcr.io" | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Fail "Failed to set container image"; exit 1 }

az webapp restart --name $AppServiceName --resource-group $ResourceGroup | Out-Null
Write-Success "App Service restarted"

# Health check
$HealthUrl = "https://${AppHostname}/health"
Write-Host "  Health-checking: $HealthUrl"
$attempts = 12
for ($i = 1; $i -le $attempts; $i++) {
    try {
        $response = Invoke-RestMethod -Uri $HealthUrl -TimeoutSec 10
        Write-Success "Health check passed"
        break
    } catch {
        if ($i -eq $attempts) {
            Write-Fail "Health check failed after $attempts attempts."
            Write-Host "  Check logs: az webapp log tail --name $AppServiceName --resource-group $ResourceGroup" -ForegroundColor Yellow
            exit 1
        }
        Write-Host "  Attempt $i/$attempts failed, retrying in 15s..."
        Start-Sleep -Seconds 15
    }
}

Write-Host ""
Write-Host "  Update complete! API: https://$AppHostname" -ForegroundColor Green
