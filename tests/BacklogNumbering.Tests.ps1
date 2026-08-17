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
# docs/development/workflow.md:649 — "A blocked item keeps its last stage". Only done/ is pinned
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
