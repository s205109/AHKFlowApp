#Requires -Version 5.1
<#
.SYNOPSIS
  One exclusive lock shared by every local test run that builds and runs .NET tests.
.DESCRIPTION
  Two overlapping runs build into the same bin folders and instrument the same assemblies.
  Backlog 082 measured the result: coverlet cannot write the module it is instrumenting,
  writes no coverage file for that project, and dotnet test still exits 0. The coverage gate
  then reports a threshold failure that has nothing to do with coverage.

  The lock is one file per repository root, held open with FileShare::None for the life of
  the run. A second run cannot open it and fails immediately with a message naming the holder.
  The open handle blocks, never the file. The release step closes the handle and leaves the
  file, so the file is present between runs and a run always takes the lock again.

  A blocked run cannot read the lock file itself, because the holder shares nothing. So the
  holder also writes a readable sibling file describing itself. That file is advisory only.
  A killed run leaves it behind while Windows releases the real handle, so its presence alone
  must never block anybody.
#>

function Get-AhkFlowTestRunLockPath {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)
    return (Join-Path $RepoRoot '.test-run.lock')
}

function Get-AhkFlowTestRunLockOwnerPath {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)
    return (Join-Path $RepoRoot '.test-run.lock.owner')
}

function Enter-AhkFlowTestRunLock {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Mode
    )

    $lockPath = Get-AhkFlowTestRunLockPath -RepoRoot $RepoRoot
    $ownerPath = Get-AhkFlowTestRunLockOwnerPath -RepoRoot $RepoRoot

    try {
        $stream = [System.IO.File]::Open(
            $lockPath,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None)
    }
    catch [System.IO.IOException] {
        $holder = 'unknown'
        if (Test-Path -LiteralPath $ownerPath) {
            $holder = (Get-Content -LiteralPath $ownerPath -Raw -ErrorAction SilentlyContinue).Trim()
        }

        throw @"
Another AHKFlowApp test run holds the test-run lock, so this $Mode run cannot start.
Holder: $holder
Lock file: $lockPath

Two overlapping runs build into the same bin folders and instrument the same assemblies.
That destroys coverage data and produces a coverage failure with no real cause.
Wait for the other run to finish, then start this one again.
Only a live run blocks you. A lock file left behind by an earlier run does not.
"@
    }

    $description = "Mode=$Mode; ProcessId=$PID; Started=$([DateTime]::UtcNow.ToString('o'))"
    Set-Content -LiteralPath $ownerPath -Value $description -Encoding utf8

    return [pscustomobject]@{
        Path      = $lockPath
        OwnerPath = $ownerPath
        Stream    = $stream
    }
}

function Exit-AhkFlowTestRunLock {
    param([object]$Handle)

    if (-not $Handle) { return }

    if ($Handle.Stream) {
        try { $Handle.Stream.Dispose() } catch { }
    }

    if ($Handle.OwnerPath) {
        Remove-Item -LiteralPath $Handle.OwnerPath -Force -ErrorAction SilentlyContinue
    }
}
