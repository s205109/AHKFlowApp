#Requires -Version 7.0

# Cross-platform regression test for the Codex skills content hash.
#
# The bash and PowerShell setup scripts each compute the plugin version hash
# independently and MUST agree byte-for-byte, otherwise the same skills payload
# produces different Codex plugin versions on Windows vs Linux. A past bug had the
# bash pipeline tokenize the "<blob-oid>  <path>" line with awk, truncating any
# path containing a space (e.g. "reference/file with spaces.md" -> "reference/file").
# This test builds a payload with a spaced filename and asserts:
#   1. bash and PowerShell produce the same hash (parity), and
#   2. the full spaced path influences the hash (no truncation).
#
# Runs on Linux CI: the bash script refuses to run under Windows Git Bash, and both
# bash and pwsh are available on ubuntu runners.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($IsWindows) {
    Write-Host 'Skipping Codex skills hash parity test on Windows (bash script is Linux-only).'
    exit 0
}

$suiteRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$bashScript = Join-Path $suiteRoot 'scripts/agents/setup-cross-agent-skills.sh'
$psScript = Join-Path $suiteRoot 'scripts/agents/setup-cross-agent-skills.ps1'
$gitPrefix = 'plugins/ahkflowapp/skills/'

# Build a throwaway git repo whose payload mirrors the real plugin skills layout so
# the bash script's repo-root-relative `git hash-object --stdin-paths` resolves.
function New-Payload {
    param([hashtable] $Files)

    $repo = Join-Path ([System.IO.Path]::GetTempPath()) ("codexhash-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    git -C $repo init --quiet | Out-Null

    $skillsRoot = Join-Path $repo $gitPrefix
    foreach ($rel in $Files.Keys) {
        $full = Join-Path $skillsRoot $rel
        New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
        [System.IO.File]::WriteAllText($full, $Files[$rel])
    }
    return @{ Repo = $repo; SkillsRoot = $skillsRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) }
}

function Get-BashHash {
    param([string] $SkillsRoot)
    $out = & bash $bashScript --print-codex-hash $SkillsRoot $gitPrefix
    if ($LASTEXITCODE -ne 0) { throw "bash hash failed for $SkillsRoot" }
    return ($out | Select-Object -Last 1).Trim()
}

function Get-PsHash {
    param([string] $SkillsRoot)
    $out = & pwsh -NoProfile -File $psScript -PrintCodexHash $SkillsRoot
    if ($LASTEXITCODE -ne 0) { throw "pwsh hash failed for $SkillsRoot" }
    return ($out | Select-Object -Last 1).Trim()
}

$failures = @()
$payloads = @()

try {
    # Payload A: contains a spaced filename plus ordinary companions.
    $a = New-Payload @{
        'dck-example/SKILL.md'            = "---`nname: dck-example`n---`nBody`n"
        'reference/file with spaces.md'   = "spaced content`n"
        'reference/plain.md'              = "plain content`n"
    }
    $payloads += $a.Repo

    $aBash = Get-BashHash $a.SkillsRoot
    $aPs = Get-PsHash $a.SkillsRoot

    if ($aBash -ne $aPs) {
        $failures += "Parity: bash hash '$aBash' != PowerShell hash '$aPs' for a payload with a spaced filename."
    }

    # Payload B: identical except the spaced filename's suffix differs (same content).
    # Under the old awk-truncation bug both A and B collapse the path to "reference/file"
    # and hash identically; the fixed pipeline keeps the full path, so the hashes differ.
    $b = New-Payload @{
        'dck-example/SKILL.md'            = "---`nname: dck-example`n---`nBody`n"
        'reference/file with spacez.md'   = "spaced content`n"
        'reference/plain.md'              = "plain content`n"
    }
    $payloads += $b.Repo

    $bBash = Get-BashHash $b.SkillsRoot
    if ($aBash -eq $bBash) {
        $failures += "Truncation: bash hash is identical for 'file with spaces.md' and 'file with spacez.md' — the spaced path tail is being dropped."
    }
}
finally {
    foreach ($repo in $payloads) {
        if (Test-Path -LiteralPath $repo) { Remove-Item -LiteralPath $repo -Recurse -Force }
    }
}

if ($failures.Count -gt 0) {
    throw ($failures -join [Environment]::NewLine)
}

Write-Host 'Codex skills hash parity tests passed.'
