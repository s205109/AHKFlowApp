#Requires -Version 5.1
<#
.SYNOPSIS
    Idempotent Entra ID app registration setup for AHKFlowApp.

.PARAMETER Environment
    Target environment: dev, test, or prod.

.PARAMETER SwaHostname
    Static Web App default hostname (e.g. red-stone-abc123.azurestaticapps.net).
    If omitted, the script attempts to resolve it via `az staticwebapp show`.

.EXAMPLE
    .\setup-entra-app.ps1 -Environment dev

.EXAMPLE
    .\setup-entra-app.ps1 -Environment test -SwaHostname "red-stone-abc123.azurestaticapps.net"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('dev', 'test', 'prod')]
    [string] $Environment,

    [string] $SwaHostname
)

$ErrorActionPreference = 'Stop'
$displayName = "AHKFlowApp-$Environment"

# Safe wrapper around ConvertFrom-Json: az commands return empty stdout on
# missing-resource / transient failures, and ConvertFrom-Json on empty/non-JSON
# input throws under $ErrorActionPreference = 'Stop' — defeating retry loops.
function ConvertFrom-JsonSafe([string] $Json) {
    if ([string]::IsNullOrWhiteSpace($Json)) { return $null }
    try { return $Json | ConvertFrom-Json } catch { return $null }
}

# az rest --body '...' is unreliable on Windows PowerShell due to quoting.
# Write JSON to a temp file and use --body @file instead.
function Invoke-GraphPatch([string] $ObjectId, [string] $JsonBody) {
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($tmp, $JsonBody, [System.Text.Encoding]::UTF8)
        az rest --method PATCH `
            --uri "https://graph.microsoft.com/v1.0/applications/$ObjectId" `
            --headers 'Content-Type=application/json' `
            --body "@$tmp" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "az rest PATCH failed (exit $LASTEXITCODE)" }
    } finally {
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
}

function Wait-ForCondition([string] $Description, [scriptblock] $Condition, [int] $MaxAttempts = 12, [int] $DelaySeconds = 5) {
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        if (& $Condition) {
            if ($attempt -gt 1) {
                Write-Host "$Description verified"
            }

            return
        }

        if ($attempt -lt $MaxAttempts) {
            Write-Host "Waiting for $Description ..."
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    throw "$Description was not visible after $MaxAttempts attempts"
}

# ---------------------------------------------------------------------------
# Resolve or create the app registration
# ---------------------------------------------------------------------------
$existing = az ad app list --display-name $displayName --query '[0]' -o json | ConvertFrom-Json
if ($existing) {
    Write-Host "Found existing app: $displayName ($($existing.appId))"
    $appId = $existing.appId
    $objectId = $existing.id
} else {
    Write-Host "Creating app registration: $displayName"
    $app = az ad app create --display-name $displayName --query '{appId:appId,id:id}' -o json | ConvertFrom-Json
    $appId = $app.appId
    $objectId = $app.id
    Write-Host "Created: $appId"
}

$tenantId = az account show --query tenantId -o tsv

# ---------------------------------------------------------------------------
# Ensure service principal exists (az ad app create does not create one automatically;
# AADSTS500011 is thrown if the SP is missing when the app is used as an OAuth resource)
# ---------------------------------------------------------------------------
$existingSp = ConvertFrom-JsonSafe (az ad sp show --id $appId -o json 2>$null)
if (-not $existingSp) {
    Write-Host "Creating service principal for $appId ..."
    az ad sp create --id $appId | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "az ad sp create failed (exit $LASTEXITCODE)" }
    Write-Host "Service principal created"
} else {
    Write-Host "Service principal already exists"
}

Wait-ForCondition -Description "service principal" -MaxAttempts 18 -Condition {
    $sp = ConvertFrom-JsonSafe (az ad sp show --id $appId -o json 2>$null)
    return [bool]$sp.id
}

# ---------------------------------------------------------------------------
# Resolve SWA hostname
# ---------------------------------------------------------------------------
if (-not $SwaHostname -and $Environment -ne 'dev') {
    $swaName = "ahkflowapp-swa-$Environment"
    Write-Host "Resolving SWA hostname for $swaName ..."
    $SwaHostname = az staticwebapp show --name $swaName --query defaultHostname -o tsv 2>$null
}

# ---------------------------------------------------------------------------
# Build redirect URI lists
# ---------------------------------------------------------------------------
$redirectUris = @('http://localhost:5601/authentication/login-callback')
if ($Environment -eq 'dev') {
    $redirectUris += 'https://localhost:7601/authentication/login-callback'
}
if ($SwaHostname) {
    $redirectUris += "https://$SwaHostname/authentication/login-callback"
}

$logoutUris = $redirectUris -replace 'login-callback', 'logout-callback'

# ---------------------------------------------------------------------------
# Set identifier URI and redirect URIs
# ---------------------------------------------------------------------------
az ad app update `
    --id $objectId `
    --identifier-uris "api://$appId" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "az ad app update failed (exit $LASTEXITCODE)" }

$spaJson = @{ spa = @{ redirectUris = $redirectUris } } | ConvertTo-Json -Depth 5 -Compress
Invoke-GraphPatch -ObjectId $objectId -JsonBody $spaJson

Wait-ForCondition -Description "SPA redirect URIs" -Condition {
    $configuredUris = ConvertFrom-JsonSafe (az ad app show --id $objectId --query 'spa.redirectUris' -o json 2>$null)
    if (-not $configuredUris) {
        return $false
    }

    foreach ($uri in $redirectUris) {
        if ($uri -notin $configuredUris) {
            return $false
        }
    }

    return $true
}

Write-Host "Redirect URIs set: $($redirectUris -join ', ')"

# ---------------------------------------------------------------------------
# Ensure access_as_user oauth2PermissionScope exists
# NOTE: PATCHing api.oauth2PermissionScopes replaces the whole collection.
# Safe here because this is a bootstrap script for a single-purpose app that
# only needs one scope. If you later add extra scopes manually, update this
# block to merge rather than replace.
# ---------------------------------------------------------------------------
$scopeId = [guid]::NewGuid().ToString()
$scopeJson = @{
    api = @{
        oauth2PermissionScopes = @(
            @{
                id                      = $scopeId
                value                   = 'access_as_user'
                type                    = 'User'
                adminConsentDisplayName = 'Access AHKFlowApp as user'
                adminConsentDescription = 'Allows the app to access AHKFlowApp API on behalf of the signed-in user.'
                userConsentDisplayName  = 'Access AHKFlowApp'
                userConsentDescription  = 'Allows this app to access AHKFlowApp on your behalf.'
                isEnabled               = $true
            }
        )
    }
} | ConvertTo-Json -Depth 10 -Compress

# Only add if not already present
$currentScopes = ConvertFrom-JsonSafe (az ad app show --id $objectId --query 'api.oauth2PermissionScopes[].value' -o json 2>$null)
if ('access_as_user' -notin $currentScopes) {
    Invoke-GraphPatch -ObjectId $objectId -JsonBody $scopeJson
    Wait-ForCondition -Description "oauth2PermissionScope access_as_user" -Condition {
        $scopes = ConvertFrom-JsonSafe (az ad app show --id $objectId --query 'api.oauth2PermissionScopes[].value' -o json 2>$null)
        return 'access_as_user' -in $scopes
    }
    Write-Host "Added oauth2PermissionScope: access_as_user"
} else {
    Write-Host "Scope access_as_user already exists"
    $scopeId = az ad app show --id $objectId --query 'api.oauth2PermissionScopes[?value==`access_as_user`].id | [0]' -o tsv
}

# ---------------------------------------------------------------------------
# Pre-authorize the SPA (same app) for its own scope
# ---------------------------------------------------------------------------
$preAuthBody = @{
    api = @{
        preAuthorizedApplications = @(
            @{
                appId                  = $appId
                delegatedPermissionIds = @($scopeId)
            }
        )
    }
} | ConvertTo-Json -Depth 10 -Compress

Invoke-GraphPatch -ObjectId $objectId -JsonBody $preAuthBody

Wait-ForCondition -Description "pre-authorized SPA scope" -Condition {
    $preAuthorizedApps = ConvertFrom-JsonSafe (az ad app show --id $objectId --query 'api.preAuthorizedApplications' -o json 2>$null)
    if (-not $preAuthorizedApps) {
        return $false
    }

    foreach ($entry in $preAuthorizedApps) {
        if ($entry.appId -eq $appId -and $scopeId -in $entry.delegatedPermissionIds) {
            return $true
        }
    }

    return $false
}

Write-Host "Pre-authorized SPA ($appId) for scope $scopeId"

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
$defaultScope = "api://$appId/access_as_user"

Write-Host ""
Write-Host "===== AHKFlowApp Entra App Registration ($Environment) =====" -ForegroundColor Cyan
Write-Host "Client ID  : $appId"
Write-Host "Tenant ID  : $tenantId"
Write-Host "Default scope: $defaultScope"
Write-Host ""
Write-Host "--- Next steps ---" -ForegroundColor Yellow
if ($Environment -eq 'dev') {
    Write-Host "Run from the repo root:"
    Write-Host "  dotnet user-secrets set 'AzureAd:TenantId' '$tenantId' --project src/Backend/AHKFlowApp.API"
    Write-Host "  dotnet user-secrets set 'AzureAd:ClientId' '$appId' --project src/Backend/AHKFlowApp.API"
    Write-Host "Then update wwwroot/appsettings.Development.json in AHKFlowApp.UI.Blazor:"
    Write-Host "  Authority    = https://login.microsoftonline.com/$tenantId"
    Write-Host "  ClientId     = $appId"
    Write-Host "  DefaultScope = $defaultScope"
} else {
    Write-Host "Values wired into GitHub Variables automatically when invoked from deploy.ps1."
    Write-Host "To set manually:"
    $envUpper = $Environment.ToUpper()
    Write-Host "  gh variable set AZURE_AD_TENANT_ID_$envUpper --body '$tenantId'"
    Write-Host "  gh variable set AZURE_AD_CLIENT_ID_$envUpper --body '$appId'"
    Write-Host "  gh variable set AZURE_AD_DEFAULT_SCOPE_$envUpper --body '$defaultScope'"
}

# Emit result for programmatic callers (deploy.ps1, setup-dev-entra.ps1)
[PSCustomObject]@{
    ClientId     = $appId
    TenantId     = $tenantId
    DefaultScope = $defaultScope
}
