#Requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$setupScript = Join-Path $repoRoot 'scripts\setup-worktree-local-dev.ps1'

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [string] $Message)
    if (-not [string]::Equals([string] $Expected, [string] $Actual, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Message (expected '$Expected', got '$Actual')"
    }
}

function Invoke-TestGit {
    param([string] $RepoDir, [string[]] $GitArgs)
    $out = & git -C $RepoDir @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($GitArgs -join ' ') failed: $out"
    }
    return $out
}

# Fresh main-checkout repo seeded with just the tracked backend appsettings the setup script reads
# to derive the per-worktree database (Get-WorktreeDatabaseConfig). Worktrees are created as
# siblings, matching the harness in the other Worktree*.Tests.ps1 files.
function New-TempMainCheckout {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('wtsetup-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $repo = Join-Path $root 'repo'
    $backendDir = Join-Path $repo 'src\Backend\AHKFlowApp.API'
    New-Item -ItemType Directory -Path $backendDir -Force | Out-Null

    & git -C $repo init *> $null
    & git -C $repo symbolic-ref HEAD refs/heads/main *> $null
    & git -C $repo config user.email 'test@example.com' *> $null
    & git -C $repo config user.name 'Worktree Setup Test' *> $null

    # Mirror the real backend appsettings sections the setup script patches (Cors, ConnectionStrings)
    # so per-worktree overrides take the in-place update path rather than creating empty sections.
    $appsettings = @{
        Cors = @{ AllowedOrigins = @('http://localhost:5601') }
        ConnectionStrings = @{
            DefaultConnection = 'Server=localhost,1433;Database=AHKFlowAppDb;User Id=sa;Password=Dev!LocalOnly_2026;TrustServerCertificate=True;MultipleActiveResultSets=true'
        }
    } | ConvertTo-Json -Depth 8
    Set-Content -LiteralPath (Join-Path $backendDir 'appsettings.json') -Value $appsettings -Encoding utf8

    # Mirror the real backend launchSettings: two Docker SQL profiles (marker
    # AHKFLOW_START_DOCKER_SQL=true) that must both get per-worktree SQL isolation, and a
    # LocalDB profile that must stay untouched.
    $launchSettingsDir = Join-Path $backendDir 'Properties'
    New-Item -ItemType Directory -Path $launchSettingsDir -Force | Out-Null
    $connection = 'Server=localhost,1433;Database=AHKFlowAppDb;User Id=sa;Password=Dev!LocalOnly_2026;TrustServerCertificate=True;MultipleActiveResultSets=true'
    $launchSettings = @{
        profiles = @{
            'Docker SQL (Recommended)' = @{
                commandName = 'Project'
                environmentVariables = @{
                    ASPNETCORE_ENVIRONMENT = 'Development'
                    AHKFLOW_START_DOCKER_SQL = 'true'
                    COMPOSE_PROJECT_NAME = 'ahkflowapp'
                    ConnectionStrings__DefaultConnection = $connection
                }
                applicationUrl = 'http://localhost:5600'
            }
            'Docker SQL (No Auth)' = @{
                commandName = 'Project'
                environmentVariables = @{
                    ASPNETCORE_ENVIRONMENT = 'Development'
                    AHKFLOW_START_DOCKER_SQL = 'true'
                    COMPOSE_PROJECT_NAME = 'ahkflowapp'
                    ConnectionStrings__DefaultConnection = $connection
                    Auth__UseTestProvider = 'true'
                }
                applicationUrl = 'http://localhost:5600'
            }
            'LocalDB SQL' = @{
                commandName = 'Project'
                environmentVariables = @{
                    ASPNETCORE_ENVIRONMENT = 'Development'
                    AHKFLOW_START_DOCKER_SQL = 'false'
                }
                applicationUrl = 'http://localhost:5600'
            }
        }
    } | ConvertTo-Json -Depth 8
    Set-Content -LiteralPath (Join-Path $launchSettingsDir 'launchSettings.json') -Value $launchSettings -Encoding utf8

    # Compose file marks the repo as a Docker SQL adopter so profile patching is expected.
    Set-Content -LiteralPath (Join-Path $repo 'docker-compose.yml') -Value "services: {}" -Encoding utf8

    Invoke-TestGit $repo @('add', '-A') | Out-Null
    Invoke-TestGit $repo @('commit', '-m', 'seed') | Out-Null

    return (Resolve-Path -LiteralPath $repo).Path
}

function Add-TestWorktree {
    param([string] $RepoDir, [string] $BranchName)
    $wtPath = Join-Path (Split-Path -Parent $RepoDir) ('wt-' + $BranchName)
    Invoke-TestGit $RepoDir @('worktree', 'add', '-b', $BranchName, $wtPath, 'main') | Out-Null
    return (Resolve-Path -LiteralPath $wtPath).Path
}

function Remove-TempTree {
    param([string] $RepoDir)
    $root = Split-Path -Parent $RepoDir
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop
            return
        } catch {
            if ($attempt -eq 3) { return }
            Start-Sleep -Milliseconds 200
        }
    }
}

function Get-ManifestPort {
    param([string] $ManifestPath, [string] $Key)
    foreach ($line in Get-Content -LiteralPath $ManifestPath) {
        if ($line -match "^\s*$([regex]::Escape($Key))\s*=\s*(.+?)\s*$") { return $matches[1] }
    }
    throw "Manifest '$ManifestPath' has no key '$Key'."
}

# --- Test: setup writes both no-auth dev configs, frontend points at the allocated API port ---
$repo = New-TempMainCheckout
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-noauth'

    & $setupScript -RepoRoot $wtPath -Quiet
    Assert-True ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) 'Setup script should succeed.'

    $backendDev = Join-Path $wtPath 'src\Backend\AHKFlowApp.API\appsettings.Development.json'
    $frontendDev = Join-Path $wtPath 'src\Frontend\AHKFlowApp.UI.Blazor\wwwroot\appsettings.Development.json'

    Assert-True (Test-Path -LiteralPath $backendDev) "Backend dev config should be written at $backendDev."
    Assert-True (Test-Path -LiteralPath $frontendDev) "Frontend dev config should be written at $frontendDev."

    $backend = Get-Content -Raw -LiteralPath $backendDev | ConvertFrom-Json
    Assert-True ([bool] $backend.Auth.UseTestProvider) 'Backend dev config must enable the test auth provider.'

    $frontend = Get-Content -Raw -LiteralPath $frontendDev | ConvertFrom-Json
    Assert-True ([bool] $frontend.Auth.UseTestProvider) 'Frontend dev config must enable the test auth provider.'

    # Regression guard: the old copy-from-main behavior leaked the main checkout's real Azure AD IDs
    # into worktrees. The deterministic writer must not emit an AzureAd section.
    Assert-True (($frontend.PSObject.Properties.Name) -notcontains 'AzureAd') 'Frontend dev config must not carry Azure AD IDs.'

    $apiPort = Get-ManifestPort (Join-Path $wtPath 'scripts\.env.worktree') 'AHKFLOW_API_PORT'
    Assert-Equal "http://localhost:$apiPort" $frontend.ApiHttpClient.BaseAddress 'Frontend BaseAddress must match the allocated API port.'

    # Regression guard: every Docker SQL profile (marker AHKFLOW_START_DOCKER_SQL=true) must get
    # per-worktree SQL isolation — originally only "Docker SQL (Recommended)" was patched, so
    # "Docker SQL (No Auth)" kept pointing at the main checkout's SQL container on 1433.
    $sqlPort = Get-ManifestPort (Join-Path $wtPath 'scripts\.env.worktree') 'AHKFLOW_SQL_PORT'
    $composeProject = Get-ManifestPort (Join-Path $wtPath 'scripts\.env.worktree') 'AHKFLOW_COMPOSE_PROJECT'
    $launchSettingsPath = Join-Path $wtPath 'src\Backend\AHKFlowApp.API\Properties\launchSettings.json'
    $launch = Get-Content -Raw -LiteralPath $launchSettingsPath | ConvertFrom-Json

    foreach ($profileName in @('Docker SQL (Recommended)', 'Docker SQL (No Auth)')) {
        $profileEnv = $launch.profiles.$profileName.environmentVariables
        Assert-Equal $composeProject $profileEnv.COMPOSE_PROJECT_NAME "'$profileName' must use the worktree compose project."
        Assert-Equal $sqlPort $profileEnv.AHKFLOW_SQL_PORT "'$profileName' must use the worktree SQL port."
        Assert-True ($profileEnv.ConnectionStrings__DefaultConnection -match [regex]::Escape("localhost,$sqlPort")) "'$profileName' connection string must target the worktree SQL port."
    }

    $localDbEnv = $launch.profiles.'LocalDB SQL'.environmentVariables
    Assert-True (($localDbEnv.PSObject.Properties.Name) -notcontains 'COMPOSE_PROJECT_NAME') 'Non-Docker profile must not be patched with a compose project.'
} finally {
    Remove-TempTree $repo
}

Write-Host 'Worktree local-dev setup no-auth tests passed.'
