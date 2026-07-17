#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RemoteName,
    [string]$RemoteLocation
)

$ErrorActionPreference = 'Stop'

if ($env:SKIP_PUSH_HOOK -or $env:SKIP_COVERAGE_HOOK) {
    Write-Host "[pre-push] SKIP_PUSH_HOOK is set - skipping quick checks." -ForegroundColor Yellow
    exit 0
}

# Derive the root from the working tree being pushed, not $PSScriptRoot. core.hooksPath is
# an absolute path into the main checkout, so $PSScriptRoot resolves there from every
# worktree and would verify main instead of the branch being pushed. Git runs hooks with the
# working directory set to the root of the working tree, so rev-parse yields the right one.
$repoRoot = & git rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repoRoot)) {
    throw "[pre-push] Could not determine the repository root ('git rev-parse --show-toplevel' failed)."
}

$repoRoot = $repoRoot.Trim()
$quickChecksScriptPath = Join-Path $repoRoot 'scripts' 'pre-push-quick-checks.ps1'
if (-not (Test-Path -LiteralPath $quickChecksScriptPath)) {
    throw "[pre-push] Quick checks script not found at '$quickChecksScriptPath'."
}

Write-Host "[pre-push] Running quick checks before push..." -ForegroundColor Cyan
Write-Host "[pre-push] Verifying: $repoRoot" -ForegroundColor DarkGray
Write-Host "[pre-push] Skip with: SKIP_PUSH_HOOK=1 git push  (or: git push --no-verify)" -ForegroundColor DarkGray
if ($RemoteName) {
    Write-Host "[pre-push] Remote: $RemoteName $RemoteLocation" -ForegroundColor DarkGray
}

Push-Location $repoRoot
try {
    & $quickChecksScriptPath
    if ($LASTEXITCODE -ne 0) {
        throw "Quick checks failed."
    }
}
finally {
    Pop-Location
}

Write-Host "[pre-push] Quick checks passed." -ForegroundColor Green
