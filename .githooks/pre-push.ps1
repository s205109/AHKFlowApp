#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RemoteName,
    [string]$RemoteLocation
)

$ErrorActionPreference = 'Stop'

if ($env:SKIP_COVERAGE_HOOK) {
    Write-Host "[pre-push] SKIP_COVERAGE_HOOK is set - skipping coverage verification." -ForegroundColor Yellow
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
$coverageScriptPath = Join-Path $repoRoot 'scripts' 'run-coverage.ps1'
if (-not (Test-Path -LiteralPath $coverageScriptPath)) {
    throw "[pre-push] Coverage script not found at '$coverageScriptPath'."
}

Write-Host "[pre-push] Running coverage verification before push..." -ForegroundColor Cyan
Write-Host "[pre-push] Verifying: $repoRoot" -ForegroundColor DarkGray
Write-Host "[pre-push] Skip with: SKIP_COVERAGE_HOOK=1 git push  (or: git push --no-verify)" -ForegroundColor DarkGray
if ($RemoteName) {
    Write-Host "[pre-push] Remote: $RemoteName $RemoteLocation" -ForegroundColor DarkGray
}

Push-Location $repoRoot
try {
    & $coverageScriptPath
    if ($LASTEXITCODE -ne 0) {
        throw "Coverage verification failed."
    }
}
finally {
    Pop-Location
}

Write-Host "[pre-push] Coverage verification passed." -ForegroundColor Green
