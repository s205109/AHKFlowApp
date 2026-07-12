#Requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$suiteRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$pluginSkills = Join-Path $suiteRoot 'plugins\ahkflowapp\skills'
$agentsRoot = Join-Path $suiteRoot '.agents'

# Names of every skill that has a SKILL.md directly under a root's skill dir.
function Get-SkillNames {
    param([string] $Root)

    $names = @()
    foreach ($dir in (Get-ChildItem -LiteralPath $Root -Directory)) {
        if (Test-Path -LiteralPath (Join-Path $dir.FullName 'SKILL.md')) { $names += $dir.Name }
    }
    return , $names
}

$failures = @()

# Set comparison first: a deleted plugin skill (or a canonical with no plugin copy) would
# otherwise slip through the byte loop below, which only iterates existing plugin copies.
$pluginNames = Get-SkillNames $pluginSkills
$canonicalNames = Get-SkillNames $agentsRoot
foreach ($name in ($canonicalNames | Where-Object { $pluginNames -notcontains $_ })) {
    $failures += "Canonical .agents/$name/SKILL.md has no plugin copy. Re-run scripts/agents/setup-cross-agent-skills.ps1."
}
foreach ($name in ($pluginNames | Where-Object { $canonicalNames -notcontains $_ })) {
    $failures += "Plugin skill '$name' has no canonical .agents/$name/SKILL.md. Edit skills only under .agents."
}

foreach ($skillFile in (Get-ChildItem -LiteralPath $pluginSkills -Recurse -Filter 'SKILL.md' -File)) {
    $skillName = Split-Path -Leaf (Split-Path -Parent $skillFile.FullName)
    $canonical = Join-Path $agentsRoot (Join-Path $skillName 'SKILL.md')

    if (-not (Test-Path -LiteralPath $canonical)) {
        continue
    }

    $pluginBytes = [System.IO.File]::ReadAllBytes($skillFile.FullName)
    $canonicalBytes = [System.IO.File]::ReadAllBytes($canonical)
    $identical = ($pluginBytes.Length -eq $canonicalBytes.Length)
    if ($identical) {
        for ($i = 0; $i -lt $pluginBytes.Length; $i++) {
            if ($pluginBytes[$i] -ne $canonicalBytes[$i]) { $identical = $false; break }
        }
    }

    if (-not $identical) {
        $failures += "Plugin skill '$skillName' SKILL.md differs from .agents/$skillName/SKILL.md. Re-run scripts/agents/setup-cross-agent-skills.ps1 and edit only the .agents copy."
    }
}

if ($failures.Count -gt 0) {
    throw ($failures -join [Environment]::NewLine)
}

Write-Host 'Skill parity tests passed.'
