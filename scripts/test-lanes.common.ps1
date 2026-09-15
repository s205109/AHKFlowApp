# Shared machine-wide test Lane pool. This file must load in Windows PowerShell 5.1.

. (Join-Path $PSScriptRoot 'suite-worker-count.common.ps1')

function Get-AhkFlowLanePoolRoot {
    if (-not [string]::IsNullOrWhiteSpace($env:AHKFLOW_TEST_LANES_ROOT)) {
        return $env:AHKFLOW_TEST_LANES_ROOT.Trim()
    }

    $localData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($localData)) {
        throw 'The per-user LocalApplicationData folder is unavailable.'
    }
    return (Join-Path (Join-Path $localData 'AHKFlowApp') 'test-lanes')
}

function Get-AhkFlowLaneRole {
    $setting = $env:AHKFLOW_TEST_LANES
    if (-not [string]::IsNullOrWhiteSpace($setting)) {
        if ($setting.Trim() -ieq 'off') { return 'off' }
        throw "AHKFLOW_TEST_LANES must be empty or 'off'. Got '$setting'."
    }
    if (-not [string]::IsNullOrWhiteSpace($env:AHKFLOW_TEST_LANES_HOLDER)) { return 'nested' }
    return 'owner'
}

function Enter-AhkFlowLaneOwnership {
    $previous = $env:AHKFLOW_TEST_LANES_HOLDER
    $env:AHKFLOW_TEST_LANES_HOLDER = [string]$PID
    return $previous
}

function Exit-AhkFlowLaneOwnership {
    param($Previous)
    if ($null -eq $Previous) { Remove-Item Env:\AHKFLOW_TEST_LANES_HOLDER -ErrorAction SilentlyContinue }
    else { $env:AHKFLOW_TEST_LANES_HOLDER = [string]$Previous }
}

function Get-AhkFlowLaneProposal {
    param([int] $PhysicalCoreCount)
    if ($env:GITHUB_ACTIONS -ieq 'true') {
        return (Get-DefaultSuiteWorkerCount -AllProcessors)
    }
    if (-not $PSBoundParameters.ContainsKey('PhysicalCoreCount')) { $PhysicalCoreCount = Get-PhysicalCoreCount }
    return (Get-DefaultSuiteWorkerCount -PhysicalCoreCount $PhysicalCoreCount)
}

function Test-AhkFlowLaneContention {
    param([Parameter(Mandatory = $true)][System.Exception] $Exception)
    if ($Exception.GetType().FullName -cne 'System.IO.IOException') { return $false }
    if ([System.IO.Path]::DirectorySeparatorChar -eq '\') { return ([int]$Exception.HResult -eq -2147024864) }
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Linux)) {
        return ([int]$Exception.HResult -eq 11)
    }
    return $false
}

function Open-AhkFlowLaneFile {
    param([Parameter(Mandatory = $true)][string] $Path)
    try {
        return [System.IO.File]::Open($Path, 'OpenOrCreate', 'ReadWrite', 'None')
    } catch [System.IO.IOException] {
        $failure = $_.Exception
        while ($failure.GetType().Namespace -eq 'System.Management.Automation' -and $null -ne $failure.InnerException) {
            $failure = $failure.InnerException
        }
        if (Test-AhkFlowLaneContention -Exception $failure) { return $null }
        throw
    }
}

function Test-AhkFlowLaneFileHeld {
    param([Parameter(Mandatory = $true)][string] $Path)
    if (-not [System.IO.File]::Exists($Path)) { return $false }
    $stream = Open-AhkFlowLaneFile -Path $Path
    if ($null -eq $stream) { return $true }
    $stream.Dispose()
    return $false
}

function Resolve-AhkFlowLaneCapacity {
    param(
        [Parameter(Mandatory = $true)][string] $PoolRoot,
        [Parameter(Mandatory = $true)][ValidateRange(1, [int]::MaxValue)][int] $Proposal
    )
    $held = $false
    foreach ($file in @(Get-ChildItem -LiteralPath $PoolRoot -Filter 'lane-*.lock' -File -ErrorAction Stop)) {
        if (Test-AhkFlowLaneFileHeld -Path $file.FullName) { $held = $true; break }
    }
    $capacityPath = Join-Path $PoolRoot 'capacity.txt'
    if (-not $held) {
        Set-Content -LiteralPath $capacityPath -Value ([string]$Proposal) -Encoding ascii -ErrorAction Stop
        return $Proposal
    }
    try {
        $text = Get-Content -LiteralPath $capacityPath -Raw -ErrorAction Stop
        $capacity = 0
        if ([int]::TryParse($text.Trim(), [ref]$capacity) -and $capacity -gt 0) { return $capacity }
    } catch { }
    return 0
}

function Get-AhkFlowLaneShareCount {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('One', 'Half', 'Whole')][string] $Share,
        [Parameter(Mandatory = $true)][ValidateRange(1, [int]::MaxValue)][int] $Capacity
    )
    if ($Share -eq 'One') { return 1 }
    if ($Share -eq 'Half') { return [int][Math]::Ceiling($Capacity / 2.0) }
    return $Capacity
}

function Enter-AhkFlowLanes {
    param(
        [Parameter(Mandatory = $true)][string] $PoolRoot,
        [Parameter(Mandatory = $true)][ValidateSet('One', 'Half', 'Whole')][string] $Share,
        [Parameter(Mandatory = $true)][ValidateRange(1, [int]::MaxValue)][int] $Proposal,
        [object] $Run
    )
    New-Item -ItemType Directory -Path $PoolRoot -Force -ErrorAction Stop | Out-Null
    $entry = $null
    $lanes = New-Object System.Collections.Generic.List[System.IO.FileStream]
    $completed = $false
    try {
        $capacity = 0
        while ($capacity -lt 1) {
            $entry = Open-AhkFlowLaneFile -Path (Join-Path $PoolRoot 'entry.lock')
            if ($null -ne $entry) {
                $capacity = Resolve-AhkFlowLaneCapacity -PoolRoot $PoolRoot -Proposal $Proposal
                if ($capacity -lt 1) { $entry.Dispose(); $entry = $null }
            }
            if ($capacity -lt 1) { Wait-AhkFlowLaneRetry -Run $Run }
        }
        $needed = Get-AhkFlowLaneShareCount -Share $Share -Capacity $capacity
        while ($lanes.Count -lt $needed) {
            for ($index = 0; $index -lt $capacity -and $lanes.Count -lt $needed; $index++) {
                $path = Join-Path $PoolRoot "lane-$index.lock"
                $alreadyHeld = $false
                foreach ($lane in $lanes) { if ($lane.Name -eq $path) { $alreadyHeld = $true; break } }
                if ($alreadyHeld) { continue }
                $stream = Open-AhkFlowLaneFile -Path $path
                if ($null -ne $stream) { $lanes.Add($stream) }
            }
            if ($lanes.Count -lt $needed) { Wait-AhkFlowLaneRetry -Run $Run }
        }
        $completed = $true
        return [pscustomobject]@{ PoolRoot = $PoolRoot; Capacity = $capacity; Streams = $lanes }
    } finally {
        if (-not $completed) { foreach ($lane in $lanes) { $lane.Dispose() } }
        if ($null -ne $entry) { $entry.Dispose() }
    }
}

function Exit-AhkFlowLanes {
    param($Handle)
    if ($null -eq $Handle) { return }
    foreach ($stream in @($Handle.Streams)) { if ($null -ne $stream) { $stream.Dispose() } }
}

function Get-AhkFlowHeldLaneCount {
    param([Parameter(Mandatory = $true)][string] $PoolRoot)
    if (-not [System.IO.Directory]::Exists($PoolRoot)) { return 0 }
    $count = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $PoolRoot -Filter 'lane-*.lock' -File -ErrorAction Stop)) {
        if (Test-AhkFlowLaneFileHeld -Path $file.FullName) { $count++ }
    }
    return $count
}

function Register-AhkFlowLaneRun {
    param(
        [Parameter(Mandatory = $true)][string] $PoolRoot,
        [Parameter(Mandatory = $true)][string] $Mode,
        [Parameter(Mandatory = $true)][string] $Checkout
    )
    $directory = Join-Path $PoolRoot 'runs'
    New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
    $id = [string]$PID + '-' + [guid]::NewGuid().ToString('N')
    $run = [pscustomobject]@{
        Id = $id; PoolRoot = $PoolRoot; Mode = $Mode; Checkout = $Checkout
        LockPath = Join-Path $directory ($id + '.lock')
        RecordPath = Join-Path $directory ($id + '.txt')
        Stream = $null
        Printed = New-Object 'System.Collections.Concurrent.ConcurrentDictionary[string,bool]'
    }
    $completed = $false
    try {
        $run.Stream = Open-AhkFlowLaneFile -Path $run.LockPath
        if ($null -eq $run.Stream) { throw 'The test Lane run record is already locked.' }
        $record = [pscustomobject]@{ Id = $id; Mode = $Mode; Pid = $PID; Checkout = $Checkout }
        $record | ConvertTo-Json -Compress | Set-Content -LiteralPath $run.RecordPath -Encoding UTF8 -ErrorAction Stop
        $completed = $true
        return $run
    } finally {
        if (-not $completed) { Unregister-AhkFlowLaneRun -Run $run }
    }
}

function Unregister-AhkFlowLaneRun {
    param([object] $Run)
    if ($null -eq $Run) { return }
    try { if ($null -ne $Run.Stream) { $Run.Stream.Dispose() } }
    finally {
        # Records are advisory. Cleanup failures must not interrupt Lane or marker cleanup.
        foreach ($path in @($Run.RecordPath, $Run.LockPath)) {
            try { Remove-Item -LiteralPath $path -Force -ErrorAction Stop } catch { }
        }
    }
}

function Get-AhkFlowOtherLaneRuns {
    param([Parameter(Mandatory = $true)][string] $PoolRoot, [string] $ExceptId)
    $directory = Join-Path $PoolRoot 'runs'
    try { $files = @(Get-ChildItem -LiteralPath $directory -Filter '*.txt' -File -ErrorAction Stop) }
    catch { return }
    foreach ($file in $files) {
        if ($file.BaseName -eq $ExceptId) { continue }
        try {
            $record = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($null -eq $record) { continue }
            $complete = $true
            foreach ($name in @('Id', 'Mode', 'Pid', 'Checkout')) {
                if ($null -eq $record.PSObject.Properties[$name] -or [string]::IsNullOrWhiteSpace([string]$record.$name)) { $complete = $false; break }
            }
            if (-not $complete -or $record.Id -cne $file.BaseName) { continue }
            $processId = 0
            if (-not [int]::TryParse([string]$record.Pid, [ref]$processId) -or $processId -lt 1) { continue }
            if (Test-AhkFlowLaneFileHeld -Path (Join-Path $directory ($file.BaseName + '.lock'))) { $record }
        } catch { }
    }
}

function Write-AhkFlowLaneSharingLine {
    param([object] $Run)
    if ($null -eq $Run) { return }
    try {
        if ($Run.Printed.ContainsKey('sharing')) { return }
        $peers = @(Get-AhkFlowOtherLaneRuns -PoolRoot $Run.PoolRoot -ExceptId $Run.Id)
        if ($peers.Count -eq 0) { return }
        $descriptions = @($peers | ForEach-Object { "$($_.Mode) run $($_.Pid) in $($_.Checkout)" })
        if ($Run.Printed.TryAdd('sharing', $true)) {
            Write-Host ('Sharing the test Lane pool with: ' + ($descriptions -join '; '))
        }
    } catch { }
}

function Wait-AhkFlowLaneRetry {
    param([object] $Run)
    if ($null -ne $Run) { [void](Write-AhkFlowLaneSharingLine -Run $Run) }
    Start-Sleep -Milliseconds 200
}

function Enter-AhkFlowLaneRun {
    param(
        [Parameter(Mandatory = $true)][string] $Mode,
        [Parameter(Mandatory = $true)][string] $Checkout,
        [Parameter(Mandatory = $true)][ValidateSet('Half', 'Whole')][string] $Share
    )
    $role = Get-AhkFlowLaneRole
    $state = [pscustomobject]@{ Role = $role; PreviousHolder = $null; Run = $null; Lanes = $null }
    if ($role -ne 'owner') { return $state }
    $state.PreviousHolder = Enter-AhkFlowLaneOwnership
    $completed = $false
    try {
        $root = Get-AhkFlowLanePoolRoot
        $state.Run = Register-AhkFlowLaneRun -PoolRoot $root -Mode $Mode -Checkout $Checkout
        Write-AhkFlowLaneSharingLine -Run $state.Run
        $state.Lanes = Enter-AhkFlowLanes -PoolRoot $root -Share $Share -Proposal (Get-AhkFlowLaneProposal) -Run $state.Run
        $completed = $true
        return $state
    } finally {
        if (-not $completed) { Exit-AhkFlowLaneRun -State $state }
    }
}

function Exit-AhkFlowLaneRun {
    param([object] $State)
    if ($null -eq $State -or $State.Role -ne 'owner') { return }
    try { Exit-AhkFlowLanes -Handle $State.Lanes }
    finally {
        try { Unregister-AhkFlowLaneRun -Run $State.Run }
        finally { Exit-AhkFlowLaneOwnership -Previous $State.PreviousHolder }
    }
}
