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
# Removal is destructive, so this returns $true only when ALL THREE signals agree, and $false for
# anything it cannot establish -- an unclear answer keeps the worktree.
#
#   1. WORK. The branch ref log holds a subject for an operation that creates a commit. Git writes
#      'commit:', 'commit (amend):', 'commit (merge):', 'commit (initial):', 'cherry-pick:',
#      'revert:' and 'merge <ref>: Merge made by ...'. The list is closed on purpose -- see the
#      forgery note below.
#   2. MERGE. A SHA the ref log records under one of those subjects, or under 'rebase (finish)', is
#      a NON-FIRST parent of a merge commit reachable from $MainRef -- what a GitHub "Merge pull
#      request" (`--no-ff`) leaves behind. Git history, not text.
#   3. NOTHING DISCARDED. Removing the branch would strand no commit that a `git reset` dropped.
#      Get-StrandedCommits and Test-StrandedWorkWasSuperseded decide it, by reachability.
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
#   - Text cannot be authenticated. A caller who sets GIT_REFLOG_ACTION=commit and fast-forwards an
#     unstarted branch onto an already-merged tip satisfies signals 1 and 2, and an empty branch
#     strands nothing, so signal 3 has nothing to refuse. The worktree goes. Nothing in git records
#     which branch created a commit, so no stronger proof is available here. Backlog 096 tracks it.
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

# The branch name `gh pr list --base` needs, read from config rather than by splitting a ref.
# 'origin/main' cannot be halved on the slash: a remote may contain one and a branch always may.
# This is the same source Resolve-MergedBaseRef reads.
function Resolve-BaseBranchName {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [string] $LocalRef = 'main'
    )

    $ErrorActionPreference = 'Continue'

    $remoteBranchRef = "$(& git -C $RepoRoot config --get "branch.$LocalRef.merge" 2>$null)".Trim()
    if ($remoteBranchRef.StartsWith('refs/heads/')) {
        return $remoteBranchRef.Substring('refs/heads/'.Length)
    }

    return $LocalRef
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

    try {
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $gh.Source
        $startInfo.Arguments = ConvertTo-ProcessArgumentLine $arguments
        $startInfo.WorkingDirectory = $RepoRoot
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true

        $process = [System.Diagnostics.Process]::Start($startInfo)

        # Read to the end BEFORE waiting. A child that fills the pipe buffer blocks on the write
        # while the parent blocks on the wait, and neither ever moves.
        $stdout = $process.StandardOutput.ReadToEnd()
        $null = $process.StandardError.ReadToEnd()

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $null = Stop-ProcessTree -ProcessId $process.Id
            return (& $unavailable 'timeout')
        }
        if ($process.ExitCode -ne 0) { return (& $unavailable 'gh-failed') }

        $records = @(ConvertFrom-GhMergedPrJson -Json $stdout)
        $trimmed = "$stdout".Trim()
        if ($records.Count -eq 0 -and $trimmed -and $trimmed -ne '[]') {
            return (& $unavailable 'unparsable')
        }

        return [pscustomobject]@{ Available = $true; Reason = 'ok'; Records = $records }
    } catch {
        return (& $unavailable 'gh-failed')
    }
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

    # Signal 4. The merge proves the work that existed when it happened, and nothing after it.
    $after = Get-WorkAfterMergeProof -RepoRoot $RepoRoot -Branch $Branch -ProofShas $proofs
    if ($null -eq $after -or $after.Count -gt 0) { return $false }

    # Signal 3. Signals 1 and 2 can be satisfied by different work, so the last question is the one
    # that makes removal safe: would removing this branch discard a commit nothing else holds?
    $stranded = Get-StrandedCommits -RepoRoot $RepoRoot -Branch $Branch -Shas @($facts.AllShas.Keys)
    if ($null -eq $stranded) { return $false }

    return (Test-StrandedWorkWasSuperseded -RepoRoot $RepoRoot -Entries $facts.Entries -Stranded $stranded)
}
