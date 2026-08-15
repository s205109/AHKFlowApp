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
