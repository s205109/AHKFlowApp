#Requires -Version 7.0

# Backlog 151. A pull request merged an item's work and left the item open: backlog 132, merged
# in pull request #400 as commit 7ca15577 on 2026-09-10, with all five Acceptance boxes ticked
# and 'Stage: 4-execute'. Nothing detected it. This suite proves the check that does.
#
# The rule needs two conditions together, and each one blocks a different wrong report:
#
#   | Situation                          | Boxes          | Draft | Verdict              |
#   |------------------------------------|----------------|-------|----------------------|
#   | Partial delivery, PR 1 of 3        | some unticked  | ready | passes, boxes open   |
#   | Document-to-Ship window            | all ticked     | draft | passes, still draft  |
#   | Backlog 132                        | all ticked     | ready | fails, correct       |
#
# Run it by hand with:  pwsh ./tests/ShippingPrClosesItem.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# $suiteRoot, never $repoRoot. The script dot-sourced below has a -RepoRoot parameter, and
# dot-sourcing a script binds its parameter names into this scope. A variable called $repoRoot
# here would be wiped to an empty string.
# tests/ShippedPlanTicked.Tests.ps1:18 names it the same way for the same reason.
$suiteRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

# Dot-source, never '&'. '&' runs the script in a child scope and its functions vanish with it,
# so every call below would fail with "not recognized".
. (Join-Path $suiteRoot 'scripts/check-shipping-pr-closes-item.ps1') -AsModule

$failures = @()

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { $script:failures += $Message }
}

function Invoke-FixtureGit {
    param([string] $RepoDir, [string[]] $GitArgs)
    $out = & git -C $RepoDir @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed: $out" }
    return $out
}

# An item with the given stage and the given number of ticked boxes out of $Total.
function Write-FixtureItem {
    param([string] $Path, [string] $Key, [string] $Stage, [int] $Total = 2, [int] $Ticked = 2)
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("# $Key - Fixture item")
    $lines.Add('')
    $lines.Add('## Metadata')
    $lines.Add('')
    $lines.Add('- **Epic**: Fixture')
    $lines.Add("- **Stage**: $Stage")
    $lines.Add('')
    $lines.Add('## Acceptance criteria')
    $lines.Add('')
    for ($i = 1; $i -le $Total; $i++) {
        $mark = if ($i -le $Ticked) { 'x' } else { ' ' }
        $lines.Add("- [$mark] criterion $i")
    }
    $lines.Add('')
    $lines.Add('## Notes / dependencies')
    $lines.Add('')
    $lines.Add('- Plan: `docs/superpowers/plans/2026-09-10-a-topic-plan-140.md`')
    Set-Content -LiteralPath $Path -Value (($lines -join "`n") + "`n") -Encoding utf8
}

# A repository whose main branch holds one open item at 1-pickup, and a branch that changes it.
# -Ticked sets how many of -Total boxes the branch ticks. -Closed makes the branch also move the
# item to backlog/done/ at 9-ship. -Progress leaves a PLAN-PROGRESS.md on the branch.
# -StartClosed files the item in backlog/done/ from the start, so the branch only edits a
# finished item.
function New-ShippingFixture {
    param(
        [string] $Stage = '4-execute',
        [int] $Total = 2,
        [int] $Ticked = 2,
        [switch] $Closed,
        [switch] $Progress,
        [switch] $StartClosed
    )

    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('shipping-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $repo = Join-Path $root 'repo'
    New-Item -ItemType Directory -Path $repo -Force | Out-Null

    & git -C $repo init --quiet
    & git -C $repo symbolic-ref HEAD refs/heads/main
    Invoke-FixtureGit $repo @('config', 'user.email', 'test@example.com') | Out-Null
    Invoke-FixtureGit $repo @('config', 'user.name', 'Shipping Pr Test') | Out-Null

    foreach ($subfolder in @('backlog', 'backlog/done', 'backlog/blocked')) {
        New-Item -ItemType Directory -Path (Join-Path $repo $subfolder) -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $repo "$subfolder/.gitkeep") -Value '' -Encoding utf8
    }

    $startFolder = if ($StartClosed) { 'backlog/done' } else { 'backlog' }
    $itemPath = Join-Path $repo "$startFolder/140-fixture.md"
    $startStage = if ($StartClosed) { '9-ship' } else { '1-pickup' }
    Write-FixtureItem -Path $itemPath -Key '140' -Stage $startStage -Total $Total -Ticked 0
    Invoke-FixtureGit $repo @('add', '-A') | Out-Null
    Invoke-FixtureGit $repo @('commit', '--quiet', '-m', 'file the item') | Out-Null
    $mergeBase = (Invoke-FixtureGit $repo @('rev-parse', 'HEAD')).Trim()

    Invoke-FixtureGit $repo @('checkout', '--quiet', '-b', 'fix/wt-fixture') | Out-Null
    Write-FixtureItem -Path $itemPath -Key '140' -Stage $Stage -Total $Total -Ticked $Ticked
    if ($Progress) {
        Set-Content -LiteralPath (Join-Path $repo 'PLAN-PROGRESS.md') -Value "# Progress`n" -Encoding utf8
    }
    Invoke-FixtureGit $repo @('add', '-A') | Out-Null
    Invoke-FixtureGit $repo @('commit', '--quiet', '-m', 'do the work') | Out-Null

    if ($Closed) {
        Invoke-FixtureGit $repo @('mv', 'backlog/140-fixture.md', 'backlog/done/140-fixture.md') | Out-Null
        Write-FixtureItem -Path (Join-Path $repo 'backlog/done/140-fixture.md') -Key '140' -Stage '9-ship' -Total $Total -Ticked $Ticked
        if ($Progress) { Remove-Item -LiteralPath (Join-Path $repo 'PLAN-PROGRESS.md') -Force }
        Invoke-FixtureGit $repo @('add', '-A') | Out-Null
        Invoke-FixtureGit $repo @('commit', '--quiet', '-m', 'close the records') | Out-Null
    }

    return [pscustomobject]@{
        Root = $root
        Repo = $repo
        MergeBase = $mergeBase
        Target = (Invoke-FixtureGit $repo @('rev-parse', 'HEAD')).Trim()
    }
}

function Get-FixtureProblem {
    param([psobject] $Fixture, [bool] $IsDraft)
    return @(Get-ShippingPrProblem -RepoRoot $Fixture.Repo -MergeBase $Fixture.MergeBase `
        -TargetCommit $Fixture.Target -PullRequestIsDraft $IsDraft)
}

# --- The rule fires: ready, all ticked, item still open ---

$f = New-ShippingFixture
$p = @(Get-FixtureProblem -Fixture $f -IsDraft $false)
Assert-True ($p.Count -ge 1) "A ready pull request with all boxes ticked and the item open must be reported, got none"
Assert-True (($p -join "`n") -match '140') "The report must name the item number, got:`n$($p -join "`n")"
Remove-Item -LiteralPath $f.Root -Recurse -Force

# --- Still a draft: the Document-to-Ship window is legitimate ---

$f = New-ShippingFixture
$p = @(Get-FixtureProblem -Fixture $f -IsDraft $true)
Assert-True ($p.Count -eq 0) "A draft pull request must not be reported, got:`n$($p -join "`n")"
Remove-Item -LiteralPath $f.Root -Recurse -Force

# --- A box left unticked: partial delivery ---

$f = New-ShippingFixture -Total 3 -Ticked 2
$p = @(Get-FixtureProblem -Fixture $f -IsDraft $false)
Assert-True ($p.Count -eq 0) "An item with an unticked box must not be reported, got:`n$($p -join "`n")"
Remove-Item -LiteralPath $f.Root -Recurse -Force

# --- Records closed in the same branch ---

$f = New-ShippingFixture -Closed
$p = @(Get-FixtureProblem -Fixture $f -IsDraft $false)
Assert-True ($p.Count -eq 0) "A branch that closed its records must not be reported, got:`n$($p -join "`n")"
Remove-Item -LiteralPath $f.Root -Recurse -Force

# --- An item with no boxes at all ---

$f = New-ShippingFixture -Total 0 -Ticked 0
$p = @(Get-FixtureProblem -Fixture $f -IsDraft $false)
Assert-True ($p.Count -eq 0) "An item with no acceptance boxes must not be reported, got:`n$($p -join "`n")"
Remove-Item -LiteralPath $f.Root -Recurse -Force

# --- A branch that only edits an item already in backlog/done/ ---

$f = New-ShippingFixture -StartClosed -Stage '9-ship'
$p = @(Get-FixtureProblem -Fixture $f -IsDraft $false)
Assert-True ($p.Count -eq 0) "Editing an item already in backlog/done/ must not be reported, got:`n$($p -join "`n")"
Remove-Item -LiteralPath $f.Root -Recurse -Force

# --- A surviving PLAN-PROGRESS.md is its own problem line ---

$f = New-ShippingFixture -Progress
$p = @(Get-FixtureProblem -Fixture $f -IsDraft $false)
Assert-True (($p -join "`n") -match 'PLAN-PROGRESS') "A surviving PLAN-PROGRESS.md must be reported, got:`n$($p -join "`n")"
Assert-True ($p.Count -ge 2) "PLAN-PROGRESS.md must be its own problem line, got $($p.Count) line(s)"
Remove-Item -LiteralPath $f.Root -Recurse -Force

# --- And it is gone once the records are closed ---

$f = New-ShippingFixture -Progress -Closed
$p = @(Get-FixtureProblem -Fixture $f -IsDraft $false)
Assert-True ($p.Count -eq 0) "A closed branch that deleted PLAN-PROGRESS.md must not be reported, got:`n$($p -join "`n")"
Remove-Item -LiteralPath $f.Root -Recurse -Force

# --- The real case: pull request #400 and backlog 132 ---
#
# PINNED TO A COMMIT ON PURPOSE. Do not turn this into a fixture. The commit IS the evidence:
# 7ca15577 is the merge of pull request #400, which merged all of backlog 132's work on
# 2026-09-10 with all five Acceptance boxes ticked and 'Stage: 4-execute'. A historical commit
# does not move, so this test does not rot. Pull request #400 must have been ready, because
# GitHub cannot merge a draft, and that is the one fact supplied rather than read.
#
# The check judges the pull request HEAD against its merge base, so both come from the merge
# commit: its second parent is the branch head, its first parent is main at the time.

$realMerge = '7ca15577'
$haveCommit = $false
& git -C $suiteRoot rev-parse --verify --quiet "$realMerge^{commit}" *> $null
if ($LASTEXITCODE -eq 0) { $haveCommit = $true }

if (-not $haveCommit) {
    # A shallow clone cannot answer this, and a silent skip would be a false green.
    $failures += "Commit $realMerge is not in this clone, so the real backlog 132 replay could not run. Fetch full history."
}
else {
    $prHead = (Invoke-FixtureGit $suiteRoot @('rev-parse', "$realMerge^2")).Trim()
    $prBase = (Invoke-FixtureGit $suiteRoot @('merge-base', "$realMerge^1", $prHead)).Trim()

    $realProblems = @(Get-ShippingPrProblem -RepoRoot $suiteRoot -MergeBase $prBase `
        -TargetCommit $prHead -PullRequestIsDraft $false)
    $joined = $realProblems -join "`n"

    Assert-True ($realProblems.Count -ge 1) `
        "Pull request #400 left backlog 132 open, so the check must report it. Got no problem."
    Assert-True ($joined -match '132') `
        "The report must name backlog 132, got:`n$joined"

    # The same pull request, told it is a draft, must say nothing. This is the second half of the
    # rule proved against the real case, not only against a fixture.
    $asDraft = @(Get-ShippingPrProblem -RepoRoot $suiteRoot -MergeBase $prBase `
        -TargetCommit $prHead -PullRequestIsDraft $true)
    Assert-True ($asDraft.Count -eq 0) `
        "The same pull request as a draft must report nothing, got:`n$($asDraft -join "`n")"
}

# --- Report ---

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host ''; Write-Host $failure -ForegroundColor Red }
    Write-Host ''
    throw "Shipping pull request tests failed with $($failures.Count) problem(s). See the detail above."
}

Write-Host 'Shipping pull request tests passed.'
