<#
.SYNOPSIS
    Tears down an AHKFlowApp Azure environment.

.DESCRIPTION
    Deletes the Azure resource group (and all resources in it), the Entra security group,
    and the GitHub secrets/variables for the specified environment.

    WARNING: This is destructive and irreversible — including the SQL database.

.PARAMETER Environment
    Target environment: 'test' or 'prod'. Prompts if not provided.

.EXAMPLE
    .\teardown.ps1
    .\teardown.ps1 -Environment test
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
function Write-Warn([string]$Message) { Write-Host "  ! $Message" -ForegroundColor Yellow }
function Write-Fail([string]$Message) { Write-Host "`n  ✗ $Message" -ForegroundColor Red }

# Load saved config
if (-not $Environment) {
    $Environment = Read-Host "  Environment [test/prod]"
    if ([string]::IsNullOrWhiteSpace($Environment)) { throw "Environment is required" }
}

$EnvFile = Join-Path $PSScriptRoot ".env.$Environment"
if (-not (Test-Path $EnvFile)) {
    Write-Fail "Config file not found: $EnvFile"
    Write-Host "  Nothing to tear down — deploy.ps1 was never run for this environment." -ForegroundColor Yellow
    exit 0
}

$config = @{}
Get-Content $EnvFile | Where-Object { $_ -match '^\s*[^#]' -and $_ -match '=' } | ForEach-Object {
    $parts = $_ -split '=', 2
    $config[$parts[0].Trim()] = $parts[1].Trim()
}

$ResourceGroup   = $config['RESOURCE_GROUP']
$SqlAdminGroup   = $config['SQL_ADMIN_GROUP']
$SqlAdminGroupId = $config['SQL_ADMIN_GROUP_ID']
$GitHubOrgRepo   = $config['GITHUB_ORG_REPO']
$EnvSuffix       = $Environment.ToUpper()

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Red
Write-Host "  AHKFlowApp — TEARDOWN ($Environment)" -ForegroundColor Red
Write-Host "==========================================================" -ForegroundColor Red
Write-Host ""
Write-Warn "This will permanently delete:"
Write-Host "    Resource group : $ResourceGroup (and ALL resources inside)"
Write-Host "    Entra group    : $SqlAdminGroup"
Write-Host "    GitHub secrets/variables for environment: $Environment"
Write-Host ""

$confirm = Read-Host "  Type the resource group name to confirm deletion"
if ($confirm -ne $ResourceGroup) {
    Write-Host "  Mismatch — aborted." -ForegroundColor Yellow
    exit 0
}

# Verify az login
$null = az account show 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Not logged into Azure. Run: az login"
    exit 1
}

# ---------------------------------------------------------------------------
# 1. Delete Azure resource group
# ---------------------------------------------------------------------------

Write-Step "Deleting resource group: $ResourceGroup..."
az group delete --name $ResourceGroup --yes --no-wait
if ($LASTEXITCODE -eq 0) {
    Write-Success "Resource group deletion started (async)"
    Write-Host "    Check: az group show --name $ResourceGroup" -ForegroundColor Gray
} else {
    Write-Warn "Resource group deletion may have failed — check Azure Portal"
}

# ---------------------------------------------------------------------------
# 2. Delete Entra security group
# ---------------------------------------------------------------------------

Write-Step "Deleting Entra security group: $SqlAdminGroup..."
if ($SqlAdminGroupId) {
    az ad group delete --group $SqlAdminGroupId 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Entra group deleted"
    } else {
        Write-Warn "Could not delete Entra group (may already be deleted)"
    }
} else {
    Write-Warn "No group ID in config — skipping Entra group deletion"
}

# ---------------------------------------------------------------------------
# 3. Clean up GitHub secrets and variables
# ---------------------------------------------------------------------------

Write-Step "Removing GitHub secrets and variables (environment: $Environment)..."

$secretsToDelete = @(
    "AZURE_CLIENT_ID_${EnvSuffix}",
    "AZURE_STATIC_WEB_APPS_API_TOKEN_${EnvSuffix}"
)

# Remove shared secrets only if this is the last environment
# (We leave AZURE_TENANT_ID and AZURE_SUBSCRIPTION_ID as they may serve other envs)
foreach ($secret in $secretsToDelete) {
    gh secret delete $secret --repo $GitHubOrgRepo 2>$null
    Write-Success "Deleted secret: $secret"
}

$variablesToDelete = @(
    "AZURE_RESOURCE_GROUP_${EnvSuffix}",
    "APP_SERVICE_NAME_${EnvSuffix}",
    "SQL_SERVER_NAME_${EnvSuffix}",
    "SQL_SERVER_FQDN_${EnvSuffix}",
    "SQL_DATABASE_NAME_${EnvSuffix}"
)
foreach ($variable in $variablesToDelete) {
    gh variable delete $variable --repo $GitHubOrgRepo 2>$null
    Write-Success "Deleted variable: $variable"
}

# ---------------------------------------------------------------------------
# 4. Remove local config file
# ---------------------------------------------------------------------------

Remove-Item $EnvFile -ErrorAction SilentlyContinue
Write-Success "Removed local config: .env.$Environment"

Write-Host ""
Write-Host "  Teardown complete." -ForegroundColor Green
Write-Host "  Note: Azure resource group deletion runs asynchronously."
Write-Host "  Verify with: az group show --name $ResourceGroup"
Write-Host ""
