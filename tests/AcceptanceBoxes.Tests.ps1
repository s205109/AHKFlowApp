#Requires -Version 7.0

# Backlog 151. The acceptance-box counter, driven straight against text. No git here: the
# counter is pure, and that is the whole reason it lives in its own file.
#
# Run it by hand with:  pwsh ./tests/AcceptanceBoxes.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts/backlog-acceptance.common.ps1')

$failures = @()

function Assert-Count {
    param([string] $Name, [string[]] $Lines, [int] $ExpectedTotal, [int] $ExpectedTicked)
    $actual = Get-AcceptanceBoxCount -Lines $Lines
    if ($actual.Total -ne $ExpectedTotal) {
        $script:failures += "$Name : expected Total $ExpectedTotal, got $($actual.Total)"
    }
    if ($actual.Ticked -ne $ExpectedTicked) {
        $script:failures += "$Name : expected Ticked $ExpectedTicked, got $($actual.Ticked)"
    }
}

# --- The plain case ---

Assert-Count 'two boxes, one ticked' @(
    '## Acceptance criteria'
    ''
    '- [x] first'
    '- [ ] second'
) 2 1

# --- A box outside the section is not counted (backlog 072) ---

Assert-Count 'box under another heading is ignored' @(
    '## Acceptance criteria'
    ''
    '- [x] first'
    ''
    '## Friction baselines'
    ''
    '- [ ] not an acceptance box'
) 1 1

# --- A ### subheading does not end the section (backlog 121, 122) ---

Assert-Count 'subheading keeps the section open' @(
    '## Acceptance criteria'
    ''
    '### First group'
    ''
    '- [x] one'
    ''
    '### Second group'
    ''
    '- [x] two'
) 2 2

# --- Fenced code is skipped (backlog 132) ---

Assert-Count 'fenced box is ignored' @(
    '## Acceptance criteria'
    ''
    '- [x] real'
    ''
    '```'
    '- [ ] example inside a fence'
    '```'
) 1 1

# --- Only column zero counts ---

Assert-Count 'indented box is ignored' @(
    '## Acceptance criteria'
    ''
    '- [x] real'
    '  - [ ] nested detail'
) 1 1

# --- No section at all ---

Assert-Count 'no acceptance section' @(
    '# 999 - Something'
    ''
    '## Summary'
    ''
    '- [ ] not acceptance'
) 0 0

# --- A section with no boxes ---

Assert-Count 'empty section' @(
    '## Acceptance criteria'
    ''
    'Nothing here yet.'
) 0 0

# --- An upper-case mark counts as ticked ---

Assert-Count 'upper-case X counts' @(
    '## Acceptance criteria'
    ''
    '- [X] first'
) 1 1

# --- Null and empty input ---

Assert-Count 'empty array' @() 0 0
$nullResult = Get-AcceptanceBoxCount -Lines $null
if ($nullResult.Total -ne 0 -or $nullResult.Ticked -ne 0) {
    $failures += 'null input must count zero and zero'
}

# --- The real backlog parses ---
#
# Every open item must report at least one box. A zero there means the counter stopped reading
# the section, which is the failure mode a fixture cannot show.

$backlogRoot = Join-Path $repoRoot 'backlog'
foreach ($file in (Get-ChildItem -LiteralPath $backlogRoot -Filter '*.md')) {
    if ($file.Name -eq '000-backlog-item-template.md') { continue }
    $count = Get-AcceptanceBoxCount -Lines (Get-Content -LiteralPath $file.FullName)
    if ($count.Total -eq 0) {
        $failures += "$($file.Name) : the counter found no acceptance box in a real open item"
    }
}

# Backlog 072 proves the section scope against real data. Measured 2026-09-10: the file holds 30
# checkboxes, and only 19 of them are Acceptance boxes. The other 11 sit under
# '## Friction baselines'. A counter with no section scope reports 30 here.
#
# Note what this item is NOT: it is not a fully ticked item. One of its 19 Acceptance boxes is
# honestly unticked, at line 99, with the reason written beside it. AGENTS.md asks for exactly
# that, so 18 of 19 is the correct reading and not a defect.
$item072 = Join-Path $backlogRoot 'done/072-process-wave-2-parity-drift-guard-templates.md'
if (Test-Path -LiteralPath $item072) {
    $lines072 = @(Get-Content -LiteralPath $item072)
    $count072 = Get-AcceptanceBoxCount -Lines $lines072

    $wholeFile = @($lines072 | Where-Object { $_ -match '^- \[[ xX]\] ' }).Count
    if ($wholeFile -le $count072.Total) {
        $failures += "backlog 072 must hold more checkboxes than it holds Acceptance boxes, got $wholeFile in the file and $($count072.Total) in the section. The section scope is not being applied."
    }
    if ($count072.Total -ne 19) {
        $failures += "backlog 072 must read 19 Acceptance boxes, got $($count072.Total). A count of $wholeFile means the section scope was dropped."
    }
    if ($count072.Ticked -ne 18) {
        $failures += "backlog 072 must read 18 of its 19 Acceptance boxes as ticked, got $($count072.Ticked)."
    }
}
else {
    $failures += 'backlog 072 was not found, so the section-scope check could not run.'
}

# --- Report ---

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host ''; Write-Host $failure -ForegroundColor Red }
    Write-Host ''
    throw "Acceptance box tests failed with $($failures.Count) problem(s). See the detail above."
}

Write-Host 'Acceptance box tests passed.'
