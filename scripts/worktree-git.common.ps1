#Requires -Version 5.1
# Shared git-worktree probes used by new-worktree.ps1 and setup-worktree-local-dev.ps1.
# Both scripts must agree on what "a linked worktree" means, so keep it defined once.
function Resolve-GitPath {
    param([string] $Root, [string] $Kind)

    $path = (& git -C $Root rev-parse $Kind 2>$null).Trim()
    if (-not $path) {
        throw "Could not resolve git path: $Kind."
    }

    if ([System.IO.Path]::IsPathRooted($path)) {
        return (Resolve-Path -LiteralPath $path).Path
    }

    return (Resolve-Path -LiteralPath (Join-Path $Root $path)).Path
}

function Test-LinkedWorktree {
    param([string] $Root)

    $gitDir = Resolve-GitPath $Root '--git-dir'
    $commonDir = Resolve-GitPath $Root '--git-common-dir'
    return $gitDir.TrimEnd('\') -ine $commonDir.TrimEnd('\')
}

function Test-RefExists {
    param(
        [string] $Root,
        [string] $Ref
    )

    # Deliberately broader than a branch probe: a base ref may legitimately be a local branch, a
    # remote-tracking ref, a tag, or a raw SHA. The '^{commit}' suffix rejects a ref that resolves
    # to something that cannot be branched from.
    & git -C $Root rev-parse --verify --quiet "$Ref^{commit}" *> $null
    return $LASTEXITCODE -eq 0
}

# Which ref a new worktree's branch starts from. Pure so the precedence is testable without a
# repo: an existing branch owns its own history, an explicit -BaseRef stacks on unmerged work,
# and HEAD is the default that preserves the historical behavior.
function Resolve-WorktreeSourceRef {
    param(
        [string] $BranchName,
        [bool] $BranchExists,
        [string] $BaseRef
    )

    # Silently ignoring -BaseRef here would hand back a worktree based on something other than
    # what was asked for — the exact confusion the parameter exists to prevent.
    if ($BaseRef -and $BranchExists) {
        throw "Branch '$BranchName' already exists, so -BaseRef '$BaseRef' cannot apply. Omit -BaseRef to check out the existing branch, or pick a new -BranchName."
    }

    if ($BranchExists) {
        return $BranchName
    }

    if ($BaseRef) {
        return $BaseRef
    }

    return 'HEAD'
}

# The exact 'git worktree add' argv. Kept separate from the call so a test can assert the start
# point is really passed through: dropping $SourceRef would still produce a working script and
# would be invisible to a test that only checked the resolver's return value.
function Get-WorktreeAddArguments {
    param(
        [string] $WorktreePath,
        [string] $BranchName,
        [bool] $BranchExists,
        [string] $SourceRef
    )

    if ($BranchExists) {
        return , @('worktree', 'add', $WorktreePath, $BranchName)
    }

    return , @('worktree', 'add', $WorktreePath, '-b', $BranchName, $SourceRef)
}

# Quotes an argv array into the single string Start-Process takes on Windows PowerShell 5.1,
# where -ArgumentList joins an array with spaces and quotes nothing. Without this, a repository
# path containing a space would arrive at git as two arguments.
function ConvertTo-ProcessArgumentLine {
    param([Parameter(Mandatory)][string[]] $Arguments)

    $quoted = foreach ($argument in $Arguments) {
        # A trailing backslash would escape the closing quote, so double the run that touches it.
        $value = [regex]::Replace($argument, '(\\*)$', '$1$1')
        '"' + ($value -replace '"', '\"') + '"'
    }

    return ($quoted -join ' ')
}

# Kills a process and everything it started, then waits for the tree to actually be gone.
#
# Process.Kill() asks the OS to terminate one process and returns immediately, so a caller that
# stops there has neither killed the children nor waited for the parent. `git fetch` starts
# children -- a credential helper, an askpass program, ssh -- and any one of them can be the thing
# that is hung. taskkill /T walks the tree, /F skips the polite request.
#
# Returns $true when nothing of the tree is left within $WaitMilliseconds.
function Stop-ProcessTree {
    param(
        [Parameter(Mandatory)][int] $ProcessId,
        [int] $WaitMilliseconds = 5000
    )

    # Function-scoped, discarded on return. Windows PowerShell 5.1 turns anything a native command
    # writes to stderr into a terminating error while the preference is 'Stop', and taskkill reports
    # an already-dead process that way.
    $ErrorActionPreference = 'Continue'

    & taskkill.exe /PID $ProcessId /T /F *> $null

    $deadline = [DateTime]::UtcNow.AddMilliseconds($WaitMilliseconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $null = [System.Diagnostics.Process]::GetProcessById($ProcessId)
        } catch {
            return $true
        }
        Start-Sleep -Milliseconds 100
    }

    try {
        $null = [System.Diagnostics.Process]::GetProcessById($ProcessId)
        return $false
    } catch {
        return $true
    }
}

# Decides whether the fetch may impose `ssh -oBatchMode=yes`, which stops ssh asking for a
# passphrase. Returns that command, or $null when somebody else already chose the transport.
#
# `GIT_SSH_COMMAND` is not only a batch-mode switch: it is how a caller points git at an identity
# file, a proxy, or a different ssh client, and git documents that it is used INSTEAD OF ssh.
# Overwriting it makes the fetch fail for those remotes, which would leave the sweep permanently
# unable to refresh its base -- and therefore permanently unable to remove anything. The timeout
# already bounds a transport that hangs.
#
# `core.sshCommand` counts as chosen too: the environment variable wins over it, so setting one
# silently overrides the other.
function Resolve-BatchModeSshCommand {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [string] $ExistingCommand
    )

    $ErrorActionPreference = 'Continue'

    if ($ExistingCommand) { return $null }

    $configured = "$(& git -C $RepoRoot config --get core.sshCommand 2>$null)".Trim()
    if ($configured) { return $null }

    return 'ssh -oBatchMode=yes'
}

# Resolves the base that a merged-worktree decision must be made against.
#
# The local branch is the wrong base. `gh pr merge` merges on GitHub and never advances a local
# ref, so a worktree whose pull request merged an hour ago still looks unmerged locally, and stays
# that way until a human pulls. The remote-tracking branch is the fact the decision needs.
#
# Returns [pscustomobject]@{ Ref; Remote; Fetched; Reason }. Reason is one of:
#   'remote-fetched' - the tracking ref was just updated from the remote.
#   'remote-stale'   - the fetch failed or timed out; the cached tracking ref is returned, and the
#                      caller must treat it as a base it cannot trust for a destructive decision.
#   'no-upstream'    - $LocalRef tracks nothing, so the local branch is the only base there is.
#
# A cached tracking ref is not a safe base for removal. The remote can LOSE history -- a force
# update, a reverted merge -- and then the cache holds a merge the remote no longer has. Deciding
# against it would remove a worktree whose work is not on the remote at all. So 'remote-stale' is
# good enough to report with and not good enough to delete with; callers fail closed on it.
#
# Never throws, and never writes to stdout. Worktree creation must not fail because a network is
# down, so every failure path returns a usable Ref.
function Resolve-MergedBaseRef {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [string] $LocalRef = 'main',
        [int] $TimeoutSeconds = 15
    )

    # Function-scoped, discarded on return. A branch with no upstream makes `git rev-parse` write
    # "fatal: no upstream configured" to stderr, and Windows PowerShell 5.1 turns that into a
    # terminating error while the preference is 'Stop' -- even with 2>$null. This function must
    # never throw, so it opts out for its own body only.
    $ErrorActionPreference = 'Continue'

    $localOnly = [pscustomobject]@{ Ref = $LocalRef; Remote = $null; Fetched = $false; Reason = 'no-upstream' }

    # "$value" rather than [string] $value: under Set-StrictMode -Version Latest a cast of the
    # $null a failed git command returns stays $null, and .Trim() on it throws.
    $trackingRef = "$(& git -C $RepoRoot rev-parse --symbolic-full-name "$LocalRef@{upstream}" 2>$null)".Trim()
    if ($LASTEXITCODE -ne 0 -or -not $trackingRef.StartsWith('refs/remotes/')) { return $localOnly }

    # The remote name and the remote branch name come from config rather than from splitting
    # 'origin/main' on '/': a remote may be named with a slash in it, and a branch always may.
    $remote = "$(& git -C $RepoRoot config --get "branch.$LocalRef.remote" 2>$null)".Trim()
    $remoteBranchRef = "$(& git -C $RepoRoot config --get "branch.$LocalRef.merge" 2>$null)".Trim()
    if (-not $remote -or -not $remoteBranchRef.StartsWith('refs/heads/')) { return $localOnly }

    $shortRef = $trackingRef.Substring('refs/remotes/'.Length)
    $remoteBranch = $remoteBranchRef.Substring('refs/heads/'.Length)
    # One explicit refspec: no tags, no other branches, one small round trip. The leading '+'
    # accepts a force-updated remote branch, which a plain refspec would reject.
    $refspec = '+{0}:{1}' -f $remoteBranchRef, $trackingRef

    $result = [pscustomobject]@{ Ref = $shortRef; Remote = $remote; Fetched = $false; Reason = 'remote-stale' }

    # Nothing here may wait for a human. Terminal prompting is off, git's own askpass program is
    # cleared, and ssh runs in batch mode unless the caller chose its own transport (see
    # Resolve-BatchModeSshCommand). `credential.helper` is deliberately LEFT ALONE: clearing
    # it would break the ordinary authenticated fetch this whole feature depends on. Git Credential
    # Manager is told not to open a window instead -- `credential.interactive` is the current
    # setting, GCM_INTERACTIVE the older one, and both are cheap to set.
    $arguments = @(
        '-c', 'core.askPass=',
        '-c', 'credential.interactive=false',
        '-C', $RepoRoot,
        'fetch', '--quiet', '--no-tags', $remote, $refspec
    )

    $savedEnvironment = @{}
    $suppressed = @{
        GIT_TERMINAL_PROMPT = '0'
        GCM_INTERACTIVE     = 'never'
        GIT_ASKPASS         = ''
        SSH_ASKPASS         = ''
    }
    $batchModeSsh = Resolve-BatchModeSshCommand -RepoRoot $RepoRoot `
        -ExistingCommand ([Environment]::GetEnvironmentVariable('GIT_SSH_COMMAND', 'Process'))
    if ($batchModeSsh) { $suppressed['GIT_SSH_COMMAND'] = $batchModeSsh }
    foreach ($name in $suppressed.Keys) {
        $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, $suppressed[$name], 'Process')
    }

    $process = $null
    try {
        # Not Start-Process: on Windows PowerShell 5.1 the object it returns without -Wait reports
        # ExitCode as $null, so every successful fetch read as a failure. Owning the Process object
        # gives the same answer on both hosts. The output streams are drained asynchronously,
        # because a full pipe buffer would block the child forever.
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = 'git'
        $startInfo.Arguments = ConvertTo-ProcessArgumentLine $arguments
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        $null = $process.Start()
        $null = $process.StandardOutput.ReadToEndAsync()
        $null = $process.StandardError.ReadToEndAsync()

        if ($process.WaitForExit($TimeoutSeconds * 1000)) {
            if ($process.ExitCode -eq 0) {
                $result.Fetched = $true
                $result.Reason = 'remote-fetched'
            }
        } else {
            # An unresponsive host must not hold up the caller for the OS connect timeout, and a
            # hung helper must not outlive the fetch that started it.
            $null = Stop-ProcessTree -ProcessId $process.Id
        }
    } catch {
        # git missing from PATH, or the process could not start. The cached ref still answers.
    } finally {
        foreach ($name in $savedEnvironment.Keys) {
            [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
        }
        if ($process) { $process.Dispose() }
    }

    return $result
}

# Describes a Resolve-MergedBaseRef result in one line, for the caller to write to stderr.
# Separated from the resolver so the wording is testable without a repository or a network.
function Format-MergedBaseRefMessage {
    param(
        [Parameter(Mandatory)][string] $Prefix,
        [Parameter(Mandatory)][object] $Base
    )

    switch ($Base.Reason) {
        'remote-fetched' { return "$($Prefix): base '$($Base.Ref)' (fetched from $($Base.Remote))." }
        'remote-stale'   { return "$($Prefix): base '$($Base.Ref)' (fetch from $($Base.Remote) failed; it may be behind the remote)." }
        default          { return "$($Prefix): base '$($Base.Ref)' (local only; no remote-tracking branch)." }
    }
}

# AGENTS.md: worktree-born branches are '<type>/wt-<topic>'. The Claude WorktreeCreate hook
# only ever supplies a worktree name, so an untyped name cannot express intent and falls back
# to the 'fix/' type; a type prefix the caller did supply is preserved.
function ConvertTo-WorktreeBranchName {
    param([string] $Value)

    # Same sanitization as the worktree directory name, except '/' survives so a type prefix
    # can be expressed. Collapsed and trimmed because git rejects '//' and a trailing '/'.
    $safe = ($Value.Trim() -replace '[^A-Za-z0-9._/-]+', '-') -replace '/{2,}', '/'
    $safe = $safe.Trim([char[]] @('-', '/'))
    if (-not $safe) {
        throw 'Worktree branch name cannot be empty.'
    }

    # The branch prefixes from AGENTS.md 'Git Workflow' — deliberately NOT the conventional
    # commit types listed alongside them ('refactor:', 'test:', 'docs:', 'chore:'), which name
    # commits rather than branches. An unrecognized leading segment is topic text, not a type.
    $type = 'fix'
    $topic = $safe
    if ($safe -match '^(?<type>feature|fix|hotfix)/(?<topic>.+)$') {
        $type = $Matches.type
        $topic = $Matches.topic
    }

    if ($topic -notmatch '^wt-') {
        $topic = "wt-$topic"
    }

    return "$type/$topic"
}

# Lists the commits that removing this branch would strand: reachable from somewhere the branch has
# pointed, and reachable from no other ref. `--exclude` applies to the `--all` that follows it, so
# the branch being judged does not shield its own history.
#
# Identity, not patch text. `git cherry` was used here before and answered wrongly three ways: it
# normalizes whitespace, it skips merge commits entirely, and it ignores author, message, signature
# and empty-commit intent. Reachability has none of those blind spots.
#
# Returns $null when git fails, which every caller must read as "cannot tell" and keep the worktree.
function Get-StrandedCommits {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][string] $Branch,
        [Parameter(Mandatory)][string[]] $Shas
    )

    if ($Shas.Count -eq 0) { return , @() }

    # '--single-worktree' keeps '--all' to this repository's refs. Without it '--all' also examines
    # every OTHER worktree's HEAD, and this branch's own worktree has HEAD at the branch tip -- so
    # any commit reachable from the tip was reported as held by something else, when removing the
    # branch would take it too. Measured: a commit made after the branch merged was hidden that way.
    # The reset case this function exists for is unaffected either way, because a commit a reset
    # dropped is not reachable from the tip that reset created.
    $stranded = & git -C $RepoRoot rev-list --single-worktree @Shas --not --exclude="refs/heads/$Branch" --all 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }

    return , @($stranded | ForEach-Object { ([string] $_).Trim() } | Where-Object { $_ })
}

# Decides whether the stranded commits are superseded work or discarded work.
#
# Every rebase and every `git commit --amend` strands the commits it replaced -- that is what
# rewriting history means, and nobody expects those originals back. A `git reset` is different: it
# drops commits without putting anything in their place, and after it the ref log is the only thing
# still holding them.
#
# So the rule is about the reset entries alone. For each one, the commits it dropped are those
# reachable from the branch's previous position and not from where the reset moved it. If any of
# those is stranded, this worktree still holds the last copy and must stay.
#
# $Entries is newest first, as `git reflog show` prints it, so entry i+1 is the position entry i
# moved away from.
function Test-StrandedWorkWasSuperseded {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Entries,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $Stranded
    )

    if ($Stranded.Count -eq 0) { return $true }

    $strandedSet = @{}
    foreach ($sha in $Stranded) { $strandedSet[$sha] = $true }

    for ($i = 0; $i -lt $Entries.Count; $i++) {
        if ($Entries[$i].Subject -notmatch '^reset:') { continue }
        if ($i + 1 -ge $Entries.Count) { continue }

        $before = $Entries[$i + 1].Sha
        $after = $Entries[$i].Sha
        $dropped = & git -C $RepoRoot rev-list $before --not $after 2>$null
        if ($LASTEXITCODE -ne 0) { return $false }

        foreach ($sha in $dropped) {
            if ($strandedSet.ContainsKey(([string] $sha).Trim())) { return $false }
        }
    }

    return $true
}

# Answers what `git branch --merged` cannot: did this branch's own work get merged into $MainRef?
# A just-created worktree branch points at a commit main already had, so the merged test passes
# for it and the sweep would delete unstarted work.
#
# Removal is destructive, so this returns $true only when ALL FIVE signals agree, and $false for
# anything it cannot establish -- an unclear answer keeps the worktree.
#
#   1. WORK. The branch ref log holds a subject for an operation that creates a commit. Git writes
#      'commit:', 'commit (amend):', 'commit (merge):', 'commit (initial):', 'cherry-pick:',
#      'revert:' and 'merge <ref>: Merge made by ...'. The list is closed on purpose -- see the
#      forgery note below.
#   2. MERGE. A SHA the ref log records under one of those subjects, or under 'rebase (finish)', is
#      a NON-FIRST parent of a merge commit reachable from $MainRef -- what a GitHub "Merge pull
#      request" (`--no-ff`) leaves behind. Git history, not text.
#
#      A rebase merge leaves none of that: GitHub replays the commits under new SHAs and writes no
#      merge commit, so nothing local ties the branch to the base. GitHub is then asked instead, and
#      a merged pull request counts only when the branch's own ref log recorded its head SHA.
#      $MergedPullRequests carries records a caller already fetched; $MergedPullRequestLookup fetches
#      them on demand. Both are optional, and neither can turn a "keep" into anything but a "remove"
#      -- an answer that cannot be got costs a removal and never causes one.
#   3. NOTHING DISCARDED. Removing the branch would strand no commit that a `git reset` dropped.
#      Get-StrandedCommits and Test-StrandedWorkWasSuperseded decide it, by reachability.
#   4. NOTHING AFTER THE PROOF. The branch tip reaches no work that no merge proof reaches and no
#      other ref holds. Get-WorkAfterMergeProof decides it. Ancestry used to refuse that case for
#      free, because a branch that gained commits after its merge stopped being an ancestor of the
#      base; the rule that replaced ancestry has to ask the question directly.
#   5. THE PROOF IS THIS BRANCH'S OWN WORK. At least one merge-proof SHA was NOT reachable from
#      the base ref at the moment this branch was created. Get-BaseRefAtBranchCreation resolves
#      that position from the branch's oldest ref-log entry. This is the only signal that refuses
#      a forged 'commit:' subject on a branch nobody committed on, because it is the only one that
#      looks at what the base already contained. It may only refuse: when the position cannot be
#      resolved it is skipped.
#
# No signal is sufficient alone, and each covers the others' blind spots:
#   - Ref-log subjects are caller-controlled text. GIT_REFLOG_ACTION and `git update-ref -m` let
#     any caller write 'commit: Fast-forward' onto a branch that created no commit, so signal 1
#     alone can be forged into deleting a brand-new worktree.
#   - A branch created AT an already-merged branch's tip (the -BaseRef shape) really is a
#     non-first parent, so signal 2 alone reads unstarted work as finished. Its ref log shows no
#     commit, so signal 1 rejects it.
#   - Signals 1 and 2 can describe DIFFERENT work: commit, `git reset --hard` the commit away, then
#     rebase the emptied branch onto an unrelated merged branch. Both read as satisfied while the
#     branch's own commit survives nowhere else. Signal 3 is what refuses that.
#
# Signal 3 asks about discarding, not about merging. A rebase or an amend strands the commits it
# rewrote, and those originals are superseded work nobody expects back. A reset strands commits
# without replacing them, and after it the ref log is their last holder -- so a reset that stranded
# anything keeps the worktree.
#
# Signal 2 accepts 'rebase (finish)' because a rebased branch merges under a SHA that no commit
# entry ever held. `git rebase` replays the work and records the new tip under that subject, while
# the commit entry keeps the pre-rebase SHA, which never reaches $MainRef. Reading commit entries
# alone kept every rebased worktree forever. `git rebase` and `git rebase -i` write the same
# subject.
#
# Known limits, both deliberate:
#   - Text cannot be authenticated, and signal 5 narrows that rather than ending it. Git records
#     no link between a commit and the branch that created it. A caller who sets
#     GIT_REFLOG_ACTION=commit and fast-forwards an unstarted branch onto an already-merged tip
#     satisfies signals 1 and 2, and an empty branch gives signals 3 and 4 nothing to refuse.
#     Signal 5 refuses that branch when the tip was already in the base before the branch existed,
#     which is the shape backlog 096 reported. Two windows stay open. It cannot refuse a
#     fast-forward onto work that entered the base afterwards. It also cannot refuse one whose
#     base move shares a second with the branch's creation: ref-log stamps hold whole seconds,
#     and the rule is STRICTLY earlier, so that move is skipped and an older base position is
#     used. Such a branch still holds no commit, so nothing is lost.
#   - Superseded originals are not protected. A rebase or an amend leaves its old commits reachable
#     only from this ref log, and removing the branch removes that ref log with it. `git branch -d`
#     does the same to a merged branch, so the sweep is no more destructive than the command it
#     automates. Work a reset discarded IS protected, which is the case that matters.
# Everything the branch's own ref log records, read in one walk.
#
# '%gs' is the subject, '%H' is the commit the branch pointed at after that entry. A missing ref log
# (core.logAllRefUpdates off, gc expired it) or an unknown branch exits non-zero, and this returns
# $null so the caller reads it as unstarted.
#
# One walk produces three sets and an ordered list. CommitShas carries the work proof, MergeProofShas
# the SHAs allowed to satisfy signal 2, AllShas every place the branch has been, and Entries keeps
# ref-log order, which signal 3 needs to read what a reset dropped.
#
# 'branch: Created from' lands in AllShas only: a branch started at an already-merged branch's tip
# (`new-worktree.ps1 -BaseRef`) carries a non-first parent there, and letting that SHA prove a merge
# would pair it with a forged 'commit:' subject on a later fast-forward, without a single commit
# ever being made.
function Get-BranchRefLogFacts {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][string] $Branch
    )

    $entries = & git -C $RepoRoot reflog show --format='%H %gs' "refs/heads/$Branch" 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }

    $commitShas = @{}
    $mergeProofShas = @{}
    $allShas = @{}
    $entryList = @()
    foreach ($entry in $entries) {
        $text = ([string] $entry).Trim()
        if (-not $text) { continue }

        $sha, $subject = $text -split '\s+', 2
        if (-not $sha -or -not $subject) { continue }

        $allShas[$sha] = $true
        $entryList += [pscustomobject]@{ Sha = $sha; Subject = $subject }

        # The closed list of subjects git writes for an operation that creates a commit.
        # 'commit (finish):' is absent because git never writes it; only GIT_REFLOG_ACTION=commit on
        # a rebase produces that subject. 'merge <ref>:' is included only with the message git
        # writes for a real merge commit -- a fast-forward writes 'merge <ref>: Fast-forward' and
        # creates nothing, so accepting the whole 'merge' prefix would sweep unstarted worktrees.
        if ($subject -match "^(commit(:| \((amend|merge|initial)\):)|cherry-pick:|revert:|merge [^:]+: Merge made by )") {
            $commitShas[$sha] = $true
            $mergeProofShas[$sha] = $true
        }
        # No '\b' after 'rebase (finish)': ')' and the ':' that follows it are both non-word
        # characters, so a word boundary never matches between them.
        elseif ($subject -match '^rebase \(finish\)') { $mergeProofShas[$sha] = $true }
    }

    return [pscustomobject]@{
        CommitShas     = $commitShas
        MergeProofShas = $mergeProofShas
        AllShas        = $allShas
        Entries        = $entryList
    }
}

# Signal 2, and the SHAs that satisfied it.
#
# `--format=%P` emits a 'commit <sha>' header line per commit followed by that commit's parents;
# --min-parents=2 keeps merges only, and every parent after the first is a tip that was merged in.
#
# Every SHA the ref log recorded counts, not just the current tip. A finished worktree that runs
# `git merge --ff-only main` after its pull request merged moves its tip off the merge commit's
# second parent onto the merge commit itself. The work was still merged, and the sweep must still
# remove it, so the proof has to survive that move.
#
# The matched SHAs are returned rather than a bare $true, because signal 4 needs them: they are the
# boundary between merged work and anything the branch did afterwards. Returns $null when git fails.
function Get-LocalMergeProofShas {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][string] $MainRef,
        [Parameter(Mandatory)][hashtable] $MergeProofShas
    )

    $parentLines = & git -C $RepoRoot rev-list --min-parents=2 --format='%P' $MainRef 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }

    $proofs = @{}
    foreach ($line in $parentLines) {
        $text = ([string] $line).Trim()
        if (-not $text -or $text -like 'commit *') { continue }
        $parents = @($text -split '\s+')
        for ($i = 1; $i -lt $parents.Count; $i++) {
            if ($MergeProofShas.ContainsKey($parents[$i])) { $proofs[$parents[$i]] = $true }
        }
    }

    return , @($proofs.Keys)
}

# Runs one child process, captures its stdout, and gives up after $TimeoutSeconds.
#
# Two rules meet here, and only one order satisfies both. A child that fills a pipe buffer blocks
# on the write forever if nobody drains it. And a BLOCKING read of a child that never exits ignores
# the timeout entirely, because that read only returns when the pipe closes -- which a hung process
# never does. So the drains start first, asynchronously, and their results are read only after the
# child has actually exited. Resolve-MergedBaseRef does the same for its fetch.
#
# A hung child is killed with its whole tree: a credential helper or an editor it started can be
# the thing that is stuck.
#
# Never throws. Returns [pscustomobject]@{ Started; TimedOut; ExitCode; StdOut }:
#   Started  - $false when the executable could not be launched at all.
#   TimedOut - $true when the child outlived the timeout and was killed. ExitCode is then $null.
function Invoke-CapturedProcess {
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [Parameter(Mandatory)][string[]] $Arguments,
        [string] $WorkingDirectory,
        [int] $TimeoutSeconds = 15
    )

    $ErrorActionPreference = 'Continue'

    $failed = [pscustomobject]@{ Started = $false; TimedOut = $false; ExitCode = $null; StdOut = '' }

    $process = $null
    try {
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $FilePath
        $startInfo.Arguments = ConvertTo-ProcessArgumentLine $Arguments
        if ($WorkingDirectory) { $startInfo.WorkingDirectory = $WorkingDirectory }
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        $null = $process.Start()

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $null = Stop-ProcessTree -ProcessId $process.Id
            return [pscustomobject]@{ Started = $true; TimedOut = $true; ExitCode = $null; StdOut = '' }
        }

        $exitCode = $process.ExitCode

        # The child exited, so both pipes are closed and these complete. The bound is belt and
        # braces for a grandchild that inherited the handle and outlived its parent.
        if (-not $stdoutTask.Wait($TimeoutSeconds * 1000)) {
            return [pscustomobject]@{ Started = $true; TimedOut = $true; ExitCode = $null; StdOut = '' }
        }
        $null = $stderrTask.Wait(1000)

        return [pscustomobject]@{
            Started  = $true
            TimedOut = $false
            ExitCode = $exitCode
            StdOut   = $stdoutTask.Result
        }
    } catch {
        return $failed
    } finally {
        if ($process) { $process.Dispose() }
    }
}

# The branch name `gh pr list --base` needs, read from config rather than by splitting a ref.
# 'origin/main' cannot be halved on the slash: a remote may contain one and a branch always may.
# This is the same source Resolve-MergedBaseRef reads.
# $LocalRef may arrive in either shape, because a run decides against 'main' before its base is
# resolved and against 'origin/main' afterwards. Both must produce the same answer, and callers must
# pass the base they are really deciding against: defaulting to 'main' here asked GitHub about the
# wrong branch whenever a run used -MainRef release, and a pull request merged into main could then
# prove a merge that never reached release.
function Resolve-BaseBranchName {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [string] $LocalRef = 'main'
    )

    $ErrorActionPreference = 'Continue'

    $candidate = $LocalRef

    # A remote-tracking ref carries the remote name in front. Strip it using the remote names git
    # actually has, never by splitting on the first slash: a remote may contain a slash, and a
    # branch always may, so 'origin/feature/x' and a remote literally named 'origin/feature' are
    # both possible. The longest matching remote wins.
    $remotes = @(& git -C $RepoRoot remote 2>$null | ForEach-Object { ([string] $_).Trim() } | Where-Object { $_ })
    if ($remotes.Count -gt 0) {
        foreach ($remote in ($remotes | Sort-Object -Property Length -Descending)) {
            if ($candidate.StartsWith($remote + '/')) {
                $candidate = $candidate.Substring($remote.Length + 1)
                break
            }
        }
    }

    # The local branch's configured upstream is the authority: the remote branch may be named
    # differently from the local one.
    $remoteBranchRef = "$(& git -C $RepoRoot config --get "branch.$candidate.merge" 2>$null)".Trim()
    if ($remoteBranchRef.StartsWith('refs/heads/')) {
        return $remoteBranchRef.Substring('refs/heads/'.Length)
    }

    return $candidate
}

# Asks GitHub which pull requests merged into $BaseBranch, for the case local git cannot prove.
#
# A rebase merge writes no merge commit and rewrites the SHA, so nothing in the local repository
# ties the branch to the base. GitHub holds that fact and nothing else does.
#
# Never throws, and an answer it cannot get is 'not available', never 'not merged': this signal may
# only ACCEPT a removal, so its absence costs a removal and can never cause one.
#
# One call serves a whole sweep run. The caller caches the records and hands them to each decision.
# $Limit is a real cutoff -- a pull request merged longer ago than that is not found, and its
# worktree is kept, which is the safe direction.
function Get-MergedPullRequestRecords {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][string] $BaseBranch,
        [string] $HeadBranch,
        [int] $Limit = 100,
        [int] $TimeoutSeconds = 15
    )

    $ErrorActionPreference = 'Continue'

    $unavailable = {
        param([string] $Reason)

        [pscustomobject]@{ Available = $false; Reason = $Reason; Records = @() }
    }

    $gh = Get-Command 'gh' -ErrorAction SilentlyContinue
    if (-not $gh -or -not $gh.Source) { return (& $unavailable 'gh-missing') }

    $arguments = @('pr', 'list', '--state', 'merged', '--base', $BaseBranch,
        '--limit', "$Limit", '--json', 'number,headRefName,headRefOid')
    if ($HeadBranch) { $arguments += @('--head', $HeadBranch) }

    $run = Invoke-CapturedProcess -FilePath $gh.Source -Arguments $arguments `
        -WorkingDirectory $RepoRoot -TimeoutSeconds $TimeoutSeconds

    if ($run.TimedOut) { return (& $unavailable 'timeout') }
    if (-not $run.Started) { return (& $unavailable 'gh-failed') }
    if ($run.ExitCode -ne 0) { return (& $unavailable 'gh-failed') }

    $records = @(ConvertFrom-GhMergedPrJson -Json $run.StdOut)
    $trimmed = "$($run.StdOut)".Trim()
    if ($records.Count -eq 0 -and $trimmed -and $trimmed -ne '[]') {
        return (& $unavailable 'unparsable')
    }

    return [pscustomobject]@{ Available = $true; Reason = 'ok'; Records = $records }
}

# Reads `gh pr list --json number,headRefName,headRefOid` output into records.
#
# Pure: no process, no network, so a fixture can test it against the shape GitHub really returns.
# Unparsable or empty input is not an error here -- it means "no records", and the caller decides
# what that costs. A record missing either field is dropped rather than defaulted: without a head
# SHA it cannot bind to a branch, and binding is the whole point.
function ConvertFrom-GhMergedPrJson {
    param([string] $Json)

    if ([string]::IsNullOrWhiteSpace($Json)) { return , @() }

    # ConvertFrom-Json throws ArgumentException on invalid JSON -- measured on Windows PowerShell 5.1
    # and on pwsh 7 -- so this must be caught rather than tested for a $null return.
    try {
        $parsed = $Json | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return , @()
    }

    # Read through PSObject.Properties, never as $item.headRefOid: under Set-StrictMode -Version
    # Latest a missing property on a PSCustomObject throws, and a record with fields missing is
    # exactly what this function has to tolerate.
    $readProperty = {
        param($Item, [string] $Name)

        $property = $Item.PSObject.Properties[$Name]
        if (-not $property) { return '' }
        return "$($property.Value)".Trim()
    }

    $records = @()
    foreach ($item in @($parsed)) {
        if ($null -eq $item) { continue }
        $oid = & $readProperty $item 'headRefOid'
        $name = & $readProperty $item 'headRefName'
        if (-not $oid -or -not $name) { continue }
        $records += [pscustomobject]@{
            Number      = (& $readProperty $item 'number')
            HeadRefName = $name
            HeadRefOid  = $oid
        }
    }

    return , $records
}

# The commit the base ref pointed at BEFORE $Branch was created.
#
# Signal 5 needs to know what the base already contained before this branch existed. Git records
# it without any marker of ours. The branch's OLDEST ref-log entry carries its creation time, and
# the base ref's own ref log carries every position it has held.
#
# STRICTLY EARLIER is the rule, and '<base>@{<time>}' cannot express it. That syntax returns the
# newest entry AT OR BEFORE the time, so a branch created in the same second the base moved
# resolves to the later position -- the one that already holds the branch's own work. Signal 5
# would then refuse a legitimate merged branch. So this walks the ref log and compares stamps.
#
# '--date=unix' makes '%gd' print '<shortname>@{<seconds>}', which compares as an integer. No date
# parsing, and no dependence on the local time zone.
#
# Returns $null for every answer that cannot be trusted, and the caller must then SKIP signal 5
# rather than refuse -- an unanswerable question must not change today's decision. Three cases:
#   - the branch has no ref log, or its oldest entry does not parse;
#   - the base ref has no ref log, or no such ref;
#   - no base entry is strictly earlier than the branch's creation. That is a branch older than
#     the base's whole ref log, and it is also every test fixture built inside one second.
function Get-BaseRefAtBranchCreation {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][string] $Branch,
        [Parameter(Mandatory)][string] $MainRef
    )

    $branchEntries = & git -C $RepoRoot reflog show --date=unix --format='%gd' "refs/heads/$Branch" 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }

    # Newest first, so the branch's creation is the LAST entry.
    $oldest = @($branchEntries | ForEach-Object { ([string] $_).Trim() } | Where-Object { $_ }) | Select-Object -Last 1
    if (-not $oldest -or $oldest -notmatch '@\{(\d+)') { return $null }
    $createdAt = [long] $Matches[1]

    $baseEntries = & git -C $RepoRoot reflog show --date=unix --format='%H %gd' $MainRef 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }

    # Newest first again, so the first strictly-earlier entry is the position the base held when
    # this branch was created.
    foreach ($entry in @($baseEntries | ForEach-Object { ([string] $_).Trim() } | Where-Object { $_ })) {
        if ($entry -notmatch '^([0-9a-f]{40}) \S+@\{(\d+)') { continue }
        if ([long] $Matches[2] -lt $createdAt) { return $Matches[1] }
    }

    return $null
}

# Signal 4. The commits the branch tip reaches that no merge proof reaches and no other ref holds.
#
# Ancestry used to refuse this case for free: a branch that gained commits after its pull request
# merged stopped being an ancestor of the base, so `git branch --merged` dropped it. The rule that
# replaces ancestry has to ask the question directly, or the sweep removes a worktree holding
# unpushed work -- and `git branch -d` then refuses the branch, leaving it orphaned.
#
# The proof SHAs are the boundary. Anything reachable from one of them is merged work. Anything else
# the tip reaches is later work, unless another ref holds it -- and then removing this worktree
# discards nothing, which is the same question Get-StrandedCommits asks.
#
# Returns $null when git fails or when there is no proof to measure against, which every caller must
# read as "cannot tell" and keep the worktree.
function Get-WorkAfterMergeProof {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][string] $Branch,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $ProofShas
    )

    if ($ProofShas.Count -eq 0) { return $null }

    # Exactly ONE '--not', with every exclusion after it. '--not' TOGGLES polarity each time it
    # appears, so '--not a --not b' excludes a and then re-includes b -- which quietly turned '--all'
    # back into an inclusion and made a plainly merged branch look like it carried later work.
    # '--single-worktree' is load-bearing. Without it '--all' also examines every OTHER worktree's
    # HEAD, and this branch's own worktree has HEAD at the branch tip -- so the later work looked
    # like something another ref held, and signal 4 reported nothing.
    $arguments = @('-C', $RepoRoot, 'rev-list', '--single-worktree', "refs/heads/$Branch", '--not')
    $arguments += $ProofShas
    $arguments += @("--exclude=refs/heads/$Branch", '--all')

    $after = & git @arguments 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }

    return , @($after | ForEach-Object { ([string] $_).Trim() } | Where-Object { $_ })
}

function Test-BranchOwnWorkWasMerged {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][string] $Branch,
        [string] $MainRef = 'main',
        [object[]] $MergedPullRequests,
        [scriptblock] $MergedPullRequestLookup
    )

    # Signal 1. A branch nobody has committed on is unstarted, not finished.
    $facts = Get-BranchRefLogFacts -RepoRoot $RepoRoot -Branch $Branch
    if ($null -eq $facts) { return $false }
    if ($facts.CommitShas.Count -eq 0) { return $false }

    # Signal 2.
    $proofs = Get-LocalMergeProofShas -RepoRoot $RepoRoot -MainRef $MainRef -MergeProofShas $facts.MergeProofShas
    if ($null -eq $proofs) { return $false }

    # Signal 2, the GitHub half. Asked LAST, and only when local git proved nothing: a merge-commit
    # merge therefore costs no network call at all. This signal may only ACCEPT a removal, so an
    # answer that cannot be got costs a removal and can never cause one.
    if ($proofs.Count -eq 0) {
        $lookupResult = $null
        if ($MergedPullRequests) {
            $lookupResult = [pscustomobject]@{ Available = $true; Reason = 'ok'; Records = $MergedPullRequests }
        } elseif ($MergedPullRequestLookup) {
            $lookupResult = & $MergedPullRequestLookup
        }

        if ($lookupResult -and $lookupResult.Available) {
            foreach ($record in @($lookupResult.Records)) {
                # The branch NAME is not the binding, and must never become it. Branch names repeat
                # in this repository -- two pull requests have shared one head -- so a name match
                # would let a recreated worktree inherit an older merge and lose live work. The head
                # SHA the branch itself recorded cannot be borrowed that way.
                if ($facts.MergeProofShas.ContainsKey($record.HeadRefOid)) { $proofs += $record.HeadRefOid }
            }
        }
    }

    if ($proofs.Count -eq 0) { return $false }

    # Signal 5. The proof must point at work the base did not already have.
    #
    # Signals 1 and 2 are satisfiable without creating a commit: GIT_REFLOG_ACTION=commit on a
    # fast-forward onto an already-merged tip writes 'commit: Fast-forward' carrying a SHA that
    # really is a non-first parent. That branch strands nothing and gains nothing afterwards, so
    # signals 3 and 4 have nothing to refuse either.
    #
    # This asks the question none of them ask: was that SHA already in the base before this branch
    # existed? Work the branch can claim as its own cannot have been.
    #
    # Skipped, not failed, when the base at creation cannot be resolved. This signal may only
    # REFUSE a removal, so an unanswerable question leaves the decision exactly as it was.
    $baseAtCreation = Get-BaseRefAtBranchCreation -RepoRoot $RepoRoot -Branch $Branch -MainRef $MainRef
    if ($baseAtCreation) {
        $ownProof = $false
        foreach ($proof in $proofs) {
            & git -C $RepoRoot merge-base --is-ancestor $proof $baseAtCreation 2>$null | Out-Null
            # Exit 1 means the proof was NOT already reachable from the base, which is the answer
            # that makes it this branch's own work. Any other non-zero code is a failed check, and
            # must not count as proof.
            if ($LASTEXITCODE -eq 1) { $ownProof = $true; break }
        }
        if (-not $ownProof) { return $false }
    }

    # Signal 4. The merge proves the work that existed when it happened, and nothing after it.
    $after = Get-WorkAfterMergeProof -RepoRoot $RepoRoot -Branch $Branch -ProofShas $proofs
    if ($null -eq $after -or $after.Count -gt 0) { return $false }

    # Signal 3. Signals 1 and 2 can be satisfied by different work, so the last question is the one
    # that makes removal safe: would removing this branch discard a commit nothing else holds?
    $stranded = Get-StrandedCommits -RepoRoot $RepoRoot -Branch $Branch -Shas @($facts.AllShas.Keys)
    if ($null -eq $stranded) { return $false }

    return (Test-StrandedWorkWasSuperseded -RepoRoot $RepoRoot -Entries $facts.Entries -Stranded $stranded)
}

# Returned when the manifest is there but cannot be read, usually because another process holds
# it. This is NOT the same answer as empty: empty means "no item to judge" and allows removal,
# so a read failure that returned empty would let the guard pass without ever checking a plan.
$WorktreeBacklogItemUnreadable = '<manifest-unreadable>'

# The backlog item a worktree records for itself. setup-worktree-local-dev.ps1 writes the key at
# creation; a worktree made before that key existed has no manifest entry and reads as empty,
# which Test-WorktreePlanWasImplemented treats as "nothing to judge".
function Get-ManifestBacklogItem {
    param([Parameter(Mandatory)][string] $WorktreePath)

    $manifest = Join-Path $WorktreePath 'scripts\.env.worktree'
    if (-not (Test-Path -LiteralPath $manifest)) { return '' }

    try {
        $lines = @(Get-Content -LiteralPath $manifest -ErrorAction Stop)
    } catch {
        return $WorktreeBacklogItemUnreadable
    }

    foreach ($line in $lines) {
        if ($line -match '^\s*AHKFLOW_BACKLOG_ITEM\s*=\s*(?<value>.*)$') { return $Matches.value.Trim() }
    }
    return ''
}

$WorktreeManifestWriteAttempts = 12
$WorktreeManifestWriteDelayMs = 250

# Records which backlog item a worktree serves. Returns $true when the value is on disk.
#
# The read and the write happen through one exclusive handle, so a reader-then-writer pair cannot
# lose an edit made in between, and a second writer waits instead of overwriting a stale snapshot.
# An editor or a scanner holding the file is normal and passes, which is why this retries. It
# returns $false rather than throwing, and the caller decides: for the plan guard, a number that
# never reached the manifest reads as empty, and empty ALLOWS removal.
function Set-ManifestBacklogItem {
    param(
        [Parameter(Mandatory)][string] $WorktreePath,
        [Parameter(Mandatory)][string] $ItemNumber
    )

    $manifest = Join-Path $WorktreePath 'scripts\.env.worktree'
    if (-not (Test-Path -LiteralPath $manifest)) { return $false }

    $key = 'AHKFLOW_BACKLOG_ITEM'
    $encoding = New-Object System.Text.UTF8Encoding($false)

    for ($attempt = 1; $attempt -le $WorktreeManifestWriteAttempts; $attempt++) {
        $stream = $null
        try {
            $stream = [System.IO.File]::Open($manifest, 'Open', 'ReadWrite', 'None')

            $buffer = New-Object byte[] $stream.Length
            $read = 0
            while ($read -lt $buffer.Length) {
                $got = $stream.Read($buffer, $read, $buffer.Length - $read)
                if ($got -le 0) { break }
                $read += $got
            }
            $existing = $encoding.GetString($buffer, 0, $read)

            $lines = @($existing -split "`r?`n")
            # A trailing newline leaves one empty element; dropping it keeps the file from growing
            # a blank line on every write.
            if ($lines.Count -gt 0 -and $lines[-1] -eq '') { $lines = $lines[0..($lines.Count - 2)] }

            $updated = @()
            $replaced = $false
            foreach ($line in $lines) {
                if ($line -match "^\s*$key\s*=") { $updated += "$key=$ItemNumber"; $replaced = $true }
                else { $updated += $line }
            }
            if (-not $replaced) { $updated += "$key=$ItemNumber" }

            $bytes = $encoding.GetBytes(($updated -join [Environment]::NewLine) + [Environment]::NewLine)
            $stream.Position = 0
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.SetLength($bytes.Length)
            $stream.Flush()
            return $true
        } catch {
            if ($attempt -eq $WorktreeManifestWriteAttempts) { return $false }
            Start-Sleep -Milliseconds $WorktreeManifestWriteDelayMs
        } finally {
            if ($stream) { $stream.Dispose() }
        }
    }

    return $false
}

# The plans folder is the only place a "- Plan:" bullet may point at. The pointer comes off a
# markdown bullet that nothing validates, and the guard reads whatever it names. Almost any other
# file holds no unticked step, which the guard would read as "implemented" and allow the removal.
$WorktreePlansFolder = 'docs/superpowers/plans'

# The path out of a "- Plan:" bullet, or '' when the bullet does not name a plan.
# scripts/backlog.common.ps1 holds the canonical rule that CI enforces on new items; it demands
# backticks, which older items do not all have (backlog/done/104 writes the path bare). So this
# accepts an optional full stop and optional backticks, and is strict about everything else:
# the folder prefix, the .md extension, one path segment, and no traversal.
function Get-BacklogPlanRelativePath {
    param([Parameter(Mandatory)][string] $BulletRest)

    $value = $BulletRest.Trim()
    if ($value.EndsWith('.') -and $value.Length -gt 1) { $value = $value.Substring(0, $value.Length - 1) }
    $value = $value.Trim([char] 0x60).Trim()

    if ($value -notmatch ('^' + [regex]::Escape($WorktreePlansFolder) + '/[^/\\]+\.md$')) { return '' }
    if ($value -match '\.\.') { return '' }
    return $value
}

# The resolved plan file, or '' when the pointer escapes the plans folder. Get-BacklogPlanRelativePath
# already rejects traversal in the text; this re-checks after the path is resolved, because a
# symlink or a short name can still land somewhere else.
function Resolve-BacklogPlanPath {
    param(
        [Parameter(Mandatory)][string] $MainCheckout,
        [Parameter(Mandatory)][string] $PlanRelative
    )

    $plansRoot = Join-Path $MainCheckout ($WorktreePlansFolder -replace '/', '\')
    $candidate = Join-Path $MainCheckout ($PlanRelative -replace '/', '\')
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { return '' }

    try {
        $fullPlansRoot = (Resolve-Path -LiteralPath $plansRoot -ErrorAction Stop).Path.TrimEnd('\', '/')
        $fullCandidate = (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path
    } catch {
        return ''
    }

    $boundary = $fullPlansRoot + [System.IO.Path]::DirectorySeparatorChar
    if (-not $fullCandidate.StartsWith($boundary, [System.StringComparison]::OrdinalIgnoreCase)) { return '' }
    return $fullCandidate
}

# One snapshot of the base: the commit it names, plus every path under backlog/ in that commit.
# The merge gate decides against the resolved base, so the plan gate must read the same base -- an
# item filed on the branch and merged on GitHub lives in that ref long before a local pull puts it
# on disk.
#
# The plan gate looks the item up twice, once by slug and once by number, and both lookups read
# this one snapshot. Resolving the ref inside each lookup let a fetch move it in between: the guard
# could answer "no item carries this slug" against one commit and then read the recorded item out
# of another. That is the wrong-item defect through a third door.
#
# Status 'ok' carries Sha and Paths. Status 'unusable' means the ref could not be resolved, or git
# could not list it, and Detail is the end of a sentence the caller starts with the ref name.
function Get-BacklogInventoryFromRef {
    param(
        [Parameter(Mandatory)][string] $MainCheckout,
        [Parameter(Mandatory)][string] $BaseRef
    )

    # Pin the base to one commit first. Without this, a ref that does not exist and a ref that
    # simply lacks the item both arrive as an empty listing, and they are not the same answer.
    $sha = (& git -C $MainCheckout rev-parse --verify --quiet "$BaseRef^{commit}" 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $sha) {
        return [pscustomobject]@{ Status = 'unusable'; Sha = ''; Paths = @(); Detail = 'could not be resolved' }
    }
    $sha = ([string] $sha).Trim()

    $listed = & git -C $MainCheckout ls-tree -r --name-only $sha -- backlog 2>$null
    if ($LASTEXITCODE -ne 0) {
        return [pscustomobject]@{ Status = 'unusable'; Sha = $sha; Paths = @(); Detail = 'could not be listed' }
    }

    return [pscustomobject]@{ Status = 'ok'; Sha = $sha; Paths = @($listed); Detail = '' }
}

# The lines of a backlog item, read from a base snapshot rather than from disk.
#
# Returns Status plus Lines. 'found' means exactly one item and its content. 'absent' means the
# snapshot does not carry the item. 'unusable' means more than one file claims the number, or the
# read of the one file failed. The caller must not treat any of the three as a reason to read the
# working tree instead: a base was supplied because the base is the authority.
function Get-BacklogItemLinesFromRef {
    param(
        [Parameter(Mandatory)][string] $MainCheckout,
        [Parameter(Mandatory)][psobject] $Inventory,
        [Parameter(Mandatory)][string] $ItemNumber
    )

    $pattern = '^backlog/(done/|blocked/)?' + [regex]::Escape($ItemNumber) + '-[^/]*\.md$'
    $matched = @(@($Inventory.Paths) | Where-Object { $_ -match $pattern })
    if ($matched.Count -eq 0) {
        return [pscustomobject]@{ Status = 'absent'; Lines = @(); Detail = 'does not carry the item' }
    }
    if ($matched.Count -gt 1) {
        return [pscustomobject]@{ Status = 'unusable'; Lines = @(); Detail = "carries $($matched.Count) files for the item" }
    }

    $content = & git -C $MainCheckout show "$($Inventory.Sha):$($matched[0])" 2>$null
    if ($LASTEXITCODE -ne 0 -or $null -eq $content) {
        return [pscustomobject]@{ Status = 'unusable'; Lines = @(); Detail = 'holds an item that could not be read' }
    }
    return [pscustomobject]@{ Status = 'found'; Lines = @($content); Detail = '' }
}

# The number shape a backlog file name may carry. Three digits, plus an optional lower-case
# letter: this repository ships suffixed items such as 022b, and tests/BacklogNumbering.Tests.ps1
# pins that shape. A digits-only pattern would skip 022b in silence.
$WorktreeBacklogNumberPattern = '[0-9]{3}[a-z]?'

# The slug half of a worktree directory name, or '' when the name has no 'wt-' prefix.
# A worktree is named 'wt-' plus the title slug and a backlog file is the number plus the same
# slug, both from ConvertTo-BacklogSlug. A renumber changes the number and never the slug, so the
# slug is the identity that does not drift. Accepts a full path or a bare leaf name, and the
# folder does not have to exist: this reads the string only.
function Get-WorktreeSlugFromName {
    param([string] $WorktreeName)

    if ([string]::IsNullOrWhiteSpace($WorktreeName)) { return '' }
    $leaf = Split-Path -Leaf ($WorktreeName.TrimEnd('\', '/'))
    if (-not $leaf.StartsWith('wt-')) { return '' }
    return $leaf.Substring(3)
}

# The lines of a backlog item found by slug rather than by number, read from the same base snapshot
# the number lookup reads. Shaped exactly like Get-BacklogItemLinesFromRef, and returns the matched
# number as well, because the caller has to report which item it judged.
#
# The three statuses are not interchangeable, and the caller must not treat them as one.
# 'absent' means no item carries this slug, so there is nothing here to judge. 'unusable' means the
# slug DID name an item and the lookup could not deliver it: more than one match, or a read that
# failed. Those two answers lead to opposite decisions, so Detail is written as a complete clause
# that names the real reason, ready to go straight into a refusal.
function Get-BacklogItemLinesFromRefBySlug {
    param(
        [Parameter(Mandatory)][string] $MainCheckout,
        [Parameter(Mandatory)][psobject] $Inventory,
        [Parameter(Mandatory)][string] $Slug
    )

    $pattern = '^backlog/(done/|blocked/)?(?<num>' + $WorktreeBacklogNumberPattern + ')-' + [regex]::Escape($Slug) + '\.md$'
    $matched = @(@($Inventory.Paths) | Where-Object { $_ -match $pattern })
    if ($matched.Count -eq 0) {
        return [pscustomobject]@{ Status = 'absent'; Lines = @(); Detail = "no backlog item carries the slug '$Slug'"; ItemNumber = '' }
    }
    if ($matched.Count -gt 1) {
        return [pscustomobject]@{ Status = 'unusable'; Lines = @(); Detail = "$($matched.Count) backlog items carry the slug '$Slug'"; ItemNumber = '' }
    }

    $null = $matched[0] -match $pattern
    $number = $Matches.num

    # The number is already known, so a read failure names the item it could not read. Returning it
    # empty would make the caller blame the recorded number, which is an item it never opened.
    $content = & git -C $MainCheckout show "$($Inventory.Sha):$($matched[0])" 2>$null
    if ($LASTEXITCODE -ne 0 -or $null -eq $content) {
        return [pscustomobject]@{ Status = 'unusable'; Lines = @(); Detail = "backlog item $number could not be read"; ItemNumber = $number }
    }
    return [pscustomobject]@{ Status = 'found'; Lines = @($content); Detail = ''; ItemNumber = $number }
}

# The working-tree twin of Get-BacklogItemLinesFromRefBySlug, for the call that supplies no base.
# It scans the same three folders the number path scans, and it counts matches across all three
# rather than stopping at the first folder: two folders holding the same slug is the ambiguity
# this must refuse, not a race to whichever folder is read first.
#
# A folder that exists and cannot be read is 'unusable', never 'absent'. "Could not look" and
# "nothing is there" lead to opposite decisions, and collapsing them lets the caller fall back to
# the recorded number, which is the defect this whole route exists to close.
function Get-BacklogItemLinesFromWorkingTreeBySlug {
    param(
        [Parameter(Mandatory)][string] $MainCheckout,
        [Parameter(Mandatory)][string] $Slug
    )

    $namePattern = '^(?<num>' + $WorktreeBacklogNumberPattern + ')-' + [regex]::Escape($Slug) + '$'
    $found = @()
    foreach ($folder in @('backlog', 'backlog\done', 'backlog\blocked')) {
        $directory = Join-Path $MainCheckout $folder
        if (-not (Test-Path -LiteralPath $directory)) { continue }
        # No -Filter here, and that is deliberate. Get-ChildItem with a filter answers a folder it
        # cannot read with an empty list and raises nothing at all, so -ErrorAction Stop never fires
        # and a permission problem arrives as "no item carries this slug". The caller then falls back
        # to the recorded number and judges somebody else's item. Without the filter the same call
        # throws, and the name test below already does the filtering the filter did.
        try {
            $candidates = @(Get-ChildItem -LiteralPath $directory -File -ErrorAction Stop)
        } catch {
            return [pscustomobject]@{ Status = 'unusable'; Lines = @(); Detail = "the folder '$folder' could not be read"; ItemNumber = '' }
        }
        foreach ($candidate in $candidates) {
            if ($candidate.BaseName -match $namePattern) {
                $found += [pscustomobject]@{ Path = $candidate.FullName; Number = $Matches.num }
            }
        }
    }

    if ($found.Count -eq 0) {
        return [pscustomobject]@{ Status = 'absent'; Lines = @(); Detail = "no backlog item carries the slug '$Slug'"; ItemNumber = '' }
    }
    if ($found.Count -gt 1) {
        return [pscustomobject]@{ Status = 'unusable'; Lines = @(); Detail = "$($found.Count) backlog items carry the slug '$Slug'"; ItemNumber = '' }
    }

    # As in the ref twin: the number is known, so a read failure names the item it could not read.
    try {
        $lines = @(Get-Content -LiteralPath $found[0].Path -ErrorAction Stop)
    } catch {
        return [pscustomobject]@{ Status = 'unusable'; Lines = @(); Detail = "backlog item $($found[0].Number) could not be read"; ItemNumber = $found[0].Number }
    }
    return [pscustomobject]@{ Status = 'found'; Lines = $lines; Detail = ''; ItemNumber = $found[0].Number }
}

# One shape for every verdict the plan guard returns. ItemNumber is the item that was judged and
# RecordedItemNumber is what the manifest said, which are not always the same number after a
# renumber. When they differ the reason names both, so no caller has to guess which one applied.
#
# Code, PlanPath, TickedCount and UntickedCount exist for callers that must act on one verdict and
# not on the others. Reason is a sentence written for a person, and it interpolates the item number
# and the step counts, so a caller that matched it would break the first time somebody improved the
# wording. Reading a count back out of that sentence is the same defect wearing a different hat.
#
# Only the two verdicts that actually read a plan set PlanPath and the counts, so an empty PlanPath
# means "no plan was read". Only the never-implemented verdict sets Code.
function New-WorktreePlanVerdict {
    param(
        [Parameter(Mandatory)][bool] $Allow,
        [Parameter(Mandatory)][AllowEmptyString()][string] $Reason,
        [AllowEmptyString()][string] $ItemNumber = '',
        [AllowEmptyString()][string] $RecordedItemNumber = '',
        [AllowEmptyString()][string] $Code = '',
        [AllowEmptyString()][string] $PlanPath = '',
        [int] $TickedCount = 0,
        [int] $UntickedCount = 0
    )

    $text = $Reason
    if ($ItemNumber -and $RecordedItemNumber -and $ItemNumber -ne $RecordedItemNumber) {
        $text = "$Reason (the worktree manifest records item $RecordedItemNumber)"
    }

    return [pscustomobject]@{
        Allow = $Allow
        Reason = $text
        ItemNumber = $ItemNumber
        RecordedItemNumber = $RecordedItemNumber
        Code = $Code
        PlanPath = $PlanPath
        TickedCount = $TickedCount
        UntickedCount = $UntickedCount
    }
}

# Answers whether a worktree's plan was ever implemented, which is a different question from
# whether its branch merged. Plans live in docs/superpowers, a second private repository that the
# public branch never carries, so a branch can merge holding only its backlog stage stamps while
# the code work never happened.
#
# "Never implemented" is the literal reading: NO step ticked. A plan with some steps ticked and
# some not was implemented, and this says nothing about it. Refusing on any unticked step would
# fire on nearly every worktree, because plans routinely keep unticked steps after the work
# merged, and a guard that always fires gets ignored.
#
# Everything is read from the main checkout. By the time the watcher asks, the worktree folder may
# already be renamed or deleted.
function Test-WorktreePlanWasImplemented {
    param(
        [Parameter(Mandatory)][string] $MainCheckout,
        [string] $ItemNumber,
        [string] $BaseRef,
        [string] $WorktreeName
    )

    $recorded = $ItemNumber

    # A manifest that is there but could not be read is not a worktree with nothing to judge. The
    # guard has no answer, and a guard with no answer refuses.
    if ($ItemNumber -eq $WorktreeBacklogItemUnreadable) {
        return New-WorktreePlanVerdict -Allow $false -Reason 'the worktree manifest could not be read'
    }

    # No recorded number means a worktree created with -Name, or one created before the manifest
    # carried the key. Nothing can be judged, so nothing is refused.
    #
    # This stays ahead of the slug route on purpose. A worktree with nothing recorded is removable
    # by contract, and a slug that happens to match some open item must not turn that allow into a
    # refusal.
    if ([string]::IsNullOrWhiteSpace($ItemNumber)) {
        return New-WorktreePlanVerdict -Allow $true -Reason 'no backlog item is recorded for this worktree'
    }

    # The recorded number goes stale. A renumber is a hand `git mv` plus a heading edit, and
    # nothing rewrites the manifest, so the guard used to judge somebody else's item. The worktree
    # directory name carries the title slug, which a renumber never changes, so the slug resolves
    # the item the worktree really serves.
    #
    # The lookup's three answers lead to three different decisions, and collapsing any two of them
    # is how this guard fails open:
    #
    #   found    - judge that item.
    #   absent   - no item carries this slug, so there is nothing here to judge. Fall back to the
    #              recorded number, which is exactly the old behaviour. A slug that matches nothing
    #              must never skip a check the guard would otherwise make.
    #   unusable - the slug DID name this worktree's item and the lookup could not deliver it.
    #              Refuse. Falling back here judges a DIFFERENT item, and a stale recorded item
    #              saying "Plan: none" would then allow the very removal this guard exists to stop.
    $itemLines = $null
    $judged = $ItemNumber

    # Both lookups below read this one snapshot, so a fetch that moves the base mid-run cannot make
    # them disagree. It is taken here, after the empty-number allow, so a worktree with nothing
    # recorded still costs no git call.
    $inventory = $null
    if ($BaseRef) {
        $inventory = Get-BacklogInventoryFromRef -MainCheckout $MainCheckout -BaseRef $BaseRef
        if ($inventory.Status -ne 'ok') {
            return New-WorktreePlanVerdict -Allow $false -Reason "the base '$BaseRef' $($inventory.Detail)" `
                -ItemNumber '' -RecordedItemNumber $recorded
        }
    }

    $slug = Get-WorktreeSlugFromName -WorktreeName $WorktreeName
    if ($slug) {
        $bySlug = if ($inventory) {
            Get-BacklogItemLinesFromRefBySlug -MainCheckout $MainCheckout -Inventory $inventory -Slug $slug
        } else {
            Get-BacklogItemLinesFromWorkingTreeBySlug -MainCheckout $MainCheckout -Slug $slug
        }
        if ($bySlug.Status -eq 'found') {
            $judged = $bySlug.ItemNumber
            $itemLines = $bySlug.Lines
        } elseif ($bySlug.Status -eq 'unusable') {
            # ItemNumber names the item that was judged, so it carries the lookup's own answer and
            # nothing else. One item found and unreadable names that item. An ambiguous or
            # unresolvable lookup selected none, and it reports none: filling in the recorded number
            # there would blame an item the guard never opened.
            return New-WorktreePlanVerdict -Allow $false -Reason $bySlug.Detail `
                -ItemNumber $bySlug.ItemNumber -RecordedItemNumber $recorded
        }
    }

    # A supplied base is the authority, and it decides alone. Falling back to the working tree when
    # the base cannot answer throws away the reason the base was resolved: a stale local item saying
    # "Plan: none" would then allow the very removal this guard exists to stop. So the base answers
    # or the worktree is kept. The working tree is read only when no base was supplied at all.
    if ($null -eq $itemLines -and $inventory) {
        $fromRef = Get-BacklogItemLinesFromRef -MainCheckout $MainCheckout -Inventory $inventory -ItemNumber $ItemNumber
        if ($fromRef.Status -ne 'found') {
            $wording = if ($fromRef.Status -eq 'absent') { "backlog item $ItemNumber is not in '$BaseRef'" }
                       else { "the base '$BaseRef' $($fromRef.Detail)" }
            return New-WorktreePlanVerdict -Allow $false -Reason $wording -ItemNumber $judged -RecordedItemNumber $recorded
        }
        $itemLines = $fromRef.Lines
    }

    if ($null -eq $itemLines) {
        $itemPath = $null
        foreach ($folder in @('backlog', 'backlog\done', 'backlog\blocked')) {
            $directory = Join-Path $MainCheckout $folder
            if (-not (Test-Path -LiteralPath $directory)) { continue }
            $match = @(Get-ChildItem -LiteralPath $directory -Filter "$ItemNumber-*.md" -File -ErrorAction SilentlyContinue)
            if ($match.Count -eq 1) { $itemPath = $match[0].FullName; break }
        }

        if (-not $itemPath) {
            return New-WorktreePlanVerdict -Allow $false -Reason "backlog item $ItemNumber could not be found" -ItemNumber $judged -RecordedItemNumber $recorded
        }

        try {
            $itemLines = @(Get-Content -LiteralPath $itemPath -ErrorAction Stop)
        } catch {
            return New-WorktreePlanVerdict -Allow $false -Reason "backlog item $ItemNumber could not be read" -ItemNumber $judged -RecordedItemNumber $recorded
        }
    }

    $planBullet = $itemLines | Where-Object { $_ -match '^\s*-\s*Plan:\s*(?<rest>.+)$' } | Select-Object -First 1
    if (-not $planBullet) {
        return New-WorktreePlanVerdict -Allow $true -Reason "backlog item $judged names no plan" -ItemNumber $judged -RecordedItemNumber $recorded
    }

    $null = $planBullet -match '^\s*-\s*Plan:\s*(?<rest>.+)$'
    $rest = $Matches.rest.Trim()
    if ($rest -match '^none\b') {
        return New-WorktreePlanVerdict -Allow $true -Reason "backlog item $judged states it has no plan" -ItemNumber $judged -RecordedItemNumber $recorded
    }

    # Both forms exist in the backlog today: with backticks and without, and with or without a
    # closing full stop. Anything that is not a single file under the plans folder is refused
    # rather than read, because an ordinary file has no unticked step and would read as done.
    $planRelative = Get-BacklogPlanRelativePath -BulletRest $rest
    if (-not $planRelative) {
        return New-WorktreePlanVerdict -Allow $false -Reason "backlog item $judged names a plan outside $WorktreePlansFolder" -ItemNumber $judged -RecordedItemNumber $recorded
    }

    $planPath = Resolve-BacklogPlanPath -MainCheckout $MainCheckout -PlanRelative $planRelative
    if (-not $planPath) {
        return New-WorktreePlanVerdict -Allow $false -Reason "the plan for item $judged could not be read" -ItemNumber $judged -RecordedItemNumber $recorded
    }

    try {
        $planText = Get-Content -Raw -LiteralPath $planPath -ErrorAction Stop
    } catch {
        return New-WorktreePlanVerdict -Allow $false -Reason "the plan for item $judged could not be read" -ItemNumber $judged -RecordedItemNumber $recorded
    }

    $ticked = [regex]::Matches($planText, '(?m)^\s*-\s*\[x\]', 'IgnoreCase').Count
    $unticked = [regex]::Matches($planText, '(?m)^\s*-\s*\[ \]').Count

    if ($unticked -gt 0 -and $ticked -eq 0) {
        return New-WorktreePlanVerdict -Allow $false -Reason "the plan for item $judged was never implemented ($unticked steps, none ticked)" `
            -ItemNumber $judged -RecordedItemNumber $recorded `
            -Code 'plan-never-implemented' -PlanPath $planPath -TickedCount $ticked -UntickedCount $unticked
    }

    return New-WorktreePlanVerdict -Allow $true -Reason "the plan for item $judged has $ticked ticked steps" `
        -ItemNumber $judged -RecordedItemNumber $recorded `
        -PlanPath $planPath -TickedCount $ticked -UntickedCount $unticked
}
