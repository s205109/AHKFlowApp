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
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
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
} finally {
    Remove-TempTree $repo
}

Write-Host 'Worktree local-dev setup no-auth tests passed.'
