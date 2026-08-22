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
$processes = @()

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
    $cwdProc = Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -PassThru `
        -WorkingDirectory $cwdDir `
        -ArgumentList @('-NoProfile', '-Command', 'Start-Sleep -Seconds 60')
    $processes += $cwdProc
    Start-Sleep -Seconds 2
    $cwdHolders = @(Get-WorktreeFolderHolder -Path $cwdDir)
    Assert-True (@($cwdHolders | Where-Object { $_.ProcessId -eq $cwdProc.Id }).Count -eq 1) `
        "The current-directory holder (PID $($cwdProc.Id)) must be named"

    # --- an open-file holder ----------------------------------------------
    $fileDir = Join-Path $temp 'openfile'
    New-Item -ItemType Directory -Path $fileDir -Force | Out-Null
    $held = Join-Path $fileDir 'held.txt'
    Set-Content -LiteralPath $held -Value 'x'
    $fileProc = Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -PassThru `
        -WorkingDirectory ([System.IO.Path]::GetTempPath()) `
        -ArgumentList @('-NoProfile', '-Command',
            "`$s = [System.IO.File]::Open('$held', 'Open', 'Read', 'None'); Start-Sleep -Seconds 60; `$s.Dispose()")
    $processes += $fileProc
    Start-Sleep -Seconds 2
    $fileHolders = @(Get-WorktreeFolderHolder -Path $fileDir)
    Assert-True (@($fileHolders | Where-Object { $_.ProcessId -eq $fileProc.Id }).Count -eq 1) `
        "The open-file holder (PID $($fileProc.Id)) must be named"

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
