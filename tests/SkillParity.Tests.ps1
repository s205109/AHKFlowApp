#Requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$suiteRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$pluginSkills = [System.IO.Path]::Combine($suiteRoot, 'plugins', 'ahkflowapp', 'skills')
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

# Relative paths of every file under a skill directory.
function Get-SkillFiles {
    param([string] $SkillDir)

    $files = @(Get-ChildItem -LiteralPath $SkillDir -Recurse -File |
        ForEach-Object { $_.FullName.Substring($SkillDir.Length).TrimStart('\', '/') })
    return , $files
}

# Every parity problem between one canonical root and one plugin mirror, as message strings.
# Returns an empty array when the two roots agree.
#
# Every comparison here is case-sensitive: -ccontains and -cnotcontains, never the plain
# operators. The plain ones ignore letter case on every platform. The two roots are separate
# directories, so '.agents/Foo' and a mirror named 'foo' both exist happily on Windows, and the
# plain operators call them one match. See backlog 138.
function Get-SkillParityFailure {
    param([string] $AgentsRoot, [string] $PluginSkillsRoot)

    $failures = @()

    # Set comparison first: a deleted plugin skill (or a canonical with no plugin copy) would
    # otherwise slip through the byte loop below, which only iterates existing plugin copies.
    $pluginNames = Get-SkillNames $PluginSkillsRoot
    $canonicalNames = Get-SkillNames $AgentsRoot
    foreach ($name in ($canonicalNames | Where-Object { $pluginNames -cnotcontains $_ })) {
        $failures += "Canonical .agents/$name/SKILL.md has no plugin copy. Re-run scripts/agents/setup-cross-agent-skills.ps1."
    }
    foreach ($name in ($pluginNames | Where-Object { $canonicalNames -cnotcontains $_ })) {
        $failures += "Plugin skill '$name' has no canonical .agents/$name/SKILL.md. Edit skills only under .agents."
    }

    # Full-tree comparison per skill: the plugin mirror must contain exactly the canonical
    # files (SKILL.md plus companions like templates and agents/openai.yaml), byte-identical.
    #
    # -ccontains, not -contains. A pair differing only in case is already reported above, and
    # letting it in here would build a mirror path that does not exist on a case-sensitive
    # filesystem. That ends the suite with a path error instead of the parity failure.
    foreach ($skillName in ($canonicalNames | Where-Object { $pluginNames -ccontains $_ })) {
        $canonicalDir = Join-Path $AgentsRoot $skillName
        $pluginDir = Join-Path $PluginSkillsRoot $skillName

        $canonicalFiles = Get-SkillFiles $canonicalDir
        $pluginFiles = Get-SkillFiles $pluginDir

        foreach ($rel in ($canonicalFiles | Where-Object { $pluginFiles -cnotcontains $_ })) {
            $failures += "Plugin skill '$skillName' is missing '$rel'. Re-run scripts/agents/setup-cross-agent-skills.ps1."
        }
        foreach ($rel in ($pluginFiles | Where-Object { $canonicalFiles -cnotcontains $_ })) {
            $failures += "Plugin skill '$skillName' has stale '$rel' with no canonical copy. Re-run scripts/agents/setup-cross-agent-skills.ps1."
        }

        foreach ($rel in ($canonicalFiles | Where-Object { $pluginFiles -ccontains $_ })) {
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

    # The leading comma is load-bearing. Without it an empty result returns nothing, and a
    # caller reading .Count under Set-StrictMode fails on $null.
    return , $failures
}

$script:caseFailures = @()

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-TestCase {
    param([string] $Name, [scriptblock] $Body)
    try {
        & $Body
        Write-Host "  PASS  $Name" -ForegroundColor Green
    } catch {
        $script:caseFailures += "$Name :: $($_.Exception.Message)"
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        Write-Host "        $($_.Exception.Message)" -ForegroundColor DarkRed
    }
}

# A throwaway pair of roots under the system temp directory. Each tree is a hashtable of
# skill name -> hashtable of relative file path -> file content. Returns the fixture root,
# whose 'agents' and 'plugin' children are the two roots the comparison takes.
#
# The build runs inside try/catch because a caller can only clean up what this function
# returns. A throw part-way through would leave the folder behind with nobody holding its
# path, so this function removes it here and lets the error carry on.
function New-SkillFixture {
    param([hashtable] $Canonical, [hashtable] $Plugin)

    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('skillparity-' + [guid]::NewGuid().ToString('N').Substring(0, 8))

    try {
        foreach ($side in @(@{ Name = 'agents'; Tree = $Canonical }, @{ Name = 'plugin'; Tree = $Plugin })) {
            $sideRoot = Join-Path $root $side.Name
            New-Item -ItemType Directory -Path $sideRoot -Force | Out-Null
            foreach ($skillName in $side.Tree.Keys) {
                foreach ($rel in $side.Tree[$skillName].Keys) {
                    $full = Join-Path (Join-Path $sideRoot $skillName) $rel
                    New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
                    [System.IO.File]::WriteAllText($full, $side.Tree[$skillName][$rel])
                }
            }
        }
    } catch {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }

    return $root
}

Write-Host 'Skill parity comparison cases:'

# --- Case 1: two roots that agree produce no failures. The control for the cases below. ---
Invoke-TestCase 'roots that agree produce no failures' {
    $fixture = New-SkillFixture -Canonical @{ alpha = @{ 'SKILL.md' = 'a' } } -Plugin @{ alpha = @{ 'SKILL.md' = 'a' } }
    try {
        $result = Get-SkillParityFailure -AgentsRoot (Join-Path $fixture 'agents') -PluginSkillsRoot (Join-Path $fixture 'plugin')
        Assert-True ($result.Count -eq 0) "Expected no failures, got: $($result -join '; ')"
    } finally { Remove-Item -LiteralPath $fixture -Recurse -Force }
}

# --- Case 2: skill names differing only in letter case are two skills, not one match ---
Invoke-TestCase 'skill names differing only in case are two skills' {
    $fixture = New-SkillFixture -Canonical @{ Alpha = @{ 'SKILL.md' = 'a' } } -Plugin @{ alpha = @{ 'SKILL.md' = 'a' } }
    try {
        $result = Get-SkillParityFailure -AgentsRoot (Join-Path $fixture 'agents') -PluginSkillsRoot (Join-Path $fixture 'plugin')
        Assert-True ($result.Count -eq 2) "Expected 2 failures, got $($result.Count): $($result -join '; ')"
        Assert-True (@($result | Where-Object { $_ -clike '*Canonical .agents/Alpha/SKILL.md has no plugin copy*' }).Count -eq 1) "Expected the canonical-only message naming 'Alpha', got: $($result -join '; ')"
        Assert-True (@($result | Where-Object { $_ -clike "*Plugin skill 'alpha' has no canonical*" }).Count -eq 1) "Expected the plugin-only message naming 'alpha', got: $($result -join '; ')"
    } finally { Remove-Item -LiteralPath $fixture -Recurse -Force }
}

# --- Case 3: file names differing only in letter case are two files ---
Invoke-TestCase 'file names differing only in case are two files' {
    $fixture = New-SkillFixture -Canonical @{ alpha = @{ 'SKILL.md' = 'a'; 'Notes.md' = 'n' } } -Plugin @{ alpha = @{ 'SKILL.md' = 'a'; 'notes.md' = 'n' } }
    try {
        $result = Get-SkillParityFailure -AgentsRoot (Join-Path $fixture 'agents') -PluginSkillsRoot (Join-Path $fixture 'plugin')
        Assert-True ($result.Count -eq 2) "Expected 2 failures, got $($result.Count): $($result -join '; ')"
        Assert-True (@($result | Where-Object { $_ -clike "*is missing 'Notes.md'*" }).Count -eq 1) "Expected the missing message naming 'Notes.md', got: $($result -join '; ')"
        Assert-True (@($result | Where-Object { $_ -clike "*has stale 'notes.md'*" }).Count -eq 1) "Expected the stale message naming 'notes.md', got: $($result -join '; ')"
    } finally { Remove-Item -LiteralPath $fixture -Recurse -Force }
}

# --- Case 4: a skill missing from the mirror is still reported ---
Invoke-TestCase 'a skill missing from the mirror is reported' {
    $fixture = New-SkillFixture -Canonical @{ alpha = @{ 'SKILL.md' = 'a' }; beta = @{ 'SKILL.md' = 'b' } } -Plugin @{ alpha = @{ 'SKILL.md' = 'a' } }
    try {
        $result = Get-SkillParityFailure -AgentsRoot (Join-Path $fixture 'agents') -PluginSkillsRoot (Join-Path $fixture 'plugin')
        Assert-True ($result.Count -eq 1) "Expected 1 failure, got $($result.Count): $($result -join '; ')"
        Assert-True ($result[0] -clike '*Canonical .agents/beta/SKILL.md has no plugin copy*') "Expected the canonical-only message naming 'beta', got: $($result[0])"
    } finally { Remove-Item -LiteralPath $fixture -Recurse -Force }
}

# --- Case 5: a file whose bytes differ is still reported ---
Invoke-TestCase 'a file whose bytes differ is reported' {
    $fixture = New-SkillFixture -Canonical @{ alpha = @{ 'SKILL.md' = 'canonical text' } } -Plugin @{ alpha = @{ 'SKILL.md' = 'mirror text' } }
    try {
        $result = Get-SkillParityFailure -AgentsRoot (Join-Path $fixture 'agents') -PluginSkillsRoot (Join-Path $fixture 'plugin')
        Assert-True ($result.Count -eq 1) "Expected 1 failure, got $($result.Count): $($result -join '; ')"
        Assert-True ($result[0] -clike "*file 'SKILL.md' differs from .agents/alpha/SKILL.md*") "Expected the byte-difference message, got: $($result[0])"
    } finally { Remove-Item -LiteralPath $fixture -Recurse -Force }
}

if ($script:caseFailures.Count -gt 0) {
    throw ("Skill parity comparison cases failed:" + [Environment]::NewLine + ($script:caseFailures -join [Environment]::NewLine))
}

# The repository's own skill tree, judged with the comparison the cases above just proved.
$failures = Get-SkillParityFailure -AgentsRoot $agentsRoot -PluginSkillsRoot $pluginSkills
if ($failures.Count -gt 0) {
    throw ($failures -join [Environment]::NewLine)
}

Write-Host 'Skill parity tests passed.'
