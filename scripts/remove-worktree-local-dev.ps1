#Requires -Version 5.1
<#
.SYNOPSIS
    Claude Code WorktreeRemove hook: deletes the entire worktree + branch when a
    session ends, or leaves the worktree fully intact with manual cleanup guidance if
    it cannot be removed.

.DESCRIPTION
    On Windows, `claude --worktree <name>` keeps the worktree folder as its own
    current directory, so a live `claude.exe` holds a non-deletable lock on the
    folder. The WorktreeRemove hook is a *child* of that process and therefore
    cannot delete the folder synchronously (a forced `git worktree remove` would
    prune git's registry but fail to delete the locked folder, leaving an
    orphaned empty directory).

    This script runs in two modes:

      Hook    (default) Fires from Claude Code. Captures branch name and main
              checkout *while the worktree still exists*, then spawns a detached
              Watcher (outside Claude's job object, via WMI) and returns
              immediately. It never touches the worktree itself.

      Watcher (detached) Outlives claude.exe. Waits for the lock to release by
              repeatedly attempting an atomic directory rename (which only
              succeeds once nothing holds the folder). On success it deletes the
              renamed tree, prunes git, and deletes the branch with git branch -d.
              On timeout it leaves the worktree fully intact and logs manual
              cleanup commands.

    Logs:
      .claude\worktrees\worktree-removal.log under the main checkout when resolvable.
      %TEMP%\worktree-removal.log otherwise.
#>

[CmdletBinding()]
param(
    [ValidateSet('Hook', 'Watcher')]
    [string] $Mode = 'Hook',

    [string] $WorktreePath,
    [string] $ParamFile,

    # Watcher mode only. The temp root the hook staged this attempt in. It arrives on the command
    # line, not only in the param file, because the watcher has to know it before it parses
    # anything: a param file it cannot read is exactly when it must still delete its run directory.
    [string] $HookTempRoot,

    [string] $LogPath,

    # The base the merged gate decides against. cleanup-merged-worktrees.ps1 passes the base it
    # already resolved. Empty means resolve it here, which is what the hook path does: a merge
    # performed on GitHub never advances local main, so deciding against it preserves finished
    # worktrees until a human pulls.
    [string] $MainRef,

    [int] $TimeoutSeconds = 300
)

# A WorktreeRemove hook is non-blocking and failures are only logged by Claude
# Code in debug mode. Never let an unexpected error abort silently: keep going
# and record everything.
$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------
$script:RunId = $null
$script:WorktreeLogName = 'unknown'
$script:DiagnosticsPath = $null

# The temp folder the hook staged this attempt in. A process started through Win32_Process.Create
# does not inherit the caller's TEMP, so the watcher can read a different %TEMP% than the hook
# wrote to. The hook records its own root in the param file and the watcher sets this from it, so
# both modes agree on where the run directory and the fallback log live.
$script:TempRoot = $null

$worktreeLogHelperPath = Join-Path $PSScriptRoot 'worktree-log.common.ps1'
if (Test-Path -LiteralPath $worktreeLogHelperPath) {
    . $worktreeLogHelperPath
}

$powerShellHelperPath = Join-Path $PSScriptRoot 'worktree-powershell.common.ps1'
if (Test-Path -LiteralPath $powerShellHelperPath) {
    . $powerShellHelperPath
}

$gitHelperPath = Join-Path $PSScriptRoot 'worktree-git.common.ps1'
if (Test-Path -LiteralPath $gitHelperPath) {
    . $gitHelperPath
}

# The holder probe. The watcher copies this file into its own temp folder beside the watcher
# script, so $PSScriptRoot finds it in both modes.
$holderHelperPath = Join-Path $PSScriptRoot 'worktree-holder.common.ps1'
if (Test-Path -LiteralPath $holderHelperPath) { . $holderHelperPath }

# The watcher runs from a temp snapshot where this helper may not exist. It must still be able
# to write its outcome line, so the fallback returns no holders rather than failing.
if (-not (Get-Command Get-WorktreeFolderHolder -ErrorAction SilentlyContinue)) {
    function Get-WorktreeFolderHolder { param([string] $Path) return @() }
}
if (-not (Get-Command Format-HolderSummary -ErrorAction SilentlyContinue)) {
    function Format-HolderSummary { param([object[]] $Holder) return '' }
}

# The watcher runs from a copy of this script in %TEMP%, where scripts\ does not exist. It never
# reaches the merged gate -- that gate is on the hook path only -- but the fallback keeps the copy
# loadable, and keeps the old local-branch behavior if the helper ever goes missing.
if (-not (Get-Command Resolve-MergedBaseRef -ErrorAction SilentlyContinue)) {
    function Resolve-MergedBaseRef {
        param(
            [Parameter(Mandatory)][string] $RepoRoot,
            [string] $LocalRef = 'main',
            [int] $TimeoutSeconds = 15
        )

        return [pscustomobject]@{ Ref = $LocalRef; Remote = $null; Fetched = $false; Reason = 'no-upstream' }
    }
}

# The shared merged decision, stubbed for the watcher copy in %TEMP% where scripts\ does not exist.
# The watcher never reaches the merge gate -- the hook path decided before spawning it -- so this
# only keeps the copy loadable, and answers "cannot tell" if that ever changes.
if (-not (Get-Command Test-BranchOwnWorkWasMerged -ErrorAction SilentlyContinue)) {
    function Test-BranchOwnWorkWasMerged {
        param(
            [string] $RepoRoot,
            [string] $Branch,
            [string] $MainRef = 'main',
            [object[]] $MergedPullRequests,
            [scriptblock] $MergedPullRequestLookup
        )

        return $false
    }
}

# A guard that cannot run is not a guard that passes. The watcher runs from a copy in %TEMP% where
# the shared helper does not exist, so this keeps the worktree and says why. The one asymmetry,
# and it is deliberate: with NO recorded item the fallback still allows. A legacy worktree must not
# become unremovable just because the watcher lost its helper.
if (-not (Get-Variable -Name WorktreeBacklogItemUnreadable -Scope Script -ErrorAction SilentlyContinue)) {
    $WorktreeBacklogItemUnreadable = '<manifest-unreadable>'
}

if (-not (Get-Command Test-WorktreePlanWasImplemented -ErrorAction SilentlyContinue)) {
    function Test-WorktreePlanWasImplemented {
        # -WorktreeName is accepted and ignored. The fallback resolves no item at all, so it has
        # no slug route to run; the parameter is here only so a call site never fails to bind.
        param([string] $MainCheckout, [string] $ItemNumber, [string] $BaseRef, [string] $WorktreeName)
        # Code, PlanPath and the two counts are empty or zero in every fallback answer, because the
        # fallback reads no plan. They are still present on the object: a caller under
        # Set-StrictMode that reads .Code would throw on a shape the shared copy does not have, and
        # the two copies must not drift.
        #
        # An unreadable manifest is checked before the empty case, so a read failure never borrows
        # the legacy worktree's free pass.
        if ($ItemNumber -eq $WorktreeBacklogItemUnreadable) {
            return [pscustomobject]@{ Allow = $false; Reason = 'the worktree manifest could not be read'; ItemNumber = ''; RecordedItemNumber = ''; Code = ''; PlanPath = ''; TickedCount = 0; UntickedCount = 0 }
        }
        if ([string]::IsNullOrWhiteSpace($ItemNumber)) {
            return [pscustomobject]@{ Allow = $true; Reason = 'no backlog item is recorded for this worktree'; ItemNumber = ''; RecordedItemNumber = ''; Code = ''; PlanPath = ''; TickedCount = 0; UntickedCount = 0 }
        }
        return [pscustomobject]@{ Allow = $false; Reason = 'the plan check could not run'; ItemNumber = $ItemNumber; RecordedItemNumber = $ItemNumber; Code = ''; PlanPath = ''; TickedCount = 0; UntickedCount = 0 }
    }
}

if (-not (Get-Command Get-ManifestBacklogItem -ErrorAction SilentlyContinue)) {
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
}

if (-not (Get-Command Resolve-BaseBranchName -ErrorAction SilentlyContinue)) {
    function Resolve-BaseBranchName {
        param([string] $RepoRoot, [string] $LocalRef = 'main')

        return $LocalRef
    }
}

if (-not (Get-Command Format-MergedBaseRefMessage -ErrorAction SilentlyContinue)) {
    function Format-MergedBaseRefMessage {
        param(
            [Parameter(Mandatory)][string] $Prefix,
            [Parameter(Mandatory)][object] $Base
        )

        return "$($Prefix): base '$($Base.Ref)'."
    }
}

if (-not (Get-Command Resolve-PowerShellExecutable -ErrorAction SilentlyContinue)) {
    function Resolve-PowerShellExecutable {
        $currentProcessPath = [System.Diagnostics.Process]::GetCurrentProcess().Path
        if ($currentProcessPath -and (Test-Path -LiteralPath $currentProcessPath)) {
            return $currentProcessPath
        }

        foreach ($name in @('pwsh.exe', 'powershell.exe')) {
            $psHomeCandidate = Join-Path $PSHOME $name
            if (Test-Path -LiteralPath $psHomeCandidate) {
                return $psHomeCandidate
            }

            $command = Get-Command $name -ErrorAction SilentlyContinue
            if ($command -and $command.Source -and (Test-Path -LiteralPath $command.Source)) {
                return $command.Source
            }
        }

        throw 'Could not resolve a PowerShell executable. Expected current host, pwsh.exe, or powershell.exe to be available.'
    }
}

if (-not (Get-Command New-HiddenProcessStartup -ErrorAction SilentlyContinue)) {
    function New-HiddenProcessStartup { return $null }
}

if (-not (Get-Command Write-WorktreeLog -ErrorAction SilentlyContinue)) {
    function Write-WorktreeLog {
        param(
            [Parameter(Mandatory)][string] $LogPath,
            [Parameter(Mandatory)][string] $Worktree,
            [Parameter(Mandatory)][string] $Message
        )

        $resolvedLogPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogPath)

        $directory = Split-Path -Parent $resolvedLogPath
        if ($directory -and -not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }

        $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        $line = '{0}  {1}  {2}' -f $stamp, $Worktree, $Message
        # UTF-8 without BOM, matching worktree-log.common.ps1 so encoding never
        # depends on which definition (shared or fallback) loaded.
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::AppendAllText($resolvedLogPath, $line + [Environment]::NewLine, $utf8NoBom)
    }
}

if (-not (Get-Command Format-WorktreeLogReason -ErrorAction SilentlyContinue)) {
    function Format-WorktreeLogReason {
        param([string] $Text)
        if ([string]::IsNullOrWhiteSpace($Text)) { return 'no reason given' }
        $flat = (($Text -replace '[\r\n\t]+', ' ') -replace '\s{2,}', ' ').Trim()
        if ($flat.Length -gt 300) { $flat = $flat.Substring(0, 299) + [char] 0x2026 }
        return $flat
    }
}

if (-not (Get-Command Get-WorktreeDiagnosticsPath -ErrorAction SilentlyContinue)) {
    function Get-WorktreeDiagnosticsPath {
        param([Parameter(Mandatory)][string] $OutcomeLogPath)
        $directory = Split-Path -Parent $OutcomeLogPath
        $leaf = [System.IO.Path]::GetFileNameWithoutExtension($OutcomeLogPath)
        $extension = [System.IO.Path]::GetExtension($OutcomeLogPath)
        return Join-Path $directory ($leaf + '-diagnostics' + $extension)
    }
}

if (-not (Get-Command Write-WorktreeDiagnostic -ErrorAction SilentlyContinue)) {
    function Write-WorktreeDiagnostic {
        param(
            [Parameter(Mandatory)][string] $LogPath,
            [Parameter(Mandatory)][string] $Worktree,
            [Parameter(Mandatory)][string] $Message
        )
        try {
            $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            $single = $Message -replace '[\r\n]+', ' '
            $line = '{0}  {1}  {2}' -f $stamp, $Worktree, $single
            [System.IO.File]::AppendAllText($LogPath, $line + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
        } catch { }
    }
}

# The temp root, not the run directory. The shared outcome log lives here, and so does every run
# directory. The watcher's working directory is set here too, because a process holds its own
# working directory and the watcher has to delete its run directory at the end.
function Get-RemovalTempDir {
    if ($script:TempRoot) {
        return $script:TempRoot
    }

    return [System.IO.Path]::GetTempPath()
}

# The private folder for one removal attempt. It holds the watcher script, the param file, and both
# helper copies, so two watchers started by the same sweep never write over each other's files.
function Get-RemovalRunTempDir {
    param([string] $RunId)

    if ([string]::IsNullOrWhiteSpace($RunId)) {
        # Without an id the name is the bare prefix, and Test-RemovalRunTempDirPath would accept a
        # folder no attempt owns. Refusing here keeps that folder from ever being created.
        throw 'Get-RemovalRunTempDir needs a run id.'
    }

    return (Join-Path (Get-RemovalTempDir) "ahkflowapp-wt-remove-$RunId")
}

function Set-ProductionLogPath {
    param([string] $MainCheckout)

    if ($script:LogPath) {
        return
    }

    if ($MainCheckout) {
        $script:LogPath = Join-Path $MainCheckout '.claude\worktrees\worktree-removal.log'
        $script:DiagnosticsPath = $null
        return
    }

    $script:LogPath = Join-Path (Get-RemovalTempDir) 'worktree-removal.log'
    $script:DiagnosticsPath = $null
}

# The one outcome line for this removal attempt. Called exactly once per attempt, by whichever
# process reached the decision. It is mirrored into diagnostics so that file tells the whole
# story of an attempt without a reader holding two files side by side.
function Write-Outcome {
    param([string] $Message)

    if (-not $script:LogPath) {
        Set-ProductionLogPath $null
    }

    Write-WorktreeLog -LogPath $script:LogPath -Worktree $script:WorktreeLogName -Message $Message
    Write-DiagnosticLog "OUTCOME $Message"
}

# Everything that is not the outcome. Goes to the diagnostics file and to stderr. Stderr alone
# is not enough: the watcher is detached, so its stderr reaches nobody.
function Write-DiagnosticLog {
    param([string] $Message)

    $prefix = if ($script:RunId) { "[$script:RunId] $Mode" } else { $Mode }
    $line = "{0} {1} {2}" -f [DateTimeOffset]::Now.ToString('O'), $prefix, $Message
    try { [Console]::Error.WriteLine($line) } catch { }

    if (-not $script:DiagnosticsPath) {
        if (-not $script:LogPath) { Set-ProductionLogPath $null }
        $script:DiagnosticsPath = Get-WorktreeDiagnosticsPath -OutcomeLogPath $script:LogPath
    }

    Write-WorktreeDiagnostic -LogPath $script:DiagnosticsPath -Worktree $script:WorktreeLogName -Message "[$script:RunId] $Message"
}

function Set-WorktreeLogName {
    param([string] $WorktreePath)

    if (-not $WorktreePath) {
        $script:WorktreeLogName = 'unknown'
        return
    }

    $leaf = Split-Path -Leaf (ConvertTo-NormalizedPath $WorktreePath)
    $script:WorktreeLogName = if ($leaf) { $leaf } else { 'unknown' }
}

# True when two filesystem paths point at the same location (case-insensitive,
# trailing-separator-insensitive). Used to refuse deleting the main checkout.
function Test-SamePath {
    param([string] $A, [string] $B)
    $na = ConvertTo-NormalizedPath $A
    $nb = ConvertTo-NormalizedPath $B
    if (-not $na -or -not $nb) { return $false }
    return [string]::Equals($na, $nb, [System.StringComparison]::OrdinalIgnoreCase)
}

function ConvertTo-NormalizedPath {
    param([string] $Path)

    if (-not $Path) {
        return $null
    }

    try {
        return ([System.IO.Path]::GetFullPath($Path)).TrimEnd('\', '/')
    } catch {
        return $Path.TrimEnd('\', '/')
    }
}

function Resolve-MainCheckoutFromScriptRoot {
    $scriptRoot = $PSScriptRoot
    if (-not $scriptRoot -and $PSCommandPath) {
        $scriptRoot = Split-Path -Parent $PSCommandPath
    }

    if (-not $scriptRoot) {
        return $null
    }

    try {
        $scriptCheckout = (Resolve-Path -LiteralPath (Join-Path $scriptRoot '..') -ErrorAction Stop).Path
    } catch {
        return $null
    }

    # A linked worktree's script root belongs to that worktree. Git's common directory still
    # points at the main checkout, where the one removal log lives.
    $commonResult = Invoke-GitCapture @('-C', $scriptCheckout, 'rev-parse', '--path-format=absolute', '--git-common-dir')
    if ($commonResult.ExitCode -eq 0 -and $commonResult.Lines.Count -gt 0) {
        $gitCommonDir = ($commonResult.Lines[0]).Trim()
        try {
            if ((Split-Path -Leaf $gitCommonDir) -ieq '.git') {
                return (Resolve-Path -LiteralPath (Split-Path -Parent $gitCommonDir) -ErrorAction Stop).Path
            }
        } catch { }
    }

    return $scriptCheckout
}

# Reads the hook payload from stdin as UTF-8, and never through [Console]::In.
# [Console]::InputEncoding is the console code page, IBM437 on a default Windows install. Reading
# through it decodes every byte above 0x7F wrongly. Two things break as a result. A UTF-8 byte
# order mark arrives as three garbage characters instead of one U+FEFF, and ConvertFrom-Json then
# rejects the whole document -- which is how a hook call became a silent no-op. Any non-ASCII
# character in a worktree path is mangled the same way.
#
# A StreamReader over the raw stdin stream fixes both. detectEncodingFromByteOrderMarks consumes
# a leading mark instead of passing it on, and the UTF-8 fallback covers a payload written without
# one. Windows PowerShell 5.1 writes that mark by default from Set-Content -Encoding utf8, so any
# producer running under 5.1 sends one.
function Read-RawStdin {
    if (-not [Console]::IsInputRedirected) { return $null }

    try {
        $stream = [Console]::OpenStandardInput()
        $reader = New-Object System.IO.StreamReader($stream, (New-Object System.Text.UTF8Encoding($false)), $true)
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    } catch {
        return $null
    }
}

# Copied verbatim from scripts/new-worktree.ps1 (Test-EnvironmentFlagEnabled) so both
# scripts recognize the same truthy values for their respective opt-in env vars.
function Test-EnvironmentFlagEnabled {
    param([string] $Name)

    $value = [Environment]::GetEnvironmentVariable($Name, 'Process')
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $false
    }

    return $value.Trim() -match '^(1|true|yes|y)$'
}

# Runs git and returns merged output + exit code.
function Invoke-GitCapture {
    param([string[]] $GitArgs)

    # Git emits UTF-8 paths. A detached Windows process can retain an OEM console output encoding,
    # which makes PowerShell replace non-ASCII path bytes before this function can compare them.
    $previousOutputEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    try {
        $merged = & git @GitArgs 2>&1
        $code = $LASTEXITCODE
    } finally {
        [Console]::OutputEncoding = $previousOutputEncoding
    }

    $lines = @()
    foreach ($item in $merged) { $lines += [string] $item }
    return [pscustomobject]@{ ExitCode = $code; Lines = $lines }
}

function Write-GitResult {
    param([string] $Label, [pscustomobject] $Result, [switch] $SuppressHintLines)
    Write-DiagnosticLog "${Label}: exit=$($Result.ExitCode)"
    foreach ($line in $Result.Lines) {
        if ($SuppressHintLines -and $line -match '^hint:') {
            continue
        }
        if ($line) {
            Write-DiagnosticLog "    | $line"
        }
    }
}

function Format-GitCommand {
    param([string] $RepoRoot, [string[]] $Arguments)

    $tokens = @('git')
    if ($RepoRoot) {
        $tokens += '-C'
        $tokens += Format-PowerShellArgument -Argument $RepoRoot -AlwaysQuote
    }

    foreach ($argument in $Arguments) {
        $tokens += Format-PowerShellArgument $argument
    }

    return ($tokens -join ' ')
}

function Format-PowerShellArgument {
    param([string] $Argument, [switch] $AlwaysQuote)

    if ($null -eq $Argument) {
        return "''"
    }

    if (-not $AlwaysQuote -and $Argument -match '^[A-Za-z0-9._:/\\-]+$') {
        return $Argument
    }

    return "'$($Argument.Replace("'", "''"))'"
}

function Write-TimeoutGuidance {
    param(
        [string] $WorktreeFull,
        [string] $MainCheckout,
        [string] $BranchName,
        [string] $LastError
    )

    Write-DiagnosticLog "Could not remove worktree because the folder is still locked: $WorktreeFull"
    if ($LastError) {
        Write-DiagnosticLog "Last rename error: $LastError"
    }

    # Run once, here. The retry loop attempts a rename every 750 ms for up to 300 seconds, and
    # enumerating processes, opening a Restart Manager session and reading PEBs on every attempt
    # would cost far more than it explains.
    $holders = @(Get-WorktreeFolderHolder -Path $WorktreeFull)
    foreach ($holder in $holders) {
        Write-DiagnosticLog "Holder: $($holder.Name) (PID $($holder.ProcessId)) found by $($holder.Layer) - $($holder.Path)"
    }

    Write-DiagnosticLog 'The worktree was preserved. Close terminals, editors, shells, or Claude sessions opened inside that folder, then run:'
    if ($MainCheckout) {
        Write-DiagnosticLog ('  ' + (Format-GitCommand $MainCheckout @('worktree', 'remove', $WorktreeFull)))
        Write-DiagnosticLog ('  ' + (Format-GitCommand $MainCheckout @('worktree', 'prune')))
        if ($BranchName) {
            Write-DiagnosticLog ('  ' + (Format-GitCommand $MainCheckout @('branch', '-d', '--', $BranchName)))
        }
    } else {
        Write-DiagnosticLog '  git worktree remove <worktree-path>'
        Write-DiagnosticLog '  git worktree prune'
        if ($BranchName) {
            Write-DiagnosticLog ('  ' + (Format-GitCommand $null @('branch', '-d', '--', $BranchName)))
        }
    }
    Write-DiagnosticLog "Details were logged to: $script:DiagnosticsPath"

    $summary = Format-HolderSummary -Holder $holders
    if ($summary) {
        Write-Outcome "Kept: the folder is still in use by $summary."
    } else {
        Write-Outcome 'Kept: the folder is still in use, and no holding process could be identified.'
    }
}

# Removability probe: merged = the branch's own work reached the base, decided by the ONE rule the
# sweep uses (Test-BranchOwnWorkWasMerged in worktree-git.common.ps1); clean = no working-tree
# changes, checked separately by Test-WorktreeClean.
#
# Ancestry decided this before backlog 098, and it answered wrongly in both directions. It refused a
# rebase merge, because GitHub replays the commits under new SHAs and writes no merge commit, so the
# branch head is an ancestor of nothing. And it accepted a brand-new branch, because a branch that
# has never committed points at a commit the base already holds -- so the hook removed worktrees
# nobody had started. The sweep already refused both; now there is one rule instead of two.
#
# $BaseRef is the fetched remote-tracking branch, not local main. Backlog 094.
function Test-WorktreeMergedIntoMain {
    param(
        [string] $WorktreeFull,
        [string] $BranchName,
        [string] $BaseRef = 'main',
        [string] $MainCheckout
    )

    if (-not $BranchName) { return $false }

    $repoRoot = if ($MainCheckout) { $MainCheckout } else { $WorktreeFull }

    # The watcher runs from a copy in %TEMP% where the shared helper does not exist. It never reaches
    # this gate, but if that ever changes, "cannot tell" must keep the worktree.
    if (-not (Get-Command Test-BranchOwnWorkWasMerged -ErrorAction SilentlyContinue)) {
        Write-DiagnosticLog 'merge gate: the shared decision is unavailable, so the worktree is preserved.'
        return $false
    }

    # Never `Split-Path -Leaf $BaseRef`: a remote may contain a slash and a branch always may, so
    # 'origin/main' cannot be halved safely. Resolve-BaseBranchName reads it from config instead.
    # $BaseRef is passed explicitly: this gate may decide against a base other than main, and the
    # GitHub question has to be about that same base.
    $baseBranchName = Resolve-BaseBranchName -RepoRoot $repoRoot -LocalRef $BaseRef

    # A branch that was never pushed has no pull request, so asking GitHub about it spends a network
    # call to learn nothing. One ref lookup rules that out. The exit code is what gets read: git
    # writes "fatal: no upstream configured" to stderr when there is none.
    $null = & git -C $WorktreeFull rev-parse --symbolic-full-name "$BranchName@{upstream}" 2>$null
    $hasUpstream = ($LASTEXITCODE -eq 0)

    $lookup = $null
    if ($hasUpstream) {
        $lookup = { Get-MergedPullRequestRecords -RepoRoot $repoRoot -BaseBranch $baseBranchName -HeadBranch $BranchName }
    } else {
        Write-DiagnosticLog "merge gate: branch '$BranchName' has no upstream, so no pull request can exist; deciding on local history only."
    }

    $merged = Test-BranchOwnWorkWasMerged -RepoRoot $repoRoot -Branch $BranchName -MainRef $BaseRef -MergedPullRequestLookup $lookup
    Write-DiagnosticLog "merge gate: branch '$BranchName' merged into '$BaseRef' = $merged"
    return $merged
}

function Test-WorktreeClean {
    param([string] $WorktreeFull)

    $result = Invoke-GitCapture @('-C', $WorktreeFull, 'status', '--porcelain')
    Write-GitResult 'status --porcelain' $result
    if ($result.ExitCode -ne 0) {
        return $false
    }
    foreach ($line in $result.Lines) {
        if ($line -and $line.Trim()) {
            return $false
        }
    }
    return $true
}

# The gate's refusal: guidance in diagnostics, one Kept line in the outcome log.
#
# This is the only writer of that line, for every reason the gate refuses. Two lines on one
# attempt is the defect the two-file split exists to prevent, and a second writer with its own
# fixed wording is how the plan gate came to report a reason nobody had checked.
function Write-UnmergedPreserveGuidance {
    param(
        [string] $WorktreeFull,
        [string] $MainCheckout,
        [string] $BranchName,
        [string] $Reason
    )

    Write-DiagnosticLog "Worktree was preserved (not removed): $Reason"
    Write-DiagnosticLog 'To remove it manually once ready, run:'
    if ($MainCheckout) {
        Write-DiagnosticLog ('  ' + (Format-GitCommand $MainCheckout @('worktree', 'remove', $WorktreeFull)))
        Write-DiagnosticLog ('  ' + (Format-GitCommand $MainCheckout @('worktree', 'prune')))
        if ($BranchName) {
            Write-DiagnosticLog ('  ' + (Format-GitCommand $MainCheckout @('branch', '-d', '--', $BranchName)))
        }
    } else {
        Write-DiagnosticLog '  git worktree remove <worktree-path>'
        Write-DiagnosticLog '  git worktree prune'
        if ($BranchName) {
            Write-DiagnosticLog ('  ' + (Format-GitCommand $null @('branch', '-d', '--', $BranchName)))
        }
    }
    Write-DiagnosticLog 'To bypass this gate and remove now regardless of merge/clean status, set AHKFLOW_WORKTREE_FORCE_REMOVE=1 before exiting Claude Code.'
    Write-DiagnosticLog "Details were logged to: $script:DiagnosticsPath"

    Write-Outcome ('Kept: ' + (Format-WorktreeLogReason -Text $Reason) + '.')
}

function Write-BranchDeleteGuidance {
    param(
        [string] $MainCheckout,
        [string] $BranchName
    )

    Write-DiagnosticLog "Branch was not deleted: $BranchName"
    Write-DiagnosticLog 'Git refused safe branch deletion, usually because the branch contains unmerged commits.'
    Write-DiagnosticLog 'Inspect or merge the branch, then retry:'
    Write-DiagnosticLog ('  ' + (Format-GitCommand $MainCheckout @('branch', '-d', '--', $BranchName)))
    Write-DiagnosticLog 'Only if you intentionally want to discard that branch, run:'
    Write-DiagnosticLog ('  ' + (Format-GitCommand $MainCheckout @('branch', '-D', '--', $BranchName)))
}

function Get-RegisteredWorktreePaths {
    param([string] $MainCheckout)

    $result = Invoke-GitCapture @('-C', $MainCheckout, 'worktree', 'list', '--porcelain')
    $paths = @()
    if ($result.ExitCode -eq 0) {
        foreach ($line in $result.Lines) {
            if ($line -like 'worktree *') {
                $paths += ConvertTo-NormalizedPath ($line.Substring('worktree '.Length))
            }
        }
    }

    return [pscustomobject]@{
        Result = $result
        Paths  = $paths
    }
}

function Test-RegisteredLinkedWorktree {
    param(
        [string] $WorktreeFull,
        [string] $MainCheckout
    )

    $targetPath = ConvertTo-NormalizedPath $WorktreeFull
    $mainPath = ConvertTo-NormalizedPath $MainCheckout

    if (-not $targetPath -or -not $mainPath) {
        return [pscustomobject]@{
            IsRegistered = $false
            Reason       = 'target or main checkout path is unknown'
            GitResult    = $null
        }
    }

    if ([string]::Equals($targetPath, $mainPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{
            IsRegistered = $false
            Reason       = 'target is the main checkout, not a linked worktree'
            GitResult    = $null
        }
    }

    $registered = Get-RegisteredWorktreePaths $MainCheckout
    if ($registered.Result.ExitCode -ne 0) {
        return [pscustomobject]@{
            IsRegistered = $false
            Reason       = 'git worktree list failed'
            GitResult    = $registered.Result
        }
    }

    foreach ($registeredPath in $registered.Paths) {
        if ([string]::Equals($targetPath, $registeredPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{
                IsRegistered = $true
                Reason       = ''
                GitResult    = $registered.Result
            }
        }
    }

    return [pscustomobject]@{
        IsRegistered = $false
        Reason       = 'target path is not listed by git worktree list --porcelain'
        GitResult    = $registered.Result
    }
}

function Write-UnregisteredWorktreeRefusal {
    param(
        [string] $WorktreeFull,
        [string] $MainCheckout,
        [pscustomobject] $Validation
    )

    $reason = if ($Validation -and $Validation.Reason) { $Validation.Reason } else { 'validation failed' }
    Write-DiagnosticLog "REFUSING: WorktreePath is not a registered linked worktree under MainCheckout. WorktreePath=$WorktreeFull MainCheckout=$MainCheckout Reason=$reason"
    if ($Validation -and $Validation.GitResult) {
        Write-GitResult 'worktree list --porcelain' $Validation.GitResult
    }
}

# ===========================================================================
# HOOK MODE
# ===========================================================================
function Invoke-HookMode {
    $script:RunId = ('hook-{0:yyyyMMddHHmmss}-{1}' -f [DateTime]::Now, ([guid]::NewGuid().ToString('N').Substring(0, 6)))

    # --- resolve worktree path (param wins, else stdin worktree_path) -------
    $stdinError = $null
    $raw = Read-RawStdin
    if ($raw -and -not [string]::IsNullOrWhiteSpace($raw)) {
        try {
            $parsed = $raw | ConvertFrom-Json
            if (-not $WorktreePath -and $parsed.PSObject.Properties.Name -contains 'worktree_path') {
                $WorktreePath = [string] $parsed.worktree_path
            }
        } catch {
            $stdinError = "stdin was not valid JSON: $($_.Exception.Message)"
        }
    }

    if (-not $WorktreePath) {
        Set-ProductionLogPath (Resolve-MainCheckoutFromScriptRoot)
        Write-DiagnosticLog '====================================================================='
        Write-DiagnosticLog "WorktreeRemove hook fired. PID=$PID ScriptPath=$PSCommandPath"
        if ($stdinError) { Write-DiagnosticLog $stdinError }
        Write-DiagnosticLog 'No worktree_path provided; nothing to do.'
        # Every other refusal writes one outcome line, so a reader can always tell what an
        # attempt decided. Without this the log file is never created at all, and a worktree
        # left behind has nothing on disk explaining why.
        Write-Outcome 'Kept: the hook received no worktree path.'
        return
    }

    $worktreeFull = ConvertTo-NormalizedPath $WorktreePath
    Set-WorktreeLogName $worktreeFull

    if (-not (Test-Path -LiteralPath $worktreeFull)) {
        Set-ProductionLogPath (Resolve-MainCheckoutFromScriptRoot)
        Write-DiagnosticLog '====================================================================='
        Write-DiagnosticLog "WorktreeRemove hook fired. PID=$PID ScriptPath=$PSCommandPath"
        if ($stdinError) { Write-DiagnosticLog $stdinError }
        Write-DiagnosticLog "WorktreePath = $worktreeFull"
        Write-DiagnosticLog 'Worktree folder does not exist; nothing to remove.'
        Write-Outcome 'Kept: the worktree folder does not exist.'
        return
    }

    $dbName = $null
    $manifest = Join-Path $worktreeFull 'scripts\.env.worktree'
    if (Test-Path -LiteralPath $manifest) {
        foreach ($line in Get-Content -LiteralPath $manifest) {
            if ($line -match '^\s*AHKFLOW_DB_NAME\s*=\s*(.+?)\s*$') {
                $dbName = $matches[1].Trim()
            }
        }
    }

    $composeProject = $null
    if (Test-Path -LiteralPath $manifest) {
        foreach ($line in Get-Content -LiteralPath $manifest) {
            if ($line -match '^\s*AHKFLOW_COMPOSE_PROJECT\s*=\s*(.+?)\s*$') {
                $composeProject = $matches[1].Trim()
            }
        }
    }

    # --- capture branch + main checkout WHILE the worktree still exists ------
    $branchName = $null
    $mainCheckoutFromGit = $null

    $branchResult = Invoke-GitCapture @('-C', $worktreeFull, 'rev-parse', '--abbrev-ref', 'HEAD')
    if ($branchResult.ExitCode -eq 0 -and $branchResult.Lines.Count -gt 0) {
        $branchName = ($branchResult.Lines[0]).Trim()
        if ($branchName -eq 'HEAD') {
            $branchName = $null
        }
    }

    $commonResult = Invoke-GitCapture @('-C', $worktreeFull, 'rev-parse', '--path-format=absolute', '--git-common-dir')
    if ($commonResult.ExitCode -eq 0 -and $commonResult.Lines.Count -gt 0) {
        $gitCommonDir = ($commonResult.Lines[0]).Trim()
        try {
            if ((Split-Path -Leaf $gitCommonDir) -ieq '.git') {
                $mainCheckoutFromGit = (Resolve-Path -LiteralPath (Split-Path -Parent $gitCommonDir)).Path
            }
        } catch { }
    }
    $logCheckout = $mainCheckoutFromGit
    $logCheckoutFallbackMessage = $null
    if (-not $logCheckout) {
        $logCheckout = Resolve-MainCheckoutFromScriptRoot
        if ($logCheckout) {
            $logCheckoutFallbackMessage = "Main checkout unresolved from target git metadata; using script-root checkout for log placement only: $logCheckout"
        } else {
            $logCheckoutFallbackMessage = 'Main checkout unresolved from target git metadata and script-root fallback failed.'
        }
    }
    Set-ProductionLogPath $logCheckout
    Write-DiagnosticLog '====================================================================='
    Write-DiagnosticLog "WorktreeRemove hook fired. PID=$PID ScriptPath=$PSCommandPath"
    if ($stdinError) { Write-DiagnosticLog $stdinError }
    Write-DiagnosticLog "WorktreePath = $worktreeFull"
    Write-GitResult 'rev-parse --abbrev-ref HEAD' $branchResult
    Write-GitResult 'rev-parse --git-common-dir' $commonResult
    if (-not $branchName -and $branchResult.ExitCode -eq 0 -and $branchResult.Lines.Count -gt 0 -and (($branchResult.Lines[0]).Trim() -eq 'HEAD')) {
        Write-DiagnosticLog 'Detached HEAD detected; branch deletion will be skipped.'
    }
    if ($logCheckoutFallbackMessage) { Write-DiagnosticLog $logCheckoutFallbackMessage }
    Write-DiagnosticLog "BranchName=$branchName MainCheckout=$mainCheckoutFromGit LogPath=$script:LogPath"
    Write-DiagnosticLog "DatabaseName=$dbName"
    Write-DiagnosticLog "ComposeProject=$composeProject"

    if (-not $mainCheckoutFromGit) {
        Write-UnregisteredWorktreeRefusal $worktreeFull $mainCheckoutFromGit ([pscustomobject]@{
                IsRegistered = $false
                Reason       = 'target git metadata could not resolve a main checkout'
                GitResult    = $null
            })
        Write-Outcome 'Kept: the path is not a registered worktree of this repository.'
        return
    }

    # Fallback (spec): if the manifest did not record the database name, derive it
    # from the captured branch using the shared rule, with the base read from the
    # main checkout's tracked appsettings (the same source the watcher uses to drop)
    # so derivation and drop agree. Normal worktrees never hit this because setup
    # records/backfills the name.
    if (-not $dbName -and $branchName) {
        try {
            . (Join-Path $PSScriptRoot 'worktree-database.common.ps1')
            $fallbackBase = (Get-WorktreeDatabaseConfig -RepoRoot $mainCheckoutFromGit).BaseName
            $dbName = Get-WorktreeDatabaseNameForBranch -BaseName $fallbackBase -Branch $branchName
            Write-DiagnosticLog "DatabaseName missing from manifest; derived from branch '$branchName': $dbName"
        } catch {
            Write-DiagnosticLog "DatabaseName missing from manifest and could not derive from branch '$branchName': $($_.Exception.Message)"
        }
    }

    # --- safety: never let removal target the main checkout -----------------
    # If WorktreePath resolves to the main checkout (e.g. the hook was invoked
    # with the repo root, or git-common-dir resolution collapsed to the same
    # path), spawning the watcher would rename + recursively delete the main
    # repo. Refuse: this is not a linked worktree.
    if (Test-SamePath $worktreeFull $mainCheckoutFromGit) {
        Write-DiagnosticLog "REFUSING: WorktreePath resolves to the main checkout ($worktreeFull). This is not a linked worktree; nothing to remove."
        Write-Outcome 'Kept: the path is the main checkout, not a worktree.'
        return
    }

    $registration = Test-RegisteredLinkedWorktree -WorktreeFull $worktreeFull -MainCheckout $mainCheckoutFromGit
    if (-not $registration.IsRegistered) {
        Write-UnregisteredWorktreeRefusal $worktreeFull $mainCheckoutFromGit $registration
        Write-Outcome 'Kept: the path is not a registered worktree of this repository.'
        return
    }

    # --- gate: only remove when merged into main AND clean, unless forced ---
    $forceRemove = Test-EnvironmentFlagEnabled -Name 'AHKFLOW_WORKTREE_FORCE_REMOVE'
    if ($forceRemove) {
        Write-DiagnosticLog 'force override: AHKFLOW_WORKTREE_FORCE_REMOVE set; bypassing merge/clean gate.'
    } else {
        if (-not $branchName) {
            Write-DiagnosticLog 'The worktree is on a detached HEAD, so there is no branch to decide about.'
            Write-UnmergedPreserveGuidance -WorktreeFull $worktreeFull -MainCheckout $mainCheckoutFromGit -BranchName $branchName -Reason 'the worktree has a detached HEAD'
            return
        }

        # cleanup-merged-worktrees.ps1 passes the base it resolved, so the sweep path fetches once
        # for the whole run. A bare hook fire resolves its own.
        $baseRef = $MainRef
        if (-not $baseRef) {
            $base = Resolve-MergedBaseRef -RepoRoot $mainCheckoutFromGit
            Write-DiagnosticLog (Format-MergedBaseRefMessage -Prefix 'merge gate' -Base $base)
            $baseRef = $base.Ref

            # A base that could not be refreshed proves nothing: the remote may have dropped the
            # merge the cached ref still shows. Removal is destructive, so preserve and say why.
            if ($base.Reason -eq 'remote-stale') {
                Write-DiagnosticLog "The base '$($base.Ref)' could not be refreshed, so it may be behind the remote."
                Write-UnmergedPreserveGuidance -WorktreeFull $worktreeFull -MainCheckout $mainCheckoutFromGit -BranchName $branchName -Reason 'the base branch could not be refreshed'
                return
            }
        }

        if (-not (Test-WorktreeMergedIntoMain -WorktreeFull $worktreeFull -BranchName $branchName -BaseRef $baseRef -MainCheckout $mainCheckoutFromGit)) {
            Write-DiagnosticLog "Branch '$branchName' is not merged into $baseRef."
            Write-UnmergedPreserveGuidance -WorktreeFull $worktreeFull -MainCheckout $mainCheckoutFromGit -BranchName $branchName -Reason 'the branch is not merged'
            return
        }

        if (-not (Test-WorktreeClean -WorktreeFull $worktreeFull)) {
            Write-UnmergedPreserveGuidance -WorktreeFull $worktreeFull -MainCheckout $mainCheckoutFromGit -BranchName $branchName -Reason 'the worktree has uncommitted changes'
            return
        }

        # A merged branch does not prove the work happened: the plan lives in a second private
        # repository the public branch never carries. Asked last, and handed $baseRef, so it reads
        # the item from the same base the merge gate just decided against. Reading the working tree
        # instead would refuse a branch that merged on GitHub while the local checkout is behind.
        # -WorktreeName: the recorded number goes stale across a renumber, so the guard resolves
        # the item from the worktree's own name and keeps the recorded number as the fallback.
        $planVerdict = Test-WorktreePlanWasImplemented -MainCheckout $mainCheckoutFromGit `
            -ItemNumber (Get-ManifestBacklogItem -WorktreePath $worktreeFull) -BaseRef $baseRef `
            -WorktreeName $worktreeFull
        if (-not $planVerdict.Allow) {
            Write-DiagnosticLog "plan gate: $($planVerdict.Reason)"
            # No outcome line here. Write-UnmergedPreserveGuidance writes 'Kept: <reason>.' with
            # the guard's own reason, so this path still puts exactly one line on one attempt.
            # The line it used to write here said 'the plan was never implemented' whatever the
            # real verdict was, which sent one investigation to the wrong backlog item.
            Write-UnmergedPreserveGuidance -WorktreeFull $worktreeFull -MainCheckout $mainCheckoutFromGit `
                -BranchName $branchName -Reason $planVerdict.Reason
            return
        }

        # The guard allowed removal while the manifest names one item and the worktree name names
        # another. That is a stale recorded number, not a reason to keep anything, so it goes to
        # diagnostics and never to the outcome line. The sweep writes the same sentence, so one
        # search finds the case whichever writer handled it.
        if ($planVerdict.ItemNumber -and $planVerdict.RecordedItemNumber -and
            $planVerdict.ItemNumber -ne $planVerdict.RecordedItemNumber) {
            Write-DiagnosticLog ("Plan guard judged backlog item $($planVerdict.ItemNumber); " +
                "the worktree manifest records item $($planVerdict.RecordedItemNumber).")
        }
    }

    # --- snapshot watcher script + sidecar params outside the worktree ------
    # Every attempt gets its own directory. One merged-cleanup sweep starts several watchers at
    # once, and each one dot-sources the helpers from its own script folder. A shared folder meant
    # watcher B copied over the exact file watcher A held open, so B lost both helpers and ran on
    # its inline fallbacks (GitHub issue #339).
    $tempDir = Get-RemovalTempDir
    $runDir = Get-RemovalRunTempDir -RunId $script:RunId

    try {
        New-Item -ItemType Directory -Path $runDir -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-DiagnosticLog "Failed to create the watcher temp directory '$runDir': $($_.Exception.Message). Aborting (worktree left intact)."
        Write-Outcome 'Failed: the watcher could not be prepared.'
        return
    }

    # The directory carries the run id, so the file names inside it do not repeat it.
    $watcherScript = Join-Path $runDir 'watcher.ps1'
    $paramFile = Join-Path $runDir 'params.json'

    # -ErrorAction Stop on every copy below. This script runs with $ErrorActionPreference =
    # 'Continue', and a Copy-Item failure is a non-terminating error, so without it the catch
    # blocks never run: the copy fails in silence and the hook spawns a watcher script that is not
    # there.
    try {
        Copy-Item -LiteralPath $PSCommandPath -Destination $watcherScript -Force -ErrorAction Stop
    } catch {
        Write-DiagnosticLog "Failed to snapshot watcher script: $($_.Exception.Message). Aborting (worktree left intact)."
        Write-Outcome 'Failed: the watcher could not be prepared.'
        # The run directory was created a few lines above, and may already hold a partial
        # watcher.ps1. Without this every failed attempt leaves one more dead directory in %TEMP%.
        Remove-WatcherArtifacts -ParamFilePath $paramFile -WatcherScriptPath $watcherScript
        return
    }

    # The reliable logger travels with the watcher. Without it the watcher falls back to a
    # single-attempt append, and one sweep starts several watchers at once -- exactly the
    # collision the retrying writer was built for. A copy that fails is not fatal: the inline
    # fallback still writes, it just cannot retry.
    try {
        $logSource = Join-Path $PSScriptRoot 'worktree-log.common.ps1'
        if (Test-Path -LiteralPath $logSource) {
            Copy-Item -LiteralPath $logSource -Destination (Join-Path $runDir 'worktree-log.common.ps1') -Force -ErrorAction Stop
        }
    } catch {
        Write-DiagnosticLog "Could not copy the log helper beside the watcher: $($_.Exception.Message). The watcher will append without retrying."
    }

    # The holder probe travels with the watcher, so a timed-out removal can still name the
    # process holding the folder. A copy that fails is not fatal: the inline fallback above
    # takes over and the outcome line degrades to the no-holder wording.
    try {
        $holderSource = Join-Path $PSScriptRoot 'worktree-holder.common.ps1'
        if (Test-Path -LiteralPath $holderSource) {
            Copy-Item -LiteralPath $holderSource -Destination (Join-Path $runDir 'worktree-holder.common.ps1') -Force -ErrorAction Stop
        }
    } catch {
        Write-DiagnosticLog "Could not copy the holder probe beside the watcher: $($_.Exception.Message). A timed-out removal will not name the holder."
    }

    $payload = [ordered]@{
        RunId          = $script:RunId
        # Where this hook staged the run directory. The watcher does not inherit the hook's TEMP,
        # so without this it can look for the run directory in the wrong root and refuse to clean
        # it up.
        TempRoot       = $tempDir
        WorktreePath   = $worktreeFull
        BranchName     = $branchName
        MainCheckout   = $mainCheckoutFromGit
        DatabaseName   = $dbName
        ComposeProject = $composeProject
        LogPath        = $script:LogPath
        WatcherScript  = $watcherScript
        TimeoutSeconds = $TimeoutSeconds
    }
    try {
        [System.IO.File]::WriteAllText($paramFile, ($payload | ConvertTo-Json -Depth 5), [System.Text.Encoding]::UTF8)
    } catch {
        Write-DiagnosticLog "Failed to write sidecar param file: $($_.Exception.Message). Aborting (worktree left intact)."
        Write-Outcome 'Failed: the watcher could not be prepared.'
        Remove-WatcherArtifacts -ParamFilePath $paramFile -WatcherScriptPath $watcherScript
        return
    }

    # --- spawn the detached watcher OUTSIDE claude's job object (WMI) --------
    $psExe = Resolve-PowerShellExecutable
    $watcherCmd = '"{0}" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{1}" -Mode Watcher -ParamFile "{2}" -HookTempRoot "{3}"' -f $psExe, $watcherScript, $paramFile, $tempDir

    # Without ProcessStartupInformation the new process gets a visible console window, and
    # -WindowStyle Hidden above only hides it after the host starts. The user sees that gap as
    # a black flash on every removal.
    $cimArguments = @{
        CommandLine      = $watcherCmd
        CurrentDirectory = $tempDir
    }
    $startupInformation = New-HiddenProcessStartup
    if ($startupInformation) {
        $cimArguments['ProcessStartupInformation'] = $startupInformation
    } else {
        Write-DiagnosticLog 'Could not build hidden process startup information; the watcher window may flash.'
    }

    $spawned = $false
    try {
        $result = Invoke-CimMethod -ClassName Win32_Process -MethodName Create `
            -Arguments $cimArguments -ErrorAction Stop
        if ($result.ReturnValue -eq 0) {
            Write-DiagnosticLog "Watcher spawned via WMI. PID=$($result.ProcessId) ParamFile=$paramFile"
            $spawned = $true
        } else {
            Write-DiagnosticLog "WMI Win32_Process.Create returned $($result.ReturnValue); will fall back to Start-Process."
        }
    } catch {
        Write-DiagnosticLog "WMI spawn failed: $($_.Exception.Message); will fall back to Start-Process."
    }

    if (-not $spawned) {
        try {
            $p = Start-Process -FilePath $psExe -WindowStyle Hidden -PassThru -WorkingDirectory $tempDir -ArgumentList @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
                '-File', $watcherScript, '-Mode', 'Watcher', '-ParamFile', $paramFile,
                '-HookTempRoot', $tempDir)
            Write-DiagnosticLog "Watcher spawned via Start-Process (fallback; may be killed if claude uses a kill-on-close job). PID=$($p.Id)"
            $spawned = $true
        } catch {
            Write-DiagnosticLog "Failed to spawn watcher at all: $($_.Exception.Message). Worktree left intact."
        }
    }

    if ($spawned) {
        # No outcome line here. The watcher now owns it, and a second writer would put two
        # lines on one attempt.
        Write-DiagnosticLog 'Hook returning 0 (worktree untouched; watcher owns removal).'
    } else {
        Remove-WatcherArtifacts -ParamFilePath $paramFile -WatcherScriptPath $watcherScript
        Write-Outcome 'Failed: the watcher could not be started.'
        Write-DiagnosticLog 'Hook returning 0 (worktree untouched; watcher was not launched).'
    }
}

# ===========================================================================
# WATCHER MODE
# ===========================================================================
function Invoke-WatcherMode {
    # Before anything else, including the two cleanup paths below. Every one of them asks
    # Get-RemovalTempDir where the temp root is, and this process does not inherit the hook's TEMP.
    if ($HookTempRoot) {
        $script:TempRoot = $HookTempRoot
    }

    # Never let the watcher itself become a locker.
    try { [System.IO.Directory]::SetCurrentDirectory((Get-RemovalTempDir)) } catch { }

    if (-not $ParamFile -or -not (Test-Path -LiteralPath $ParamFile)) {
        $script:RunId = 'watcher-noparams'
        Write-DiagnosticLog "ParamFile missing: $ParamFile. Cannot proceed."
        Remove-WatcherArtifacts -ParamFilePath $ParamFile -WatcherScriptPath $PSCommandPath
        return
    }

    # A read or JSON parse failure must not leave $cfg null and silently bail
    # (with $ErrorActionPreference = 'Continue'): log it, clean up the temp
    # param file + watcher script, and stop.
    $cfg = $null
    try {
        $cfg = Get-Content -LiteralPath $ParamFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $script:RunId = 'watcher-badparams'
        Write-DiagnosticLog "Failed to read/parse ParamFile '$ParamFile': $($_.Exception.Message). Cannot proceed."
        Remove-WatcherArtifacts -ParamFilePath $ParamFile -WatcherScriptPath $PSCommandPath
        return
    }

    $script:RunId = [string] $cfg.RunId
    # Read before anything asks for a temp path. Set-ProductionLogPath and the cleanup guard both
    # call Get-RemovalTempDir, and both have to answer with the root the hook actually used.
    if ($cfg.PSObject.Properties.Name -contains 'TempRoot' -and $cfg.TempRoot) {
        $script:TempRoot = [string] $cfg.TempRoot
    }
    if ($cfg.LogPath) {
        $script:LogPath = [string] $cfg.LogPath
        $script:DiagnosticsPath = $null
    }
    $worktreeFull = ConvertTo-NormalizedPath ([string] $cfg.WorktreePath)
    Set-WorktreeLogName $worktreeFull
    $branchName = [string] $cfg.BranchName
    if ($branchName -eq 'HEAD') {
        $branchName = $null
    }
    $mainCheckout = ConvertTo-NormalizedPath ([string] $cfg.MainCheckout)
    $timeout = if ($cfg.TimeoutSeconds) { [int] $cfg.TimeoutSeconds } else { $TimeoutSeconds }
    $watcherScript = [string] $cfg.WatcherScript
    Set-ProductionLogPath $mainCheckout

    # First watcher log line == proof the watcher survived claude's exit.
    Write-DiagnosticLog '---------------------------------------------------------------------'
    Write-DiagnosticLog "Watcher started. PID=$PID Worktree=$worktreeFull Branch=$branchName Timeout=${timeout}s"

    if (-not $worktreeFull) {
        Write-DiagnosticLog 'No worktree path in params; nothing to do.'
        Remove-WatcherArtifacts -ParamFilePath $ParamFile -WatcherScriptPath $watcherScript
        return
    }

    if (-not $mainCheckout) {
        Write-UnregisteredWorktreeRefusal $worktreeFull $mainCheckout ([pscustomobject]@{
                IsRegistered = $false
                Reason       = 'main checkout path is unknown'
                GitResult    = $null
            })
        # The folder was never touched, so this is a Kept line and not the Failed one the
        # post-delete path writes for the same missing value.
        Write-Outcome 'Kept: the main checkout could not be resolved.'
        Complete-WatcherPreserved -ParamFilePath $ParamFile -WatcherScriptPath $watcherScript
        return
    }

    # --- safety: never let the watcher delete the main checkout -------------
    # The hook already refuses this, but the watcher reads paths independently
    # from the param file and is where the destructive rename + delete happen.
    if (Test-SamePath $worktreeFull $mainCheckout) {
        Write-DiagnosticLog "REFUSING: WorktreePath ($worktreeFull) equals MainCheckout. Will not rename/delete the main checkout."
        Write-Outcome 'Kept: the path is the main checkout, not a worktree.'
        Remove-WatcherArtifacts -ParamFilePath $ParamFile -WatcherScriptPath $watcherScript
        return
    }

    $registration = Test-RegisteredLinkedWorktree -WorktreeFull $worktreeFull -MainCheckout $mainCheckout
    if (-not $registration.IsRegistered) {
        Write-UnregisteredWorktreeRefusal $worktreeFull $mainCheckout $registration
        Write-Outcome 'Kept: the path is not a registered worktree of this repository.'
        Complete-WatcherPreserved -ParamFilePath $ParamFile -WatcherScriptPath $watcherScript
        return
    }

    $tempName = "$worktreeFull.removing-$script:RunId"
    $deadline = (Get-Date).AddSeconds($timeout)
    $renamed = $false
    $alreadyGone = $false
    $removalFailure = $null   # set to a plain-word reason when a step makes the removal a failure
    $lastError = ''
    $nextStatus = Get-Date

    while ((Get-Date) -lt $deadline) {
        if (-not (Test-Path -LiteralPath $worktreeFull)) {
            Write-DiagnosticLog 'Worktree folder already gone (removed elsewhere); proceeding to prune + branch cleanup.'
            $alreadyGone = $true
            $renamed = $true
            break
        }

        # `git worktree move`, not [System.IO.Directory]::Move. Git refuses a locked worktree as
        # part of the operation, so there is no window between checking the lock and acting on it,
        # and no administrative path to construct -- that name is not always the folder name. It
        # also updates git's registry, so the later prune only has to clear the deleted entry.
        $move = Invoke-GitCapture @('-C', $mainCheckout, 'worktree', 'move', $worktreeFull, $tempName)
        if ($move.ExitCode -eq 0) {
            $renamed = $true
            Write-DiagnosticLog "git worktree move succeeded -> '$tempName'. Folder is free; proceeding to delete."
            break
        }

        $lastError = ($move.Lines -join ' ').Trim()

        # A lock is a decision, not a wait. Stop now rather than retrying for the whole timeout.
        # The wording below is git's, measured on 2.55.0.windows.3, and is not ours to choose:
        #   fatal: cannot move a locked working tree, lock reason: <reason>
        #   fatal: cannot move a locked working tree;          (locked with no reason)
        if ($lastError -match 'cannot move a locked working tree') {
            $lockReason = if ($lastError -match 'lock reason:\s*(?<reason>.+?)\s+use ') { $Matches.reason } else { '' }
            Write-DiagnosticLog "git refused the move: $lastError"
            Write-Outcome ("Kept: the worktree is locked ($(Format-WorktreeLogReason -Text $lockReason)).")
            Complete-WatcherPreserved -ParamFilePath $ParamFile -WatcherScriptPath $watcherScript
            return
        }

        if ((Get-Date) -ge $nextStatus) {
            $elapsed = [int]((Get-Date) - $deadline.AddSeconds(-$timeout)).TotalSeconds
            Write-DiagnosticLog "Waiting (${elapsed}s): move blocked. LastError: $lastError"
            $nextStatus = (Get-Date).AddSeconds(5)
        }

        Start-Sleep -Milliseconds 750
    }

    if (-not $renamed) {
        Write-TimeoutGuidance $worktreeFull $mainCheckout $branchName $lastError
        Complete-WatcherPreserved -ParamFilePath $ParamFile -WatcherScriptPath $watcherScript
        return
    }

    # --- delete the renamed tree (proven free) ------------------------------
    if (-not $alreadyGone) {
        try {
            Remove-Item -LiteralPath $tempName -Recurse -Force -ErrorAction Stop
            Write-DiagnosticLog "Deleted '$tempName'."
        } catch {
            Write-DiagnosticLog "Remove-Item reported an error: $($_.Exception.Message)"
            if (Test-Path -LiteralPath $tempName) {
                Write-DiagnosticLog "Remnant left at '$tempName' (clearly-marked; the original worktree path is already gone)."
                $removalFailure = 'the worktree folder was renamed but not fully deleted'
            }
        }
    }

    if (-not $mainCheckout) {
        Write-DiagnosticLog 'Main checkout unknown; cannot prune git or delete branch.'
        Write-Outcome 'Failed: the main checkout could not be resolved.'
        Remove-WatcherArtifacts -ParamFilePath $ParamFile -WatcherScriptPath $watcherScript
        return
    }

    $pruneResult = Invoke-GitCapture @('-C', $mainCheckout, 'worktree', 'prune', '-v')
    Write-GitResult 'worktree prune -v' $pruneResult
    if ($pruneResult.ExitCode -ne 0 -and -not $removalFailure) {
        $removalFailure = "the folder is gone but git's registry still lists it"
    }

    $branchDeleteSucceeded = $false
    $branchDeleteAttempted = $false
    if ($branchName) {
        $branchDeleteAttempted = $true
        $branchDelete = Invoke-GitCapture @('-C', $mainCheckout, 'branch', '-d', '--', $branchName)
        $branchDeleteLabel = 'branch -d -- ' + (Format-PowerShellArgument $branchName)
        Write-GitResult $branchDeleteLabel $branchDelete -SuppressHintLines
        if ($branchDelete.ExitCode -ne 0) {
            Write-BranchDeleteGuidance $mainCheckout $branchName
        } else {
            $branchDeleteSucceeded = $true
        }
    } else {
        Write-DiagnosticLog 'Branch name unknown; skipping branch delete.'
    }

    if ($branchDeleteSucceeded) {
        $dbName = [string] $cfg.DatabaseName
        if ($dbName) {
            try {
                # The watcher runs from a temp snapshot of only this script, so it
                # loads the shared helper from the main checkout, not from
                # $PSScriptRoot (which points at the temp dir).
                . (Join-Path $mainCheckout 'scripts\worktree-database.common.ps1')
                $dbConfig = Get-WorktreeDatabaseConfig -RepoRoot $mainCheckout
                $masterConnectionString = Get-WorktreeMasterConnectionString $dbConfig.ConnectionString
                $dropResult = Remove-WorktreeDatabaseByName -DbName $dbName -BaseName $dbConfig.BaseName -MasterConnectionString $masterConnectionString
                if ($dropResult.Dropped) {
                    Write-DiagnosticLog "Dropped database [$dbName]."
                } elseif ($dropResult.Skipped) {
                    Write-DiagnosticLog "No worktree database to drop, or unexpected name (name='$dbName')."
                } else {
                    Write-DiagnosticLog "Could not drop database [$dbName]: $($dropResult.Error). It is likely still in use (a running API, SSMS, or test host). The database was left intact; reclaim it with 'scripts\prune-worktree-databases.ps1' or drop it manually after closing connections. Details in this log: $script:LogPath"
                }
            } catch {
                Write-DiagnosticLog "Could not resolve database settings from the main checkout to drop [$dbName]: $($_.Exception.Message). The database was left intact; reclaim it with 'scripts\prune-worktree-databases.ps1'."
            }
        } else {
            Write-DiagnosticLog 'No database name recorded; skipping database drop (prune reclaims any orphan later).'
        }

        $composeProject = [string] $cfg.ComposeProject
        if ($composeProject) {
            try {
                . (Join-Path $mainCheckout 'scripts\worktree-docker.common.ps1')
                $composeFile = Join-Path $mainCheckout 'docker-compose.yml'
                $removeResult = Remove-WorktreeDockerProject -Name $composeProject -ComposeFilePath $composeFile
                if ($removeResult.Removed) {
                    Write-DiagnosticLog "Removed Docker compose project [$composeProject]."
                } elseif ($removeResult.Skipped) {
                    Write-DiagnosticLog "No Docker compose project to remove, or unexpected name (name='$composeProject')."
                } else {
                    Write-DiagnosticLog "Could not remove Docker compose project [$composeProject]: $($removeResult.Error). It was left intact; reclaim it with 'scripts\prune-worktree-docker.ps1'."
                }
            } catch {
                Write-DiagnosticLog "Could not remove Docker compose project [$composeProject]: $($_.Exception.Message). Reclaim it with 'scripts\prune-worktree-docker.ps1'."
            }
        } else {
            Write-DiagnosticLog 'No compose project recorded; skipping Docker teardown (prune reclaims any orphan later).'
        }
    } else {
        Write-DiagnosticLog 'Skipping database drop and Docker teardown: branch was not confirmed deleted (scripts/prune-worktree-databases.ps1 and scripts/prune-worktree-docker.ps1 reclaim them later).'
    }

    # --- verify + record the one outcome ------------------------------------
    $folderGone = -not (Test-Path -LiteralPath $worktreeFull)
    Write-DiagnosticLog 'Final state:'
    Write-DiagnosticLog "  worktree folder exists: $(-not $folderGone)"
    if ($branchName) {
        $branchRef = "refs/heads/$branchName"
        $branchCheck = Invoke-GitCapture @('-C', $mainCheckout, 'show-ref', '--verify', '--quiet', $branchRef)
        Write-DiagnosticLog "  branch '$branchName' still present: $($branchCheck.ExitCode -eq 0)"
    }
    Write-GitResult '  worktree list' (Invoke-GitCapture @('-C', $mainCheckout, 'worktree', 'list'))
    if (-not $branchDeleteAttempted) {
        Write-DiagnosticLog 'Watcher done (worktree removed; branch skipped).'
    } elseif ($branchDeleteSucceeded) {
        Write-DiagnosticLog 'Watcher done (worktree + branch removed).'
    } else {
        Write-DiagnosticLog 'Watcher done (worktree removed; branch preserved).'
    }

    if ($removalFailure) {
        Write-Outcome ('Failed: ' + (Format-WorktreeLogReason -Text $removalFailure) + '.')
    } else {
        Write-Outcome 'Removed.'
    }

    Remove-WatcherArtifacts -ParamFilePath $ParamFile -WatcherScriptPath $watcherScript
}

function Complete-WatcherPreserved {
    param([string] $ParamFilePath, [string] $WatcherScriptPath)

    Write-DiagnosticLog 'Watcher done (worktree preserved).'
    Remove-WatcherArtifacts -ParamFilePath $ParamFilePath -WatcherScriptPath $WatcherScriptPath
}

# Deletes the whole run directory. Both paths handed in live inside it, so the caller does not have
# to know the directory: eleven call sites already pass these two values and none of them changed.
function Remove-WatcherArtifacts {
    param([string] $ParamFilePath, [string] $WatcherScriptPath)

    $anchor = if ($WatcherScriptPath) { $WatcherScriptPath } else { $ParamFilePath }
    if (-not $anchor) {
        return
    }

    $runDir = ''
    try {
        $runDir = Split-Path -Parent ([System.IO.Path]::GetFullPath($anchor))
    } catch {
        Write-DiagnosticLog "Could not resolve the watcher temp directory from '$anchor': $($_.Exception.Message)"
        return
    }

    if (-not $runDir -or -not (Test-Path -LiteralPath $runDir)) {
        return
    }

    if (-not (Test-RemovalRunTempDirPath -Path $runDir)) {
        Write-DiagnosticLog "Skipping deletion of non-generated watcher temp directory '$runDir'."
        return
    }

    try {
        Remove-Item -LiteralPath $runDir -Recurse -Force -ErrorAction Stop
    } catch {
        Write-DiagnosticLog "Could not delete temp artifact '$runDir': $($_.Exception.Message)"
    }
}

# True when the path is a run directory this script created: named for one attempt, and sitting
# directly in the temp root. The prefix alone is not enough -- a folder called exactly
# 'ahkflowapp-wt-remove-' belongs to no attempt, so it is refused.
function Test-RemovalRunTempDirPath {
    param([string] $Path)

    if (-not $Path) {
        return $false
    }

    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path)
        # GetTempPath() ends with a separator and Split-Path -Parent does not, so both sides are
        # trimmed before they are compared.
        $tempRoot = [System.IO.Path]::GetFullPath((Get-RemovalTempDir)).TrimEnd('\', '/')
    } catch {
        return $false
    }

    $prefix = 'ahkflowapp-wt-remove-'
    $leaf = Split-Path -Leaf $fullPath
    if (-not $leaf.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        $leaf.Length -le $prefix.Length) {
        return $false
    }

    $parent = (Split-Path -Parent $fullPath)
    if (-not $parent) {
        return $false
    }

    return [string]::Equals($parent.TrimEnd('\', '/'), $tempRoot, [System.StringComparison]::OrdinalIgnoreCase)
}

# ===========================================================================
# Entry point
# ===========================================================================
# Dot-sourced by a test: $MyInvocation.InvocationName is '.', so the entry point stays put and the
# suite can call one function without the script running a removal -- and without `exit 0` ending
# the test host. Same guard the sweep uses.
if ($MyInvocation.InvocationName -ne '.') {
    try {
        if ($Mode -eq 'Watcher') {
            Invoke-WatcherMode
        } else {
            Invoke-HookMode
        }
    } catch {
        try { Write-DiagnosticLog "UNHANDLED ERROR: $($_.Exception.Message)" } catch { }
    }

    exit 0
}
