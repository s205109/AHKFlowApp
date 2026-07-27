#Requires -Version 7.0

# Layout test for the .agents/ skill tree.
#
# Every directory in .agents/ must hold a SKILL.md file. Only .agents/skills/ and
# .agents/plugins/ may exist without one.
#
# The reason is that no agent loads a directory without a SKILL.md. Claude Code,
# GitHub Copilot, and the Codex plugin all skip it. Such a directory keeps its
# content in the repository but stops being read, so the content goes stale and
# nobody notices. Six skills were retired that way in July 2026. Their files were
# renamed from SKILL.md to REFERENCE.md and then drifted from the live code for
# months. This test stops that from happening again.
#
# The test also checks that both setup scripts use the same allowlist as this file.
# Three copies of the list exist. If they ever disagree, this test fails.
#
# Run it by hand with:  pwsh ./tests/SkillLayout.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The only two .agents/ subdirectories that are not skills.
# scripts/agents/setup-cross-agent-skills.ps1 and .sh carry the same list.
$allowedNonSkillDirs = @('skills', 'plugins')

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$agentsRoot = Join-Path $repoRoot '.agents'
$psScript = Join-Path $repoRoot 'scripts/agents/setup-cross-agent-skills.ps1'
$shScript = Join-Path $repoRoot 'scripts/agents/setup-cross-agent-skills.sh'

$failures = @()

if (-not (Test-Path -LiteralPath $agentsRoot)) {
    throw ".agents/ not found at $agentsRoot."
}

# --- Check 1: every .agents/ directory is either a skill or an allowed exception ---

$offenders = Get-ChildItem -Force -Directory -LiteralPath $agentsRoot |
    Where-Object {
        $allowedNonSkillDirs -notcontains $_.Name -and
        -not (Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md'))
    }

foreach ($offender in $offenders) {
    $stray = Get-ChildItem -Force -File -LiteralPath $offender.FullName |
        Select-Object -ExpandProperty Name
    $strayText = if ($stray) { $stray -join ', ' } else { '(no files)' }

    $failures += @"
.agents/$($offender.Name)/ has no SKILL.md. It contains: $strayText

Every directory in .agents/ must contain a SKILL.md file.
The only exceptions are .agents/skills/ and .agents/plugins/.

A skill cannot be parked. Retiring a skill means deleting its directory.
Do not rename SKILL.md to REFERENCE.md. Do not move it to a disabled folder.
No agent loads a directory without a SKILL.md, so its content goes stale unseen.

Deleted skills stay in git history. To find and read one:
  git log --diff-filter=D --name-only -- .agents/
  git show <commit>^:.agents/<skill>/SKILL.md
"@
}

# --- Check 2: both setup scripts use the same allowlist as this file ---

function Get-PowerShellAllowlist {
    param([string] $Path)

    $text = [System.IO.File]::ReadAllText($Path)
    $match = [regex]::Match($text, "(?m)^\s*\`$ignoredSkillDirs\s*=\s*@\(([^)]*)\)")
    if (-not $match.Success) {
        return $null
    }

    return [regex]::Matches($match.Groups[1].Value, "'([^']+)'") |
        ForEach-Object { $_.Groups[1].Value }
}

function Get-BashAllowlist {
    param([string] $Path)

    $text = [System.IO.File]::ReadAllText($Path)
    # Match the case pattern inside is_active_skill(), e.g. "        skills|plugins)".
    $match = [regex]::Match(
        $text,
        '(?s)is_active_skill\(\)\s*\{.*?case\s+"\$name"\s+in\s*(?:#[^\n]*\n\s*)*([A-Za-z0-9_.|-]+)\)')
    if (-not $match.Success) {
        return $null
    }

    return $match.Groups[1].Value -split '\|'
}

function Compare-Allowlist {
    param([string] $Label, [string[]] $Actual)

    if ($null -eq $Actual) {
        return "Could not read the allowlist from $Label. The test's parser needs updating."
    }

    $expectedText = ($allowedNonSkillDirs | Sort-Object) -join ', '
    $actualText = ($Actual | Sort-Object) -join ', '
    if ($expectedText -ne $actualText) {
        return @"
$Label allows [$actualText] but tests/SkillLayout.Tests.ps1 allows [$expectedText].

These two lists name the .agents/ directories that are not skills.
They must match. Update whichever one is wrong, then run this test again.
"@
    }

    return $null
}

foreach ($check in @(
        @{ Label = 'scripts/agents/setup-cross-agent-skills.ps1'; Values = (Get-PowerShellAllowlist $psScript) },
        @{ Label = 'scripts/agents/setup-cross-agent-skills.sh'; Values = (Get-BashAllowlist $shScript) }
    )) {
    $problem = Compare-Allowlist $check.Label $check.Values
    if ($problem) { $failures += $problem }
}

# --- Report ---

if ($failures.Count -gt 0) {
    # Print the detail first. A thrown multi-line string is collapsed onto one line by
    # the PowerShell error formatter, which makes the guidance hard to read in CI logs.
    foreach ($failure in $failures) {
        Write-Host ''
        Write-Host $failure -ForegroundColor Red
    }
    Write-Host ''
    throw "Skill layout tests failed with $($failures.Count) problem(s). See the detail above."
}

$skillCount = @(Get-ChildItem -Force -Directory -LiteralPath $agentsRoot |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') }).Count

Write-Host "Skill layout tests passed. $skillCount active skills in .agents/."
