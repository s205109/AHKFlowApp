#Requires -Version 5.1
<#
.SYNOPSIS
    Updates AHKFlowApp by publishing and package-deploying the current API code.

.DESCRIPTION
    Reads the saved deployment config from scripts/.env.{environment}, publishes
    the backend API from the current repository checkout, deploys the generated
    package to App Service, and health-checks the deployed site.

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
function Write-Success([string]$Message) { Write-Host "  + $Message" -ForegroundColor Green }
function Write-Fail([string]$Message) { Write-Host "`n  x $Message" -ForegroundColor Red }

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

$ResourceGroup = $config['RESOURCE_GROUP']
$AppServiceName = $config['APP_SERVICE_NAME']
$AppHostname = $config['APP_SERVICE_HOSTNAME']
$RepoRoot = Split-Path $PSScriptRoot -Parent

Write-Step "Updating AHKFlowApp ($Environment)..."

if (-not (Get-Command 'dotnet' -ErrorAction SilentlyContinue)) {
    Write-Fail ".NET SDK not found."
    exit 1
}

$null = az account show 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Not logged into Azure. Run: az login"
    exit 1
}
Write-Success "Azure login verified"

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("AHKFlowApp-api-update-" + [guid]::NewGuid().ToString('N'))
$publishDir = Join-Path $tempRoot 'publish'
$packagePath = Join-Path $tempRoot 'api-package.zip'

try {
    New-Item -ItemType Directory -Path $publishDir -Force | Out-Null

    Push-Location $RepoRoot

    Write-Host "  Publishing API package..."
    dotnet publish .\src\Backend\AHKFlowApp.API --configuration Release --output $publishDir
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "dotnet publish failed"
        exit 1
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($publishDir, $packagePath)

    Write-Host "  Deploying package to App Service..."
    az webapp deploy `
        --name $AppServiceName `
        --resource-group $ResourceGroup `
        --src-path $packagePath `
        --type zip | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Failed to deploy package to App Service"
        exit 1
    }

    az webapp restart --name $AppServiceName --resource-group $ResourceGroup | Out-Null
    Write-Success "App Service restarted"

    $HealthUrl = "https://${AppHostname}/health"
    Write-Host "  Health-checking: $HealthUrl"
    $attempts = 20
    $healthOk = $false
    for ($i = 1; $i -le $attempts; $i++) {
        try {
            $null = Invoke-RestMethod -Uri $HealthUrl -TimeoutSec 10
            Write-Success "Health check passed"
            $healthOk = $true
            break
        } catch {
            Write-Host "  Attempt $i/$attempts failed, retrying in 15s..."
            Start-Sleep -Seconds 15
        }
    }

    if (-not $healthOk) {
        Write-Fail "Health check failed after $attempts attempts."
        Write-Host "  App Service Free can cold-start slowly. Check logs: az webapp log tail --name $AppServiceName --resource-group $ResourceGroup" -ForegroundColor Yellow
        exit 1
    }

    Write-Host ""
    Write-Host "  Update complete! API: https://$AppHostname" -ForegroundColor Green
} finally {
    Pop-Location -ErrorAction SilentlyContinue
    Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
