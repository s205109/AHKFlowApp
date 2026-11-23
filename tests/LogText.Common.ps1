#Requires -Version 5.1

# Log reads for suites that read a log while another process may still write it.
# Backlog 217 moved Read-LogText here from tests/WorktreeRemoveHook.Tests.ps1, where backlog 216
# added it.
#
# A suite loads this file with:
#     . (Join-Path $PSScriptRoot 'LogText.Common.ps1')
#
# The file needs Windows PowerShell 5.1, not 7.0, because suites on both hosts load it.
# The .Common.ps1 name keeps the runner from running this file as a suite. The runner looks only
# for *.Tests.ps1.
# The file does not call Set-StrictMode, because that call leaks into the scope of the caller.

# Reads a whole log file as one string, even while another process appends to it.
function Read-LogText {
    param([Parameter(Mandatory = $true)] [string] $Path)

    # Not Get-Content -Raw. Backlog 216 saw it return an array while the watcher appended to the
    # log, and an array turns -match into a filter. One ReadToEnd() call returns one string.
    # The share must include Write: the writer holds the log open for writing, and Windows refuses
    # a reader that does not share Write with it. Delete lets the writer rotate the log meanwhile.
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]'ReadWrite, Delete')
    $reader = $null
    try {
        $reader = New-Object System.IO.StreamReader($stream, (New-Object System.Text.UTF8Encoding($false)), $true)
        return $reader.ReadToEnd()
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
        $stream.Dispose()
    }
}
