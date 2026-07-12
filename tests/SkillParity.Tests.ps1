#Requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$suiteRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$pluginSkills = Join-Path $suiteRoot 'plugins\ahkflowapp\skills'
$agentsRoot = Join-Path $suiteRoot '.agents'

$failures = @()
foreach ($skillFile in (Get-ChildItem -LiteralPath $pluginSkills -Recurse -Filter 'SKILL.md' -File)) {
    $skillName = Split-Path -Leaf (Split-Path -Parent $skillFile.FullName)
    $canonical = Join-Path $agentsRoot (Join-Path $skillName 'SKILL.md')

    if (-not (Test-Path -LiteralPath $canonical)) {
        $failures += "No canonical .agents/$skillName/SKILL.md for plugin copy $($skillFile.FullName)."
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
