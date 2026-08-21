#Requires -Version 5.1
# The two worktree cleanup logs.
#
#   worktree-removal.log             One line per removal attempt. Nothing else.
#                                    2026-06-05 14:03:11  my-feature  Removed.
#   worktree-removal-diagnostics.log Everything else, same line shape, capped at 5 MB.
#
# Both are written by processes that run at the same time: one sweep starts several detached
# watchers. So an append that loses a race is retried rather than dropped. Losing the outcome
# line loses the whole record of what happened to a worktree.

$script:WorktreeLogMaxBytes = 5MB
$script:WorktreeLogAppendAttempts = 10
$script:WorktreeLogRetryDelayMs = 50
$script:WorktreeLogReasonMaxLength = 300

# Flattens any text that reaches a log line from outside: a human's lock reason, a .NET
# exception message. One line per attempt is a promise this file keeps, not a hope about inputs.
function Format-WorktreeLogReason {
    param([string] $Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return 'no reason given' }

    $flat = $Text -replace '[\r\n\t]+', ' '
    $flat = ($flat -replace '\s{2,}', ' ').Trim()

    if ($flat.Length -gt $script:WorktreeLogReasonMaxLength) {
        $flat = $flat.Substring(0, $script:WorktreeLogReasonMaxLength - 1) + [char] 0x2026
    }

    return $flat
}

# The diagnostics log always sits beside the outcome log, so one path implies the other and no
# caller has to build the second one.
function Get-WorktreeDiagnosticsPath {
    param([Parameter(Mandatory)][string] $OutcomeLogPath)

    $directory = Split-Path -Parent $OutcomeLogPath
    $leaf = [System.IO.Path]::GetFileNameWithoutExtension($OutcomeLogPath)
    $extension = [System.IO.Path]::GetExtension($OutcomeLogPath)
    return Join-Path $directory ($leaf + '-diagnostics' + $extension)
}

function Resolve-WorktreeLogPath {
    param([Parameter(Mandatory)][string] $LogPath)

    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogPath)
    $directory = Split-Path -Parent $resolved
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    return $resolved
}

# Appends one line, retrying while another process holds the file. Returns $true when the line
# landed. Never throws: a logger that throws takes the caller down with it.
function Add-WorktreeLogLine {
    param(
        [Parameter(Mandatory)][string] $ResolvedPath,
        [Parameter(Mandatory)][string] $Line
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $random = New-Object System.Random
    for ($attempt = 1; $attempt -le $script:WorktreeLogAppendAttempts; $attempt++) {
        try {
            $stream = [System.IO.File]::Open($ResolvedPath, 'Append', 'Write', 'Read')
            try {
                $bytes = $utf8NoBom.GetBytes($Line + [Environment]::NewLine)
                $stream.Write($bytes, 0, $bytes.Length)
            } finally {
                $stream.Dispose()
            }
            return $true
        } catch {
            # Jitter, so several watchers that collided do not retry in lockstep forever.
            Start-Sleep -Milliseconds ($script:WorktreeLogRetryDelayMs + $random.Next(0, 40))
        }
    }

    return $false
}

function Format-WorktreeLogLine {
    param([string] $Worktree, [string] $Message)

    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    # The message is flattened too, not only the reasons callers build. A caller that
    # interpolates an exception straight into $Message must not be able to break the shape.
    $single = $Message -replace '[\r\n]+', ' '
    return '{0}  {1}  {2}' -f $stamp, $Worktree, $single
}

# The outcome log. One line per removal attempt.
function Write-WorktreeLog {
    param(
        [Parameter(Mandatory)][string] $LogPath,
        [Parameter(Mandatory)][string] $Worktree,
        [Parameter(Mandatory)][string] $Message
    )

    $line = Format-WorktreeLogLine -Worktree $Worktree -Message $Message

    try {
        $resolved = Resolve-WorktreeLogPath -LogPath $LogPath
        if (Add-WorktreeLogLine -ResolvedPath $resolved -Line $line) { return }
    } catch { }

    # Every fallback below is worse than the log, and all of them beat silence.
    try { [Console]::Error.WriteLine("worktree-log: could not write the outcome line: $line") } catch { }
    try {
        $rescue = Join-Path ([System.IO.Path]::GetTempPath()) 'worktree-removal-rescue.log'
        [System.IO.File]::AppendAllText($rescue, $line + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
    } catch { }
}

# The diagnostics log. Everything that is not an outcome.
function Write-WorktreeDiagnostic {
    param(
        [Parameter(Mandatory)][string] $LogPath,
        [Parameter(Mandatory)][string] $Worktree,
        [Parameter(Mandatory)][string] $Message
    )

    try {
        $resolved = Resolve-WorktreeLogPath -LogPath $LogPath
        Invoke-WorktreeLogRotation -ResolvedPath $resolved
        $line = Format-WorktreeLogLine -Worktree $Worktree -Message $Message
        if (Add-WorktreeLogLine -ResolvedPath $resolved -Line $line) { return }
    } catch { }

    try { [Console]::Error.WriteLine("worktree-log: could not write a diagnostic: $Message") } catch { }
}

# Rotation behind a cross-process lock. This is NOT Invoke-WithFileLock from
# setup-worktree-local-dev.ps1: that one waits 30 seconds and throws on timeout, which is right
# for allocating a port and wrong for writing a log. Here a lock that cannot be taken means skip
# rotation and append anyway. An oversized log is a nuisance; a lost line is a defect.
function Invoke-WorktreeLogRotation {
    param([Parameter(Mandatory)][string] $ResolvedPath)

    if (-not (Test-Path -LiteralPath $ResolvedPath)) { return }
    $info = Get-Item -LiteralPath $ResolvedPath -Force
    if ($info.Length -lt $script:WorktreeLogMaxBytes) { return }

    $lockPath = "$ResolvedPath.rotate-lock"
    $stream = $null
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(1)
    while (-not $stream -and [DateTimeOffset]::UtcNow -lt $deadline) {
        try {
            $stream = [System.IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
        } catch {
            Start-Sleep -Milliseconds 50
        }
    }

    if (-not $stream) { return }

    try {
        # Re-check under the lock. Another writer may have rotated while this one waited.
        if (-not (Test-Path -LiteralPath $ResolvedPath)) { return }
        if ((Get-Item -LiteralPath $ResolvedPath -Force).Length -lt $script:WorktreeLogMaxBytes) { return }

        $previous = "$ResolvedPath.1"
        if (Test-Path -LiteralPath $previous) { Remove-Item -LiteralPath $previous -Force }
        Move-Item -LiteralPath $ResolvedPath -Destination $previous -Force
    } catch {
    } finally {
        $stream.Dispose()
    }
}
