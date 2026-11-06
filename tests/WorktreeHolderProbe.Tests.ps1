#Requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$suiteRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$scriptsDir = Join-Path $suiteRoot 'scripts'
. (Join-Path $scriptsDir 'worktree-holder.common.ps1')

function Assert-True {
    param($Condition, [string] $Message)
    if ($Condition -isnot [bool]) {
        $caller = (Get-PSCallStack)[1]
        $typeName = if ($null -eq $Condition) { 'null' } else { $Condition.GetType().FullName }
        throw ("Assert-True needs a boolean. Got [$typeName] with $(@($Condition).Count) value(s) " +
            "from line $($caller.ScriptLineNumber): $(@($Condition) -join ' | '). Original message: $Message")
    }
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [string] $Message)
    if (-not [string]::Equals([string] $Expected, [string] $Actual, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Message (expected '$Expected', got '$Actual')"
    }
}

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ("ahkflow-holder-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $temp -Force | Out-Null
$readyDir = Join-Path $temp 'ready'
New-Item -ItemType Directory -Path $readyDir -Force | Out-Null
$processes = @()

# Starts a holder child and waits until it reports that its setup ran. A fixed wait guessed how
# long that takes, and the Gate runs many suites at once (issue 450). The ready file lives outside
# every probed folder, so it cannot make a holder of its own.
function Start-HolderChild {
    param([string] $Name, [string] $WorkingDirectory, [string] $Setup = '')

    $ready = Join-Path $readyDir "$Name.ready"
    $command = "$Setup; Set-Content -LiteralPath '$ready' -Value ready; Start-Sleep -Seconds 60"
    $process = Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -PassThru `
        -WorkingDirectory $WorkingDirectory -ArgumentList @('-NoProfile', '-Command', $command)
    $script:processes += $process

    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    while (-not (Test-Path -LiteralPath $ready)) {
        if ($process.HasExited) {
            throw "The $Name holder (PID $($process.Id)) exited with code $($process.ExitCode) before it was ready."
        }
        if ([DateTime]::UtcNow -gt $deadline) {
            throw "The $Name holder (PID $($process.Id)) was not ready after 60 seconds."
        }
        Start-Sleep -Milliseconds 100
    }
    return $process
}

# Says why a holder was not named, so a failure that does not reproduce still leaves evidence.
function Get-HolderMissReport {
    param([System.Diagnostics.Process] $Process)

    $alive = -not $Process.HasExited
    $exit = if ($alive) { 'none' } else { [string] $Process.ExitCode }
    $directory = Get-ProcessCurrentDirectory -ProcessId $Process.Id
    return "alive=$alive exit=$exit currentDirectory='$directory' pebType=$($script:HolderCwdTypeAdded) rmType=$($script:HolderRmTypeAdded)"
}

try {
    # --- nothing holds an empty folder ------------------------------------
    $idle = Join-Path $temp 'idle'
    New-Item -ItemType Directory -Path $idle -Force | Out-Null
    $none = @(Get-WorktreeFolderHolder -Path $idle)
    Assert-Equal 0 $none.Count "An unheld folder must name no holder, got $($none.Count)"
    Assert-Equal '' (Format-HolderSummary -Holder $none) 'No holders formats as an empty string'

    # --- a current-directory holder ---------------------------------------
    $cwdDir = Join-Path $temp 'cwd'
    New-Item -ItemType Directory -Path $cwdDir -Force | Out-Null
    $cwdProc = Start-HolderChild -Name 'cwd' -WorkingDirectory $cwdDir
    $cwdHolders = @(Get-WorktreeFolderHolder -Path $cwdDir)
    $cwdNamed = @($cwdHolders | Where-Object { $_.ProcessId -eq $cwdProc.Id }).Count -eq 1
    Assert-True $cwdNamed `
        "The current-directory holder (PID $($cwdProc.Id)) must be named. $(if (-not $cwdNamed) { Get-HolderMissReport -Process $cwdProc })"

    # --- an open-file holder ----------------------------------------------
    $fileDir = Join-Path $temp 'openfile'
    New-Item -ItemType Directory -Path $fileDir -Force | Out-Null
    $held = Join-Path $fileDir 'held.txt'
    Set-Content -LiteralPath $held -Value 'x'
    # The child exits after its sleep, and the OS closes the file then. So the setup needs no Dispose.
    $fileProc = Start-HolderChild -Name 'openfile' -WorkingDirectory ([System.IO.Path]::GetTempPath()) `
        -Setup "`$s = [System.IO.File]::Open('$held', 'Open', 'Read', 'None')"
    $fileHolders = @(Get-WorktreeFolderHolder -Path $fileDir)
    $fileNamed = @($fileHolders | Where-Object { $_.ProcessId -eq $fileProc.Id }).Count -eq 1
    Assert-True $fileNamed `
        "The open-file holder (PID $($fileProc.Id)) must be named. $(if (-not $fileNamed) { Get-HolderMissReport -Process $fileProc })"

    # --- a sibling folder with the same prefix is not a holder --------------
    # Every worktree sits in one parent folder, so wt-feature and wt-feature-extra are siblings.
    # A plain StartsWith on the root would report the second as holding the first, and the human
    # would go and close the wrong window.
    $sibling = $cwdDir + '-extra'
    New-Item -ItemType Directory -Path $sibling -Force | Out-Null
    $siblingProc = Start-HolderChild -Name 'sibling' -WorkingDirectory $sibling
    $siblingHolders = @(Get-WorktreeFolderHolder -Path $cwdDir)
    Assert-Equal 0 (@($siblingHolders | Where-Object { $_.ProcessId -eq $siblingProc.Id })).Count `
        "A process in '$sibling' must not be reported as holding '$cwdDir'"
    # The real holder is still found, so the fix narrowed the match rather than breaking it.
    Assert-True (@($siblingHolders | Where-Object { $_.ProcessId -eq $cwdProc.Id }).Count -eq 1) `
        "The real current-directory holder (PID $($cwdProc.Id)) must still be named"

    # --- deduplication by PID ---------------------------------------------
    $allIds = @(Get-WorktreeFolderHolder -Path $cwdDir | ForEach-Object { $_.ProcessId })
    Assert-Equal $allIds.Count (@($allIds | Sort-Object -Unique)).Count 'Holders must be deduplicated by process ID'

    # --- the summary shape -------------------------------------------------
    $three = @(
        [pscustomobject]@{ ProcessId = 1; Name = 'alpha'; Path = 'a'; Layer = 'cwd' }
        [pscustomobject]@{ ProcessId = 2; Name = 'beta';  Path = 'b'; Layer = 'cwd' }
        [pscustomobject]@{ ProcessId = 3; Name = 'gamma'; Path = 'c'; Layer = 'cwd' }
    )
    Assert-Equal 'alpha (PID 1) and beta (PID 2), and 1 more' (Format-HolderSummary -Holder $three) `
        'Three holders format as two named plus a count'

    Write-Host 'Worktree holder probe tests passed.'
} finally {
    foreach ($p in $processes) {
        try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch { }
    }
    Start-Sleep -Milliseconds 500
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
