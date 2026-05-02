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

$repoRoot = Split-Path -Parent $PSScriptRoot
$coverageScriptPath = Join-Path $repoRoot 'scripts' 'run-coverage.ps1'

Write-Host "[pre-push] Running coverage verification before push..." -ForegroundColor Cyan
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
