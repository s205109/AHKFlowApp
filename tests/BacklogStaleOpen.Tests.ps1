#Requires -Version 7.0

# Backlog 106. A pull request merged an item's work and left the item in backlog/ with its
# records open (backlog 071, merged 2026-08-12, left at Stage: 8-review with ten unticked
# boxes). Nothing detected it. This suite proves the check that does.
#
# Run it by hand with:  pwsh ./tests/BacklogStaleOpen.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts/backlog-staleness.common.ps1')

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

function Write-FixtureItem {
    param([string] $Path, [string] $Key, [string] $Stage)
    $lines = @(
        "# $Key - Fixture item"
        ''
        '## Metadata'
        ''
        '- **Epic**: Fixture'
        "- **Stage**: $Stage"
        ''
        '## Notes / dependencies'
        ''
        '- Plan: `docs/superpowers/plans/2026-08-19-a-topic-plan-140.md`'
    )
    Set-Content -LiteralPath $Path -Value (($lines -join "`n") + "`n") -Encoding utf8
}

function Add-FixtureFiller {
    param([string] $RepoDir, [int] $Count)
    for ($i = 1; $i -le $Count; $i++) {
        Set-Content -LiteralPath (Join-Path $RepoDir "filler-$i.txt") -Value "filler $i" -Encoding utf8
        Invoke-FixtureGit $RepoDir @('add', '-A') | Out-Null
        Invoke-FixtureGit $RepoDir @('commit', '--quiet', '-m', "filler $i") | Out-Null
    }
}

# A repository whose main branch holds one item. -Stage is stamped on a branch and merged into
# main unless -LeaveUnmerged is given, which instead leaves HEAD on the branch: the working tree
# then shows the new stage while the commit that wrote it is not on main. -Filler adds that many
# commits to main after the merge. -Closed makes the branch also move the item to backlog/done/
# at Stage 9-ship. -Folder parks the item in backlog/done/ or backlog/blocked/ after the merge.
# -TouchWithoutStage adds a commit that edits the item and leaves its Stage line alone.
function New-StaleFixture {
    param(
        [string] $Stage = '8-review',
        [int] $Filler = 0,
        [switch] $Closed,
        [switch] $LeaveUnmerged,
        [switch] $TouchWithoutStage,
        [string] $Folder = ''
    )

    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('stale-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $repo = Join-Path $root 'repo'
    New-Item -ItemType Directory -Path $repo -Force | Out-Null

    & git -C $repo init --quiet
    & git -C $repo symbolic-ref HEAD refs/heads/main
    Invoke-FixtureGit $repo @('config', 'user.email', 'test@example.com') | Out-Null
    Invoke-FixtureGit $repo @('config', 'user.name', 'Stale Open Test') | Out-Null

    # Not $folder: PowerShell matches variable names without case, so a loop over $folder would
    # overwrite the -Folder parameter and park every fixture in the wrong place.
    foreach ($subfolder in @('backlog', 'backlog/done', 'backlog/blocked')) {
        New-Item -ItemType Directory -Path (Join-Path $repo $subfolder) -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $repo "$subfolder/.gitkeep") -Value '' -Encoding utf8
    }

    $openPath = Join-Path $repo 'backlog/140-fixture.md'
    Write-FixtureItem -Path $openPath -Key '140' -Stage '1-pickup'
    Invoke-FixtureGit $repo @('add', '-A') | Out-Null
    Invoke-FixtureGit $repo @('commit', '--quiet', '-m', 'file the item') | Out-Null

    Invoke-FixtureGit $repo @('checkout', '--quiet', '-b', 'fix/wt-fixture') | Out-Null
    Write-FixtureItem -Path $openPath -Key '140' -Stage $Stage
    Invoke-FixtureGit $repo @('add', '-A') | Out-Null
    Invoke-FixtureGit $repo @('commit', '--quiet', '-m', 'stamp the stage') | Out-Null

    if ($Closed) {
        Invoke-FixtureGit $repo @('mv', 'backlog/140-fixture.md', 'backlog/done/140-fixture.md') | Out-Null
        Write-FixtureItem -Path (Join-Path $repo 'backlog/done/140-fixture.md') -Key '140' -Stage '9-ship'
        Invoke-FixtureGit $repo @('add', '-A') | Out-Null
        Invoke-FixtureGit $repo @('commit', '--quiet', '-m', 'close the records') | Out-Null
    }

    if ($LeaveUnmerged) {
        # main moves on without the stamp, and HEAD returns to the branch. The working tree shows
        # Stage $Stage; the commit that wrote it is not an ancestor of main.
        Invoke-FixtureGit $repo @('checkout', '--quiet', 'main') | Out-Null
        Add-FixtureFiller -RepoDir $repo -Count $Filler
        Invoke-FixtureGit $repo @('checkout', '--quiet', 'fix/wt-fixture') | Out-Null
    }
    else {
        Invoke-FixtureGit $repo @('checkout', '--quiet', 'main') | Out-Null
        Invoke-FixtureGit $repo @('merge', '--quiet', '--no-ff', '-m', 'merge the branch', 'fix/wt-fixture') | Out-Null

        if ($Folder) {
            Invoke-FixtureGit $repo @('mv', 'backlog/140-fixture.md', "backlog/$Folder/140-fixture.md") | Out-Null
            Invoke-FixtureGit $repo @('commit', '--quiet', '-m', 'park the item') | Out-Null
            $openPath = Join-Path $repo "backlog/$Folder/140-fixture.md"
        }

        if ($TouchWithoutStage) {
            Add-Content -LiteralPath $openPath -Value '- Note: a bulk edit that leaves the Stage line alone'
            Invoke-FixtureGit $repo @('add', '-A') | Out-Null
            Invoke-FixtureGit $repo @('commit', '--quiet', '-m', 'bulk edit') | Out-Null
        }

        Add-FixtureFiller -RepoDir $repo -Count $Filler
    }

    return [pscustomobject]@{ Root = $root; Repo = (Resolve-Path -LiteralPath $repo).Path }
}

function Remove-Fixture {
    param([string] $Root)
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try { Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction Stop; return }
        catch { if ($attempt -eq 5) { return }; Start-Sleep -Milliseconds 300 }
    }
}

# --- Direction 1: a merge that left the item open fails ---

$fixture = New-StaleFixture -Stage '8-review' -Filler 5
try {
    $problems = @(Get-BacklogStaleOpenProblem -RepoRoot $fixture.Repo -Threshold 3)
    Assert-True ($problems.Count -eq 1) "An item left open after its work merged must fail, got: $($problems -join ' | ')"
    if ($problems.Count -ge 1) {
        Assert-True ($problems[0] -like '*140-fixture.md*') "The message must name the file, got: $($problems[0])"
        Assert-True ($problems[0] -like '*8-review*') "The message must quote the stage, got: $($problems[0])"
    }
}
finally { Remove-Fixture $fixture.Root }

# --- Direction 2: a merge that closed the item passes ---

$fixture = New-StaleFixture -Stage '8-review' -Filler 5 -Closed
try {
    $problems = @(Get-BacklogStaleOpenProblem -RepoRoot $fixture.Repo -Threshold 3)
    Assert-True ($problems.Count -eq 0) "An item moved to backlog/done/ must pass, got: $($problems -join ' | ')"
}
finally { Remove-Fixture $fixture.Root }

# --- The cases that must stay silent, and the two that must not ---

$cases = @(
    @{ Name = 'Below the limit passes';            Stage = '4-execute'; Filler = 2; Threshold = 3; Extra = @{};                            Expect = 0 }
    @{ Name = 'Stage 3-plan is never a candidate'; Stage = '3-plan';    Filler = 9; Threshold = 3; Extra = @{};                            Expect = 0 }
    @{ Name = 'An unmerged stamp is in flight';    Stage = '8-review';  Filler = 9; Threshold = 3; Extra = @{ LeaveUnmerged = $true };     Expect = 0 }
    @{ Name = 'blocked/ is parked on purpose';     Stage = '8-review';  Filler = 9; Threshold = 3; Extra = @{ Folder = 'blocked' };        Expect = 0 }
    @{ Name = 'A bulk edit does not reset it';     Stage = '8-review';  Filler = 9; Threshold = 3; Extra = @{ TouchWithoutStage = $true }; Expect = 1 }
    @{ Name = '9-ship in backlog/ fails at once';  Stage = '9-ship';    Filler = 0; Threshold = 3; Extra = @{};                            Expect = 1 }
)

foreach ($case in $cases) {
    $arguments = @{ Stage = $case.Stage; Filler = $case.Filler } + $case.Extra
    $fixture = New-StaleFixture @arguments
    try {
        $problems = @(Get-BacklogStaleOpenProblem -RepoRoot $fixture.Repo -Threshold $case.Threshold)
        Assert-True ($problems.Count -eq $case.Expect) "$($case.Name): expected $($case.Expect) problem(s), got $($problems.Count): $($problems -join ' | ')"
    }
    finally { Remove-Fixture $fixture.Root }
}

# --- The default limit is the measured one ---

$fixture = New-StaleFixture -Stage '8-review' -Filler 8
try {
    $problems = @(Get-BacklogStaleOpenProblem -RepoRoot $fixture.Repo)
    Assert-True ($problems.Count -eq 0) "Eight commits must sit under the default limit of 12, got: $($problems -join ' | ')"
}
finally { Remove-Fixture $fixture.Root }

$fixture = New-StaleFixture -Stage '8-review' -Filler 14
try {
    $problems = @(Get-BacklogStaleOpenProblem -RepoRoot $fixture.Repo)
    Assert-True ($problems.Count -eq 1) "Fourteen commits must break the default limit of 12, got: $($problems -join ' | ')"
}
finally { Remove-Fixture $fixture.Root }

# --- Report ---

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host ''; Write-Host $failure -ForegroundColor Red }
    Write-Host ''
    throw "Backlog stale-open tests failed with $($failures.Count) problem(s). See the detail above."
}

Write-Host 'Backlog stale-open tests passed.'
