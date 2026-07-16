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

# Relative paths of every file under a skill directory.
function Get-SkillFiles {
    param([string] $SkillDir)

    $files = @(Get-ChildItem -LiteralPath $SkillDir -Recurse -File |
        ForEach-Object { $_.FullName.Substring($SkillDir.Length).TrimStart('\') })
    return , $files
}

# Full-tree comparison per skill: the plugin mirror must contain exactly the canonical
# files (SKILL.md plus companions like templates and agents/openai.yaml), byte-identical.
foreach ($skillName in ($canonicalNames | Where-Object { $pluginNames -contains $_ })) {
    $canonicalDir = Join-Path $agentsRoot $skillName
    $pluginDir = Join-Path $pluginSkills $skillName

    $canonicalFiles = Get-SkillFiles $canonicalDir
    $pluginFiles = Get-SkillFiles $pluginDir

    foreach ($rel in ($canonicalFiles | Where-Object { $pluginFiles -notcontains $_ })) {
        $failures += "Plugin skill '$skillName' is missing '$rel'. Re-run scripts/agents/setup-cross-agent-skills.ps1."
    }
    foreach ($rel in ($pluginFiles | Where-Object { $canonicalFiles -notcontains $_ })) {
        $failures += "Plugin skill '$skillName' has stale '$rel' with no canonical copy. Re-run scripts/agents/setup-cross-agent-skills.ps1."
    }

    foreach ($rel in ($canonicalFiles | Where-Object { $pluginFiles -contains $_ })) {
        $pluginBytes = [System.IO.File]::ReadAllBytes((Join-Path $pluginDir $rel))
        $canonicalBytes = [System.IO.File]::ReadAllBytes((Join-Path $canonicalDir $rel))
        $identical = ($pluginBytes.Length -eq $canonicalBytes.Length)
        if ($identical) {
            for ($i = 0; $i -lt $pluginBytes.Length; $i++) {
                if ($pluginBytes[$i] -ne $canonicalBytes[$i]) { $identical = $false; break }
            }
        }

        if (-not $identical) {
            $failures += "Plugin skill '$skillName' file '$rel' differs from .agents/$skillName/$rel. Re-run scripts/agents/setup-cross-agent-skills.ps1 and edit only the .agents copy."
        }
    }
}

if ($failures.Count -gt 0) {
    throw ($failures -join [Environment]::NewLine)
}

Write-Host 'Skill parity tests passed.'
