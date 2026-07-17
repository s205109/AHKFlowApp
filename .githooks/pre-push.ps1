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
# Nested Join-Path calls, not a single 3-argument call: -AdditionalChildPath (the third
# positional) requires PowerShell 6+, but this hook also runs under Windows PowerShell 5.1
# (the sh shim falls back to it when pwsh is absent, and #Requires -Version 5.1 declares support).
$scriptsDir = Join-Path $repoRoot 'scripts'
$quickChecksScriptPath = Join-Path $scriptsDir 'pre-push-quick-checks.ps1'
$coverageScriptPath = Join-Path $scriptsDir 'run-coverage.ps1'

# Version-skew fallback: core.hooksPath points at the main checkout, so once this hook lands on
# main it runs for pushes from EVERY worktree/branch - including ones created before the
# quick-checks script existed. Those lack pre-push-quick-checks.ps1; rather than hard-block their
# pushes, fall back to the older run-coverage.ps1 they do carry. Branches rebased onto the new
# main pick up the fast path automatically.
if (Test-Path -LiteralPath $quickChecksScriptPath) {
    $checkScriptPath = $quickChecksScriptPath
    $checkLabel = 'quick checks'
}
elseif (Test-Path -LiteralPath $coverageScriptPath) {
    $checkScriptPath = $coverageScriptPath
    $checkLabel = 'full coverage checks (legacy fallback - branch predates the quick-checks hook)'
    Write-Host "[pre-push] pre-push-quick-checks.ps1 not found; falling back to run-coverage.ps1." -ForegroundColor Yellow
}
else {
    throw "[pre-push] No pre-push check script found (looked for '$quickChecksScriptPath' and '$coverageScriptPath')."
}

Write-Host "[pre-push] Running $checkLabel before push..." -ForegroundColor Cyan
Write-Host "[pre-push] Verifying: $repoRoot" -ForegroundColor DarkGray
Write-Host "[pre-push] Skip with: SKIP_PUSH_HOOK=1 git push  (or: git push --no-verify)" -ForegroundColor DarkGray
if ($RemoteName) {
    Write-Host "[pre-push] Remote: $RemoteName $RemoteLocation" -ForegroundColor DarkGray
}

Push-Location $repoRoot
try {
    & $checkScriptPath
    if ($LASTEXITCODE -ne 0) {
        throw "Pre-push checks failed ($checkLabel)."
    }
}
finally {
    Pop-Location
}

Write-Host "[pre-push] Pre-push checks passed ($checkLabel)." -ForegroundColor Green
