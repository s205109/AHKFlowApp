#Requires -Version 5.1
<#
.SYNOPSIS
  Fast fail-fast pre-push checks: incremental build + container-free unit tests.
.DESCRIPTION
  Called by .githooks/pre-push.ps1. CI still runs the full coverage + format gate on every
  PR, so this script deliberately skips coverage collection and testcontainers to stay fast.
#>
[CmdletBinding()]
param(
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot\Common.ps1"

$skipHint = "CI still runs the full coverage + format gate on this PR. Skip locally with: SKIP_PUSH_HOOK=1 git push  (or: git push --no-verify)"

Push-Location $repoRoot
try {
    Write-Step "Building solution ($Configuration)"
    & dotnet build --configuration $Configuration
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed. $skipHint"
    }
    Write-Success 'Build succeeded.'

    Write-Step 'Running fast test slice'
    try {
        & (Join-Path $PSScriptRoot 'test-fast.ps1') -Mode Fast -Configuration $Configuration -NoBuild
        if ($LASTEXITCODE -ne 0) {
            throw "Fast test slice failed."
        }
    }
    catch {
        throw "Fast test slice failed. $skipHint"
    }
    Write-Success 'Fast test slice passed.'
}
finally {
    Pop-Location
}

Write-Success 'Pre-push quick checks passed.'
