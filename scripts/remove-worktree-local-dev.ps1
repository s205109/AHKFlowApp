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

    [string] $LogPath,

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

$worktreeLogHelperPath = Join-Path $PSScriptRoot 'worktree-log.common.ps1'
if (Test-Path -LiteralPath $worktreeLogHelperPath) {
    . $worktreeLogHelperPath
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

function Get-RemovalTempDir {
    return [System.IO.Path]::GetTempPath()
}

function Set-ProductionLogPath {
    param([string] $MainCheckout)

    if ($script:LogPath) {
        return
    }

    if ($MainCheckout) {
        $script:LogPath = Join-Path $MainCheckout '.claude\worktrees\worktree-removal.log'
        return
    }

    $script:LogPath = Join-Path (Get-RemovalTempDir) 'worktree-removal.log'
}

function Write-Log {
    param([string] $Message)

    if (-not $script:LogPath) {
        Set-ProductionLogPath $null
    }

    try {
        $dir = Split-Path -Parent $script:LogPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        Write-WorktreeLog -LogPath $script:LogPath -Worktree $script:WorktreeLogName -Message $Message
    } catch { }
    Write-DiagnosticLog $Message
}

function Write-DiagnosticLog {
    param([string] $Message)

    $prefix = if ($script:RunId) { "[$script:RunId] $Mode" } else { $Mode }
    $line = "{0} {1} {2}" -f [DateTimeOffset]::Now.ToString('O'), $prefix, $Message
    try { [Console]::Error.WriteLine($line) } catch { }
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
        return (Resolve-Path -LiteralPath (Join-Path $scriptRoot '..') -ErrorAction Stop).Path
    } catch {
        return $null
    }
}

function Read-RawStdin {
    if (-not [Console]::IsInputRedirected) { return $null }
    try { return [Console]::In.ReadToEnd() } catch { return $null }
}

# Runs git and returns merged output + exit code.
function Invoke-GitCapture {
    param([string[]] $GitArgs)

    $merged = & git @GitArgs 2>&1
    $code = $LASTEXITCODE
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

    Write-Log "Could not remove worktree because the folder is still locked: $WorktreeFull"
    if ($LastError) {
        Write-Log "Last rename error: $LastError"
    }
    Write-Log 'The worktree was preserved. Close terminals, editors, shells, or Claude sessions opened inside that folder, then run:'
    if ($MainCheckout) {
        Write-Log ('  ' + (Format-GitCommand $MainCheckout @('worktree', 'remove', $WorktreeFull)))
        Write-Log ('  ' + (Format-GitCommand $MainCheckout @('worktree', 'prune')))
        if ($BranchName) {
            Write-Log ('  ' + (Format-GitCommand $MainCheckout @('branch', '-d', '--', $BranchName)))
        }
    } else {
        Write-Log '  git worktree remove <worktree-path>'
        Write-Log '  git worktree prune'
        if ($BranchName) {
            Write-Log ('  ' + (Format-GitCommand $null @('branch', '-d', '--', $BranchName)))
        }
    }
    Write-Log "Details were logged to: $script:LogPath"
}

function Write-BranchDeleteGuidance {
    param(
        [string] $MainCheckout,
        [string] $BranchName
    )

    Write-Log "Branch was not deleted: $BranchName"
    Write-Log 'Git refused safe branch deletion, usually because the branch contains unmerged commits.'
    Write-Log 'Inspect or merge the branch, then retry:'
    Write-Log ('  ' + (Format-GitCommand $MainCheckout @('branch', '-d', '--', $BranchName)))
    Write-Log 'Only if you intentionally want to discard that branch, run:'
    Write-Log ('  ' + (Format-GitCommand $MainCheckout @('branch', '-D', '--', $BranchName)))
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
    Write-Log "REFUSING: WorktreePath is not a registered linked worktree under MainCheckout. WorktreePath=$WorktreeFull MainCheckout=$MainCheckout Reason=$reason"
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
        Write-Log '====================================================================='
        Write-Log "WorktreeRemove hook fired. PID=$PID ScriptPath=$PSCommandPath"
        if ($stdinError) { Write-Log $stdinError }
        Write-Log 'No worktree_path provided; nothing to do.'
        return
    }

    $worktreeFull = ConvertTo-NormalizedPath $WorktreePath
    Set-WorktreeLogName $worktreeFull

    if (-not (Test-Path -LiteralPath $worktreeFull)) {
        Set-ProductionLogPath (Resolve-MainCheckoutFromScriptRoot)
        Write-Log '====================================================================='
        Write-Log "WorktreeRemove hook fired. PID=$PID ScriptPath=$PSCommandPath"
        if ($stdinError) { Write-Log $stdinError }
        Write-Log "WorktreePath = $worktreeFull"
        Write-Log 'Worktree folder does not exist; nothing to remove.'
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
    Write-Log '====================================================================='
    Write-Log "WorktreeRemove hook fired. PID=$PID ScriptPath=$PSCommandPath"
    if ($stdinError) { Write-Log $stdinError }
    Write-Log "WorktreePath = $worktreeFull"
    Write-GitResult 'rev-parse --abbrev-ref HEAD' $branchResult
    Write-GitResult 'rev-parse --git-common-dir' $commonResult
    if (-not $branchName -and $branchResult.ExitCode -eq 0 -and $branchResult.Lines.Count -gt 0 -and (($branchResult.Lines[0]).Trim() -eq 'HEAD')) {
        Write-Log 'Detached HEAD detected; branch deletion will be skipped.'
    }
    if ($logCheckoutFallbackMessage) { Write-Log $logCheckoutFallbackMessage }
    Write-Log "BranchName=$branchName MainCheckout=$mainCheckoutFromGit LogPath=$script:LogPath"
    Write-Log "DatabaseName=$dbName"
    Write-Log "ComposeProject=$composeProject"

    if (-not $mainCheckoutFromGit) {
        Write-UnregisteredWorktreeRefusal $worktreeFull $mainCheckoutFromGit ([pscustomobject]@{
                IsRegistered = $false
                Reason       = 'target git metadata could not resolve a main checkout'
                GitResult    = $null
            })
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
            Write-Log "DatabaseName missing from manifest; derived from branch '$branchName': $dbName"
        } catch {
            Write-Log "DatabaseName missing from manifest and could not derive from branch '$branchName': $($_.Exception.Message)"
        }
    }

    # --- safety: never let removal target the main checkout -----------------
    # If WorktreePath resolves to the main checkout (e.g. the hook was invoked
    # with the repo root, or git-common-dir resolution collapsed to the same
    # path), spawning the watcher would rename + recursively delete the main
    # repo. Refuse: this is not a linked worktree.
    if (Test-SamePath $worktreeFull $mainCheckoutFromGit) {
        Write-Log "REFUSING: WorktreePath resolves to the main checkout ($worktreeFull). This is not a linked worktree; nothing to remove."
        return
    }

    $registration = Test-RegisteredLinkedWorktree -WorktreeFull $worktreeFull -MainCheckout $mainCheckoutFromGit
    if (-not $registration.IsRegistered) {
        Write-UnregisteredWorktreeRefusal $worktreeFull $mainCheckoutFromGit $registration
        return
    }

    # --- snapshot watcher script + sidecar params outside the worktree ------
    $tempDir = Get-RemovalTempDir
    $watcherScript = Join-Path $tempDir "ahkflowapp-wt-remove-watcher-$script:RunId.ps1"
    $paramFile = Join-Path $tempDir "ahkflowapp-wt-remove-$script:RunId.json"

    try {
        Copy-Item -LiteralPath $PSCommandPath -Destination $watcherScript -Force
    } catch {
        Write-Log "Failed to snapshot watcher script: $($_.Exception.Message). Aborting (worktree left intact)."
        return
    }

    $payload = [ordered]@{
        RunId          = $script:RunId
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
        Write-Log "Failed to write sidecar param file: $($_.Exception.Message). Aborting (worktree left intact)."
        Remove-WatcherArtifacts -ParamFilePath $paramFile -WatcherScriptPath $watcherScript
        return
    }

    # --- spawn the detached watcher OUTSIDE claude's job object (WMI) --------
    $psExe = Join-Path $PSHOME 'powershell.exe'
    $watcherCmd = '"{0}" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{1}" -Mode Watcher -ParamFile "{2}"' -f $psExe, $watcherScript, $paramFile

    $spawned = $false
    try {
        $result = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
            CommandLine      = $watcherCmd
            CurrentDirectory = $tempDir
        } -ErrorAction Stop
        if ($result.ReturnValue -eq 0) {
            Write-Log "Watcher spawned via WMI. PID=$($result.ProcessId) ParamFile=$paramFile"
            $spawned = $true
        } else {
            Write-Log "WMI Win32_Process.Create returned $($result.ReturnValue); will fall back to Start-Process."
        }
    } catch {
        Write-Log "WMI spawn failed: $($_.Exception.Message); will fall back to Start-Process."
    }

    if (-not $spawned) {
        try {
            $p = Start-Process -FilePath $psExe -WindowStyle Hidden -PassThru -WorkingDirectory $tempDir -ArgumentList @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
                '-File', $watcherScript, '-Mode', 'Watcher', '-ParamFile', $paramFile)
            Write-Log "Watcher spawned via Start-Process (fallback; may be killed if claude uses a kill-on-close job). PID=$($p.Id)"
            $spawned = $true
        } catch {
            Write-Log "Failed to spawn watcher at all: $($_.Exception.Message). Worktree left intact."
        }
    }

    if ($spawned) {
        Write-Log 'Hook returning 0 (worktree untouched; watcher owns removal).'
    } else {
        Remove-WatcherArtifacts -ParamFilePath $paramFile -WatcherScriptPath $watcherScript
        Write-Log 'Hook returning 0 (worktree untouched; watcher was not launched).'
    }
}

# ===========================================================================
# WATCHER MODE
# ===========================================================================
function Invoke-WatcherMode {
    # Never let the watcher itself become a locker.
    try { [System.IO.Directory]::SetCurrentDirectory((Get-RemovalTempDir)) } catch { }

    if (-not $ParamFile -or -not (Test-Path -LiteralPath $ParamFile)) {
        $script:RunId = 'watcher-noparams'
        Write-Log "ParamFile missing: $ParamFile. Cannot proceed."
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
        Write-Log "Failed to read/parse ParamFile '$ParamFile': $($_.Exception.Message). Cannot proceed."
        Remove-WatcherArtifacts -ParamFilePath $ParamFile -WatcherScriptPath $PSCommandPath
        return
    }

    $script:RunId = [string] $cfg.RunId
    if ($cfg.LogPath) { $script:LogPath = [string] $cfg.LogPath }
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
    Write-Log '---------------------------------------------------------------------'
    Write-Log "Watcher started. PID=$PID Worktree=$worktreeFull Branch=$branchName Timeout=${timeout}s"

    if (-not $worktreeFull) {
        Write-Log 'No worktree path in params; nothing to do.'
        Remove-WatcherArtifacts -ParamFilePath $ParamFile -WatcherScriptPath $watcherScript
        return
    }

    if (-not $mainCheckout) {
        Write-UnregisteredWorktreeRefusal $worktreeFull $mainCheckout ([pscustomobject]@{
                IsRegistered = $false
                Reason       = 'main checkout path is unknown'
                GitResult    = $null
            })
        Complete-WatcherPreserved -ParamFilePath $ParamFile -WatcherScriptPath $watcherScript
        return
    }

    # --- safety: never let the watcher delete the main checkout -------------
    # The hook already refuses this, but the watcher reads paths independently
    # from the param file and is where the destructive rename + delete happen.
    if (Test-SamePath $worktreeFull $mainCheckout) {
        Write-Log "REFUSING: WorktreePath ($worktreeFull) equals MainCheckout. Will not rename/delete the main checkout."
        Remove-WatcherArtifacts -ParamFilePath $ParamFile -WatcherScriptPath $watcherScript
        return
    }

    $registration = Test-RegisteredLinkedWorktree -WorktreeFull $worktreeFull -MainCheckout $mainCheckout
    if (-not $registration.IsRegistered) {
        Write-UnregisteredWorktreeRefusal $worktreeFull $mainCheckout $registration
        Complete-WatcherPreserved -ParamFilePath $ParamFile -WatcherScriptPath $watcherScript
        return
    }

    $tempName = "$worktreeFull.removing-$script:RunId"
    $deadline = (Get-Date).AddSeconds($timeout)
    $renamed = $false
    $alreadyGone = $false
    $lastError = ''
    $nextStatus = Get-Date

    while ((Get-Date) -lt $deadline) {
        if (-not (Test-Path -LiteralPath $worktreeFull)) {
            Write-Log 'Worktree folder already gone (removed elsewhere); proceeding to prune + branch cleanup.'
            $alreadyGone = $true
            $renamed = $true
            break
        }

        try {
            [System.IO.Directory]::Move($worktreeFull, $tempName)
            $renamed = $true
            Write-Log "Atomic rename succeeded -> '$tempName'. Folder is free; proceeding to delete."
            break
        } catch {
            $lastError = $_.Exception.Message
        }

        if ((Get-Date) -ge $nextStatus) {
            $elapsed = [int]((Get-Date) - $deadline.AddSeconds(-$timeout)).TotalSeconds
            Write-DiagnosticLog "Waiting (${elapsed}s): rename blocked. LastError: $lastError"
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
            Write-Log "Deleted '$tempName'."
        } catch {
            Write-Log "Remove-Item reported an error: $($_.Exception.Message)"
            if (Test-Path -LiteralPath $tempName) {
                Write-Log "Remnant left at '$tempName' (clearly-marked; the original worktree path is already gone)."
            }
        }
    }

    if (-not $mainCheckout) {
        Write-Log 'Main checkout unknown; cannot prune git or delete branch.'
        Remove-WatcherArtifacts -ParamFilePath $ParamFile -WatcherScriptPath $watcherScript
        return
    }

    Write-GitResult 'worktree prune -v' (Invoke-GitCapture @('-C', $mainCheckout, 'worktree', 'prune', '-v'))

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
        Write-Log 'Branch name unknown; skipping branch delete.'
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
                    Write-Log "Dropped database [$dbName]."
                } elseif ($dropResult.Skipped) {
                    Write-Log "No worktree database to drop, or unexpected name (name='$dbName')."
                } else {
                    Write-Log "Could not drop database [$dbName]: $($dropResult.Error). It is likely still in use (a running API, SSMS, or test host). The database was left intact; reclaim it with 'scripts\prune-worktree-databases.ps1' or drop it manually after closing connections. Details in this log: $script:LogPath"
                }
            } catch {
                Write-Log "Could not resolve database settings from the main checkout to drop [$dbName]: $($_.Exception.Message). The database was left intact; reclaim it with 'scripts\prune-worktree-databases.ps1'."
            }
        } else {
            Write-Log 'No database name recorded; skipping database drop (prune reclaims any orphan later).'
        }

        $composeProject = [string] $cfg.ComposeProject
        if ($composeProject) {
            try {
                . (Join-Path $mainCheckout 'scripts\worktree-docker.common.ps1')
                $composeFile = Join-Path $mainCheckout 'docker-compose.yml'
                $removeResult = Remove-WorktreeDockerProject -Name $composeProject -ComposeFilePath $composeFile
                if ($removeResult.Removed) {
                    Write-Log "Removed Docker compose project [$composeProject]."
                } elseif ($removeResult.Skipped) {
                    Write-Log "No Docker compose project to remove, or unexpected name (name='$composeProject')."
                } else {
                    Write-Log "Could not remove Docker compose project [$composeProject]: $($removeResult.Error). It was left intact; reclaim it with 'scripts\prune-worktree-docker.ps1'."
                }
            } catch {
                Write-Log "Could not remove Docker compose project [$composeProject]: $($_.Exception.Message). Reclaim it with 'scripts\prune-worktree-docker.ps1'."
            }
        } else {
            Write-Log 'No compose project recorded; skipping Docker teardown (prune reclaims any orphan later).'
        }
    } else {
        Write-Log 'Skipping database drop and Docker teardown: branch was not confirmed deleted (scripts/prune-worktree-databases.ps1 and scripts/prune-worktree-docker.ps1 reclaim them later).'
    }

    # --- verify + log final state -------------------------------------------
    Write-Log 'Final state:'
    Write-Log "  worktree folder exists: $([bool](Test-Path -LiteralPath $worktreeFull))"
    if ($branchName) {
        $branchRef = "refs/heads/$branchName"
        $branchCheck = Invoke-GitCapture @('-C', $mainCheckout, 'show-ref', '--verify', '--quiet', $branchRef)
        $stillThere = $branchCheck.ExitCode -eq 0
        Write-Log "  branch '$branchName' still present: $stillThere"
    }
    Write-GitResult '  worktree list' (Invoke-GitCapture @('-C', $mainCheckout, 'worktree', 'list'))
    if (-not $branchDeleteAttempted) {
        Write-Log 'Watcher done (worktree removed; branch skipped).'
    } elseif ($branchDeleteSucceeded) {
        Write-Log 'Watcher done (worktree + branch removed).'
    } else {
        Write-Log 'Watcher done (worktree removed; branch preserved).'
    }

    Remove-WatcherArtifacts -ParamFilePath $ParamFile -WatcherScriptPath $watcherScript
}

function Complete-WatcherPreserved {
    param([string] $ParamFilePath, [string] $WatcherScriptPath)

    Write-Log 'Watcher done (worktree preserved).'
    Remove-WatcherArtifacts -ParamFilePath $ParamFilePath -WatcherScriptPath $WatcherScriptPath
}

function Remove-WatcherArtifacts {
    param([string] $ParamFilePath, [string] $WatcherScriptPath)
    Remove-GeneratedTempArtifact -Path $ParamFilePath -LeafPattern 'ahkflowapp-wt-remove-*.json' -Description 'watcher param file'
    Remove-GeneratedTempArtifact -Path $WatcherScriptPath -LeafPattern 'ahkflowapp-wt-remove-watcher-*.ps1' -Description 'watcher script'
}

function Remove-GeneratedTempArtifact {
    param(
        [string] $Path,
        [string] $LeafPattern,
        [string] $Description
    )

    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
        return
    }

    if (-not (Test-GeneratedTempArtifactPath -Path $Path -LeafPattern $LeafPattern)) {
        Write-Log "Skipping deletion of non-generated $Description '$Path'."
        return
    }

    try {
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
    } catch {
        Write-Log "Could not delete temp artifact '$Path': $($_.Exception.Message)"
    }
}

function Test-GeneratedTempArtifactPath {
    param(
        [string] $Path,
        [string] $LeafPattern
    )

    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path)
        $tempRoot = [System.IO.Path]::GetFullPath((Get-RemovalTempDir)).TrimEnd('\', '/')
    } catch {
        return $false
    }

    $leaf = Split-Path -Leaf $fullPath
    if ($leaf -notlike $LeafPattern) {
        return $false
    }

    return $fullPath.StartsWith($tempRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)
}

# ===========================================================================
# Entry point
# ===========================================================================
try {
    if ($Mode -eq 'Watcher') {
        Invoke-WatcherMode
    } else {
        Invoke-HookMode
    }
} catch {
    try { Write-Log "UNHANDLED ERROR: $($_.Exception.Message)" } catch { }
}

exit 0
