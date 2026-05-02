#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RemoteName,
    [string]$RemoteLocation
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$coverageScriptPath = Join-Path $repoRoot 'scripts' 'run-coverage.ps1'

Write-Host "[pre-push] Running coverage verification before push..." -ForegroundColor Cyan
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
