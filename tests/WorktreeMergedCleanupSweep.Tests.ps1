#Requires -Version 7.0
# The GitHub merge query, the real sweep, and the plan guard. Backlog 126 split these out of
# WorktreeMergedCleanup.Tests.ps1. The harness they share lives in
# WorktreeMergedCleanup.Common.ps1.
#
# It also carries four -Cleanup and merge-signal sections that started in the eligibility file.
# That file measured 66 seconds on its own, over this item's 60-second limit for one suite, so
# whole sections moved here to even the two out. Nothing inside a section changed.
#
# Run it by hand with:  pwsh ./tests/WorktreeMergedCleanupSweep.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'WorktreeMergedCleanup.Common.ps1')

# --- Test: the parser reads real gh output --------------------------------------
# Captured from this repository on 2026-08-19 with:
#   gh pr list --repo s205109/AHKFlowApp --state merged --base main --limit 3 #     --json number,headRefName,headRefOid
# and, for the pair that shares a head branch name:
#   gh pr list --repo s205109/AHKFlowApp --state merged --base main #     --head fix/wt-design-technique-names-a-skill-the-agent-cannot-invoke #     --json number,headRefName,headRefOid
$capturedGhJson = @'
[{"headRefName":"fix/wt-nothing-finds-a-branch-left-behind-after-its-worktree-is-gone","headRefOid":"9bfc92bd7112bc432b54e93ce23e51725c25d353","number":325},
 {"headRefName":"fix/wt-design-technique-names-a-skill-the-agent-cannot-invoke","headRefOid":"be250b7b06ba00a4202ae0538d441577d01e4cea","number":322},
 {"headRefName":"fix/wt-design-technique-names-a-skill-the-agent-cannot-invoke","headRefOid":"bb8d90fed5377a3f87ec6b20d7e34c8324bbbb27","number":321}]
'@

$ghRecords = ConvertFrom-GhMergedPrJson -Json $capturedGhJson
Assert-Equal 3 $ghRecords.Count 'Three merged pull requests must parse.'
Assert-Equal 322 $ghRecords[1].Number 'The number must survive parsing.'
Assert-Equal 'be250b7b06ba00a4202ae0538d441577d01e4cea' $ghRecords[1].HeadRefOid 'The head SHA must survive parsing.'
# Two pull requests share one head branch name with different head SHAs. This is why the merge
# proof binds by SHA and never by branch name.
Assert-Equal $ghRecords[1].HeadRefName $ghRecords[2].HeadRefName 'The captured pair must share a branch name.'
Assert-True ($ghRecords[1].HeadRefOid -ne $ghRecords[2].HeadRefOid) 'The captured pair must differ by SHA.'

Assert-Equal 0 (ConvertFrom-GhMergedPrJson -Json 'not json').Count 'Unparsable output must read as no records.'
Assert-Equal 0 (ConvertFrom-GhMergedPrJson -Json '').Count 'Empty output must read as no records.'
Assert-Equal 0 (ConvertFrom-GhMergedPrJson -Json '[{"number":9}]').Count 'A record without a head SHA must be dropped.'

# --- Test: an absent gh reads as "cannot tell", never as "not merged" ------------
$repo = New-TempGitRepo
try {
    # A PATH holding git but not gh. The lookup must report gh-missing and stay unavailable, so the
    # decision falls back to local history instead of treating silence as a verdict.
    $savedPath = $env:PATH
    $env:PATH = (Split-Path -Parent (Get-Command git).Source)
    try {
        $result = Get-MergedPullRequestRecords -RepoRoot $repo -BaseBranch 'main' -TimeoutSeconds 5
        Assert-True (-not $result.Available) 'A missing gh must not be available.'
        Assert-Equal 'gh-missing' $result.Reason 'A missing gh must say so.'
        Assert-Equal 0 @($result.Records).Count 'A missing gh must yield no records.'
    } finally {
        $env:PATH = $savedPath
    }

    Assert-Equal 'main' (Resolve-BaseBranchName -RepoRoot $repo) 'With no upstream the local ref name is the base branch name.'
} finally {
    Remove-TempTree $repo
}

# --- Test: a rebase-merged branch is merged when GitHub says so ------------------
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-rebase-merged' -RebaseMerge
    $tip = (Invoke-TestGit $wtPath @('rev-parse', 'HEAD')) -join ''

    # Sanity: the base carries the patch under a different SHA, and no merge commit exists, so the
    # three local signals cannot prove this merge however hard they look.
    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-rebase-merged')) `
        'Local git alone must not prove a rebase merge.'

    $ghSays = { [pscustomobject]@{ Available = $true; Reason = 'ok'; Records = @(
        [pscustomobject]@{ Number = 1; HeadRefName = 'feat-rebase-merged'; HeadRefOid = $tip }) } }
    Assert-True (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-rebase-merged' -MergedPullRequestLookup $ghSays) `
        'A merged pull request whose head SHA the ref log holds must prove the merge.'

    $ghCannotTell = { [pscustomobject]@{ Available = $false; Reason = 'gh-missing'; Records = @() } }
    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-rebase-merged' -MergedPullRequestLookup $ghCannotTell)) `
        'An unavailable lookup must keep the worktree.'

    # A recycled branch name: same name, a head SHA this branch never pointed at.
    $ghWrongSha = { [pscustomobject]@{ Available = $true; Reason = 'ok'; Records = @(
        [pscustomobject]@{ Number = 2; HeadRefName = 'feat-rebase-merged'; HeadRefOid = ('0' * 40) }) } }
    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-rebase-merged' -MergedPullRequestLookup $ghWrongSha)) `
        'A pull request the ref log never recorded must not prove the merge.'

    # A merge-commit merge must never spend a network call: this lookup throws if it is consulted.
    Add-TestWorktree -RepoDir $repo -BranchName 'feat-local-proof' | Out-Null
    $ghMustNotRun = { throw 'The lookup must not run when local git already proved the merge.' }
    Assert-True (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-local-proof' -MergedPullRequestLookup $ghMustNotRun) `
        'A merge-commit merge must be proved locally, without asking GitHub.'
} finally {
    Remove-TempTree $repo
}

# --- Test: an unstarted branch is never merged, whatever GitHub says -------------
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-unstarted-pr' -NoCommits
    $tip = (Invoke-TestGit $wtPath @('rev-parse', 'HEAD')) -join ''
    $ghSays = { [pscustomobject]@{ Available = $true; Reason = 'ok'; Records = @(
        [pscustomobject]@{ Number = 3; HeadRefName = 'feat-unstarted-pr'; HeadRefOid = $tip }) } }
    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-unstarted-pr' -MergedPullRequestLookup $ghSays)) `
        'Signal 1 must refuse a branch that never committed, even with a merged pull request.'
} finally {
    Remove-TempTree $repo
}

# --- Test: a rebase merge followed by new work keeps the worktree ----------------
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-rebase-then-work' -RebaseMerge
    $mergedTip = (Invoke-TestGit $wtPath @('rev-parse', 'HEAD')) -join ''
    Set-Content -LiteralPath (Join-Path $wtPath 'after.txt') -Value 'later' -Encoding utf8
    Invoke-TestGit $wtPath @('add', '-A') | Out-Null
    Invoke-TestGit $wtPath @('commit', '-m', 'work after the rebase merge') | Out-Null

    $ghSays = { [pscustomobject]@{ Available = $true; Reason = 'ok'; Records = @(
        [pscustomobject]@{ Number = 4; HeadRefName = 'feat-rebase-then-work'; HeadRefOid = $mergedTip }) } }
    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-rebase-then-work' -MergedPullRequestLookup $ghSays)) `
        'Signal 4 must refuse work made after a rebase merge.'
} finally {
    Remove-TempTree $repo
}

# --- Test: the sweep lists a rebase-merged worktree as eligible ------------------
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-sweep-rebase' -RebaseMerge
    $tip = (Invoke-TestGit $wtPath @('rev-parse', 'HEAD')) -join ''
    $records = @([pscustomobject]@{ Number = 5; HeadRefName = 'feat-sweep-rebase'; HeadRefOid = $tip })

    $eligible = @(Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main' -MergedPullRequests $records)
    Assert-Equal 1 $eligible.Count 'A rebase-merged worktree must be eligible when GitHub proves the merge.'
    Assert-Equal 'feat-sweep-rebase' $eligible[0].Branch 'The eligible worktree must be the rebase-merged one.'

    # No @() around this call either: the function returns ', $eligible', so re-wrapping an empty
    # result yields one element that is itself the empty array.
    $none = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main'
    Assert-Equal 0 $none.Count 'Without the GitHub records the same worktree must be preserved.'
} finally {
    Remove-TempTree $repo
}

# --- Test: a child that never exits is killed at the timeout --------------------
# The lookup used to call ReadToEnd() on both streams BEFORE WaitForExit(). A blocking read only
# returns when the pipe closes, which a hung child never does, so the timeout was never reached and
# the whole sweep hung. Get-MergedPullRequestRecords now runs through Invoke-CapturedProcess, and
# this drives that helper with a child whose behavior the test controls completely.
$hostExe = [System.Diagnostics.Process]::GetCurrentProcess().Path
$watch = [System.Diagnostics.Stopwatch]::StartNew()
$hung = Invoke-CapturedProcess -FilePath $hostExe `
    -Arguments @('-NoProfile', '-Command', 'Start-Sleep -Seconds 120') -TimeoutSeconds 3
$watch.Stop()

Assert-True $hung.Started 'The child must have started.'
Assert-True $hung.TimedOut 'A child that outlives the timeout must report TimedOut.'
Assert-True ($watch.Elapsed.TotalSeconds -lt 30) `
    "The helper must give up near its timeout, not wait for the child. Took $([int]$watch.Elapsed.TotalSeconds)s."

# The same helper must still return real output from a child that exits normally.
$quick = Invoke-CapturedProcess -FilePath $hostExe `
    -Arguments @('-NoProfile', '-Command', 'Write-Output ping-from-child') -TimeoutSeconds 30
Assert-True $quick.Started 'A normal child must start.'
Assert-True (-not $quick.TimedOut) 'A normal child must not report a timeout.'
Assert-Equal 0 $quick.ExitCode 'A normal child must report its exit code.'
Assert-True ($quick.StdOut -match 'ping-from-child') "Captured stdout must hold the child's output. Got: $($quick.StdOut)"

# Output larger than one pipe buffer must not deadlock, which is what the async drain buys.
$bulk = Invoke-CapturedProcess -FilePath $hostExe `
    -Arguments @('-NoProfile', '-Command', "'x' * 200000") -TimeoutSeconds 60
Assert-True (-not $bulk.TimedOut) 'A child writing more than one pipe buffer must not time out.'
Assert-True ($bulk.StdOut.Length -ge 200000) "All of the child's output must be captured. Got $($bulk.StdOut.Length) chars."

# An executable that cannot be launched is 'not started', never a silent success.
$missing = Invoke-CapturedProcess -FilePath (Join-Path $env:TEMP 'no-such-binary-98765.exe') `
    -Arguments @('--version') -TimeoutSeconds 5
Assert-True (-not $missing.Started) 'A missing executable must report Started = false.'

# --- Test: the GitHub query base follows the base actually being decided against ---
# Resolve-BaseBranchName used to default to 'main' whatever base the caller chose, so a run with
# -MainRef release asked GitHub for pull requests merged into main. One of those could then satisfy
# the SHA lookup and allow a removal, though the branch never reached release.
$repo = New-TempGitRepo
try {
    Invoke-TestGit $repo @('branch', 'release') | Out-Null
    Invoke-TestGit $repo @('config', 'branch.release.merge', 'refs/heads/release-line') | Out-Null
    Invoke-TestGit $repo @('config', 'branch.release.remote', 'origin') | Out-Null
    Invoke-TestGit $repo @('config', 'branch.main.merge', 'refs/heads/main') | Out-Null
    Invoke-TestGit $repo @('config', 'branch.main.remote', 'origin') | Out-Null
    Invoke-TestGit $repo @('remote', 'add', 'origin', 'https://example.invalid/repo.git') | Out-Null

    Assert-Equal 'main' (Resolve-BaseBranchName -RepoRoot $repo -LocalRef 'main') 'main must map to its own remote branch.'
    Assert-Equal 'release-line' (Resolve-BaseBranchName -RepoRoot $repo -LocalRef 'release') `
        'A non-main local base must map to ITS remote branch, not to main.'

    # The base a run decides against is often the remote-tracking ref, so that form must resolve too.
    Assert-Equal 'release-line' (Resolve-BaseBranchName -RepoRoot $repo -LocalRef 'origin/release') `
        'A remote-tracking base must resolve through its remote name, not by splitting on the slash.'

    # A base with no configuration at all still answers with something usable.
    Assert-Equal 'topic' (Resolve-BaseBranchName -RepoRoot $repo -LocalRef 'topic') `
        'An unconfigured base must fall back to its own name.'
} finally {
    Remove-TempTree $repo
}

# --- Test: a rebase-merged leftover branch is reported ---------------------------
# Get-LeftoverMergedBranches seeded its candidates from `git branch --merged`, which never lists a
# rebase-merged branch, and it called the decision without the run's GitHub records. So the one
# leftover that a rebase merge produces was invisible.
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-leftover-rebase' -RebaseMerge
    $tip = (Invoke-TestGit $wtPath @('rev-parse', 'HEAD')) -join ''
    # The state a half-finished removal leaves: the worktree is pruned, the branch survives.
    Invoke-TestGit $repo @('worktree', 'remove', '--force', $wtPath) | Out-Null

    $records = @([pscustomobject]@{ Number = 7; HeadRefName = 'feat-leftover-rebase'; HeadRefOid = $tip })

    $leftover = Get-LeftoverMergedBranches -RepoRoot $repo -MainRef 'main' -MergedPullRequests $records
    Assert-Equal 1 $leftover.Count 'A rebase-merged branch whose worktree is gone must be reported.'
    Assert-Equal 'feat-leftover-rebase' $leftover[0] 'The reported branch must be the rebase-merged one.'

    $withoutRecords = Get-LeftoverMergedBranches -RepoRoot $repo -MainRef 'main'
    Assert-Equal 0 $withoutRecords.Count 'Without the GitHub records the same branch must stay unreported.'
} finally {
    Remove-TempTree $repo
}

# --- Test: an unstarted leftover branch is still never reported -------------------
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-leftover-fresh' -NoCommits
    $tip = (Invoke-TestGit $wtPath @('rev-parse', 'HEAD')) -join ''
    Invoke-TestGit $repo @('worktree', 'remove', '--force', $wtPath) | Out-Null

    $records = @([pscustomobject]@{ Number = 8; HeadRefName = 'feat-leftover-fresh'; HeadRefOid = $tip })
    $leftover = Get-LeftoverMergedBranches -RepoRoot $repo -MainRef 'main' -MergedPullRequests $records
    Assert-Equal 0 $leftover.Count 'A branch nobody committed on must never be reported as leftover.'
} finally {
    Remove-TempTree $repo
}


# --- Test: Get-BaseRefAtBranchCreation ---------------------------------------------------
# The branch's oldest ref-log entry carries its creation time. The base ref's own ref log carries
# every position it has held. The answer is the newest base position STRICTLY EARLIER than that
# creation time. Anything it cannot establish must come back as $null, so the caller skips
# signal 5 instead of refusing on a guess.
$repo = New-TempGitRepo
try {
    # main's position before anything else happens. The sleep makes that entry strictly earlier
    # than the branch created next; without it every stamp lands in the same second and the
    # function correctly reports that it cannot answer.
    $mainBefore = ((Invoke-TestGit $repo @('rev-parse', 'main')) -join '').Trim()
    Start-Sleep -Seconds 2

    Add-TestWorktree -RepoDir $repo -BranchName 'feat-base-probe' | Out-Null

    $resolved = Get-BaseRefAtBranchCreation -RepoRoot $repo -Branch 'feat-base-probe' -MainRef 'main'
    Assert-True ($resolved -eq $mainBefore) 'The base position must be where main stood before the branch was created, not after.'

    # The merge that Add-TestWorktree performed came after the branch existed, so it must NOT be
    # the answer. This is the collision that '<base>@{<time>}' gets wrong.
    $mainAfter = ((Invoke-TestGit $repo @('rev-parse', 'main')) -join '').Trim()
    Assert-True ($resolved -ne $mainAfter) 'A base move that happened after the branch was created must never be the base position.'

    # Signal 5's allow path, on the same fixture. The base position resolves, so signal 5 really
    # runs, and the branch's own commit was not reachable from that position. Signal 5 may only
    # refuse, so it must let this through. Without this assertion a signal 5 that refuses
    # everything it can resolve would still pass the suite.
    Assert-True (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-base-probe' -MainRef 'main') `
        'A resolved base at creation must allow a proof that was not already reachable from that base.'

    Assert-True ($null -eq (Get-BaseRefAtBranchCreation -RepoRoot $repo -Branch 'no-such-branch' -MainRef 'main')) 'An unknown branch must resolve to $null.'
    Assert-True ($null -eq (Get-BaseRefAtBranchCreation -RepoRoot $repo -Branch 'feat-base-probe' -MainRef 'no-such-ref')) 'An unknown base ref must resolve to $null.'
} finally {
    Remove-TempTree $repo
}

# The case of a base ref with no ref log at all is covered further down, by the fixture that
# proves an unresolvable creation position skips signal 5. That one asserts the same $null and
# then asserts what the caller does with it, so a separate fixture here would only repeat setup.


# --- Test: a forged commit subject on a never-committed branch (backlog 096) --------------
# The shape backlog 095 could not refuse. GIT_REFLOG_ACTION=commit on a fast-forward onto an
# already-merged tip satisfies signal 1 with text and signal 2 with real history. The branch holds
# no commit, so signal 3 has nothing stranded to refuse and signal 4 finds no later work.
# Signal 5 is what refuses it: the proof SHA was already in the base before this branch existed.
$repo = New-TempGitRepo
try {
    Add-TestWorktree -RepoDir $repo -BranchName 'feat-ff-donor' | Out-Null
    $donorTip = ((Invoke-TestGit $repo @('rev-parse', 'refs/heads/feat-ff-donor')) -join '').Trim()

    # The donor must already be merged, and main must already point past it, BEFORE the victim
    # branch is created. That ordering is the whole point of signal 5.
    $mergeParents = (Invoke-TestGit $repo @('rev-list', '--min-parents=2', '--format=%P', 'main')) -join ' '
    Assert-True ($mergeParents -match [regex]::Escape($donorTip)) 'Sanity check: the donor branch must already be a merged non-first parent.'

    # Two seconds of separation, so the victim's creation stamp is strictly later than main's move.
    # Ref-log stamps have one-second resolution. Without this the fixture can build everything
    # inside one second, Get-BaseRefAtBranchCreation correctly reports that it cannot answer, and
    # signal 5 is skipped -- so the test would fail while proving nothing.
    Start-Sleep -Seconds 2

    $victimPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-ff-victim' -NoCommits -BaseRef 'main^'
    Invoke-TestGitWithReflogAction -RepoDir $victimPath -Action 'commit' -GitArgs @('merge', '--ff-only', $donorTip) | Out-Null

    $entries = (Invoke-TestGit $repo @('reflog', 'show', '--format=%H %gs', 'refs/heads/feat-ff-victim')) -join "`n"
    Assert-True ($entries -match '(?m)commit: Fast-forward') 'Sanity check: the fast-forward must really have written a forged "commit:" subject.'

    # Signal 5 must actually be engaged. Without this the test could go green because the function
    # could not resolve a base position, which proves nothing about the forgery.
    Assert-True ($null -ne (Get-BaseRefAtBranchCreation -RepoRoot $repo -Branch 'feat-ff-victim' -MainRef 'main')) 'Sanity check: signal 5 must have a base position to judge against, or this test proves nothing.'

    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-ff-victim' -MainRef 'main')) 'A forged "commit:" subject on a never-committed branch must not make it eligible.'

    # Kept from the backlog 095 block this test replaces. It bounds what the refusal costs: the
    # branch strands nothing, so refusing it loses no work. Signal 5 buys safety here for free.
    $stranded = Get-StrandedCommits -RepoRoot $repo -Branch 'feat-ff-victim' -Shas @(((Invoke-TestGit $repo @('rev-parse', 'refs/heads/feat-ff-victim')) -join '').Trim())
    Assert-Equal 0 $stranded.Count 'The forged case must strand nothing, which is what bounds it.'

    $eligible = Get-EligibleMergedWorktrees -RepoRoot $repo -MainRef 'main'
    $keys = @($eligible | ForEach-Object { ConvertTo-Key $_.Path })
    Assert-True (-not ($keys -contains (ConvertTo-Key $victimPath))) 'A worktree whose only proof is work the base already had must never be eligible.'
} finally {
    Remove-TempTree $repo
}


# --- Test: an unresolvable creation position skips signal 5, it never refuses -------------
# Signal 5 may only refuse. When Get-BaseRefAtBranchCreation cannot answer, the decision must be
# exactly what the other four signals say.
#
# The base ref log is removed to make that state exact. Relying on the fixture building inside one
# second would work on a fast machine and break on a loaded one, because ref-log stamps have
# one-second resolution. Get-BaseRefAtBranchCreation is the only function that reads the base ref
# log, so removing it changes nothing else in the decision.
$repo = New-TempGitRepo
try {
    Add-TestWorktree -RepoDir $repo -BranchName 'feat-skipped' | Out-Null
    Remove-Item -LiteralPath (Join-Path $repo '.git/logs/refs/heads/main') -Force
    Assert-True ($null -eq (Get-BaseRefAtBranchCreation -RepoRoot $repo -Branch 'feat-skipped' -MainRef 'main')) 'Sanity check: a base ref with no ref log must give no usable base position.'
    Assert-True (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-skipped' -MainRef 'main') 'A skipped signal 5 must leave the decision to the other four signals.'
} finally {
    Remove-TempTree $repo
}

# --- Test: a real sweep writes exactly one outcome line per worktree it removes ---
# The source scans elsewhere check call sites. This checks the thing itself: two merged worktrees,
# one sweep, two detached watchers running at the same time, and afterwards one outcome line each.
#
# It covers two defects at once. The sweep used to write "Merged-cleanup requested removal" to the
# outcome log and then hand over to a watcher that wrote "Removed.", which is two lines for one
# attempt. And the watcher's temp copy had no reliable logger, so two watchers colliding on the
# same file could drop a line entirely.
$repo = New-WorktreeToolingRepo -ScriptsSource $scriptsDir
try {
    $first = Add-TestWorktree -RepoDir $repo -BranchName 'feat-outcome-one'
    $second = Add-TestWorktree -RepoDir $repo -BranchName 'feat-outcome-two'

    $res = Invoke-CleanupChild -RepoDir $repo -ExtraArgs @('-Cleanup')
    Assert-True (Wait-ForWorktreeCleaned -RepoDir $repo -WorktreePath $first) "The first worktree must be removed. Stderr: $($res.Stderr)"
    Assert-True (Wait-ForWorktreeCleaned -RepoDir $repo -WorktreePath $second) "The second worktree must be removed. Stderr: $($res.Stderr)"

    # The watcher writes its outcome after the folder is gone, so waiting on the folder is not
    # waiting on the line. Poll until both leaves have one, then read once.
    $outcomeLog = Join-Path $repo '.claude\worktrees\worktree-removal.log'
    $leaves = @((Split-Path -Leaf $first), (Split-Path -Leaf $second))
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    $outcomeLines = @()
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $outcomeLog) {
            $outcomeLines = @(Get-Content -LiteralPath $outcomeLog -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })
            $covered = @($leaves | Where-Object { $leaf = $_; @($outcomeLines | Where-Object { $_ -match ('\s' + [regex]::Escape($leaf) + '\s') }).Count -ge 1 })
            if ($covered.Count -eq $leaves.Count) { break }
        }
        Start-Sleep -Milliseconds 250
    }

    Assert-True (Test-Path -LiteralPath $outcomeLog) 'The sweep must write an outcome log.'
    foreach ($leaf in $leaves) {
        $mine = @($outcomeLines | Where-Object { $_ -match ('\s' + [regex]::Escape($leaf) + '\s') })
        Assert-Equal 1 $mine.Count "'$leaf' must have exactly one outcome line, got $($mine.Count): $($mine -join ' || ')"
        Assert-True ($mine[0] -match '\sRemoved\.$') "'$leaf' must end with the Removed. outcome, got '$($mine[0])'"
    }

    # Every line in this file is an outcome. Anything else belongs in the diagnostics file beside it.
    foreach ($line in $outcomeLines) {
        Assert-True ($line -match '\s(Removed\.|Kept: |Failed: )') `
            "The outcome log may hold only outcomes, found '$line'"
    }

    # And the diagnostics really did land somewhere, so the split is not just an empty promise.
    $diagnosticsLog = Join-Path $repo '.claude\worktrees\worktree-removal-diagnostics.log'
    Assert-True (Test-Path -LiteralPath $diagnosticsLog) 'The diagnostics log must sit beside the outcome log.'
    Assert-True ((Get-Content -Raw -LiteralPath $diagnosticsLog) -match 'Merged-cleanup requested removal') `
        'The hand-over line belongs in diagnostics, not in the outcome log.'
} finally {
    Remove-TempTree $repo
}

# --- Test: a kept worktree's outcome line carries the guard's own reason ------------------
# A source scan can show that a call site looks right. It cannot show that the log a human reads
# holds the reason that applied. Both writers used to log one fixed sentence, "Kept: the plan was
# never implemented.", whatever the verdict was, and that sentence sent an investigation to the
# wrong backlog item. So this drives the real sweep and reads the real log.

# A repo whose worktree manifests are ignored, so writing one does not make the worktree dirty.
# The plan gate runs before the clean check, but the removal path after it needs a clean tree.
function New-PlanGuardRepo {
    param([string] $ScriptsSource)

    $repo = New-WorktreeToolingRepo -ScriptsSource $ScriptsSource
    Set-Content -LiteralPath (Join-Path $repo '.gitignore') -Value 'scripts/.env.worktree' -Encoding utf8
    New-Item -ItemType Directory -Path (Join-Path $repo 'docs\superpowers\plans') -Force | Out-Null
    Invoke-TestGit $repo @('add', '-A') | Out-Null
    Invoke-TestGit $repo @('commit', '-m', 'ignore worktree manifests') | Out-Null
    return $repo
}

# Seeds the backlog item a worktree's own name points at, and records a different number in the
# worktree's manifest. That is the shape a renumber leaves behind.
#
# The item is committed on main because the sweep reads it from the resolved base. The plan file
# is written to disk only: the guard resolves it against the main checkout, not against a ref.
function Set-PlanGuardFixture {
    param(
        [string] $RepoDir,
        [string] $WorktreePath,
        [string] $RecordedNumber,
        [string] $ItemNumber,
        [string] $ItemFolder = 'backlog',
        [string] $PlanBullet,
        [string] $PlanBody
    )

    $slug = (Split-Path -Leaf $WorktreePath).Substring(3)
    $itemDir = Join-Path $RepoDir $ItemFolder
    New-Item -ItemType Directory -Path $itemDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $itemDir "$ItemNumber-$slug.md") `
        -Value "# $ItemNumber - $slug`n`n- Plan: $PlanBullet" -Encoding utf8

    if ($PlanBody) {
        Set-Content -LiteralPath (Join-Path $RepoDir "docs\superpowers\plans\plan-$ItemNumber.md") -Value $PlanBody -Encoding utf8
    }

    Invoke-TestGit $RepoDir @('add', '-A') | Out-Null
    Invoke-TestGit $RepoDir @('commit', '-m', "seed backlog item $ItemNumber") | Out-Null

    $scriptsDirInWorktree = Join-Path $WorktreePath 'scripts'
    New-Item -ItemType Directory -Path $scriptsDirInWorktree -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $scriptsDirInWorktree '.env.worktree') `
        -Value "AHKFLOW_BACKLOG_ITEM=$RecordedNumber" -Encoding utf8
}

# Reads the outcome lines for one worktree leaf, waiting until at least one exists.
function Get-OutcomeLinesFor {
    param([string] $RepoDir, [string] $Leaf, [int] $TimeoutMs = 20000)

    $log = Join-Path $RepoDir '.claude\worktrees\worktree-removal.log'
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    $mine = @()
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $log) {
            $mine = @(Get-Content -LiteralPath $log -ErrorAction SilentlyContinue |
                Where-Object { $_ -match ('\s' + [regex]::Escape($Leaf) + '\s') })
            if ($mine.Count -ge 1) { break }
        }
        Start-Sleep -Milliseconds 250
    }
    return , $mine
}

$repo = New-PlanGuardRepo -ScriptsSource $scriptsDir
try {
    # Two kept worktrees, two different refusal reasons, one sweep.
    $outside = Add-TestWorktree -RepoDir $repo -BranchName 'feat-plan-outside'
    Set-PlanGuardFixture -RepoDir $repo -WorktreePath $outside -RecordedNumber '118' -ItemNumber '140' `
        -PlanBullet '<path, or "none - reason">'

    $untouched = Add-TestWorktree -RepoDir $repo -BranchName 'feat-plan-untouched'
    Set-PlanGuardFixture -RepoDir $repo -WorktreePath $untouched -RecordedNumber '118' -ItemNumber '141' `
        -PlanBullet '`docs/superpowers/plans/plan-141.md`' -PlanBody "- [ ] Step 1`n- [ ] Step 2"

    $res = Invoke-CleanupChild -RepoDir $repo -ExtraArgs @('-Cleanup')

    $outsideLeaf = Split-Path -Leaf $outside
    $outsideLines = Get-OutcomeLinesFor -RepoDir $repo -Leaf $outsideLeaf
    Assert-Equal 1 $outsideLines.Count "'$outsideLeaf' must have exactly one outcome line, got: $($outsideLines -join ' || '). Stderr: $($res.Stderr)"
    Assert-True ($outsideLines[0] -match 'Kept: backlog item 140 names a plan outside docs/superpowers/plans') `
        "The kept line must carry the guard's own reason, got '$($outsideLines[0])'"
    Assert-True ($outsideLines[0] -match 'records item 118') `
        "The kept line must name the stale recorded number too, got '$($outsideLines[0])'"

    $untouchedLeaf = Split-Path -Leaf $untouched
    $untouchedLines = Get-OutcomeLinesFor -RepoDir $repo -Leaf $untouchedLeaf
    Assert-Equal 1 $untouchedLines.Count "'$untouchedLeaf' must have exactly one outcome line, got: $($untouchedLines -join ' || ')"
    Assert-True ($untouchedLines[0] -match 'the plan for item 141 was never implemented \(2 steps, none ticked\)') `
        "A second refusal must read differently, got '$($untouchedLines[0])'"

    # The two reasons must not collapse back into one sentence.
    Assert-True ($outsideLines[0] -ne $untouchedLines[0]) 'Two different refusals must produce two different lines'
    foreach ($line in @($outsideLines[0], $untouchedLines[0])) {
        Assert-True (-not ($line -match 'Kept: the plan was never implemented\.')) `
            "The old fixed sentence must be gone, got '$line'"
    }

    Assert-True (Test-Path -LiteralPath $outside) 'A refused worktree stays on disk'
    Assert-True (Test-Path -LiteralPath $untouched) 'A refused worktree stays on disk'
} finally {
    Remove-TempTree $repo
}

# --- Test: the sweep removes a worktree whose recorded number is stale --------------------
# This is the worktree that started backlog 122: its manifest records somebody else's open item,
# its own item shipped into backlog/done with an implemented plan, and every sweep refused it.
# Nothing edits the manifest -- the guard stops believing it instead.
$repo = New-PlanGuardRepo -ScriptsSource $scriptsDir
try {
    $stale = Add-TestWorktree -RepoDir $repo -BranchName 'feat-renumbered'
    Set-PlanGuardFixture -RepoDir $repo -WorktreePath $stale -RecordedNumber '118' -ItemNumber '120' `
        -ItemFolder 'backlog\done' -PlanBullet '`docs/superpowers/plans/plan-120.md`' -PlanBody "- [x] Step 1"

    # The item the stale number names: still open, and its pointer is the unfilled template. Judging
    # it refuses, so a removal here proves the guard judged the other one.
    Set-Content -LiteralPath (Join-Path $repo 'backlog\118-a-different-title.md') `
        -Value "# 118 - other`n`n- Plan: <path, or ""none - reason"">" -Encoding utf8
    Invoke-TestGit $repo @('add', '-A') | Out-Null
    Invoke-TestGit $repo @('commit', '-m', 'seed the item the stale number names') | Out-Null

    $manifestPath = Join-Path $stale 'scripts\.env.worktree'
    $manifestBefore = Get-Content -Raw -LiteralPath $manifestPath

    $res = Invoke-CleanupChild -RepoDir $repo -ExtraArgs @('-Cleanup')
    Assert-True (Wait-ForWorktreeCleaned -RepoDir $repo -WorktreePath $stale) `
        "A worktree whose own item shipped must be removed. Stderr: $($res.Stderr)"

    # The manifest is never repaired. Reading it correctly is the whole fix.
    Assert-True (-not (Test-Path -LiteralPath $manifestPath)) 'The worktree folder is gone, manifest and all'
    Assert-True ($manifestBefore -match 'AHKFLOW_BACKLOG_ITEM=118') 'The fixture really did record the stale number'

    $leaf = Split-Path -Leaf $stale
    $lines = Get-OutcomeLinesFor -RepoDir $repo -Leaf $leaf
    Assert-Equal 1 $lines.Count "'$leaf' must have exactly one outcome line, got: $($lines -join ' || ')"
    Assert-True ($lines[0] -match '\sRemoved\.$') "The outcome line must be the normal removal line, got '$($lines[0])'"

    # The disagreement is a diagnostic, never an outcome. A human who wonders why 118 was in the
    # manifest can find both numbers there.
    $diagnostics = Get-Content -Raw -LiteralPath (Join-Path $repo '.claude\worktrees\worktree-removal-diagnostics.log')
    Assert-True ($diagnostics -match 'Plan guard judged backlog item 120') `
        "The diagnostics must name the item that was judged. Log: $diagnostics"
    Assert-True ($diagnostics -match 'records item 118') `
        "The diagnostics must name the recorded number too. Log: $diagnostics"
} finally {
    Remove-TempTree $repo
}

# A handover that cannot start must still say what happened to the worktree.
$sweepSource = Get-Content -Raw -LiteralPath (Join-Path $scriptsDir 'cleanup-merged-worktrees.ps1')
Assert-True ($sweepSource -match '(?m)^function Write-SweepOutcome \{') 'cleanup-merged-worktrees.ps1 must define Write-SweepOutcome'
Assert-True ($sweepSource -match "Failed: the removal script could not be found\.") 'A missing removal script writes a Failed outcome'
Assert-True ($sweepSource -match "Failed: the removal script could not be started\.") 'A spawn failure writes a Failed outcome'


# --- Test: -Cleanup overrides config false (cleans, no prompt) ------------------
$repo = New-WorktreeToolingRepo -ScriptsSource $scriptsDir
try {
    $target = Add-TestWorktree -RepoDir $repo -BranchName 'feat-flag-over-false'
    Invoke-TestGit $repo @('config', '--local', 'ahkflow.worktreeCleanup', 'false') | Out-Null
    $res = Invoke-CleanupChild -RepoDir $repo -ExtraArgs @('-Cleanup')
    Assert-True (Wait-ForWorktreeCleaned -RepoDir $repo -WorktreePath $target) "-Cleanup must override config false. Stderr: $($res.Stderr)"
} finally {
    Remove-TempTree $repo
}

# --- Test: -Cleanup removes finished work and leaves unstarted worktrees (backlog 060) ---
# The strongest override still must not delete a worktree nobody has committed in.
$repo = New-WorktreeToolingRepo -ScriptsSource $scriptsDir
try {
    $fresh = Add-TestWorktree -RepoDir $repo -BranchName 'feat-fresh-forced' -NoCommits
    $target = Add-TestWorktree -RepoDir $repo -BranchName 'feat-done-forced'

    $res = Invoke-CleanupChild -RepoDir $repo -ExtraArgs @('-Cleanup')
    Assert-True (Wait-ForWorktreeCleaned -RepoDir $repo -WorktreePath $target) "-Cleanup must still remove a genuinely merged worktree. Stderr: $($res.Stderr)"
    Assert-True (Test-Path -LiteralPath $fresh) '-Cleanup must not remove a worktree whose branch has no commits of its own.'
    Assert-True (-not ($res.Stderr -match 'feat-fresh-forced')) 'An unstarted worktree must not even be reported as eligible.'
    $branches = (Invoke-TestGit $repo @('branch', '--list', 'feat-fresh-forced')) -join "`n"
    Assert-True ($branches -match 'feat-fresh-forced') '-Cleanup must not delete the unstarted branch.'
} finally {
    Remove-TempTree $repo
}

# --- Test: signal 2 reports which SHA proved the merge --------------------------
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-proof'
    $tip = (Invoke-TestGit $wtPath @('rev-parse', 'HEAD')) -join ''

    $facts = Get-BranchRefLogFacts -RepoRoot $repo -Branch 'feat-proof'
    Assert-True ($null -ne $facts) 'A branch with a ref log must produce facts.'
    Assert-True ($facts.MergeProofShas.ContainsKey($tip)) 'The commit entry must be usable as merge proof.'

    # No @() around the call: the function returns ', @(...)' to keep an empty result an array, and
    # re-wrapping an empty array yields one element that is itself an empty array.
    $proofs = Get-LocalMergeProofShas -RepoRoot $repo -MainRef 'main' -MergeProofShas $facts.MergeProofShas
    Assert-Equal 1 $proofs.Count 'A merged branch must yield exactly one local merge proof.'
    Assert-Equal $tip $proofs[0] 'The proof must be the SHA main merged.'

    Add-TestWorktree -RepoDir $repo -BranchName 'feat-open' -Unmerged | Out-Null
    $openFacts = Get-BranchRefLogFacts -RepoRoot $repo -Branch 'feat-open'
    $openProofs = Get-LocalMergeProofShas -RepoRoot $repo -MainRef 'main' -MergeProofShas $openFacts.MergeProofShas
    Assert-Equal 0 $openProofs.Count 'An unmerged branch must yield no proof.'
} finally {
    Remove-TempTree $repo
}

# --- Test: work made after the merge keeps the worktree (signal 4) --------------
$repo = New-TempGitRepo
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-after' -WorkAfterMerge
    $tip = (Invoke-TestGit $wtPath @('rev-parse', 'HEAD')) -join ''

    $facts = Get-BranchRefLogFacts -RepoRoot $repo -Branch 'feat-after'
    $proofs = Get-LocalMergeProofShas -RepoRoot $repo -MainRef 'main' -MergeProofShas $facts.MergeProofShas
    Assert-Equal 1 $proofs.Count 'The merge proof must still be found.'
    Assert-True ($proofs[0] -ne $tip) 'Sanity check: the tip must have moved past the proof.'

    $after = Get-WorkAfterMergeProof -RepoRoot $repo -Branch 'feat-after' -ProofShas $proofs
    Assert-Equal 1 $after.Count 'The commit made after the merge must be reported.'

    Assert-True (-not (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-after')) `
        'A branch that gained a commit after its merge must NOT report merged own work.'

    # The idle case must keep working: merged, nothing after, removable.
    Add-TestWorktree -RepoDir $repo -BranchName 'feat-idle' | Out-Null
    Assert-True (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-idle') `
        'A merged branch with no later work must still report merged own work.'
} finally {
    Remove-TempTree $repo
}

Write-Host 'Worktree merged-cleanup sweep tests passed.'
