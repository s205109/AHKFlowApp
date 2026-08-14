#Requires -Version 7.0

# A backlog item named its spec but not its plan, so a session that picked the item up built from
# the spec and missed the plan (backlog 077, 2026-08-13). This suite proves the check that stops
# it: an open or blocked item at Stage 4-execute or later must name its plan, or say why it has
# none.
#
# Run it by hand with:  pwsh ./tests/BacklogPlanPointer.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts/backlog.common.ps1')

$failures = @()

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) {
        $script:failures += $Message
    }
}

function New-TemporaryBacklogRoot {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "backlog-pointer-tests-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tempRoot 'done') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tempRoot 'blocked') -Force | Out-Null
    return $tempRoot
}

# Writes one item. $Stage of '' writes no Stage line. $Notes is the body of the
# '## Notes / dependencies' section, one string per line.
function New-PointerItem {
    param(
        [Parameter(Mandatory)][string] $Root,
        [Parameter(Mandatory)][string] $Name,
        [string] $Stage = '',
        [string[]] $Notes = @(),
        [string] $Subfolder = ''
    )

    $key = ($Name -split '-')[0]
    $lines = @("# $key - Fixture item", '', '## Metadata', '', '- **Epic**: Fixture')
    if ($Stage) {
        $lines += "- **Stage**: $Stage"
    }
    $lines += @('', '## Notes / dependencies', '')
    $lines += $Notes

    $folder = if ($Subfolder) { Join-Path $Root $Subfolder } else { $Root }
    $path = Join-Path $folder $Name
    Set-Content -LiteralPath $path -Value (($lines -join "`n") + "`n")
    return $path
}

$validPlan = '- Plan: `docs/superpowers/plans/2026-08-14-a-topic-plan-101.md`'
$secondPlan = '- Plan: `docs/superpowers/plans/2026-08-14-another-topic-plan-101.md`'

# Each case is: a name, the Stage, the Notes body, the subfolder, and whether it must pass.
$cases = @(
    @{ Name = 'No Stage line is skipped';             Stage = '';           Notes = @();                    Folder = '';        ShouldPass = $true }
    @{ Name = 'Stage 3-plan is skipped';              Stage = '3-plan';     Notes = @();                    Folder = '';        ShouldPass = $true }
    @{ Name = 'Stage 4-execute needs a pointer';      Stage = '4-execute';  Notes = @();                    Folder = '';        ShouldPass = $false }
    @{ Name = 'Stage 10-cleanup needs a pointer';     Stage = '10-cleanup'; Notes = @();                    Folder = '';        ShouldPass = $false }
    @{ Name = 'done/ is skipped';                     Stage = '9-ship';     Notes = @();                    Folder = 'done';    ShouldPass = $true }
    @{ Name = 'blocked/ is checked';                  Stage = '4-execute';  Notes = @();                    Folder = 'blocked'; ShouldPass = $false }
    @{ Name = 'One valid plan path passes';           Stage = '4-execute';  Notes = @($validPlan);          Folder = '';        ShouldPass = $true }
    @{ Name = 'Two valid plan paths pass';            Stage = '4-execute';  Notes = @($validPlan, $secondPlan); Folder = '';     ShouldPass = $true }
    @{ Name = 'none with a reason passes';            Stage = '4-execute';  Notes = @("- Plan: none $([char]0x2014) shipped without a plan"); Folder = ''; ShouldPass = $true }
    @{ Name = 'A bare none fails';                    Stage = '4-execute';  Notes = @('- Plan: none');      Folder = '';        ShouldPass = $false }
    @{ Name = 'none with an empty reason fails';      Stage = '4-execute';  Notes = @("- Plan: none $([char]0x2014)   "); Folder = ''; ShouldPass = $false }
    @{ Name = 'A path mixed with none fails';         Stage = '4-execute';  Notes = @($validPlan, "- Plan: none $([char]0x2014) why"); Folder = ''; ShouldPass = $false }
    @{ Name = 'Two none bullets fail';                Stage = '4-execute';  Notes = @("- Plan: none $([char]0x2014) a", "- Plan: none $([char]0x2014) b"); Folder = ''; ShouldPass = $false }
    @{ Name = 'A path without backticks fails';       Stage = '4-execute';  Notes = @('- Plan: docs/superpowers/plans/a-plan-101.md'); Folder = ''; ShouldPass = $false }
    @{ Name = 'A path with a subfolder fails';        Stage = '4-execute';  Notes = @('- Plan: `docs/superpowers/plans/old/a-plan-101.md`'); Folder = ''; ShouldPass = $false }
    @{ Name = 'A specs/ path fails';                  Stage = '4-execute';  Notes = @('- Plan: `docs/superpowers/specs/a-design-101.md`'); Folder = ''; ShouldPass = $false }
    @{ Name = 'A non-md extension fails';             Stage = '4-execute';  Notes = @('- Plan: `docs/superpowers/plans/a-plan-101.txt`'); Folder = ''; ShouldPass = $false }
    @{ Name = 'Trailing text after the path fails';   Stage = '4-execute';  Notes = @('- Plan: `docs/superpowers/plans/a-plan-101.md` (superseded)'); Folder = ''; ShouldPass = $false }
    @{ Name = 'A trailing full stop is allowed';      Stage = '4-execute';  Notes = @('- Plan: `docs/superpowers/plans/a-plan-101.md`.'); Folder = ''; ShouldPass = $true }
    @{ Name = 'The template placeholder fails';       Stage = '4-execute';  Notes = @('- Plan: <path, or "none ' + [char]0x2014 + ' reason">'); Folder = ''; ShouldPass = $false }
    @{ Name = 'A Superseded plan bullet is ignored';  Stage = '4-execute';  Notes = @($validPlan, '- Superseded plan: `docs/superpowers/plans/old-plan-101.md`'); Folder = ''; ShouldPass = $true }
)

$caseNumber = 100
foreach ($case in $cases) {
    $caseNumber++
    $tempRoot = New-TemporaryBacklogRoot
    try {
        New-PointerItem -Root $tempRoot -Name "$caseNumber-fixture.md" -Stage $case.Stage -Notes $case.Notes -Subfolder $case.Folder | Out-Null
        $problems = @(Get-BacklogPointerProblem -BacklogRoot $tempRoot)

        if ($case.ShouldPass) {
            Assert-True ($problems.Count -eq 0) "$($case.Name): expected no problem, got: $($problems -join ' | ')"
        }
        else {
            Assert-True ($problems.Count -eq 1) "$($case.Name): expected exactly one problem, got $($problems.Count): $($problems -join ' | ')"
            if ($problems.Count -ge 1) {
                Assert-True ($problems[0] -like "*$caseNumber-fixture.md*") "$($case.Name): the message must name the file, got: $($problems[0])"
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

# --- A '- Plan:' bullet outside the Notes section does not count ---

$tempRoot = New-TemporaryBacklogRoot
try {
    $path = Join-Path $tempRoot '130-outside.md'
    $body = @(
        '# 130 - Fixture item'
        ''
        '## Metadata'
        ''
        '- **Stage**: 4-execute'
        '- Plan: `docs/superpowers/plans/2026-08-14-a-topic-plan-130.md`'
        ''
        '## Notes / dependencies'
        ''
    )
    Set-Content -LiteralPath $path -Value (($body -join "`n") + "`n")

    $problems = @(Get-BacklogPointerProblem -BacklogRoot $tempRoot)
    Assert-True ($problems.Count -eq 1) "A pointer outside the Notes section must still fail, got: $($problems -join ' | ')"
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

# --- Two Stage lines fail, and the message quotes both values ---

$tempRoot = New-TemporaryBacklogRoot
try {
    $path = Join-Path $tempRoot '131-duplicate.md'
    $body = @(
        '# 131 - Fixture item'
        ''
        '## Metadata'
        ''
        '- **Stage**: 4-execute'
        '- **Stage**: 9-ship'
        ''
        '## Notes / dependencies'
        ''
        '- Plan: `docs/superpowers/plans/2026-08-14-a-topic-plan-131.md`'
    )
    Set-Content -LiteralPath $path -Value (($body -join "`n") + "`n")

    $problems = @(Get-BacklogPointerProblem -BacklogRoot $tempRoot)
    Assert-True ($problems.Count -eq 1) "Two Stage lines must fail, got: $($problems -join ' | ')"
    if ($problems.Count -ge 1) {
        Assert-True ($problems[0] -like '*4-execute*' -and $problems[0] -like '*9-ship*') "The duplicate message must quote both values, got: $($problems[0])"
    }
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

# --- An unknown stage value fails closed ---

$tempRoot = New-TemporaryBacklogRoot
try {
    New-PointerItem -Root $tempRoot -Name '132-unknown.md' -Stage '4-executed' -Notes @() | Out-Null

    $problems = @(Get-BacklogPointerProblem -BacklogRoot $tempRoot)
    Assert-True ($problems.Count -eq 1) "An unknown stage value must fail, got: $($problems -join ' | ')"
    if ($problems.Count -ge 1) {
        Assert-True ($problems[0] -like '*4-executed*') "The unknown-stage message must quote the value, got: $($problems[0])"
    }
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
    throw "Backlog plan pointer tests failed with $($failures.Count) problem(s). See the detail above."
}

Write-Host "Backlog plan pointer tests passed. $($cases.Count) table cases, plus the blocks below them."
