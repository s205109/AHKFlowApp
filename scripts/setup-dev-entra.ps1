#Requires -Version 7
<#
.SYNOPSIS
    Configures local dev Entra ID app registration and wires local config.

.DESCRIPTION
    Idempotent. Calls setup-entra-app.ps1 -Environment dev, then:
      - Sets backend user-secrets (AzureAd:TenantId, AzureAd:ClientId)
      - Writes wwwroot/appsettings.Development.json for the Blazor frontend
    Safe to re-run.

.EXAMPLE
    .\setup-dev-entra.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent

$EntraScript = Join-Path $PSScriptRoot 'setup-entra-app.ps1'
$entraOutput = @(& $EntraScript -Environment dev)
$entra = $entraOutput | Where-Object {
    $_ -is [psobject] -and
    $_.PSObject.Properties['ClientId'] -and
    $_.ClientId
} | Select-Object -Last 1
if (-not $entra -or -not $entra.ClientId -or -not $entra.TenantId) {
    throw "setup-entra-app.ps1 did not return a valid Entra result with ClientId and TenantId"
}

# Backend: user-secrets
$apiProject = Join-Path $RepoRoot 'src/Backend/AHKFlowApp.API'
dotnet user-secrets set 'AzureAd:TenantId' $entra.TenantId --project $apiProject | Out-Null
if ($LASTEXITCODE -ne 0) { throw "dotnet user-secrets set AzureAd:TenantId failed (exit $LASTEXITCODE)" }
dotnet user-secrets set 'AzureAd:ClientId' $entra.ClientId --project $apiProject | Out-Null
if ($LASTEXITCODE -ne 0) { throw "dotnet user-secrets set AzureAd:ClientId failed (exit $LASTEXITCODE)" }
Write-Host "  Backend user-secrets set (AzureAd:TenantId, AzureAd:ClientId)"

# Frontend: appsettings.Development.json (gitignored)
$feSettings = Join-Path $RepoRoot 'src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Development.json'
$json = [ordered]@{
    ApiHttpClient = [ordered]@{ BaseAddress = 'http://localhost:5600' }
    AzureAd = [ordered]@{
        Authority         = "https://login.microsoftonline.com/$($entra.TenantId)"
        ClientId          = $entra.ClientId
        ValidateAuthority = $true
        DefaultScope      = $entra.DefaultScope
    }
}
$json | ConvertTo-Json -Depth 5 | Set-Content -Path $feSettings -Encoding UTF8
Write-Host "  Frontend appsettings.Development.json written"

Write-Host ""
Write-Host "Dev Entra setup complete." -ForegroundColor Green
