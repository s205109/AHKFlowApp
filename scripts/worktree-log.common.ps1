#Requires -Version 5.1
# Shared human-readable worktree log. One line per event:
#   2026-06-05 14:03:11  my-feature  Removed worktree folder.
# Diagnostics belong on stderr (Write-DiagnosticLog), not in this file.
function Write-WorktreeLog {
    param(
        [Parameter(Mandatory)][string] $LogPath,
        [Parameter(Mandatory)][string] $Worktree,
        [Parameter(Mandatory)][string] $Message
    )

    # Resolve to a full filesystem path (honours the caller's PS location for a
    # relative -LogPath) so the parent-dir check and the .NET append agree.
    $resolvedLogPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogPath)

    $directory = Split-Path -Parent $resolvedLogPath
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = '{0}  {1}  {2}' -f $stamp, $Worktree, $Message
    # UTF-8 without BOM, regardless of caller or PowerShell edition (Add-Content's
    # default encoding is the ANSI code page in 5.1, which corrupts non-ASCII).
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::AppendAllText($resolvedLogPath, $line + [Environment]::NewLine, $utf8NoBom)
}
