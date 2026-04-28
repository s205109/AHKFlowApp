#Requires -Version 5.1
<#
    .SYNOPSIS
    Provisions an AHKFlowApp Azure environment and configures CI/CD.

.DESCRIPTION
    Single entrypoint that provisions all Azure resources via Bicep, configures
    Entra ID, OIDC federation, SQL access, runtime SQL credentials, and GitHub
    secrets/variables.

    Run this once per environment (test or prod). It is idempotent — safe to re-run.

.PARAMETER Environment
    Target environment: 'test' or 'prod'. Prompts interactively if not provided.

.PARAMETER Tier
    Resource tier: 'free' (App Service F1 + Azure SQL free offer) or 'basic' (App Service B1 +
    Azure SQL Basic). Free tier is significantly slower to provision (SQL alone can take 20+ min)
    and has CPU/cold-start limits in production. Prompts interactively if not provided.

.PARAMETER MaxWaitMinutes
    Maximum minutes to wait for async Azure operations. Default: 60 (free tier SQL can take 20+ min).

.PARAMETER SkipPrereqCheck
    Skip Phase 1 prerequisite checks. Use when your environment is correct
    and you want to skip checks on re-runs.

.EXAMPLE
    .\deploy.ps1
    .\deploy.ps1 -Environment test -Tier free
    .\deploy.ps1 -Environment prod -Tier basic
    .\deploy.ps1 -Environment test -SkipPrereqCheck
#>
[CmdletBinding()]
param(
    [ValidateSet('test', 'prod')]
    [string]$Environment,

    [ValidateSet('free', 'basic')]
    [string]$Tier,

    [ValidateRange(1, 240)]
    [int]$MaxWaitMinutes = 60,

    [switch]$SkipPrereqCheck
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
    $raw = az @args --output json 2>&1
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

function Try-Az-Json {
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = az @args --output json 2>&1
        if ($LASTEXITCODE -ne 0) { return $null }
        return ($output | ConvertFrom-Json)
    } catch {
        return $null
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

if ($SkipPrereqCheck) {
    Write-Host "`n  Skipping prerequisite checks (-SkipPrereqCheck)" -ForegroundColor Yellow
} else {
    Write-Step "Phase 1: Checking prerequisites..."

    # PowerShell version
    if (([version]$PSVersionTable.PSVersion) -lt [version]'5.1') {
        Write-Fail "PowerShell 5.1 or later required (found $($PSVersionTable.PSVersion))."
        Write-Host "    Install from: https://aka.ms/powershell" -ForegroundColor Yellow
        throw "Insufficient PowerShell version"
    }
    Write-Success "PowerShell $($PSVersionTable.PSVersion)"

    # .NET 10 SDK
    if (-not (Get-Command 'dotnet' -ErrorAction SilentlyContinue)) {
        Write-Fail ".NET 10 SDK not found."
        Write-Host "    Install from: https://dotnet.microsoft.com/download" -ForegroundColor Yellow
        throw "Missing prerequisite: dotnet"
    }
    $dotnetVersion = dotnet --version 2>&1
    if ($LASTEXITCODE -ne 0 -or $dotnetVersion -notmatch '^10\.') {
        Write-Fail ".NET 10 SDK required (found: $dotnetVersion)."
        Write-Host "    Install from: https://dotnet.microsoft.com/download" -ForegroundColor Yellow
        throw "Missing or incorrect .NET SDK version"
    }
    Write-Success ".NET SDK $dotnetVersion"

    Confirm-Command 'az'  'https://learn.microsoft.com/cli/azure/install-azure-cli'
    Confirm-Command 'gh'  'https://cli.github.com/'

    # Bicep (installed as az extension)
    $bicepOut = az bicep version 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Bicep CLI not found. Run: az bicep install"
        throw "Missing prerequisite: Bicep"
    }
    Write-Success "Bicep: $($bicepOut -join ' ')"

    # jq — optional, warn only
    if (-not (Get-Command 'jq' -ErrorAction SilentlyContinue)) {
        Write-Warn "jq not found — not required by this script, but useful for JSON debugging."
        Write-Warn "Install: https://jqlang.github.io/jq/download/"
    } else {
        Write-Success "jq found"
    }

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

    # sqlcmd (optional)
    $hasSqlcmd = [bool](Get-Command 'sqlcmd' -ErrorAction SilentlyContinue)
    if ($hasSqlcmd) {
        Write-Success "sqlcmd found (will use for SQL user creation)"
    } else {
        Write-Warn "sqlcmd not found — SQL user creation step will print manual instructions"
        Write-Warn "Install: https://learn.microsoft.com/sql/tools/sqlcmd/sqlcmd-utility"
    }
}

# When -SkipPrereqCheck is used, $account and $hasSqlcmd must still be populated
# (they're used in Phase 2 and 5). Populate them here.
if ($SkipPrereqCheck) {
    try {
        $account = Invoke-Az-Json account show
    } catch {
        Write-Fail "Not logged into Azure. Run: az login"
        throw
    }
    $hasSqlcmd = [bool](Get-Command 'sqlcmd' -ErrorAction SilentlyContinue)
}

# ---------------------------------------------------------------------------
# Phase 2: Gather Configuration
# ---------------------------------------------------------------------------

Write-Step "Phase 2: Gathering configuration..."

if (-not $Environment) {
    $envInput = Read-Host "  Environment [test/prod] (default: test)"
    # Apply default before assigning to $Environment — [ValidateSet] re-validates
    # every assignment, so a blank intermediate value would throw.
    $Environment = if ([string]::IsNullOrWhiteSpace($envInput)) { 'test' } else { $envInput }
    if ($Environment -notin @('test', 'prod')) { throw "Environment must be 'test' or 'prod'" }  # explicit — [ValidateSet] only applies to param binding, not variable assignment
}

if (-not $Tier) {
    Write-Host ""
    Write-Host "  Resource tier:" -ForegroundColor White
    Write-Host "    [1] free   — App Service F1 + Azure SQL free offer (serverless)" -ForegroundColor DarkGray
    Write-Host "                 No cost, but SQL provisioning takes 15-25 minutes and" -ForegroundColor DarkGray
    Write-Host "                 the app cold-starts on every request after idle periods." -ForegroundColor DarkGray
    Write-Host "    [2] basic  — App Service B1 + Azure SQL Basic (~`$15-25/month)" -ForegroundColor DarkGray
    Write-Host "                 Always On, faster provisioning, no cold-start penalty." -ForegroundColor DarkGray
    Write-Host ""
    $tierInput = Read-Host "  Choose tier [1=free/2=basic] (default: 1)"
    $Tier = switch ($tierInput.Trim()) {
        '2'     { 'basic' }
        'basic' { 'basic' }
        default { 'free' }
    }
}

if ($Tier -eq 'free') {
    Write-Warn "Free tier selected — SQL provisioning is significantly slower (15-25 min)."
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
$tierDesc = if ($Tier -eq 'free') { 'free (F1 App Service + Azure SQL free offer)' } else { 'basic (B1 App Service + Azure SQL Basic)' }
Write-Host "  Summary:" -ForegroundColor White
Write-Host "    Environment    : $Environment"
Write-Host "    Tier           : $tierDesc"
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

# Entra app registration must exist before Bicep — web.bicep wires AzureAd__TenantId
# and AzureAd__ClientId into App Service settings as required parameters.
# Without this, `az deployment group create` hangs on an invisible stdin prompt.
Write-Host "  Setting up Entra app registration (pre-Bicep)..."
$EntraScript = Join-Path $PSScriptRoot 'setup-entra-app.ps1'
# setup-entra-app.ps1 emits a PSCustomObject at the end, but az rest calls inside
# may also leak output. Pick the last object that has a ClientId.
$EntraOutput = & $EntraScript -Environment $Environment
$EntraInfo = @(
    $EntraOutput | Where-Object {
        $_ -is [psobject] -and
        $_.PSObject.Properties['ClientId'] -and
        $_.ClientId
    }
) | Select-Object -Last 1
if (-not $EntraInfo -or -not $EntraInfo.ClientId) {
    throw "setup-entra-app.ps1 did not return a ClientId"
}
$EntraTenantId = [string]$EntraInfo.TenantId
$EntraClientId = [string]$EntraInfo.ClientId
Write-Success "Entra app: $EntraClientId (tenant $EntraTenantId)"

# Deploy Bicep
$deployMsg = if ($Tier -eq 'free') {
    "Deploying Bicep template (5-15 minutes on Free tier; Free tier is slower than Basic due to resource constraints)..."
} else {
    "Deploying Bicep template (3-5 minutes on Basic tier)..."
}
Write-Host "  $deployMsg"
Write-Host "  Progress updates every 15s; first update may take ~30s while deployment registers."
$BicepTemplate = Join-Path $RepoRoot "infra\main.bicep"
$DeploymentName = "deploy-${Environment}-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

$useFreeTierParam = if ($Tier -eq 'free') { 'true' } else { 'false' }
$deployStart = Get-Date
Invoke-Az deployment group create `
    --resource-group $ResourceGroup `
    --name $DeploymentName `
    --template-file $BicepTemplate `
    --no-wait `
    --parameters `
        environment=$Environment `
        location=$Location `
        baseName=$BaseName `
        sqlAdminGroupId=$GroupId `
        sqlAdminGroupName=$SqlAdminGroup `
        azureAdTenantId=$EntraTenantId `
        azureAdClientId=$EntraClientId `
        useFreeTier=$useFreeTierParam | Out-Null

# Poll deployment until done. Print each resource operation state change with
# elapsed time so the user can see it's still making progress.
$seenOps = @{}
$seenNestedOps = @{}
$state = 'Accepted'
$ticks = 0
$lastNestedCheckTick = -99

function Get-OpDisplayFields([object]$op) {
    $propsMember = $op.PSObject.Properties['properties']
    if (-not $propsMember) { return $null }
    $props = $propsMember.Value
    $trMember = $props.PSObject.Properties['targetResource']
    if (-not $trMember -or -not $trMember.Value) { return $null }
    $tr = $trMember.Value
    $rnMember = $tr.PSObject.Properties['resourceName']
    if (-not $rnMember -or -not $rnMember.Value) { return $null }
    $rtMember = $tr.PSObject.Properties['resourceType']
    return [PSCustomObject]@{
        ResType  = if ($rtMember) { $rtMember.Value } else { '' }
        ResName  = $rnMember.Value
        OpState  = $props.provisioningState
    }
}

function Write-OpLine([string]$Prefix, [string]$Key, [string]$OpState, [string]$ElapsedStr) {
    $color = switch ($OpState) {
        'Succeeded' { 'Green' }
        'Failed'    { 'Red' }
        'Running'   { 'Yellow' }
        default     { 'DarkGray' }
    }
    $symbol = switch ($OpState) {
        'Succeeded' { '✓' }
        'Failed'    { '✗' }
        'Running'   { '…' }
        default     { '·' }
    }
    $label = switch ($OpState) {
        'Succeeded' { 'done' }
        'Failed'    { 'failed' }
        'Running'   { 'in progress' }
        'Accepted'  { 'queued' }
        default     { $OpState.ToLower() }
    }
    Write-Host "$Prefix$symbol [$ElapsedStr] $Key — $label" -ForegroundColor $color
}

while ($state -notin @('Succeeded', 'Failed', 'Canceled')) {
    Start-Sleep -Seconds 15
    $ticks++
    $elapsed = (Get-Date) - $deployStart
    $elapsedStr = '{0:D2}:{1:D2}' -f [int]$elapsed.TotalMinutes, $elapsed.Seconds

    if ($elapsed.TotalMinutes -ge $MaxWaitMinutes) {
        throw @"
Deployment '$DeploymentName' exceeded -MaxWaitMinutes ($MaxWaitMinutes min) in state '$state'.
Inspect:  az deployment group show --resource-group $ResourceGroup --name $DeploymentName
Cancel:   az deployment group cancel --resource-group $ResourceGroup --name $DeploymentName
Re-run deploy.ps1 once resolved (it is idempotent), optionally with -MaxWaitMinutes <N>.
"@
    }

    $deployment = Try-Az-Json deployment group show `
        --resource-group $ResourceGroup --name $DeploymentName
    if (-not $deployment) {
        Write-Host "  · [$elapsedStr] waiting for deployment to register..." -ForegroundColor DarkGray
        continue
    }
    $state = $deployment.properties.provisioningState

    # Top-level module operations
    $ops = Try-Az-Json deployment operation group list `
        --resource-group $ResourceGroup --name $DeploymentName
    $newActivity = $false
    if ($ops) {
        foreach ($op in $ops) {
            $fields = Get-OpDisplayFields $op
            if (-not $fields) { continue }
            $key = "$($fields.ResType)/$($fields.ResName)"
            if ($seenOps[$key] -ne $fields.OpState) {
                $seenOps[$key] = $fields.OpState
                $newActivity = $true
                Write-OpLine '  ' $key $fields.OpState $elapsedStr
            }
        }
    }

    # Every ~60s: drill into sql and web nested deployments for resource-level detail
    if (($ticks - $lastNestedCheckTick) -ge 4) {
        $lastNestedCheckTick = $ticks
        foreach ($module in @('sql', 'web')) {
            $moduleKey = "Microsoft.Resources/deployments/$module"
            if ($seenOps[$moduleKey] -notin @('Running', 'Succeeded', 'Failed')) { continue }

            $nestedOps = Try-Az-Json deployment operation group list `
                --resource-group $ResourceGroup --name $module
            if (-not $nestedOps) { continue }

            foreach ($op in $nestedOps) {
                $fields = Get-OpDisplayFields $op
                if (-not $fields) { continue }
                $nestedKey = "$module/$($fields.ResType)/$($fields.ResName)"
                if ($seenNestedOps[$nestedKey] -ne $fields.OpState) {
                    $seenNestedOps[$nestedKey] = $fields.OpState
                    $newActivity = $true
                    Write-OpLine '      ' "$($fields.ResType)/$($fields.ResName)" $fields.OpState $elapsedStr
                }
            }
        }
    }

    # Heartbeat when nothing new happened this tick, so the user knows we're alive.
    if (-not $newActivity -and ($ticks % 2) -eq 0) {
        Write-Host "  · [$elapsedStr] still working..." -ForegroundColor DarkGray
    }
}

if ($state -ne 'Succeeded') {
    throw "Bicep deployment ended in state: $state.`n  For details: az deployment group show --name $DeploymentName --resource-group $ResourceGroup"
}

$DeployOutput = Invoke-Az-Json deployment group show `
    --resource-group $ResourceGroup --name $DeploymentName

$outputs = $DeployOutput.properties.outputs

$DeployerUamiName        = $outputs.deployerUamiName.value
$DeployerUamiId          = $outputs.deployerUamiId.value
$DeployerUamiClientId    = $outputs.deployerUamiClientId.value
$DeployerUamiPrincipalId = $outputs.deployerUamiPrincipalId.value
$RuntimeUamiName         = $outputs.runtimeUamiName.value
$RuntimeUamiId           = $outputs.runtimeUamiId.value
$RuntimeUamiClientId     = $outputs.runtimeUamiClientId.value
$RuntimeUamiPrincipalId  = $outputs.runtimeUamiPrincipalId.value
$SqlServerName           = $outputs.sqlServerName.value
$SqlServerFqdn           = $outputs.sqlServerFqdn.value
$SqlDatabaseName         = $outputs.sqlDatabaseName.value
$AppServiceName          = $outputs.appServiceName.value
$AppServiceHostname      = $outputs.appServiceDefaultHostname.value
$SwaName                 = $outputs.swaName.value
$SwaHostname             = $outputs.swaDefaultHostname.value
$AppInsightsName         = $outputs.appInsightsName.value
$AppInsightsConnStr      = $outputs.appInsightsConnectionString.value

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

        $sqlcmdExitCode = 1
        while ($sqlcmdExitCode -ne 0) {
            Write-Host ""
            Write-Host "  ┌─────────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
            Write-Host "  │  ACTION REQUIRED: Browser authentication window opening...      │" -ForegroundColor Cyan
            Write-Host "  │                                                                 │" -ForegroundColor Cyan
            Write-Host "  │  sqlcmd will open a Microsoft Entra login window to connect     │" -ForegroundColor Cyan
            Write-Host "  │$("  to Azure SQL. Please sign in with: $userEmail".PadRight(65))│" -ForegroundColor Cyan
            Write-Host "  │                                                                 │" -ForegroundColor Cyan
            Write-Host "  │  The window may appear BEHIND this terminal — check your        │" -ForegroundColor Cyan
            Write-Host "  │  taskbar if nothing appears on screen.                          │" -ForegroundColor Cyan
            Write-Host "  └─────────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
            Write-Host ""

            sqlcmd -S $SqlServerFqdn -d $SqlDatabaseName -G -U $userEmail -i $tmpSql
            $sqlcmdExitCode = $LASTEXITCODE

            if ($sqlcmdExitCode -ne 0) {
                Write-Warn "sqlcmd failed (login timeout or authentication error)."
                Write-Host ""
                Write-Host "  Options:" -ForegroundColor White
                Write-Host "    [R] Retry — opens a new login popup" -ForegroundColor DarkGray
                Write-Host "    [M] Manual — create the SQL user via the Azure Portal instead" -ForegroundColor DarkGray
                Write-Host ""
                $choice = Read-Host "  Choice [R/M] (default: R)"
                if ($choice.Trim() -match '^[Mm]') {
                    break
                }
                # Any other input (including blank) retries
            }
        }

        Remove-Item $tmpSql -ErrorAction SilentlyContinue

        if ($sqlcmdExitCode -eq 0) {
            Write-Success "SQL user '$RuntimeUamiName' created/verified via sqlcmd"
        } else {
            Write-Warn "Create the SQL user manually in the Azure Portal:"
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

# Re-run Entra app setup with the SWA hostname now that Bicep has created the SWA.
# Idempotent — adds the SWA redirect URI alongside the localhost ones set in Phase 3.
Write-Host "  Updating Entra app redirect URIs with SWA hostname..."
$EntraOutput = & $EntraScript -Environment $Environment -SwaHostname $SwaHostname
$EntraInfo = @(
    $EntraOutput | Where-Object {
        $_ -is [psobject] -and
        $_.PSObject.Properties['ClientId'] -and
        $_.ClientId
    }
) | Select-Object -Last 1
if (-not $EntraInfo -or -not $EntraInfo.ClientId) {
    throw "setup-entra-app.ps1 did not return a ClientId"
}
Set-GhVariable "AZURE_AD_TENANT_ID_${EnvSuffix}"      $EntraInfo.TenantId
Set-GhVariable "AZURE_AD_CLIENT_ID_${EnvSuffix}"      $EntraInfo.ClientId
Set-GhVariable "AZURE_AD_DEFAULT_SCOPE_${EnvSuffix}"  $EntraInfo.DefaultScope

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

# Connection string (Entra auth via App Service environment credentials)
$ConnectionString = "Server=tcp:$SqlServerFqdn,1433;Database=$SqlDatabaseName;Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
az webapp config connection-string set `
    --name $AppServiceName `
    --resource-group $ResourceGroup `
    --settings DefaultConnection="$ConnectionString" `
    --connection-string-type SQLAzure | Out-Null
Write-Success "Connection string set"

# Application Insights connection string (UAMI for SQL auth is configured via Bicep)
az webapp config appsettings set `
    --name $AppServiceName `
    --resource-group $ResourceGroup `
    --settings ApplicationInsights__ConnectionString="$AppInsightsConnStr" | Out-Null
Write-Success "Application Insights connection string set"


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
AZURE_AD_CLIENT_ID=$($EntraInfo.ClientId)
AZURE_AD_DEFAULT_SCOPE=$($EntraInfo.DefaultScope)
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

Write-Host "  To update later    : .\update.ps1 -Environment $Environment"
Write-Host "  To tear down later : .\teardown.ps1 -Environment $Environment"
Write-Host ""

# ---------------------------------------------------------------------------
# Phase 9: Trigger initial deployment sequence
# ---------------------------------------------------------------------------

Write-Step "Phase 9: Triggering initial deployment sequence..."
Write-Host "  Order: API deploy (build + migrate + deploy) -> health probe -> frontend deploy" -ForegroundColor DarkGray

# Step 9a — Trigger deploy-api.yml
Write-Host ""
Write-Host "  Triggering deploy-api.yml for '$Environment'..."
$deployApiTriggeredAtUtc = (Get-Date).ToUniversalTime()
$runDispatchOutput = gh workflow run deploy-api.yml --field environment=$Environment --repo $GitHubOrgRepo 2>&1
if ($LASTEXITCODE -ne 0) { throw "Failed to trigger deploy-api.yml" }
$runDispatchOutput | ForEach-Object { Write-Host $_ }
Write-Success "deploy-api.yml triggered"

# Resolve run ID — prefer the run URL returned by gh, fall back to polling if needed
Write-Host "  Resolving the newly triggered workflow run in GitHub..."
$runId = $null
$dispatchText = ($runDispatchOutput | Out-String)
$runUrlMatch = [regex]::Match($dispatchText, '/actions/runs/(?<id>\d+)')
if ($runUrlMatch.Success) {
    $runId = $runUrlMatch.Groups['id'].Value
}

for ($attempt = 1; $attempt -le 12 -and -not $runId; $attempt++) {
    if ($attempt -gt 1) { Start-Sleep -Seconds 5 }
    $runListJson = gh run list --workflow deploy-api.yml --repo $GitHubOrgRepo --limit 20 --json databaseId,createdAt,event
    if ($LASTEXITCODE -ne 0) { throw "Failed to list runs for deploy-api.yml. Check: gh run list --workflow deploy-api.yml --repo $GitHubOrgRepo" }
    $matchingRun = $runListJson |
        ConvertFrom-Json |
        Where-Object {
            $_.event -eq 'workflow_dispatch' -and
            ([DateTimeOffset]::Parse($_.createdAt).UtcDateTime -ge $deployApiTriggeredAtUtc.AddMinutes(-2))
        } |
        Sort-Object { [DateTimeOffset]::Parse($_.createdAt).UtcDateTime } -Descending |
        Select-Object -First 1
    if ($matchingRun) { $runId = $matchingRun.databaseId }
}
if (-not $runId) { throw "Could not resolve run ID for deploy-api.yml. gh workflow run succeeded, but the follow-up lookup did not return a matching run. Check: gh run list --workflow deploy-api.yml --repo $GitHubOrgRepo --json databaseId,createdAt,event" }
Write-Host "  Watching run #$runId — this typically takes 8-15 minutes..."

# Poll inline so output stays in the scrollback buffer (gh run watch uses an alternate screen)
$runView = $null
$seenJobStates = @{}
$runDone = $false
while (-not $runDone) {
    Start-Sleep -Seconds 10
    $runViewJson = gh run view $runId --repo $GitHubOrgRepo --json status,conclusion,jobs
    if ($LASTEXITCODE -ne 0) { Write-Warning "gh run view failed (exit $LASTEXITCODE). Retrying..."; continue }
    try { $runView = $runViewJson | ConvertFrom-Json -ErrorAction Stop }
    catch { Write-Warning "Failed to parse gh run view output. Retrying..."; continue }

    foreach ($job in $runView.jobs) {
        $jobKey = $job.name
        $currentState = "$($job.status)/$($job.conclusion)"
        if ($seenJobStates[$jobKey] -ne $currentState) {
            $seenJobStates[$jobKey] = $currentState
            $label = if ($job.conclusion) { $job.conclusion } else { $job.status }
            $color = switch ($job.conclusion) {
                'success'  { 'Green'   }
                'failure'  { 'Red'     }
                'skipped'  { 'DarkGray' }
                default    { 'Yellow'  }
            }
            Write-Host "  › $($job.name): $label" -ForegroundColor $color
        }
    }

    $runDone = $runView.status -eq 'completed'
}

if ($runView.conclusion -ne 'success') {
    throw "deploy-api.yml run #$runId $($runView.conclusion). Check: gh run view $runId --repo $GitHubOrgRepo"
}
Write-Success "API deployment complete (run #$runId)"

# Step 9b — Poll health endpoint
$healthUrl = "https://$AppServiceHostname/health"
Write-Host "  Polling health endpoint: $healthUrl (up to 5 minutes)..."
$healthOk = $false
for ($i = 0; $i -lt 30; $i++) {
    try {
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $resp = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEap
        if ($resp -and $resp.StatusCode -eq 200) {
            $healthOk = $true
            break
        }
    } catch {
        $ErrorActionPreference = $prevEap
    }
    Write-Host "  . [$($i * 10)s] not yet healthy..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 10
}
if (-not $healthOk) {
    Write-Warn "Health check at $healthUrl did not return 200 within 5 minutes."
    Write-Warn "App Service Free cold starts can take longer than paid tiers. Check manually before using the frontend."
    Write-Warn "Once healthy, trigger the frontend manually: gh workflow run deploy-frontend.yml --field environment=$Environment --repo $GitHubOrgRepo"
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Yellow
    Write-Host "  Provisioning complete — MANUAL STEP REQUIRED" -ForegroundColor Yellow
    Write-Host "  Trigger frontend deploy once API is healthy:" -ForegroundColor Yellow
    Write-Host "  gh workflow run deploy-frontend.yml --field environment=$Environment --repo $GitHubOrgRepo" -ForegroundColor Yellow
    Write-Host "==========================================================" -ForegroundColor Yellow
    exit 0
}
Write-Success "API health check passed"

# Step 9c — Trigger deploy-frontend.yml
Write-Host ""
Write-Host "  Triggering deploy-frontend.yml for '$Environment'..."
gh workflow run deploy-frontend.yml --field environment=$Environment --repo $GitHubOrgRepo
if ($LASTEXITCODE -ne 0) { throw "Failed to trigger deploy-frontend.yml" }
Write-Success "deploy-frontend.yml triggered (running asynchronously)"
Write-Host "    Monitor: gh run list --workflow deploy-frontend.yml --repo $GitHubOrgRepo" -ForegroundColor DarkGray

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  AHKFlowApp ($Environment) — Provisioning + Deploy DONE!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  API health  : https://$AppServiceHostname/health"
Write-Host "  Frontend    : https://$SwaHostname"
Write-Host "  Resources   : $ResourceGroup"
Write-Host ""
Write-Host "  To update later    : .\update.ps1 -Environment $Environment"
Write-Host "  To tear down later : .\teardown.ps1 -Environment $Environment"
Write-Host ""
