#Requires -Version 7
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

# az rest --body '...' is unreliable on Windows PowerShell due to quoting.
# Write JSON to a temp file and use --body @file instead.
function Invoke-GraphPatch([string] $ObjectId, [string] $JsonBody) {
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($tmp, $JsonBody, [System.Text.Encoding]::UTF8)
        az rest --method PATCH `
            --uri "https://graph.microsoft.com/v1.0/applications/$ObjectId" `
            --headers 'Content-Type=application/json' `
            --body "@$tmp"
        if ($LASTEXITCODE -ne 0) { throw "az rest PATCH failed (exit $LASTEXITCODE)" }
    } finally {
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
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
    --identifier-uris "api://$appId"

$spaJson = @{ spa = @{ redirectUris = $redirectUris } } | ConvertTo-Json -Depth 5 -Compress
Invoke-GraphPatch -ObjectId $objectId -JsonBody $spaJson

Write-Host "Redirect URIs set: $($redirectUris -join ', ')"

# ---------------------------------------------------------------------------
# Ensure access_as_user oauth2PermissionScope exists
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
$currentScopes = az ad app show --id $objectId --query 'api.oauth2PermissionScopes[].value' -o json | ConvertFrom-Json
if ('access_as_user' -notin $currentScopes) {
    Invoke-GraphPatch -ObjectId $objectId -JsonBody $scopeJson
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
    $envUpper = $Environment.ToUpper()
    Write-Host "gh variable set AZURE_AD_TENANT_ID_$envUpper --body '$tenantId'"
    Write-Host "gh variable set AZURE_AD_CLIENT_ID_$envUpper --body '$appId'"
    Write-Host "gh variable set AZURE_AD_DEFAULT_SCOPE_$envUpper --body '$defaultScope'"
}
