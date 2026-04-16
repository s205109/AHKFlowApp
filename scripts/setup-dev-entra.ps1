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
$entra = & $EntraScript -Environment dev
if (-not $entra -or -not $entra.ClientId) {
    throw "setup-entra-app.ps1 did not return a ClientId"
}

# Backend: user-secrets
$apiProject = Join-Path $RepoRoot 'src/Backend/AHKFlowApp.API'
dotnet user-secrets set 'AzureAd:TenantId' $entra.TenantId --project $apiProject | Out-Null
dotnet user-secrets set 'AzureAd:ClientId' $entra.ClientId --project $apiProject | Out-Null
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
