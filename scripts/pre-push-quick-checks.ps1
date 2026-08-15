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

    # The private plans repository holds most of this project's citations, and CI never sees it:
    # (`.gitignore:473`, "docs/superpowers") ignores it. Pre-push is the only gate that can reach it.
    #
    # Tiers 1 and 2 only. Tier 3 would force a quoted phrase on every citation in a new plan, and
    # the largest plan carries 65 of them.
    Write-Step 'Checking citations in the private plans repository'
    . "$PSScriptRoot\plans-citation-scan.common.ps1"

    $plansRoot = Join-Path $repoRoot 'docs/superpowers'
    $pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
    $pwshPath = if ($pwshCommand) { $pwshCommand.Source } else { '' }
    $scanPlan = Get-PlansCitationScanPlan -PlansRoot $plansRoot -PwshPath $pwshPath

    if ($scanPlan.Action -ne 'Run') {
        Write-Host $scanPlan.Reason
    }
    else {
        & $pwshPath -NoProfile -File (Join-Path $PSScriptRoot 'check-citation-freshness.ps1') `
            -ScanRoot $plansRoot -ResolveRoot $repoRoot -NoAdoptionTier
        if ($LASTEXITCODE -ne 0) {
            throw "Plans repository citations failed. $skipHint"
        }
        Write-Success 'Plans repository citations passed.'
    }
}
finally {
    Pop-Location
}

Write-Success 'Pre-push quick checks passed.'
