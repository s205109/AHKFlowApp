#Requires -Version 5.1
<#
.SYNOPSIS
    Every test file that spawns scripts\new-worktree.ps1 as a child process must set
    AHKFLOW_SKIP_ORPHAN_PRUNE for that child. A file that only reads the script as text needs
    nothing.

.DESCRIPTION
    Backlog 133 aftermath. A fixture built a throwaway git repository, copied scripts\*.ps1 into
    it with a wildcard, and spawned new-worktree.ps1 there to test the WorktreeCreate hook path.
    new-worktree.ps1 always runs the orphan Docker sweep, and the throwaway repository holds none
    of this project's real worktrees, so the sweep read every real checkout's running SQL test
    container as an orphan and removed it. It destroyed eleven containers on one machine during a
    real test run.

    The fix is an opt-out: new-worktree.ps1's Invoke-OrphanDockerPrune, and
    prune-worktree-docker.ps1 itself, both return early when AHKFLOW_SKIP_ORPHAN_PRUNE is set. A
    fixture that spawns new-worktree.ps1 in a throwaway repository must set it for the child
    process, or the same destruction happens again.

    The wildcard copy that caused this is exactly the failure mode a reminder-based fix cannot
    close: a future fixture will copy scripts\*.ps1 the same way, without anyone telling it to set
    the opt-out. So this suite checks it structurally, over every test file, instead of trusting
    each new fixture to remember.

    Detection: a test file "spawns" new-worktree.ps1 when a line naming the script sits within 20
    lines of a line carrying a process-launch marker (Start-Process, ProcessStartInfo, or
    [System.Diagnostics.Process]::Start). Proximity, not whole-file co-occurrence: a file can
    mention new-worktree.ps1 in one comment and spawn an unrelated script elsewhere (for example
    WorktreeMergedCleanup.Common.ps1, which mentions new-worktree.ps1 in a comment about branch
    shape and spawns cleanup-merged-worktrees.ps1 far below it). Whole-file co-occurrence would
    flag that file wrongly. A file that only reads the script as text, such as with Get-Content,
    carries no process-launch marker at all, so it is left alone either way. This suite's own file
    is excluded from the scan, because it must name the script and the markers to describe them.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$testsDir = Join-Path $repoRoot 'tests'
$selfName = Split-Path -Leaf $PSCommandPath

function Assert-True {
    param([bool] $Condition, [string] $Message)

    if (-not $Condition) {
        throw $Message
    }
}

# The literal script name, in either path-separator spelling a test file might use.
$scriptNamePattern = 'new-worktree\.ps1'

# Any one of these means a line starts a real child process, not just a text check.
$spawnMarkerPattern = 'Start-Process|ProcessStartInfo|\[System\.Diagnostics\.Process\]::Start'

# How close a script-name line and a spawn-marker line must sit to count as one spawn call. Real
# spawn sites in this repository keep the script path and the launch call within a few lines of
# each other; an unrelated mention and an unrelated spawn elsewhere in the same file sit much
# farther apart than this.
$proximityLines = 20

$optOutVariable = 'AHKFLOW_SKIP_ORPHAN_PRUNE'

$candidates = @(Get-ChildItem -LiteralPath $testsDir -Filter '*.ps1' -File |
    Where-Object { $_.Name -ne $selfName })

Assert-True ($candidates.Count -gt 0) "Expected to find PowerShell files under '$testsDir' to scan."

$spawningFiles = [System.Collections.Generic.List[string]]::new()
$violations = [System.Collections.Generic.List[string]]::new()

foreach ($file in $candidates) {
    $lines = Get-Content -LiteralPath $file.FullName

    $scriptLines = @(for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $scriptNamePattern) { $i } })
    $markerLines = @(for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $spawnMarkerPattern) { $i } })

    if ($scriptLines.Count -eq 0 -or $markerLines.Count -eq 0) { continue }

    $spawns = $false
    foreach ($scriptLine in $scriptLines) {
        foreach ($markerLine in $markerLines) {
            if ([Math]::Abs($scriptLine - $markerLine) -le $proximityLines) {
                $spawns = $true
                break
            }
        }
        if ($spawns) { break }
    }
    if (-not $spawns) { continue }

    # This file spawns new-worktree.ps1 as a child process.
    $spawningFiles.Add($file.Name)

    $text = $lines -join "`n"
    if ($text -notmatch [regex]::Escape($optOutVariable)) {
        $violations.Add($file.Name)
    }
}

if ($violations.Count -gt 0) {
    $list = ($violations | Sort-Object) -join ', '
    throw "These test files spawn new-worktree.ps1 without setting $optOutVariable for the child process: $list. Set `$env:$optOutVariable = '1' before spawning, or the orphan Docker sweep can remove another checkout's running test container."
}

# Positive control: prove the detector actually fires on the two known spawn sites, so a change
# to the detection pattern that stops matching real code goes red here instead of the loop above
# silently finding nothing to check.
foreach ($known in @('WorktreeCreateHookStdin.Tests.ps1', 'WorktreeMergedCleanupEligibility.Tests.ps1')) {
    Assert-True ($spawningFiles -contains $known) "Expected the spawn detector to flag '$known' as spawning new-worktree.ps1. If this fails, the detection pattern stopped matching real code and the guard above is checking nothing."
}

Write-Host "Worktree spawn prune opt-out tests passed ($($spawningFiles.Count) file(s) spawn new-worktree.ps1, all set $optOutVariable)."
