#Requires -Version 5.1
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
$entraOutput = @(& $EntraScript -Environment dev -SkipDevNextSteps)
$entra = $entraOutput | Where-Object {
    $_ -is [psobject] -and
    $_.PSObject.Properties['ClientId'] -and
    $_.ClientId
} | Select-Object -Last 1
if (-not $entra -or -not $entra.ClientId -or -not $entra.TenantId) {
    throw "setup-entra-app.ps1 did not return a valid Entra result with ClientId and TenantId"
}

# Backend: user-secrets (idempotent — only set when missing or different)
$apiProject = Join-Path $RepoRoot 'src/Backend/AHKFlowApp.API'

$currentSecrets = @{}
foreach ($line in @(dotnet user-secrets list --project $apiProject 2>$null)) {
    if ($line -match '^(?<k>[^=]+?)\s*=\s*(?<v>.*)$') {
        $currentSecrets[$Matches.k.Trim()] = $Matches.v.Trim()
    }
}

function Set-UserSecretIdempotent([string] $Key, [string] $Value) {
    if ($currentSecrets[$Key] -eq $Value) {
        Write-Host "  $Key already set"
        return
    }
    $action = if ($currentSecrets.ContainsKey($Key)) { 'updated' } else { 'set' }
    dotnet user-secrets set $Key $Value --project $apiProject | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "dotnet user-secrets set $Key failed (exit $LASTEXITCODE)" }
    Write-Host "  $Key $action"
}

Set-UserSecretIdempotent 'AzureAd:TenantId' $entra.TenantId
Set-UserSecretIdempotent 'AzureAd:ClientId' $entra.ClientId

# Frontend: appsettings.Development.json (gitignored) — only (re)write when missing or different
$feSettings = Join-Path $RepoRoot 'src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Development.json'
$json = [ordered]@{
    ApiHttpClient = [ordered]@{ BaseAddress = 'http://localhost:5600' }
    AzureAd = [ordered]@{
        Instance          = 'https://login.microsoftonline.com/'
        TenantId          = $entra.TenantId
        ClientId          = $entra.ClientId
        ValidateAuthority = $true
    }
}

$feUpToDate = $false
if (Test-Path $feSettings) {
    try {
        $existing = Get-Content -Path $feSettings -Raw | ConvertFrom-Json
        $feUpToDate = (
            $existing.ApiHttpClient.BaseAddress -eq 'http://localhost:5600' -and
            $existing.AzureAd.Instance -eq 'https://login.microsoftonline.com/' -and
            $existing.AzureAd.TenantId -eq $entra.TenantId -and
            $existing.AzureAd.ClientId -eq $entra.ClientId -and
            $existing.AzureAd.ValidateAuthority -eq $true
        )
    } catch { $feUpToDate = $false }
}

if ($feUpToDate) {
    Write-Host "  Frontend appsettings.Development.json already up to date"
} else {
    $action = if (Test-Path $feSettings) { 'updated' } else { 'written' }
    $json | ConvertTo-Json -Depth 5 | Set-Content -Path $feSettings -Encoding UTF8
    Write-Host "  Frontend appsettings.Development.json $action"
}

Write-Host ""
Write-Host "Dev Entra setup complete — backend secrets and frontend config are in place. No manual steps needed." -ForegroundColor Green
