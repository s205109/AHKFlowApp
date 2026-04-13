<#
.SYNOPSIS
    Provisions an AHKFlowApp Azure environment and configures CI/CD.

.DESCRIPTION
    Single entrypoint that provisions all Azure resources via Bicep, configures
    Entra ID, OIDC federation, SQL access, and GitHub secrets/variables.

    Run this once per environment (test or prod). It is idempotent — safe to re-run.

.PARAMETER Environment
    Target environment: 'test' or 'prod'. Prompts interactively if not provided.

.EXAMPLE
    .\deploy.ps1
    .\deploy.ps1 -Environment test
#>
[CmdletBinding()]
param(
    [ValidateSet('test', 'prod')]
    [string]$Environment
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Success([string]$Message) {
    Write-Host "  ✓ $Message" -ForegroundColor Green
}

function Write-Warn([string]$Message) {
    Write-Host "  ! $Message" -ForegroundColor Yellow
}

function Write-Fail([string]$Message) {
    Write-Host "`n  ✗ $Message" -ForegroundColor Red
}

function Confirm-Command([string]$Name, [string]$InstallUrl) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Write-Fail "$Name is not installed."
        Write-Host "    Install from: $InstallUrl" -ForegroundColor Yellow
        throw "Missing prerequisite: $Name"
    }
    Write-Success "$Name found"
}

function Invoke-Az {
    $output = az @args 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "az $($args -join ' ') failed:`n$output"
    }
    return $output
}

function Invoke-Az-Json {
    $raw = az @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "az $($args -join ' ') failed:`n$raw" }
    return $raw | ConvertFrom-Json
}

# Run an az command that is expected to sometimes return "not found" (exit code 1).
# Returns the output string on success, $null on failure.
# Uses $ErrorActionPreference = 'Continue' to prevent PowerShell from treating
# native command stderr as a terminating error when $ErrorActionPreference = 'Stop'.
function Try-Az {
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = az @args 2>&1
        if ($LASTEXITCODE -ne 0) { return $null }
        return $output
    } finally {
        $ErrorActionPreference = $prevEap
    }
}

# ---------------------------------------------------------------------------
# Phase 1: Prerequisites
# ---------------------------------------------------------------------------

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "  AHKFlowApp — Azure Provisioning Script" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

Write-Step "Phase 1: Checking prerequisites..."

Confirm-Command 'az'       'https://learn.microsoft.com/cli/azure/install-azure-cli'
Confirm-Command 'gh'       'https://cli.github.com/'
Confirm-Command 'dotnet'   'https://dotnet.microsoft.com/download'

# Verify az login
try {
    $account = Invoke-Az-Json account show
    Write-Success "Logged into Azure as $($account.user.name) (subscription: $($account.name))"
} catch {
    Write-Fail "Not logged into Azure. Run: az login"
    throw
}

# Verify gh auth
$ghStatus = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Fail "GitHub CLI not authenticated. Run: gh auth login"
    throw "GitHub CLI not authenticated"
}
Write-Success "GitHub CLI authenticated"

# Verify sqlcmd (optional — we fall back to portal instructions)
$hasSqlcmd = [bool](Get-Command 'sqlcmd' -ErrorAction SilentlyContinue)
if ($hasSqlcmd) {
    Write-Success "sqlcmd found (will use for SQL user creation)"
} else {
    Write-Warn "sqlcmd not found — SQL user creation step will print manual instructions"
    Write-Warn "Install: https://learn.microsoft.com/sql/tools/sqlcmd/sqlcmd-utility"
}

# ---------------------------------------------------------------------------
# Phase 2: Gather Configuration
# ---------------------------------------------------------------------------

Write-Step "Phase 2: Gathering configuration..."

if (-not $Environment) {
    $Environment = Read-Host "  Environment [test/prod] (default: test)"
    if ([string]::IsNullOrWhiteSpace($Environment)) { $Environment = 'test' }
    if ($Environment -notin @('test', 'prod')) { throw "Environment must be 'test' or 'prod'" }
}

$Location = Read-Host "  Azure region (default: westeurope)"
if ([string]::IsNullOrWhiteSpace($Location)) { $Location = 'westeurope' }

$BaseName = Read-Host "  Base name (default: ahkflowapp)"
if ([string]::IsNullOrWhiteSpace($BaseName)) { $BaseName = 'ahkflowapp' }

# Auto-detect GitHub org/repo from git remote
$GitRemote = git remote get-url origin 2>$null
$GitHubOrgRepo = if ($GitRemote -match 'github\.com[:/](.+?)(?:\.git)?$') { $Matches[1] } else { '' }
if ($GitHubOrgRepo) {
    $GitHubInput = Read-Host "  GitHub org/repo (detected: $GitHubOrgRepo)"
    if (-not [string]::IsNullOrWhiteSpace($GitHubInput)) { $GitHubOrgRepo = $GitHubInput }
} else {
    $GitHubOrgRepo = Read-Host "  GitHub org/repo (e.g. myorg/AHKFlowApp)"
}
if (-not $GitHubOrgRepo) { throw "GitHub org/repo is required" }

# Derived values
$ResourceGroup     = "rg-${BaseName}-${Environment}"
$SqlAdminGroup     = "${BaseName}-sql-admins-${Environment}"
$EnvSuffix         = $Environment.ToUpper()
$AspnetcoreEnv     = if ($Environment -eq 'prod') { 'Production' } else { 'Test' }
$RepoRoot          = Split-Path $PSScriptRoot -Parent

Write-Host ""
Write-Host "  Summary:" -ForegroundColor White
Write-Host "    Environment    : $Environment"
Write-Host "    Location       : $Location"
Write-Host "    Base name      : $BaseName"
Write-Host "    Resource group : $ResourceGroup"
Write-Host "    GitHub repo    : $GitHubOrgRepo"
Write-Host "    Subscription   : $($account.name) ($($account.id))"
Write-Host ""

$confirm = Read-Host "  Proceed? [y/N]"
if ($confirm -notmatch '^[Yy]') { Write-Host "Aborted."; exit 0 }

# ---------------------------------------------------------------------------
# Phase 3: Provision Azure Resources (Bicep)
# ---------------------------------------------------------------------------

Write-Step "Phase 3: Provisioning Azure resources via Bicep..."

# Resource group
$rgExists = (az group exists --name $ResourceGroup) -eq 'true'
if (-not $rgExists) {
    Write-Host "  Creating resource group '$ResourceGroup' in '$Location'..."
    Invoke-Az group create --name $ResourceGroup --location $Location | Out-Null
}
Write-Success "Resource group: $ResourceGroup"

# Entra security group for SQL admin (must exist before Bicep runs)
$GroupId = az ad group list --filter "displayName eq '$SqlAdminGroup'" --query "[0].id" -o tsv
if (-not $GroupId) {
    Write-Host "  Creating Entra security group '$SqlAdminGroup'..."
    $GroupId = (Invoke-Az-Json ad group create --display-name $SqlAdminGroup --mail-nickname $SqlAdminGroup).id
}
Write-Success "Entra group: $SqlAdminGroup ($GroupId)"

# Add current user to the SQL admin group
$MeId = (Invoke-Az-Json ad signed-in-user show).id
$isMember = az ad group member check --group $GroupId --member-id $MeId --query value -o tsv
if ($isMember -ne 'true') {
    Invoke-Az ad group member add --group $GroupId --member-id $MeId | Out-Null
    Write-Success "Added current user to SQL admin group"
} else {
    Write-Success "Current user already in SQL admin group"
}

# Deploy Bicep
Write-Host "  Deploying Bicep template (this may take 3-5 minutes)..."
$BicepTemplate = Join-Path $RepoRoot "infra\main.bicep"
$DeploymentName = "deploy-${Environment}-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

$DeployOutput = Invoke-Az-Json deployment group create `
    --resource-group $ResourceGroup `
    --name $DeploymentName `
    --template-file $BicepTemplate `
    --parameters `
        environment=$Environment `
        location=$Location `
        baseName=$BaseName `
        sqlAdminGroupId=$GroupId `
        sqlAdminGroupName=$SqlAdminGroup

$outputs = $DeployOutput.properties.outputs

$DeployerUamiName       = $outputs.deployerUamiName.value
$DeployerUamiId         = $outputs.deployerUamiId.value
$DeployerUamiClientId   = $outputs.deployerUamiClientId.value
$DeployerUamiPrincipalId = $outputs.deployerUamiPrincipalId.value
$RuntimeUamiName        = $outputs.runtimeUamiName.value
$RuntimeUamiId          = $outputs.runtimeUamiId.value
$RuntimeUamiClientId    = $outputs.runtimeUamiClientId.value
$RuntimeUamiPrincipalId = $outputs.runtimeUamiPrincipalId.value
$SqlServerName          = $outputs.sqlServerName.value
$SqlServerFqdn          = $outputs.sqlServerFqdn.value
$SqlDatabaseName        = $outputs.sqlDatabaseName.value
$AppServiceName         = $outputs.appServiceName.value
$AppServiceHostname     = $outputs.appServiceDefaultHostname.value
$SwaName                = $outputs.swaName.value
$SwaHostname            = $outputs.swaDefaultHostname.value
$AppInsightsName        = $outputs.appInsightsName.value
$AppInsightsConnStr     = $outputs.appInsightsConnectionString.value

Write-Success "Bicep deployment complete"

# ---------------------------------------------------------------------------
# Phase 4: Entra & OIDC Configuration
# ---------------------------------------------------------------------------

Write-Step "Phase 4: Configuring Entra ID and OIDC federation..."

$TenantId        = (Invoke-Az-Json account show).tenantId
$SubscriptionId  = (Invoke-Az-Json account show).id
$RgScope         = (Invoke-Az-Json group show --name $ResourceGroup).id

# Federated identity credentials — main branch
$credNameMain = "gh-$(($GitHubOrgRepo -split '/')[-1])-main"
$existingCred = Try-Az identity federated-credential show `
    --name $credNameMain --identity-name $DeployerUamiName `
    --resource-group $ResourceGroup
if (-not $existingCred) {
    Invoke-Az identity federated-credential create `
        --name $credNameMain `
        --identity-name $DeployerUamiName `
        --resource-group $ResourceGroup `
        --issuer "https://token.actions.githubusercontent.com" `
        --subject "repo:${GitHubOrgRepo}:ref:refs/heads/main" `
        --audiences "api://AzureADTokenExchange" | Out-Null
    Write-Success "Created federated credential: main branch"
} else {
    Write-Success "Federated credential already exists: main branch"
}

# Federated identity credentials — pull_request
$credNamePr = "gh-$(($GitHubOrgRepo -split '/')[-1])-pull-request"
$existingCredPr = Try-Az identity federated-credential show `
    --name $credNamePr --identity-name $DeployerUamiName `
    --resource-group $ResourceGroup
if (-not $existingCredPr) {
    Invoke-Az identity federated-credential create `
        --name $credNamePr `
        --identity-name $DeployerUamiName `
        --resource-group $ResourceGroup `
        --issuer "https://token.actions.githubusercontent.com" `
        --subject "repo:${GitHubOrgRepo}:pull_request" `
        --audiences "api://AzureADTokenExchange" | Out-Null
    Write-Success "Created federated credential: pull_request"
} else {
    Write-Success "Federated credential already exists: pull_request"
}

# Contributor role on RG for deployer UAMI
$existingRole = az role assignment list `
    --assignee $DeployerUamiPrincipalId `
    --role "Contributor" --scope $RgScope --query "[0].id" -o tsv
if (-not $existingRole) {
    Invoke-Az role assignment create `
        --role "Contributor" `
        --assignee-object-id $DeployerUamiPrincipalId `
        --assignee-principal-type ServicePrincipal `
        --scope $RgScope | Out-Null
    Write-Success "Assigned Contributor role to deployer UAMI on resource group"
} else {
    Write-Success "Contributor role already assigned to deployer UAMI"
}

# Add deployer UAMI to SQL admin group
$deployerMember = az ad group member check `
    --group $GroupId --member-id $DeployerUamiPrincipalId --query value -o tsv
if ($deployerMember -ne 'true') {
    Invoke-Az ad group member add --group $GroupId --member-id $DeployerUamiPrincipalId | Out-Null
    Write-Success "Added deployer UAMI to SQL admin group"
} else {
    Write-Success "Deployer UAMI already in SQL admin group"
}

Write-Warn "Waiting 30s for Entra group membership to propagate..."
Start-Sleep -Seconds 30

# ---------------------------------------------------------------------------
# Phase 5: SQL User Setup
# ---------------------------------------------------------------------------

Write-Step "Phase 5: Creating SQL user for runtime UAMI..."

# Add current public IP to SQL firewall (temporary)
$MyIp = (Invoke-RestMethod -Uri 'https://api.ipify.org')
$FirewallRuleName = "operator-deploy-$(Get-Date -Format 'yyyyMMddHHmmss')"
Invoke-Az sql server firewall-rule create `
    --resource-group $ResourceGroup `
    --server $SqlServerName `
    --name $FirewallRuleName `
    --start-ip-address $MyIp `
    --end-ip-address $MyIp | Out-Null
Write-Success "Added temporary firewall rule for $MyIp"

try {
    $sqlScript = @"
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$RuntimeUamiName')
BEGIN
    CREATE USER [$RuntimeUamiName] FROM EXTERNAL PROVIDER;
END
IF IS_ROLEMEMBER('db_datareader', '$RuntimeUamiName') = 0
    ALTER ROLE db_datareader ADD MEMBER [$RuntimeUamiName];
IF IS_ROLEMEMBER('db_datawriter', '$RuntimeUamiName') = 0
    ALTER ROLE db_datawriter ADD MEMBER [$RuntimeUamiName];
GRANT EXECUTE TO [$RuntimeUamiName];
"@

    if ($hasSqlcmd) {
        $tmpSql = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.sql'
        $sqlScript | Set-Content -Path $tmpSql -Encoding UTF8

        # -G -U <email> = Active Directory Interactive auth (uses the Azure CLI logged-in
        # account, not Windows Kerberos). Avoids "Failed to resolve UPN" errors that occur
        # when the local Windows account isn't domain-joined to Entra ID.
        $userEmail = az account show --query user.name -o tsv

        Write-Host ""
        Write-Host "  ┌─────────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
        Write-Host "  │  ACTION REQUIRED: Browser authentication window opening...      │" -ForegroundColor Cyan
        Write-Host "  │                                                                 │" -ForegroundColor Cyan
        Write-Host "  │  sqlcmd will open a Microsoft Entra login window to connect     │" -ForegroundColor Cyan
        Write-Host "  │$("  to Azure SQL. Please sign in with: $userEmail".PadRight(65))│" -ForegroundColor Cyan
        Write-Host "  │                                                                 │" -ForegroundColor Cyan
        Write-Host "  │  The window may appear BEHIND this terminal — check your        │" -ForegroundColor Cyan
        Write-Host "  │  taskbar if nothing appears on screen.                          │" -ForegroundColor Cyan
        Write-Host "  │                                                                 │" -ForegroundColor Cyan
        Write-Host "  │  If you close the window without signing in, sqlcmd will fail   │" -ForegroundColor Cyan
        Write-Host "  │  and the script will print manual Portal instructions instead.  │" -ForegroundColor Cyan
        Write-Host "  └─────────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
        Write-Host ""

        sqlcmd -S $SqlServerFqdn -d $SqlDatabaseName -G -U $userEmail -i $tmpSql
        $sqlcmdExitCode = $LASTEXITCODE

        Remove-Item $tmpSql -ErrorAction SilentlyContinue

        if ($sqlcmdExitCode -eq 0) {
            Write-Success "SQL user '$RuntimeUamiName' created/verified via sqlcmd"
        } else {
            Write-Warn "sqlcmd could not authenticate. Create the SQL user manually in the Azure Portal:"
            Write-Host "    URL: https://portal.azure.com" -ForegroundColor Yellow
            Write-Host "    Navigate to: SQL Database '$SqlDatabaseName' > Query Editor" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "    Run this SQL:" -ForegroundColor Yellow
            Write-Host $sqlScript -ForegroundColor Gray
            Read-Host "`n  Press Enter once you have created the SQL user..."
        }
    } else {
        Write-Warn "sqlcmd not available. Create the SQL user manually in the Azure Portal:"
        Write-Host "    URL: https://portal.azure.com" -ForegroundColor Yellow
        Write-Host "    Navigate to: SQL Database '$SqlDatabaseName' on server '$SqlServerName' > Query Editor" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "    Run this SQL:" -ForegroundColor Yellow
        Write-Host $sqlScript -ForegroundColor Gray
        Read-Host "`n  Press Enter once you have created the SQL user..."
    }
} finally {
    # Always remove the temporary firewall rule
    $null = Try-Az sql server firewall-rule delete `
        --resource-group $ResourceGroup `
        --server $SqlServerName `
        --name $FirewallRuleName `
        --yes
    Write-Success "Removed temporary firewall rule"
}

# ---------------------------------------------------------------------------
# Phase 6: GitHub Secrets & Variables
# ---------------------------------------------------------------------------

Write-Step "Phase 6: Configuring GitHub secrets and variables..."

function Set-GhSecret([string]$Name, [string]$Value) {
    $Value | gh secret set $Name --repo $GitHubOrgRepo
    if ($LASTEXITCODE -ne 0) { throw "Failed to set secret $Name" }
    Write-Success "Secret: $Name"
}

function Set-GhVariable([string]$Name, [string]$Value) {
    gh variable set $Name --body $Value --repo $GitHubOrgRepo
    if ($LASTEXITCODE -ne 0) { throw "Failed to set variable $Name" }
    Write-Success "Variable: $Name"
}

# Shared secrets (idempotent — overwrite if already set)
Set-GhSecret "AZURE_TENANT_ID"      $TenantId
Set-GhSecret "AZURE_SUBSCRIPTION_ID" $SubscriptionId

# Environment-specific secrets
$SwaToken = (Invoke-Az-Json staticwebapp secrets list --name $SwaName).properties.apiKey
Set-GhSecret "AZURE_CLIENT_ID_${EnvSuffix}"                    $DeployerUamiClientId
Set-GhSecret "AZURE_STATIC_WEB_APPS_API_TOKEN_${EnvSuffix}"    $SwaToken
Set-GhSecret "AZURE_API_BASE_URL_${EnvSuffix}"                 "https://$AppServiceHostname"

# Environment-specific variables
Set-GhVariable "AZURE_RESOURCE_GROUP_${EnvSuffix}"  $ResourceGroup
Set-GhVariable "APP_SERVICE_NAME_${EnvSuffix}"       $AppServiceName
Set-GhVariable "SQL_SERVER_NAME_${EnvSuffix}"        $SqlServerName
Set-GhVariable "SQL_SERVER_FQDN_${EnvSuffix}"        $SqlServerFqdn
Set-GhVariable "SQL_DATABASE_NAME_${EnvSuffix}"      $SqlDatabaseName

# ---------------------------------------------------------------------------
# Phase 7: App Service Configuration
# ---------------------------------------------------------------------------

Write-Step "Phase 7: Configuring App Service..."

# Connection string (Entra auth — no password)
$ConnectionString = "Server=$SqlServerFqdn;Database=$SqlDatabaseName;Authentication=Active Directory Default;Encrypt=True;"
az webapp config connection-string set `
    --name $AppServiceName `
    --resource-group $ResourceGroup `
    --settings DefaultConnection="$ConnectionString" `
    --connection-string-type SQLAzure | Out-Null
Write-Success "Connection string set"

# Application Insights connection string
az webapp config appsettings set `
    --name $AppServiceName `
    --resource-group $ResourceGroup `
    --settings ApplicationInsights__ConnectionString="$AppInsightsConnStr" | Out-Null
Write-Success "Application Insights connection string set"

# Set GHCR placeholder image (will be replaced by deploy-api.yml on first CI run)
$Owner = ($GitHubOrgRepo -split '/')[0]
$PlaceholderImage = "ghcr.io/${Owner}/ahkflowapp-api:latest-${Environment}"
az webapp config container set `
    --name $AppServiceName `
    --resource-group $ResourceGroup `
    --container-image-name $PlaceholderImage `
    --container-registry-url "https://ghcr.io" | Out-Null
Write-Success "Container image placeholder set"


# CORS -- allow the SWA frontend
az webapp cors add `
    --name $AppServiceName `
    --resource-group $ResourceGroup `
    --allowed-origins "https://${SwaHostname}" | Out-Null
Write-Success "CORS configured for SWA frontend"

# ---------------------------------------------------------------------------
# Phase 8: Save config + Summary
# ---------------------------------------------------------------------------

Write-Step "Phase 8: Saving configuration..."

$EnvFileOut = Join-Path $PSScriptRoot ".env.${Environment}"
@"
# AHKFlowApp deployment config -- $Environment -- generated by deploy.ps1
# DO NOT COMMIT -- this file is gitignored
ENVIRONMENT=$Environment
BASE_NAME=$BaseName
LOCATION=$Location
RESOURCE_GROUP=$ResourceGroup
GITHUB_ORG_REPO=$GitHubOrgRepo
AZURE_TENANT_ID=$TenantId
AZURE_SUBSCRIPTION_ID=$SubscriptionId
SQL_SERVER_NAME=$SqlServerName
SQL_SERVER_FQDN=$SqlServerFqdn
SQL_DATABASE_NAME=$SqlDatabaseName
SQL_ADMIN_GROUP=$SqlAdminGroup
SQL_ADMIN_GROUP_ID=$GroupId
APP_SERVICE_NAME=$AppServiceName
APP_SERVICE_HOSTNAME=$AppServiceHostname
SWA_NAME=$SwaName
SWA_HOSTNAME=$SwaHostname
DEPLOYER_UAMI_NAME=$DeployerUamiName
RUNTIME_UAMI_NAME=$RuntimeUamiName
APP_INSIGHTS_NAME=$AppInsightsName
"@ | Set-Content -Path $EnvFileOut -Encoding UTF8
Write-Success "Config saved to scripts/.env.$Environment"

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  AHKFlowApp ($Environment) -- Provisioning Complete!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  API health  : https://$AppServiceHostname/health"
Write-Host "  Frontend    : https://$SwaHostname"
Write-Host "  Resources   : $ResourceGroup"
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Cyan
Write-Host "  1. Push to 'main' to trigger GitHub Actions deploy"
Write-Host "  2. The first push will build and push the container image to GHCR."
Write-Host ""
Write-Host "  IMPORTANT: GHCR packages are private by default." -ForegroundColor Yellow
Write-Host "  After the first deploy-api.yml run, make the container image public:"
Write-Host "  https://github.com/$($GitHubOrgRepo.Split('/')[0])?tab=packages"
Write-Host "  Find 'ahkflowapp-api' -> Package settings -> Change visibility -> Public"
Write-Host "  Then re-run the failed deploy job."
Write-Host ""
Write-Host "  To update later    : .\update.ps1 -Environment $Environment"
Write-Host "  To tear down later : .\teardown.ps1 -Environment $Environment"
Write-Host ""
