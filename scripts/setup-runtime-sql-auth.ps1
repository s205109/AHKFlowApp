#Requires -Version 5.1
<#
.SYNOPSIS
    Idempotent runtime SQL auth application setup for AHKFlowApp.

.DESCRIPTION
    Ensures a dedicated Microsoft Entra application and service principal exist
    for the hosted API runtime, then rotates a client secret for App Service
    environment credential-based SQL authentication.

.PARAMETER Environment
    Target environment: 'test' or 'prod'.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('test', 'prod')]
    [string]$Environment
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$displayName = "AHKFlowApp-SqlRuntime-$Environment"

Write-Host "Ensuring runtime SQL auth app exists: $displayName"

$app = az ad app list --display-name $displayName --query '[0]' -o json | ConvertFrom-Json
if (-not $app) {
    $app = az ad app create `
        --display-name $displayName `
        --sign-in-audience AzureADMyOrg `
        --query '{appId:appId,id:id,displayName:displayName}' `
        -o json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw "Failed to create runtime SQL auth app registration." }
    Write-Host "Created app registration: $($app.appId)"
} else {
    Write-Host "Found existing app registration: $($app.appId)"
}

$servicePrincipal = az ad sp list --filter "appId eq '$($app.appId)'" --query '[0]' -o json | ConvertFrom-Json
if (-not $servicePrincipal) {
    $servicePrincipal = az ad sp create --id $app.appId --query '{id:id,appId:appId,displayName:displayName}' -o json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw "Failed to create runtime SQL auth service principal." }
    Write-Host "Created service principal: $($servicePrincipal.id)"
} else {
    Write-Host "Found existing service principal: $($servicePrincipal.id)"
}

$secretDisplayName = "deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$clientSecret = az ad app credential reset `
    --id $app.appId `
    --append `
    --display-name $secretDisplayName `
    --years 2 `
    --query password `
    -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($clientSecret)) {
    throw "Failed to rotate runtime SQL auth client secret."
}

$tenantId = az account show --query tenantId -o tsv

[PSCustomObject]@{
    TenantId                 = $tenantId
    ClientId                 = [string]$app.appId
    ClientSecret             = [string]$clientSecret
    DisplayName              = [string]$displayName
    AppObjectId              = [string]$app.id
    ServicePrincipalObjectId = [string]$servicePrincipal.id
}
