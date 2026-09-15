#Requires -Version 7.0

function New-PinnedLanePool {
    param([Parameter(Mandatory = $true)][ValidateRange(1, 98)][int] $Capacity)
    $root = Join-Path ([IO.Path]::GetTempPath()) ('ahkflow-lane-pool-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $root -ErrorAction Stop | Out-Null
    Set-Content -LiteralPath (Join-Path $root 'capacity.txt') -Value $Capacity -Encoding ascii
    $pin = [IO.File]::Open((Join-Path $root 'lane-99.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    [pscustomobject]@{ Root = $root; Pin = $pin; Capacity = $Capacity }
}

function Remove-PinnedLanePool {
    param($Pool)
    if ($null -eq $Pool) { return }
    if ($null -ne $Pool.Pin) { $Pool.Pin.Dispose() }
    Remove-Item -LiteralPath $Pool.Root -Recurse -Force -ErrorAction Stop
}

function Get-RunLaneCount { param($Pool); (Get-AhkFlowHeldLaneCount -PoolRoot $Pool.Root) - 1 }

function Use-LaneEnvironment {
    param([hashtable] $Value = @{}, [Parameter(Mandatory = $true)][scriptblock] $Body)
    $names = @('AHKFLOW_TEST_LANES', 'AHKFLOW_TEST_LANES_HOLDER', 'AHKFLOW_TEST_LANES_ROOT')
    $saved = @{}
    foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process'); [Environment]::SetEnvironmentVariable($name, $null, 'Process') }
    try { foreach ($name in $Value.Keys) { [Environment]::SetEnvironmentVariable($name, [string]$Value[$name], 'Process') }; & $Body }
    finally { foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') } }
}

function ConvertTo-LaneEncodedCommand([string] $Text) {
    [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Text))
}

function Start-LaneChildProcess {
    param([Parameter(Mandatory = $true)][string[]] $ArgumentList)
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $info.ArgumentList.Clear()
    foreach ($argument in $ArgumentList) { [void]$info.ArgumentList.Add($argument) }
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true; $info.RedirectStandardInput = $true
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $info
    if (-not $process.Start()) { throw 'Failed to start Lane child process.' }
    [pscustomobject]@{ Process = $process; Stdout = $process.StandardOutput.ReadToEndAsync(); Stderr = $process.StandardError.ReadToEndAsync(); Stopped = $false }
}

function Stop-LaneChildProcess {
    param($Child)
    if ($null -eq $Child -or $Child.Stopped) { return }
    if (-not $Child.Process.HasExited) { $Child.Process.Kill($true) }
    if (-not $Child.Process.WaitForExit(5000)) { throw 'Lane child could not be reaped.' }
    if (-not $Child.Stdout.Wait(5000) -or -not $Child.Stderr.Wait(5000)) { throw 'Lane child output did not settle.' }
    $Child.Process.Dispose()
    $Child.Stopped = $true
}

function Wait-LaneChildProcess {
    param($Child, [Parameter(Mandatory = $true)][int] $TimeoutSeconds)
    $timedOut = -not $Child.Process.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) { Stop-LaneChildProcess $Child; throw "Lane child timed out after $TimeoutSeconds seconds." }
    if (-not $Child.Stdout.Wait(5000) -or -not $Child.Stderr.Wait(5000)) { throw 'Lane child output did not settle.' }
    [pscustomobject]@{ ExitCode = $Child.Process.ExitCode; TimedOut = $false; Output = $Child.Stdout.Result; Error = $Child.Stderr.Result }
}

function Wait-LanePath {
    param([string] $Path, [int] $TimeoutSeconds, $Child)
    $watch = [Diagnostics.Stopwatch]::StartNew()
    while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        if (Test-Path -LiteralPath "$Path.done") { return (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop) }
        if ($null -ne $Child -and $Child.Process.HasExited) { throw "Lane child exited before publishing '$Path'." }
        Start-Sleep -Milliseconds 50
    }
    throw "Timed out waiting for completed Lane signal '$Path'."
}

function Start-LaneHolder {
    param([string] $PoolRoot, [hashtable] $Signals, [string] $Tag, [string] $Share, [int] $Proposal, [string] $ModulePath)
    if ([string]::IsNullOrWhiteSpace($ModulePath)) { $ModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/test-lanes.common.ps1' }
    $module = $ModulePath.Replace("'", "''")
    $root = $PoolRoot.Replace("'", "''"); $acquired = ([string]$Signals.Acquired).Replace("'", "''"); $release = ([string]$Signals.Release).Replace("'", "''")
    $wrapper = "function Start-Sleep { param(`$Milliseconds); if (`$parentProcess.HasExited) { throw 'Lane fixture parent exited.' }; Microsoft.PowerShell.Utility\Start-Sleep -Milliseconds `$Milliseconds }; `$realResolve=`${function:Resolve-AhkFlowLaneCapacity}; `$script:resolving=`$false; function Resolve-AhkFlowLaneCapacity { param(`$PoolRoot,`$Proposal); `$script:resolving=`$true; try { & `$realResolve -PoolRoot `$PoolRoot -Proposal `$Proposal } finally { `$script:resolving=`$false } }; "
    if ($Signals.ContainsKey('FailedAttempt')) {
        $failed = ([string]$Signals.FailedAttempt).Replace("'", "''")
        $wrapper += "`$realOpen=`${function:Open-AhkFlowLaneFile}; function Open-AhkFlowLaneFile { param([string]`$Path); `$opened=& `$realOpen -Path `$Path; if (`$null -eq `$opened -and -not `$script:resolving -and -not (Test-Path '$failed.done')) { Publish-LaneSignal '$failed' `$Path }; `$opened }; "
    }
    if ($Signals.ContainsKey('CapacityWait')) {
        $capacityWait = ([string]$Signals.CapacityWait).Replace("'", "''")
        $resume = ([string]$Signals.Resume).Replace("'", "''")
        $wrapper += "`$script:invalidCapacity=`$false; function Resolve-AhkFlowLaneCapacity { param(`$PoolRoot,`$Proposal); `$c=& `$realResolve -PoolRoot `$PoolRoot -Proposal `$Proposal; if (`$c -eq 0) { `$script:invalidCapacity=`$true }; `$c }; function Start-Sleep { param(`$Milliseconds); if (`$parentProcess.HasExited) { throw 'Lane fixture parent exited.' }; if (`$script:invalidCapacity) { `$script:invalidCapacity=`$false; Publish-LaneSignal '$capacityWait' waiting; Wait-LanePath '$resume' 15 | Out-Null }; Microsoft.PowerShell.Utility\Start-Sleep -Milliseconds `$Milliseconds }; "
    }
    $common = $PSCommandPath.Replace("'", "''")
    $code = "`$ErrorActionPreference='Stop'; . '$module'; . '$common'; `$parentProcess=[Diagnostics.Process]::GetProcessById($PID); $wrapper`$h=`$null; try { `$h=Enter-AhkFlowLanes -PoolRoot '$root' -Share '$Share' -Proposal $Proposal; Publish-LaneSignal '$acquired' ('$Tag|' + `$h.Capacity + '|' + `$h.Streams.Count); Wait-LanePath '$release' 30 | Out-Null } finally { Exit-AhkFlowLanes `$h; `$parentProcess.Dispose() }"
    Start-LaneChildProcess -ArgumentList @('-NoProfile', '-EncodedCommand', (ConvertTo-LaneEncodedCommand $code))
}

function Publish-LaneSignal {
    param([string] $Path, [string] $Value = 'released')
    # Publish data first. Readers only inspect it after the completion marker exists.
    Set-Content -LiteralPath $Path -Value $Value -ErrorAction Stop
    Set-Content -LiteralPath "$Path.done" -Value complete -ErrorAction Stop
}

function Add-LaneIntervalSuite {
    param([System.Collections.IList] $Suite, [string] $Tag, [string] $StartPath, [string] $ReleasePath, [string] $FinishPath)
    $suitePath = Join-Path (Split-Path $StartPath -Parent) "$Tag.Tests.ps1"
    $common = $PSCommandPath.Replace("'", "''")
    $start = $StartPath.Replace("'", "''"); $release = $ReleasePath.Replace("'", "''"); $finish = $FinishPath.Replace("'", "''")
    Set-Content -LiteralPath $suitePath -Value ". '$common'; Publish-LaneSignal '$start' ([Diagnostics.Stopwatch]::GetTimestamp()); Wait-LanePath '$release' 30 | Out-Null; Publish-LaneSignal '$finish' ([Diagnostics.Stopwatch]::GetTimestamp())"
    [void]$Suite.Add([pscustomobject]@{ Tag = $Tag; Path = $suitePath; StartPath = $StartPath; ReleasePath = $ReleasePath; FinishPath = $FinishPath })
}

function Get-LanePeakOverlap {
    param([Parameter(Mandatory = $true)][object[]] $Intervals)
    $events = foreach ($item in $Intervals) { [pscustomobject]@{ Time = [long]$item.Start; Delta = 1 }; [pscustomobject]@{ Time = [long]$item.End; Delta = -1 } }
    $current = 0; $peak = 0
    foreach ($event in @($events | Sort-Object Time, @{ Expression = 'Delta'; Ascending = $true })) { $current += $event.Delta; if ($current -gt $peak) { $peak = $current } }
    $peak
}
