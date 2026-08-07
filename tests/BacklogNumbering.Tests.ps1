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
    Set-Content -LiteralPath (Join-Path $tempRoot '022-parent.md') -Value "# 022 - Parent`n"
    Set-Content -LiteralPath (Join-Path $tempRoot '022b-followup.md') -Value "# 022b - Followup`n"

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
    Set-Content -LiteralPath (Join-Path $tempRoot '060-open.md') -Value "# 060 - Open`n"

    $problems = @(Get-BacklogProblem -BacklogRoot $tempRoot)
    Assert-True ($problems.Count -eq 0) "A root with no blocked/ folder should pass, found: $($problems -join ' | ')"
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
