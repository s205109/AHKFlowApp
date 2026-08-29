#Requires -Version 7.0

# Backlog item numbers are picked by hand today. Nothing checks the result, so two files have
# already ended up sharing the same number (backlog 061). This test proves the real backlog/ is
# clean today, and that Get-BacklogProblem and new-backlog-item.ps1 catch the failure modes that
# let that happen.
#
# Run it by hand with:  pwsh ./tests/BacklogNumbering.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts/backlog.common.ps1')

$scaffoldScript = Join-Path $repoRoot 'scripts/new-backlog-item.ps1'
$templatePath = Join-Path $repoRoot 'backlog/000-backlog-item-template.md'

$failures = @()

function New-TemporaryBacklogRoot {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "backlog-numbering-tests-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tempRoot 'done') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tempRoot 'blocked') -Force | Out-Null
    Copy-Item -LiteralPath $templatePath -Destination (Join-Path $tempRoot '000-backlog-item-template.md')
    return $tempRoot
}

function Invoke-FixtureGit {
    param([string] $RepoDir, [string[]] $GitArgs)
    $out = & git -C $RepoDir @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed: $out" }
    return $out
}

# A git repository with backlog/, backlog/done/, and backlog/blocked/ folders and one committed
# item on main. Returns the repo path. Callers add branches and worktrees on top.
function New-GitBacklogFixture {
    param([string] $FirstItem = '100-first.md')

    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('backlog-num-git-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $repo = Join-Path $root 'repo'
    New-Item -ItemType Directory -Path $repo -Force | Out-Null

    & git -C $repo init --quiet
    & git -C $repo symbolic-ref HEAD refs/heads/main
    Invoke-FixtureGit $repo @('config', 'user.email', 'test@example.com') | Out-Null
    Invoke-FixtureGit $repo @('config', 'user.name', 'Backlog Numbering Test') | Out-Null

    foreach ($subfolder in @('backlog', 'backlog/done', 'backlog/blocked')) {
        New-Item -ItemType Directory -Path (Join-Path $repo $subfolder) -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $repo "$subfolder/.gitkeep") -Value '' -Encoding utf8
    }
    Copy-Item -LiteralPath $templatePath -Destination (Join-Path $repo 'backlog/000-backlog-item-template.md')

    Set-Content -LiteralPath (Join-Path $repo "backlog/$FirstItem") -Value "# $($FirstItem.Substring(0,3)) - First`n" -Encoding utf8
    Invoke-FixtureGit $repo @('add', '-A') | Out-Null
    Invoke-FixtureGit $repo @('commit', '--quiet', '-m', 'file the first item') | Out-Null

    return (Resolve-Path -LiteralPath $repo).Path
}

# Adds a branch off main that commits one backlog file, then returns HEAD to main.
function Add-FixtureBranchItem {
    param([string] $RepoDir, [string] $Branch, [string] $ItemFile)
    Invoke-FixtureGit $RepoDir @('checkout', '--quiet', '-b', $Branch, 'main') | Out-Null
    Set-Content -LiteralPath (Join-Path $RepoDir "backlog/$ItemFile") -Value "# $($ItemFile.Substring(0,3)) - Branch item`n" -Encoding utf8
    Invoke-FixtureGit $RepoDir @('add', '-A') | Out-Null
    Invoke-FixtureGit $RepoDir @('commit', '--quiet', '-m', "file $ItemFile on $Branch") | Out-Null
    Invoke-FixtureGit $RepoDir @('checkout', '--quiet', 'main') | Out-Null
}

function Remove-GitFixture {
    param([string] $RepoPath)
    $root = Split-Path -Parent $RepoPath
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop; return }
        catch { if ($attempt -eq 5) { return }; Start-Sleep -Milliseconds 300 }
    }
}

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) {
        $script:failures += $Message
    }
}

# Get-BacklogProblem requires a Stage line on every item (backlog 087), so a fixture file needs a
# metadata block rather than a bare heading. Fixtures that only filter their problems can still
# use a bare heading; the two cases that assert a zero problem count cannot.
function New-TestItemText {
    param(
        [Parameter(Mandatory)][string] $Heading,
        [string] $Stage = '1-pickup'
    )
    return "$Heading`n`n## Metadata`n`n- **Type**: Bug`n- **Stage**: $Stage`n"
}

# --- Case 1: the real backlog/ passes with zero problems ---

$realProblems = @(Get-BacklogProblem -BacklogRoot (Join-Path $repoRoot 'backlog'))
Assert-True ($realProblems.Count -eq 0) "Real backlog/ should have zero problems, found: $($realProblems -join ' | ')"

# --- Case 2: two files sharing a number fail, naming both files ---

$tempRoot = New-TemporaryBacklogRoot
try {
    Set-Content -LiteralPath (Join-Path $tempRoot '058-first.md') -Value "# 058 - First`n"
    Set-Content -LiteralPath (Join-Path $tempRoot 'done/058-second.md') -Value "# 058 - Second`n"

    $problems = @(Get-BacklogProblem -BacklogRoot $tempRoot)
    $dupProblem = $problems | Where-Object { $_ -like "*Duplicate backlog number '058'*" }
    Assert-True ($null -ne $dupProblem) "Expected a duplicate-058 problem, got: $($problems -join ' | ')"
    if ($dupProblem) {
        Assert-True ($dupProblem -like '*058-first.md*') "Duplicate message should name 058-first.md: $dupProblem"
        Assert-True ($dupProblem -like '*058-second.md*') "Duplicate message should name 058-second.md: $dupProblem"
    }
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

# --- Case 3: 022 plus 022b pass ---

$tempRoot = New-TemporaryBacklogRoot
try {
    Set-Content -LiteralPath (Join-Path $tempRoot '022-parent.md') -Value (New-TestItemText -Heading '# 022 - Parent')
    Set-Content -LiteralPath (Join-Path $tempRoot '022b-followup.md') -Value (New-TestItemText -Heading '# 022b - Followup')

    $problems = @(Get-BacklogProblem -BacklogRoot $tempRoot)
    Assert-True ($problems.Count -eq 0) "022 and 022b should both pass, found: $($problems -join ' | ')"
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

# --- Case 4: a file not matching NNN[a-z]?-slug.md fails ---

$tempRoot = New-TemporaryBacklogRoot
try {
    Set-Content -LiteralPath (Join-Path $tempRoot 'notes.md') -Value "# Notes`n"

    $problems = @(Get-BacklogProblem -BacklogRoot $tempRoot)
    $badName = $problems | Where-Object { $_ -like '*notes.md*' }
    Assert-True ($null -ne $badName) "Expected notes.md to fail the file name check, got: $($problems -join ' | ')"
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

# --- Case 5: heading number drift fails ---

$tempRoot = New-TemporaryBacklogRoot
try {
    Set-Content -LiteralPath (Join-Path $tempRoot '063-x.md') -Value "# 051 - x`n"

    $problems = @(Get-BacklogProblem -BacklogRoot $tempRoot)
    $drift = $problems | Where-Object { $_ -like '*063-x.md*' -and $_ -like '*Heading number mismatch*' }
    Assert-True ($null -ne $drift) "Expected a heading mismatch for 063-x.md, got: $($problems -join ' | ')"
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

# --- Case 6: the template's literal '# NNN - <Title>' heading does not fail ---

$tempRoot = New-TemporaryBacklogRoot
try {
    $problems = @(Get-BacklogProblem -BacklogRoot $tempRoot)
    Assert-True ($problems.Count -eq 0) "A folder with only the template should have zero problems, found: $($problems -join ' | ')"
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

# --- Case 7: the scaffold script picks the next free number, twice in a row ---

$tempRoot = New-TemporaryBacklogRoot
try {
    Set-Content -LiteralPath (Join-Path $tempRoot '062-existing.md') -Value "# 062 - Existing`n"

    & $scaffoldScript -Title 'Smoke test throwaway item' -BacklogRoot $tempRoot | Out-Null
    $firstPath = Join-Path $tempRoot '063-smoke-test-throwaway-item.md'
    Assert-True (Test-Path -LiteralPath $firstPath) "Expected $firstPath to be created"
    if (Test-Path -LiteralPath $firstPath) {
        $heading = Get-Content -LiteralPath $firstPath -TotalCount 1
        Assert-True ($heading -eq '# 063 - Smoke test throwaway item') "Expected heading '# 063 - Smoke test throwaway item', got '$heading'"
    }

    & $scaffoldScript -Title 'Second throwaway item' -BacklogRoot $tempRoot | Out-Null
    $secondPath = Join-Path $tempRoot '064-second-throwaway-item.md'
    Assert-True (Test-Path -LiteralPath $secondPath) "Expected $secondPath to be created"
    if (Test-Path -LiteralPath $secondPath) {
        $heading = Get-Content -LiteralPath $secondPath -TotalCount 1
        Assert-True ($heading -eq '# 064 - Second throwaway item') "Expected heading '# 064 - Second throwaway item', got '$heading'"
    }
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

# --- Case 8: New-BacklogFile writes UTF-8 without BOM and LF-only line endings ---

$tempRoot = New-TemporaryBacklogRoot
try {
    $targetPath = Join-Path $tempRoot '001-new-file.md'
    New-BacklogFile -Path $targetPath -Content "# 001 - New file`nSecond line`n"

    $bytes = [System.IO.File]::ReadAllBytes($targetPath)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    Assert-True (-not $hasBom) 'New-BacklogFile should not write a UTF-8 BOM'

    $rawText = [System.IO.File]::ReadAllText($targetPath)
    Assert-True (-not $rawText.Contains("`r")) 'New-BacklogFile should write LF-only line endings'
    Assert-True ($rawText -eq "# 001 - New file`nSecond line`n") "Unexpected content: '$rawText'"
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

# --- Case 9: a concurrent writer between number selection and the write must not be clobbered ---
#
# This exercises the same write path new-backlog-item.ps1 uses in production, not just a
# standalone guard function. FileMode.CreateNew (inside New-BacklogFile) makes the existence
# check and the write one atomic operation, so a file that appears at the target path after
# number selection but before the write causes a throw instead of a silent overwrite.

$tempRoot = New-TemporaryBacklogRoot
try {
    $targetPath = Join-Path $tempRoot '001-race.md'

    # Simulate a second process creating the file after this process picked the same number.
    Set-Content -LiteralPath $targetPath -Value 'first writer content' -NoNewline

    $threw = $false
    try {
        New-BacklogFile -Path $targetPath -Content 'second writer content'
    }
    catch {
        $threw = $true
    }
    Assert-True $threw 'Expected New-BacklogFile to throw when the target already exists'

    $finalContent = Get-Content -LiteralPath $targetPath -Raw
    Assert-True ($finalContent -eq 'first writer content') "Concurrent write should not clobber the first writer's file, got: '$finalContent'"
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

# --- Case 10: a blocked item in blocked/ still holds its number ---
#
# A blocked item is not finished, so it keeps its number reserved. If the scan skipped
# blocked/, this duplicate would go unreported and two files could end up sharing one number —
# the exact failure backlog 061 was filed for.

$tempRoot = New-TemporaryBacklogRoot
try {
    Set-Content -LiteralPath (Join-Path $tempRoot '058-open.md') -Value "# 058 - Open`n"
    Set-Content -LiteralPath (Join-Path $tempRoot 'blocked/058-blocked.md') -Value "# 058 - Blocked`n"

    $problems = @(Get-BacklogProblem -BacklogRoot $tempRoot)
    $dupProblem = $problems | Where-Object { $_ -like "*Duplicate backlog number '058'*" }
    Assert-True ($null -ne $dupProblem) "Expected a duplicate-058 problem across backlog/ and blocked/, got: $($problems -join ' | ')"
    if ($dupProblem) {
        Assert-True ($dupProblem -like '*058-open.md*') "Duplicate message should name 058-open.md: $dupProblem"
        Assert-True ($dupProblem -like '*blocked/058-blocked.md*') "Duplicate message should name blocked/058-blocked.md: $dupProblem"
    }
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

# --- Case 11: a blocked item counts toward the next free number ---

$tempRoot = New-TemporaryBacklogRoot
try {
    Set-Content -LiteralPath (Join-Path $tempRoot '060-open.md') -Value "# 060 - Open`n"
    Set-Content -LiteralPath (Join-Path $tempRoot 'blocked/071-blocked.md') -Value "# 071 - Blocked`n"

    $next = Get-NextBacklogNumber -BacklogRoot $tempRoot
    Assert-True ($next -eq '072') "Expected the next number to follow the blocked item, got '$next'"
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

# --- Case 12: a backlog root with no blocked/ folder still works ---
#
# The folder is optional. A checkout that has never blocked an item has no blocked/ directory, and
# the scan must not fail on that.

$tempRoot = New-TemporaryBacklogRoot
try {
    Remove-Item -LiteralPath (Join-Path $tempRoot 'blocked') -Recurse -Force
    Set-Content -LiteralPath (Join-Path $tempRoot '060-open.md') -Value (New-TestItemText -Heading '# 060 - Open')

    $problems = @(Get-BacklogProblem -BacklogRoot $tempRoot)
    Assert-True ($problems.Count -eq 0) "A root with no blocked/ folder should pass, found: $($problems -join ' | ')"
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

# --- Case 13: the slug rule lives in slug.common.ps1 and still behaves the same ---
#
# new-worktree.ps1 requires PowerShell 5.1 and backlog.common.ps1 requires 7.0, so the two
# cannot share a file. They share this one instead. A second copy of the rule would let the
# worktree name and the backlog item file name drift apart.

$slugCommonPath = Join-Path $repoRoot 'scripts/slug.common.ps1'
Assert-True (Test-Path -LiteralPath $slugCommonPath) "Expected $slugCommonPath to exist"

$slugCommonText = Get-Content -LiteralPath $slugCommonPath -Raw
Assert-True ($slugCommonText -match '#Requires -Version 5\.1') 'slug.common.ps1 must declare #Requires -Version 5.1, or new-worktree.ps1 cannot dot-source it'

$backlogCommonText = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts/backlog.common.ps1') -Raw
Assert-True (([regex]::Matches($backlogCommonText, 'function ConvertTo-BacklogSlug')).Count -eq 0) 'backlog.common.ps1 must not define ConvertTo-BacklogSlug any more; it dot-sources slug.common.ps1'

Assert-True ((ConvertTo-BacklogSlug -Title 'Race Safe Intake') -eq 'race-safe-intake') 'Slug: spaces become hyphens and the result is lower case'
Assert-True ((ConvertTo-BacklogSlug -Title '  Downloads page: row stays disabled!  ') -eq 'downloads-page-row-stays-disabled') 'Slug: punctuation collapses and the edges are trimmed'
Assert-True ((ConvertTo-BacklogSlug -Title 'CLI winget distribution') -eq 'cli-winget-distribution') 'Slug: an acronym lower-cases like any other word'

# --- Case 14: the backlog item file name and the worktree name agree for one title ---
#
# Both sides call ConvertTo-BacklogSlug, so they agree by construction. This pins the
# construction. The -Title block in tests/WorktreeBranchName.Tests.ps1 pins the worktree side
# against the same function, so together they cover the end-to-end promise.
#
# $scaffoldScript is defined at tests/BacklogNumbering.Tests.ps1:19 and
# New-TemporaryBacklogRoot at :24.

$tempRoot = New-TemporaryBacklogRoot
try {
    $title = 'Downloads page row stays disabled'
    & $scaffoldScript -Title $title -BacklogRoot $tempRoot | Out-Null

    # New-TemporaryBacklogRoot copies the template in, so it is excluded here.
    $written = @(Get-ChildItem -LiteralPath $tempRoot -Filter '*.md' -File |
        Where-Object { $_.Name -ne '000-backlog-item-template.md' })
    Assert-True ($written.Count -eq 1) "Expected one backlog item file, got $($written.Count)"
    if ($written.Count -eq 1) {
        # Strip the 'NNN-' prefix the script adds; what remains must be the title's slug, which
        # is the slug new-worktree.ps1 -Title puts after 'wt-'.
        $fileSlug = $written[0].BaseName -replace '^\d{3}[a-z]?-', ''
        $expectedSlug = ConvertTo-BacklogSlug -Title $title
        Assert-True ($fileSlug -eq $expectedSlug) "The backlog item file slug '$fileSlug' must equal the title slug '$expectedSlug'"
    }
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

# --- Case 15: a scaffolded item inherits the template's Stage line ---
#
# new-backlog-item.ps1 copies every template line but the heading (scripts/new-backlog-item.ps1:41-43),
# so the template is the only place the field has to be written. This proves that, rather than
# assuming it.

$tempRoot = New-TemporaryBacklogRoot
try {
    & $scaffoldScript -Title 'Stage line throwaway item' -BacklogRoot $tempRoot | Out-Null
    $itemPath = Join-Path $tempRoot '001-stage-line-throwaway-item.md'
    Assert-True (Test-Path -LiteralPath $itemPath) "Expected $itemPath to be created"

    if (Test-Path -LiteralPath $itemPath) {
        $stageLines = @(Get-Content -LiteralPath $itemPath |
            Select-String -Pattern '^- \*\*Stage\*\*: 0-intake$')
        Assert-True ($stageLines.Count -eq 1) "A scaffolded item must carry exactly one '- **Stage**: 0-intake' line, found $($stageLines.Count)"
    }
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

# --- Case 15b: a scaffolded item carries Difficulty as well as Stage (backlog 072) ---
#
# Difficulty decides which stage the work starts at, so an item filed without it makes the
# classification a memory rather than a record. The scaffold script copies the template, so
# the template is again the only place the field has to be written.

$tempRoot = New-TemporaryBacklogRoot
try {
    & $scaffoldScript -Title 'Difficulty line throwaway item' -BacklogRoot $tempRoot | Out-Null
    $itemPath = Join-Path $tempRoot '001-difficulty-line-throwaway-item.md'
    Assert-True (Test-Path -LiteralPath $itemPath) "Expected $itemPath to be created"

    if (Test-Path -LiteralPath $itemPath) {
        $filedLines = Get-Content -LiteralPath $itemPath
        $difficultyLines = @($filedLines | Where-Object { $_ -match '^- \*\*Difficulty\*\*:' })
        Assert-True ($difficultyLines.Count -eq 1) "A scaffolded item must carry exactly one Difficulty line, found $($difficultyLines.Count)"
        $stageLines = @($filedLines | Where-Object { $_ -match '^- \*\*Stage\*\*:' })
        Assert-True ($stageLines.Count -eq 1) "A scaffolded item must still carry exactly one Stage line, found $($stageLines.Count)"
    }
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

# --- Cases 16 to 19: the Stage field ---
#
# The field is the durable record of where work stands (docs/development/workflow.md:78,634-642).
# Before backlog 087 nothing checked it, so a shipped item reached backlog/done/ still reading
# 'Stage: 4-execute' (backlog/done/080-race-safe-intake-remove-the-backlog-number-from-worktree-names.md).
# These four cases replace the reviewer's eye. New-TestItemText is defined at the top of this file.

# --- Case 16: an item with no Stage line fails, naming the file ---

$tempRoot = New-TemporaryBacklogRoot
try {
    Set-Content -LiteralPath (Join-Path $tempRoot '058-no-stage.md') -Value "# 058 - No stage`n"

    $problems = @(Get-BacklogProblem -BacklogRoot $tempRoot)
    $missing = $problems | Where-Object { $_ -like '*058-no-stage.md*' -and $_ -like '*Stage field problem*' }
    Assert-True ($null -ne $missing) "Expected a missing-Stage problem for 058-no-stage.md, got: $($problems -join ' | ')"
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

# --- Case 17: a shipped item that does not read 9-ship fails ---
#
# This is the backlog 080 regression: it reached backlog/done/ still reading 'Stage: 4-execute'.

$tempRoot = New-TemporaryBacklogRoot
try {
    Set-Content -LiteralPath (Join-Path $tempRoot 'done/059-shipped.md') `
        -Value (New-TestItemText -Heading '# 059 - Shipped' -Stage '4-execute')

    $problems = @(Get-BacklogProblem -BacklogRoot $tempRoot)
    $stale = $problems | Where-Object { $_ -like '*059-shipped.md*' -and $_ -like '*must read*9-ship*' }
    Assert-True ($null -ne $stale) "Expected a shipped-item Stage problem for done/059-shipped.md, got: $($problems -join ' | ')"
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

# --- Case 18: a stage value that is not one of the eleven fails ---

$tempRoot = New-TemporaryBacklogRoot
try {
    Set-Content -LiteralPath (Join-Path $tempRoot '060-bad-stage.md') `
        -Value (New-TestItemText -Heading '# 060 - Bad stage' -Stage '4-executing')

    $problems = @(Get-BacklogProblem -BacklogRoot $tempRoot)
    $unknown = $problems | Where-Object { $_ -like "*Unknown stage '4-executing'*" -and $_ -like '*060-bad-stage.md*' }
    Assert-True ($null -ne $unknown) "Expected an unknown-stage problem for 060-bad-stage.md, got: $($problems -join ' | ')"
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

# --- Case 19: a blocked item keeps its last stage, so blocked/ takes any valid value ---
#
# (`docs/development/workflow.md:715`, "A blocked item keeps its last stage"). Only done/ is pinned
# to a single value.

$tempRoot = New-TemporaryBacklogRoot
try {
    Set-Content -LiteralPath (Join-Path $tempRoot 'blocked/061-waiting.md') `
        -Value (New-TestItemText -Heading '# 061 - Waiting' -Stage '4-execute')

    $problems = @(Get-BacklogProblem -BacklogRoot $tempRoot)
    Assert-True ($problems.Count -eq 0) "A blocked item at 4-execute should pass, found: $($problems -join ' | ')"
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

# --- Case 20: a title slug longer than 40 characters is truncated with a hash suffix ---
#
# ConvertTo-BacklogSlug (scripts/slug.common.ps1) caps at 40 characters by default so a long
# backlog title cannot produce an overlong worktree directory name. Both new-worktree.ps1 and
# new-backlog-item.ps1 call it with no length argument, so the truncated slug still agrees
# between the worktree name and the backlog item file name (Case 14 pins the untruncated case).

$longTitle = 'Worktree removal decides merged by ancestry so a rebase merge is refused'
$longSlug = ConvertTo-BacklogSlug -Title $longTitle
Assert-True ($longSlug.Length -le 40) "Truncated slug '$longSlug' must be at most 40 characters, was $($longSlug.Length)"
Assert-True ($longSlug -match '-[0-9a-f]{8}$') "Truncated slug '$longSlug' must end with a '-' plus an 8-character lowercase hex hash"
Assert-True ((ConvertTo-BacklogSlug -Title $longTitle) -eq $longSlug) 'Slug: the hash suffix is deterministic, not random, so repeated calls agree'

$tempRoot = New-TemporaryBacklogRoot
try {
    & $scaffoldScript -Title $longTitle -BacklogRoot $tempRoot | Out-Null

    $written = @(Get-ChildItem -LiteralPath $tempRoot -Filter '*.md' -File |
        Where-Object { $_.Name -ne '000-backlog-item-template.md' })
    Assert-True ($written.Count -eq 1) "Expected one backlog item file, got $($written.Count)"
    if ($written.Count -eq 1) {
        $fileSlug = $written[0].BaseName -replace '^\d{3}[a-z]?-', ''
        Assert-True ($fileSlug -eq $longSlug) "The backlog item file slug '$fileSlug' must equal the truncated title slug '$longSlug', so a long title still keeps the worktree name and file name in agreement"
    }
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

# --- Case 21: a number committed on another branch is considered ---

$repo = New-GitBacklogFixture -FirstItem '100-first.md'
try {
    Add-FixtureBranchItem -RepoDir $repo -Branch 'feat/x' -ItemFile '130-on-branch.md'
    $next = Get-NextBacklogNumber -BacklogRoot (Join-Path $repo 'backlog')
    Assert-True ($next -eq '131') "The next number must follow the item on feat/x, got '$next'"
}
finally { Remove-GitFixture $repo }

# --- Case 22: two refs that each claim the same next number, and the function skips it ---

$repo = New-GitBacklogFixture -FirstItem '140-first.md'
try {
    Add-FixtureBranchItem -RepoDir $repo -Branch 'feat/x' -ItemFile '141-x.md'
    Add-FixtureBranchItem -RepoDir $repo -Branch 'feat/y' -ItemFile '141-y.md'
    $next = Get-NextBacklogNumber -BacklogRoot (Join-Path $repo 'backlog')
    Assert-True ($next -eq '142') "Two branches both holding 141 must push the next number to 142, got '$next'"
}
finally { Remove-GitFixture $repo }

# --- Case 23: a repository with no remote still returns a number ---

$repo = New-GitBacklogFixture -FirstItem '150-first.md'
try {
    $remotes = & git -C $repo remote
    Assert-True ([string]::IsNullOrWhiteSpace(($remotes -join ''))) 'The fixture must have no remote'
    $next = Get-NextBacklogNumber -BacklogRoot (Join-Path $repo 'backlog') -WarningVariable w -WarningAction SilentlyContinue
    Assert-True ($next -eq '151') "A repository with no remote must still number, got '$next'"
    Assert-True ($w.Count -eq 0) "No remote is not an error, so no warning is expected, got: $($w -join ' | ')"
}
finally { Remove-GitFixture $repo }

# --- Case 24: an unreadable ref makes the function warn, not fail ---
#
# A ref that points at a blob rather than a commit is a clean "cannot read this ref": git
# for-each-ref lists it because the object exists, and git ls-tree on it exits non-zero.

$repo = New-GitBacklogFixture -FirstItem '160-first.md'
try {
    $blobSha = (& git -C $repo rev-parse 'HEAD:backlog/160-first.md').Trim()
    Set-Content -LiteralPath (Join-Path $repo '.git/refs/heads/points-at-a-blob') -Value $blobSha -Encoding ascii -NoNewline

    $next = Get-NextBacklogNumber -BacklogRoot (Join-Path $repo 'backlog') -WarningVariable w -WarningAction SilentlyContinue
    Assert-True ($next -eq '161') "An unreadable ref must not stop numbering, got '$next'"
    Assert-True ($w.Count -ge 1) 'An unreadable ref must produce a warning'
    Assert-True (($w -join ' ') -like '*points-at-a-blob*') "The warning must name the ref, got: $($w -join ' | ')"
}
finally { Remove-GitFixture $repo }

# --- Case 25: two worktrees of one repository, neither pushed, pick different numbers ---

$repo = New-GitBacklogFixture -FirstItem '170-first.md'
try {
    # The main checkout scaffolds first and commits, the way Intake does.
    & $scaffoldScript -Title 'Item from the main checkout' -BacklogRoot (Join-Path $repo 'backlog') | Out-Null
    $firstNumber = (Get-ChildItem -LiteralPath (Join-Path $repo 'backlog') -Filter '*.md' -File |
        Where-Object { $_.BaseName -match '^\d{3}-item-from-the-main-checkout$' }).BaseName.Substring(0, 3)
    Assert-True ($firstNumber -eq '171') "The main checkout must pick 171, got '$firstNumber'"
    Invoke-FixtureGit $repo @('add', '-A') | Out-Null
    Invoke-FixtureGit $repo @('commit', '--quiet', '-m', 'file the main-checkout item') | Out-Null

    $tree = Join-Path (Split-Path -Parent $repo) 'wt-second'
    Invoke-FixtureGit $repo @('worktree', 'add', '--quiet', '-b', 'feat/second', $tree, 'main') | Out-Null

    $secondNext = Get-NextBacklogNumber -BacklogRoot (Join-Path $tree 'backlog')
    Assert-True ($secondNext -eq '172') "The second worktree must not reuse 171, got '$secondNext'"
}
finally { Remove-GitFixture $repo }

# --- Case 26: an item written but not committed in a sibling worktree is still seen ---

$repo = New-GitBacklogFixture -FirstItem '180-first.md'
try {
    $tree = Join-Path (Split-Path -Parent $repo) 'wt-uncommitted'
    Invoke-FixtureGit $repo @('worktree', 'add', '--quiet', '-b', 'feat/uncommitted', $tree, 'main') | Out-Null

    # The sibling worktree scaffolds an item and does NOT commit it.
    & $scaffoldScript -Title 'Uncommitted sibling item' -BacklogRoot (Join-Path $tree 'backlog') | Out-Null

    $next = Get-NextBacklogNumber -BacklogRoot (Join-Path $repo 'backlog')
    Assert-True ($next -eq '182') "The main checkout must skip the uncommitted 181 in the sibling worktree, got '$next'"
}
finally { Remove-GitFixture $repo }

# --- Case 27: a number reachable only from a tag is considered ---
#
# "Any local or remote ref" includes tags. release-cli.yml tags releases as v*, and this repo
# already carries refs/tags/v0.1.0 through v0.1.3.

$repo = New-GitBacklogFixture -FirstItem '200-first.md'
try {
    Add-FixtureBranchItem -RepoDir $repo -Branch 'tmp/tagbase' -ItemFile '250-tagged.md'
    Invoke-FixtureGit $repo @('tag', 'v9.9.9', 'tmp/tagbase') | Out-Null
    # Delete the branch so only the tag reaches 250. A branch scan alone would now miss it.
    Invoke-FixtureGit $repo @('branch', '-D', 'tmp/tagbase') | Out-Null

    $next = Get-NextBacklogNumber -BacklogRoot (Join-Path $repo 'backlog')
    Assert-True ($next -eq '251') "A number reachable only from a tag must be considered, got '$next'"
}
finally { Remove-GitFixture $repo }

# --- Case 28: the helper works when $PSNativeCommandUseErrorActionPreference does not exist ---
#
# That variable is new in PowerShell 7.3. Under Set-StrictMode an unguarded read of it throws on
# 7.0 to 7.2. The runner has 7.4, so simulate the older host by removing the variable for one call.

$repo = New-GitBacklogFixture -FirstItem '190-first.md'
try {
    $hadVar = Test-Path -LiteralPath 'Variable:PSNativeCommandUseErrorActionPreference'
    $savedVar = if ($hadVar) { $PSNativeCommandUseErrorActionPreference } else { $null }
    if ($hadVar) { Remove-Item -LiteralPath 'Variable:PSNativeCommandUseErrorActionPreference' }
    try {
        $next = Get-NextBacklogNumber -BacklogRoot (Join-Path $repo 'backlog')
        Assert-True ($next -eq '191') "The helper must work with the native-preference variable absent, got '$next'"
    }
    finally {
        if ($hadVar) { Set-Variable -Name 'PSNativeCommandUseErrorActionPreference' -Value $savedVar -Scope Global }
    }
}
finally { Remove-GitFixture $repo }

# --- Case 29: a branch named 'head' is read, not skipped ---
#
# refs/remotes/<remote>/HEAD is a symbolic alias and is skipped on purpose. Git also accepts a
# branch called 'head' in lower case. That is an ordinary ref with an ordinary backlog tree
# behind it, so its numbers must count.

$repo = New-GitBacklogFixture -FirstItem '210-first.md'
try {
    Add-FixtureBranchItem -RepoDir $repo -Branch 'head' -ItemFile '260-on-head-branch.md'
    $refNames = @(& git -C $repo for-each-ref --format='%(refname)' refs/heads)
    Assert-True ($refNames -ccontains 'refs/heads/head') "The fixture must create refs/heads/head, got: $($refNames -join ', ')"

    $next = Get-NextBacklogNumber -BacklogRoot (Join-Path $repo 'backlog')
    Assert-True ($next -eq '261') "A branch named 'head' holds 260, so the next number is 261, got '$next'"
}
finally { Remove-GitFixture $repo }

# --- Case 30: git metadata that cannot be read produces a warning ---
#
# A .git file pointing at a directory that does not exist. Git reports the same "not a git
# repository" message it gives for a folder with no repository at all, so the message cannot tell
# the two apart. The .git entry is there, so this one must warn.

$corruptRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('backlog-num-corrupt-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    foreach ($subfolder in @('backlog', 'backlog/done', 'backlog/blocked')) {
        New-Item -ItemType Directory -Path (Join-Path $corruptRoot $subfolder) -Force | Out-Null
    }
    Set-Content -LiteralPath (Join-Path $corruptRoot 'backlog/220-first.md') -Value "# 220 - First`n" -Encoding utf8
    Set-Content -LiteralPath (Join-Path $corruptRoot '.git') -Value 'gitdir: ./no-such-git-dir' -Encoding ascii

    $next = Get-NextBacklogNumber -BacklogRoot (Join-Path $corruptRoot 'backlog') `
        -WarningVariable corruptWarnings -WarningAction SilentlyContinue
    Assert-True ($next -eq '221') "Unreadable git metadata must not stop numbering, got '$next'"
    Assert-True ($corruptWarnings.Count -ge 1) 'Unreadable git metadata must warn, so the caller knows numbers held on refs were not read'
}
finally { Remove-Item -LiteralPath $corruptRoot -Recurse -Force -ErrorAction SilentlyContinue }

# --- Case 31: a folder with no repository behind it stays silent ---
#
# The other half of Case 30. Every fixture test runs in such a folder, and that is not an error.

$tempRoot = New-TemporaryBacklogRoot
try {
    Set-Content -LiteralPath (Join-Path $tempRoot '230-first.md') -Value "# 230 - First`n"

    $next = Get-NextBacklogNumber -BacklogRoot $tempRoot -WarningVariable plainWarnings -WarningAction SilentlyContinue
    Assert-True ($next -eq '231') "A folder with no repository must still number, got '$next'"
    Assert-True ($plainWarnings.Count -eq 0) "No repository is not an error, so no warning is expected, got: $($plainWarnings -join ' | ')"
}
finally { Remove-Item -LiteralPath $tempRoot -Recurse -Force }

# --- Report ---

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Host ''
        Write-Host $failure -ForegroundColor Red
    }
    Write-Host ''
    throw "Backlog numbering tests failed with $($failures.Count) problem(s). See the detail above."
}

$itemCount = @(Get-BacklogItem -BacklogRoot (Join-Path $repoRoot 'backlog')).Count
Write-Host "Backlog numbering tests passed. $itemCount backlog items checked."
