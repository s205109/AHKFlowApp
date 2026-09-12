#Requires -Version 5.1
<#
.SYNOPSIS
    Every test file that spawns scripts\new-worktree.ps1, or scripts\prune-worktree-docker.ps1
    directly, as a child process must set AHKFLOW_SKIP_ORPHAN_PRUNE for that child. A file that
    only reads either script as text needs nothing.

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
    process, or the same destruction happens again. A fixture that spawns
    prune-worktree-docker.ps1 directly, skipping new-worktree.ps1 entirely, needs the same opt-out
    for the same reason, and a first version of this suite only watched for the first route.

    The wildcard copy that caused this is exactly the failure mode a reminder-based fix cannot
    close: a future fixture will copy scripts\*.ps1 the same way, without anyone telling it to set
    the opt-out. So this suite checks it structurally, over every test file, instead of trusting
    each new fixture to remember.

    Detection: a test file "spawns" a script when a line naming it sits within 20 lines of a line
    carrying a process-launch marker. Three markers are literal (Start-Process, ProcessStartInfo,
    [System.Diagnostics.Process]::Start), and a fourth matches the call-operator spelling this
    repository's own suite runner uses to start a PowerShell host, such as
    '& $HostExe -NoProfile -File $Path'. Proximity, not whole-file co-occurrence: a file can
    mention new-worktree.ps1 in one comment and spawn an unrelated script elsewhere (for example
    WorktreeMergedCleanupEligibility.Tests.ps1, which mentions new-worktree.ps1 in a comment about
    branch shape and spawns cleanup-merged-worktrees.ps1 far below it). Whole-file co-occurrence
    would flag that file wrongly. A file that only reads a script as text, such as with
    Get-Content, carries no process-launch marker at all, so it is left alone either way. This
    suite's own file is excluded from the scan, because it must name both scripts and the markers
    to describe them.

    The scan recurses into tests\, so a suite nested one folder down is not invisible just because
    every suite lives directly under tests\ today. bin\ and obj\ are excluded: a built test project
    leaves NuGet-bundled PowerShell under there, such as Playwright's own install scripts, and none
    of that is a suite this repository owns.
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

# Whether $Lines "spawn" a script matching $ScriptNamePattern: a line naming it sits within
# $ProximityLines of a line carrying $MarkerPattern. Extracted from the scan below so a fixture case
# further down can drive it directly against a couple of in-memory lines, proving the pattern works
# without writing a new file into tests\ just to exercise it.
function Test-SpawnsScriptNearby {
    param(
        # AllowEmptyCollection covers an empty .ps1 file, where Get-SpawningFile passes @(). Every
        # ordinary .ps1 file also has blank lines, and a mandatory [string[]] parameter implicitly
        # refuses any element that is an empty string, not only an empty array. AllowEmptyString is
        # what lets a real file's blank lines through this parameter at all.
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][AllowEmptyString()][string[]] $Lines,
        [Parameter(Mandatory = $true)][string] $ScriptNamePattern,
        [Parameter(Mandatory = $true)][string] $MarkerPattern,
        [Parameter(Mandatory = $true)][int] $ProximityLines
    )

    $scriptLines = @(for ($i = 0; $i -lt $Lines.Count; $i++) { if ($Lines[$i] -match $ScriptNamePattern) { $i } })
    $markerLines = @(for ($i = 0; $i -lt $Lines.Count; $i++) { if ($Lines[$i] -match $MarkerPattern) { $i } })

    if ($scriptLines.Count -eq 0 -or $markerLines.Count -eq 0) { return $false }

    foreach ($scriptLine in $scriptLines) {
        foreach ($markerLine in $markerLines) {
            if ([Math]::Abs($scriptLine - $markerLine) -le $ProximityLines) { return $true }
        }
    }
    return $false
}

# Runs the detector over every candidate file and splits the result: every file that spawns the
# named script, and the subset of those that never set $OptOutVariable anywhere in their text.
function Get-SpawningFile {
    param(
        [Parameter(Mandatory = $true)][object[]] $Candidates,
        [Parameter(Mandatory = $true)][string] $ScriptNamePattern,
        [Parameter(Mandatory = $true)][string] $MarkerPattern,
        [Parameter(Mandatory = $true)][int] $ProximityLines,
        [Parameter(Mandatory = $true)][string] $OptOutVariable
    )

    $spawning = [System.Collections.Generic.List[string]]::new()
    $violating = [System.Collections.Generic.List[string]]::new()

    foreach ($file in $Candidates) {
        # An empty file makes Get-Content return $null, not an empty collection, and @($null) is a
        # one-element array holding a null, not a zero-element array. Binding that single null as
        # [string[]] still fails the same mandatory check this guards against, so $null is mapped to
        # @() explicitly instead of trusting @(...) alone to normalize it.
        $content = Get-Content -LiteralPath $file.FullName
        $lines = if ($null -eq $content) { @() } else { @($content) }
        $spawns = Test-SpawnsScriptNearby -Lines $lines -ScriptNamePattern $ScriptNamePattern `
            -MarkerPattern $MarkerPattern -ProximityLines $ProximityLines
        if (-not $spawns) { continue }

        $spawning.Add($file.Name)

        $text = $lines -join "`n"
        if ($text -notmatch [regex]::Escape($OptOutVariable)) {
            $violating.Add($file.Name)
        }
    }

    [pscustomobject]@{ Spawning = $spawning; Violating = $violating }
}

# The literal script names, in either path-separator spelling a test file might use.
$newWorktreeNamePattern = 'new-worktree\.ps1'
$pruneNamePattern = 'prune-worktree-docker\.ps1'

# Any one of these means a line starts a real child process, not just a text check. The last
# alternative is the call-operator idiom this repository's own suite runner uses to start a
# PowerShell host, such as scripts/powershell-suites.common.ps1's `& $HostExe -NoProfile -File
# $Path`, which the first three markers do not cover.
$spawnMarkerPattern = 'Start-Process|ProcessStartInfo|\[System\.Diagnostics\.Process\]::Start|&\s*\$\w+.*-File\b'

# How close a script-name line and a spawn-marker line must sit to count as one spawn call. Real
# spawn sites in this repository keep the script path and the launch call within a few lines of
# each other; an unrelated mention and an unrelated spawn elsewhere in the same file sit much
# farther apart than this.
$proximityLines = 20

$optOutVariable = 'AHKFLOW_SKIP_ORPHAN_PRUNE'

# -Recurse, even though every *.Tests.ps1 suite lives directly under tests\ today. A future suite
# nested one folder down would otherwise scan clean while still spawning one of these scripts.
# bin\ and obj\ hold build output, never a suite this repository owns, so they are excluded.
$candidates = @(Get-ChildItem -LiteralPath $testsDir -Filter '*.ps1' -File -Recurse |
    Where-Object { $_.Name -ne $selfName -and $_.FullName -notmatch '[\\/](bin|obj)[\\/]' })

Assert-True ($candidates.Count -gt 0) "Expected to find PowerShell files under '$testsDir' to scan."

# First detector: a fixture that spawns new-worktree.ps1. That script always runs the orphan sweep
# itself, so its child process needs the opt-out.
$newWorktree = Get-SpawningFile -Candidates $candidates -ScriptNamePattern $newWorktreeNamePattern `
    -MarkerPattern $spawnMarkerPattern -ProximityLines $proximityLines -OptOutVariable $optOutVariable

# Second detector: a fixture that spawns prune-worktree-docker.ps1 directly, skipping
# new-worktree.ps1 entirely. prune-worktree-docker.ps1 checks the same opt-out variable for itself,
# but the first detector above only ever looks for new-worktree.ps1's name, so a fixture that calls
# the prune script directly was invisible to this suite until this second detector existed.
$prune = Get-SpawningFile -Candidates $candidates -ScriptNamePattern $pruneNamePattern `
    -MarkerPattern $spawnMarkerPattern -ProximityLines $proximityLines -OptOutVariable $optOutVariable

$violations = [System.Collections.Generic.List[string]]::new()
foreach ($name in $newWorktree.Violating) { $violations.Add("$name (spawns new-worktree.ps1)") }
foreach ($name in $prune.Violating) { $violations.Add("$name (spawns prune-worktree-docker.ps1 directly)") }

if ($violations.Count -gt 0) {
    $list = ($violations | Sort-Object) -join ', '
    throw "These test files spawn a worktree script without setting $optOutVariable for the child process: $list. Set `$env:$optOutVariable = '1' before spawning, or the orphan Docker sweep can remove another checkout's running test container."
}

# Positive control: prove the first detector actually fires on the two known spawn sites, so a
# change to the detection pattern that stops matching real code goes red here instead of the loop
# above silently finding nothing to check.
foreach ($known in @('WorktreeCreateHookStdin.Tests.ps1', 'WorktreeMergedCleanupEligibility.Tests.ps1')) {
    Assert-True ($newWorktree.Spawning -contains $known) "Expected the spawn detector to flag '$known' as spawning new-worktree.ps1. If this fails, the detection pattern stopped matching real code and the guard above is checking nothing."
}

# --- proving the widened marker and the second detector -------------------------------------------
#
# Nothing under tests\ today spawns new-worktree.ps1 with only the call-operator marker (the two
# known files above both use Start-Process), and nothing under tests\ today spawns
# prune-worktree-docker.ps1 directly with a marker this pattern recognises. Both are proved instead
# against a couple of in-memory lines, the way CitationFreshness.Tests.ps1 proves its own parser
# against fixture text rather than only against real files.

$callOperatorSpawn = @(
    '$psExe = (Get-Process -Id $PID).Path'
    "& `$psExe -NoProfile -File (Join-Path `$scriptsDir 'new-worktree.ps1') -Title 'probe'"
)
Assert-True (Test-SpawnsScriptNearby -Lines $callOperatorSpawn -ScriptNamePattern $newWorktreeNamePattern `
        -MarkerPattern $spawnMarkerPattern -ProximityLines $proximityLines) `
    'The widened pattern must catch the call-operator plus -File spelling this repository uses to start a PowerShell host. Got no match.'

$pruneDirectSpawn = @(
    "`$pruneScript = Join-Path `$scriptsDir 'prune-worktree-docker.ps1'"
    "& `$psExe -NoProfile -File `$pruneScript"
)
Assert-True (Test-SpawnsScriptNearby -Lines $pruneDirectSpawn -ScriptNamePattern $pruneNamePattern `
        -MarkerPattern $spawnMarkerPattern -ProximityLines $proximityLines) `
    'The second detector must catch a fixture that spawns prune-worktree-docker.ps1 directly. Got no match.'

# Negative control: a comment that only names a script, with no spawn marker nearby, must not trip
# either detector. Reading the script as text, such as with Get-Content, must not trip it either.
$textOnlyMention = @(
    '# prune-worktree-docker.ps1 checks the same opt-out variable for itself.'
    'Get-Content -LiteralPath $someOtherFile'
)
Assert-True (-not (Test-SpawnsScriptNearby -Lines $textOnlyMention -ScriptNamePattern $pruneNamePattern `
        -MarkerPattern $spawnMarkerPattern -ProximityLines $proximityLines)) `
    'A file that only mentions the script name near a text read, with no spawn marker, must not be flagged as spawning it.'

Write-Host ("Worktree spawn prune opt-out tests passed " +
    "($($newWorktree.Spawning.Count) file(s) spawn new-worktree.ps1, " +
    "$($prune.Spawning.Count) spawn prune-worktree-docker.ps1 directly, all set $optOutVariable).")
