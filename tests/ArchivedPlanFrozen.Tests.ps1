#Requires -Version 7.0

# CI cannot see the plans repository (.gitignore keeps docs/superpowers out), so this suite
# tests the rule against fixture folders. Pre-push applies it to the real plans.
#
# Run it by hand with:  pwsh ./tests/ArchivedPlanFrozen.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts/check-archived-plan-frozen.ps1') -AsModule
$failures = @()

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { $script:failures += $Message }
}

# Builds a plans folder and a backlog folder, so no test touches the real ones. Never point a test
# at the real docs/superpowers: every worktree links to that folder, and it is shared live.
function New-Fixture {
    param([hashtable] $Files, [string[]] $OpenItems = @(), [string[]] $BlockedItems = @())

    $root = Join-Path ([System.IO.Path]::GetTempPath()) "archived-plan-$([guid]::NewGuid())"
    foreach ($sub in @('plans', 'specs', 'backlog/blocked')) {
        New-Item -ItemType Directory -Path (Join-Path $root $sub) -Force | Out-Null
    }
    foreach ($name in $Files.Keys) {
        Set-Content -LiteralPath (Join-Path $root $name) -Value ($Files[$name] -join "`n")
    }
    foreach ($item in $OpenItems) {
        Set-Content -LiteralPath (Join-Path $root "backlog/$item") -Value '# item'
    }
    foreach ($item in $BlockedItems) {
        Set-Content -LiteralPath (Join-Path $root "backlog/blocked/$item") -Value '# item'
    }
    return $root
}

function Get-Hit {
    param([string] $Root)
    # The comma keeps the array intact. A bare `return @()` unrolls to nothing, the caller gets
    # $null, and $null.Count throws under Set-StrictMode rather than reading as zero.
    return , @(Get-UnfrozenArchivedPlan -PlansRoot $Root -BacklogRoot (Join-Path $Root 'backlog'))
}

$canonical = '(`scripts/x.ps1:1`, "text")'  # citation-check:ignore: fixture text, not a claim
$frozen = @('<!-- citation-check:ignore-file -->', '# Plan', $canonical)
$plain = @('# Plan', $canonical)

# 1. Archived and unfrozen is reported. This is the whole point: a shipped plan left open to the
#    check re-audits its citations against a tree that has moved on.
$hits = Get-Hit (New-Fixture -Files @{ 'plans/a-plan-201.md' = $plain })
Assert-True ($hits.Count -eq 1 -and $hits[0] -eq 'plans/a-plan-201.md') `
    "archived and unfrozen should be reported, got: $($hits -join ', ')"

# 2. The same plan, frozen, is silent.
$hits = Get-Hit (New-Fixture -Files @{ 'plans/a-plan-201.md' = $frozen })
Assert-True ($hits.Count -eq 0) "frozen should be silent, got: $($hits -join ', ')"

# 3. An open item's plan is never asked to freeze. Its citations are live claims.
$hits = Get-Hit (New-Fixture -Files @{ 'plans/a-plan-201.md' = $plain } -OpenItems @('201-thing.md'))
Assert-True ($hits.Count -eq 0) "open item should be silent, got: $($hits -join ', ')"

# 4. A blocked item counts as open: that work is paused, not done.
$hits = Get-Hit (New-Fixture -Files @{ 'plans/a-plan-201.md' = $plain } -BlockedItems @('201-thing.md'))
Assert-True ($hits.Count -eq 0) "blocked item should be silent, got: $($hits -join ', ')"

# 5. A legacy citation never reaches tier 2, so a legacy-only plan cannot rot into a failure and
#    needs no freeze. Asking for one would mean freezing 250 old plans for nothing.
$hits = Get-Hit (New-Fixture -Files @{ 'plans/a-plan-201.md' = @('# Plan', 'see scripts/x.ps1:1') })
Assert-True ($hits.Count -eq 0) "legacy-only should be silent, got: $($hits -join ', ')"

# 6. A name with no number belongs to no open item, so it is archived by definition.
$hits = Get-Hit (New-Fixture -Files @{ 'plans/a-plan.md' = $plain })
Assert-True ($hits.Count -eq 1) "numberless plan should be reported, got: $($hits -join ', ')"

# 7. Specs are checked as well as plans.
$hits = Get-Hit (New-Fixture -Files @{ 'specs/a-design-201.md' = $plain })
Assert-True ($hits.Count -eq 1 -and $hits[0] -eq 'specs/a-design-201.md') `
    "specs should be checked, got: $($hits -join ', ')"

# 8. The number is read from the file name's tail, not from anywhere in it. A date like 2026-08-201
#    must not be mistaken for item 201, and the open set must still silence the real match.
$hits = Get-Hit (New-Fixture -Files @{ 'plans/2026-08-19-thing-plan-201.md' = $plain } -OpenItems @('201-thing.md'))
Assert-True ($hits.Count -eq 0) "the trailing number should match the open item, got: $($hits -join ', ')"

# 9. A missing plans folder is not an error. A checkout without the private repository skips.
$bare = Join-Path ([System.IO.Path]::GetTempPath()) "archived-plan-bare-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $bare -Force | Out-Null
$hits = @(Get-UnfrozenArchivedPlan -PlansRoot $bare -BacklogRoot $bare)
Assert-True ($hits.Count -eq 0) "a missing plans folder should report nothing, got: $($hits -join ', ')"
Remove-Item -LiteralPath $bare -Recurse -Force

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Host ''
        Write-Host "FAIL: $failure" -ForegroundColor Red
    }
    Write-Host ''
    throw "Archived plan freeze tests failed with $($failures.Count) problem(s). See the detail above."
}

Write-Host 'Archived plan freeze tests passed. 9 cases.'
