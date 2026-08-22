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
    param(
        [hashtable] $Files,
        [string[]] $OpenItems = @(),
        [string[]] $BlockedItems = @(),
        [string[]] $DoneItems = @(),
        [hashtable] $DonePointers = @{}
    )

    $root = Join-Path ([System.IO.Path]::GetTempPath()) "archived-plan-$([guid]::NewGuid())"
    foreach ($sub in @('plans', 'specs', 'backlog/blocked', 'backlog/done')) {
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
    foreach ($item in $DoneItems) {
        $body = @('# item')
        if ($DonePointers.ContainsKey($item)) {
            $value = $DonePointers[$item]
            $body += if ($value -eq 'none') { '- Plan: none - this item had no plan' }
                     else { '- Plan: `docs/superpowers/plans/{0}`' -f $value }
        }
        Set-Content -LiteralPath (Join-Path $root "backlog/done/$item") -Value ($body -join "`n")
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

# 1. A shipped item's plan, left unfrozen, is reported. This is the whole point: it re-audits its
#    citations against a tree that has moved on.
$hits = Get-Hit (New-Fixture -Files @{ 'plans/a-plan-201.md' = $plain } -DoneItems @('201-thing.md'))
Assert-True ($hits.Count -eq 1 -and $hits[0] -eq 'plans/a-plan-201.md') `
    "shipped and unfrozen should be reported, got: $($hits -join ', ')"

# 2. The same plan, frozen, is silent.
$hits = Get-Hit (New-Fixture -Files @{ 'plans/a-plan-201.md' = $frozen } -DoneItems @('201-thing.md'))
Assert-True ($hits.Count -eq 0) "frozen should be silent, got: $($hits -join ', ')"

# 3. An open item's plan is never asked to freeze. Its citations are live claims.
$hits = Get-Hit (New-Fixture -Files @{ 'plans/a-plan-201.md' = $plain } -OpenItems @('201-thing.md'))
Assert-True ($hits.Count -eq 0) "open item should be silent, got: $($hits -join ', ')"

# 4. A blocked item counts as open: that work is paused, not done.
$hits = Get-Hit (New-Fixture -Files @{ 'plans/a-plan-201.md' = $plain } -BlockedItems @('201-thing.md'))
Assert-True ($hits.Count -eq 0) "blocked item should be silent, got: $($hits -join ', ')"

# 5. THE REGRESSION FROM REVIEW ROUND 1. An item this worktree cannot see at all - because it is
#    open on another branch - must be skipped, never read as shipped. The old rule inferred
#    "archived" from absence, so it demanded a freeze on another branch's live plan and blocked
#    that neighbour's push. Item 113 was open on main and invisible here when this was found.
$hits = Get-Hit (New-Fixture -Files @{ 'plans/a-plan-113.md' = $plain })
Assert-True ($hits.Count -eq 0) `
    "an item this worktree cannot see must be skipped, not demanded frozen, got: $($hits -join ', ')"

# 6. A legacy citation never reaches tier 2, so a legacy-only plan cannot rot into a failure and
#    needs no freeze. Asking for one would mean freezing 250 old plans for nothing.
$hits = Get-Hit (New-Fixture -Files @{ 'plans/a-plan-201.md' = @('# Plan', 'see scripts/x.ps1:1') } -DoneItems @('201-thing.md'))
Assert-True ($hits.Count -eq 0) "legacy-only should be silent, got: $($hits -join ', ')"

# 7. A name with no number cannot be placed, so it is skipped rather than demanded.
$hits = Get-Hit (New-Fixture -Files @{ 'plans/a-plan.md' = $plain } -DoneItems @('201-thing.md'))
Assert-True ($hits.Count -eq 0) "an unplaceable name should be skipped, got: $($hits -join ', ')"

# 8. Specs are checked as well as plans.
$hits = Get-Hit (New-Fixture -Files @{ 'specs/a-design-201.md' = $plain } -DoneItems @('201-thing.md'))
Assert-True ($hits.Count -eq 1 -and $hits[0] -eq 'specs/a-design-201.md') `
    "specs should be checked, got: $($hits -join ', ')"

# 9. The '- Plan:' pointer wins over the file name. Item 207 shipped plan-205, which is the real
#    shape of item 107 and its 2026-08-17-personal-plans-home-plan-105.md.
$hits = Get-Hit (New-Fixture -Files @{ 'plans/a-plan-205.md' = $plain } `
    -DoneItems @('207-thing.md') -DonePointers @{ '207-thing.md' = 'a-plan-205.md' })
Assert-True ($hits.Count -eq 1 -and $hits[0] -eq 'plans/a-plan-205.md') `
    "the Plan pointer should place a mismatched file name, got: $($hits -join ', ')"

# 10. Reopening that item takes its plan out of the archive again, as workflow.md stage 9 requires.
#     The number 205 belongs to no done item, and no done pointer names the file any more.
$hits = Get-Hit (New-Fixture -Files @{ 'plans/a-plan-205.md' = $plain } -OpenItems @('207-thing.md'))
Assert-True ($hits.Count -eq 0) `
    "a reopened item's plan must not be demanded frozen, got: $($hits -join ', ')"

# 11. A pointer that names a missing file must not break the number fall-back. Item 107's bullet
#     named a plan-107 file that never existed, until pull request 341 repaired it.
$hits = Get-Hit (New-Fixture -Files @{ 'plans/a-plan-201.md' = $plain } `
    -DoneItems @('201-thing.md') -DonePointers @{ '201-thing.md' = 'nowhere-plan-201.md' })
Assert-True ($hits.Count -eq 1) `
    "a dangling pointer must still leave the number fall-back working, got: $($hits -join ', ')"

# 12. A 'none' pointer names no file. Parsing must ignore it and fall back to the number, so the
#     unfrozen plan is still reported rather than silently skipped.
$hits = Get-Hit (New-Fixture -Files @{ 'plans/a-plan-201.md' = $plain } `
    -DoneItems @('201-thing.md') -DonePointers @{ '201-thing.md' = 'none' })
Assert-True ($hits.Count -eq 1) "a none pointer must fall back to the number, got: $($hits -join ', ')"

# 13. A missing plans folder is not an error. A checkout without the private repository skips.
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

Write-Host 'Archived plan freeze tests passed. 13 cases.'
