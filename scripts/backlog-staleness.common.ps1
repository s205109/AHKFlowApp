#Requires -Version 7.0
# Shared helpers for the stale-open backlog check. Dot-sourced by
# tests/BacklogStaleOpen.Tests.ps1.
#
# An item's work merged and its records stayed open: backlog 071 merged on 2026-08-12 and sat
# in backlog/ at 'Stage: 8-review' with ten unticked boxes. See backlog 106 for the invariant
# this file implements and for the candidates it rejects.
#
# The check reads two things and nothing else: the text of an item's '- **Stage**:' line, and
# the shape of the commit graph. It never reads a commit subject, a branch name, or a pull
# request title, because a title goes stale - pull request #312 is titled 'backlog 096' and
# did item 097's work.

Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'backlog.common.ps1')

# Stage 3's exit condition is 'Plan committed', so 4-execute is the first stage whose records
# can outlive their own work. The plan-pointer check uses the same index for the same reason
# (`scripts/backlog.common.ps1:143`, "$script:BacklogPointerTriggerIndex = 4").
$script:BacklogStaleTriggerIndex = 4

# Measured on 2026-08-19 against main at 7433ca2f. The largest value a legitimately open item
# ever reached was 7 (backlog 080, shipped over several pull requests). Backlog 071, the one
# real defect, reached 26. Twelve sits between them.
$script:BacklogStaleThreshold = 12

function Invoke-BacklogGit {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][string[]] $GitArgs
    )

    # PowerShell 7.4 turns a non-zero exit code into a terminating error when
    # $ErrorActionPreference is 'Stop'. A caller here asks git questions that legitimately
    # answer 'no', so exit codes must stay data. run-powershell-suites.ps1 opts out the same
    # way for the same reason.
    $previous = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        $output = & git -C $RepoRoot @GitArgs 2>$null
        # Text, not the raw lines: every caller here wants one trimmed string, and three
        # callers spelling that out three ways is three chances to spell it wrong.
        return [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Text     = ((@($output) -join "`n").Trim())
        }
    }
    finally {
        $PSNativeCommandUseErrorActionPreference = $previous
    }
}

# The base branch is what the sweep judges against: work that merged is work that reached it.
# origin/main first, because a merge happens on GitHub and never advances a local ref. Nothing
# fetches here - a test suite must not touch the network - so a clone that never fetched judges
# against a stale tip, which delays a report and never invents one.
function Resolve-BacklogBaseRef {
    param([Parameter(Mandatory)][string] $RepoRoot)

    foreach ($candidate in @('origin/main', 'main')) {
        $result = Invoke-BacklogGit -RepoRoot $RepoRoot -GitArgs @('rev-parse', '--verify', '--quiet', "$candidate^{commit}")
        if ($result.ExitCode -eq 0) { return $candidate }
    }

    return 'HEAD'
}

function Get-BacklogStaleOpenProblem {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [string] $BaseRef = '',
        [int] $Threshold = -1
    )

    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
    if ($Threshold -lt 0) { $Threshold = $script:BacklogStaleThreshold }
    if ([string]::IsNullOrWhiteSpace($BaseRef)) { $BaseRef = Resolve-BacklogBaseRef -RepoRoot $RepoRoot }

    $problems = @()

    # A shallow clone cannot answer the question, and a silent pass would be a false green.
    # CI checks out full history for this job (`.github/workflows/ci.yml:108`, "fetch-depth: 0").
    $shallow = Invoke-BacklogGit -RepoRoot $RepoRoot -GitArgs @('rev-parse', '--is-shallow-repository')
    if ($shallow.ExitCode -ne 0) {
        return @("Cannot read git history in $RepoRoot. The stale-open check needs a git repository.")
    }
    if ($shallow.Text -eq 'true') {
        return @("The clone in $RepoRoot is shallow, so the stale-open check cannot read history. Fetch full history (fetch-depth: 0) and run it again.")
    }

    $backlogRoot = Join-Path $RepoRoot 'backlog'

    foreach ($item in Get-BacklogItem -BacklogRoot $backlogRoot) {
        if ((Split-Path -Leaf $item.Path) -eq '000-backlog-item-template.md') { continue }

        # A finished item and a parked item are both meant to sit still.
        if ($item.Folder -in @('done', 'blocked')) { continue }

        # A missing, repeated, or unknown Stage value belongs to the check that already owns
        # those messages (`scripts/backlog.common.ps1:80`, "function Get-BacklogProblem {").
        if ($item.Stages.Count -ne 1) { continue }
        $stage = $item.Stages[0]
        $index = [array]::IndexOf($script:BacklogStageOrder, $stage)
        if ($index -lt 0) { continue }

        # Arm 2: the last inch of the failure. Ship writes 9-ship and moves the file in one
        # commit, so an item reading 9-ship in backlog/ is already wrong, whatever the graph
        # says. This is not the invariant - it misses the 071 shape, which stopped at 8-review -
        # but it costs one comparison and reports the day the defect appears.
        if ($stage -eq '9-ship') {
            $problems += @"
Backlog $($item.Key) reads 'Stage: 9-ship' and is still open.
  File:  $($item.RelativePath)
  Fix:   tick the boxes and 'git mv' it into backlog/done/, in one commit.
"@
            continue
        }

        if ($index -lt $script:BacklogStaleTriggerIndex) { continue }

        # The newest commit that changed this item's Stage line. -G matches the line text
        # without its '+' or '-' prefix, so one pattern covers both sides of the diff.
        $stampResult = Invoke-BacklogGit -RepoRoot $RepoRoot -GitArgs @(
            'log', '-1', '--format=%H', '-G', '^- \*\*Stage\*\*:', 'HEAD', '--', $item.RelativePath)
        $stamp = $stampResult.Text
        if ($stampResult.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($stamp)) { continue }

        # Work still in flight: the newest record has not reached the base branch, so nothing
        # about it is late.
        $merged = Invoke-BacklogGit -RepoRoot $RepoRoot -GitArgs @('merge-base', '--is-ancestor', $stamp, $BaseRef)
        if ($merged.ExitCode -ne 0) { continue }

        $countResult = Invoke-BacklogGit -RepoRoot $RepoRoot -GitArgs @(
            'rev-list', '--count', '--first-parent', "$stamp..$BaseRef")
        if ($countResult.ExitCode -ne 0) { continue }
        $distance = [int] $countResult.Text

        if ($distance -le $Threshold) { continue }

        $problems += @"
Backlog $($item.Key) reached Stage $stage, its records merged, and it is still open.
  File:     $($item.RelativePath)
  Stage:    $stage
  Stamp:    $stamp (the newest commit that changed its Stage line)
  Distance: $distance first-parent commits behind $BaseRef, over a limit of $Threshold
  Fix:      close it - tick the boxes, set 'Stage: 9-ship', and 'git mv' it into
            backlog/done/. If the work really is unfinished, stamp the stage it is at.
            If it waits on something outside this repository, move it to backlog/blocked/.
"@
    }

    return $problems
}
