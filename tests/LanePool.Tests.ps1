#Requires -Version 7.0

param([string] $ModulePath, [switch] $ContentionOnly)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($ModulePath)) { $ModulePath = Join-Path $repoRoot 'scripts/test-lanes.common.ps1' }
. $ModulePath
. (Join-Path $PSScriptRoot 'LanePool.Common.ps1')

$failures = [System.Collections.Generic.List[string]]::new()
function Invoke-Case([string] $Name, [scriptblock] $Body) {
    if ($ContentionOnly -and $Name -notin @('Entry contention blocks until an acknowledged real-open failure clears', 'Missing parent throws and genuine contention returns null')) { return }
    try { & $Body; Write-Host "  PASS  $Name" -ForegroundColor Green }
    catch { $failures.Add("$Name :: $($_.Exception.Message)"); Write-Host "  FAIL  $Name`n        $($_.Exception.Message)" -ForegroundColor Red }
}
function Assert-Equal($Expected, $Actual, [string] $Message) {
    if ([string]$Expected -cne [string]$Actual) { throw "$Message (expected '$Expected', got '$Actual')" }
}
function Assert-True([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }

Invoke-Case 'Role precedence and validation' {
    Use-LaneEnvironment -Value @{ AHKFLOW_TEST_LANES = ' OFF '; AHKFLOW_TEST_LANES_HOLDER = '42' } -Body {
        Assert-Equal off (Get-AhkFlowLaneRole) 'Opt-out must win.'
    }
    Use-LaneEnvironment -Value @{ AHKFLOW_TEST_LANES_HOLDER = ' 42 ' } -Body {
        Assert-Equal nested (Get-AhkFlowLaneRole) 'A holder must select nested.'
    }
    Use-LaneEnvironment -Value @{} -Body { Assert-Equal owner (Get-AhkFlowLaneRole) 'Empty variables must select owner.' }
    Use-LaneEnvironment -Value @{ AHKFLOW_TEST_LANES = '  '; AHKFLOW_TEST_LANES_HOLDER = '  '; AHKFLOW_TEST_LANES_ROOT = '  temporary-pool  ' } -Body {
        Assert-Equal owner (Get-AhkFlowLaneRole) 'Whitespace values must select owner.'
        Assert-Equal 'temporary-pool' (Get-AhkFlowLanePoolRoot) 'Root override must be trimmed.'
    }
    Use-LaneEnvironment -Value @{ AHKFLOW_TEST_LANES = 'yes' } -Body {
        $threw = $false; try { Get-AhkFlowLaneRole } catch { $threw = $true }
        Assert-True $threw 'Invalid opt-out must throw.'
    }
}

Invoke-Case 'Ownership restores the prior marker' {
    Use-LaneEnvironment -Value @{ AHKFLOW_TEST_LANES_HOLDER = 'before' } -Body {
        $previous = Enter-AhkFlowLaneOwnership
        Assert-Equal $PID $env:AHKFLOW_TEST_LANES_HOLDER 'Ownership must publish this PID.'
        Exit-AhkFlowLaneOwnership -Previous $previous
        Assert-Equal before $env:AHKFLOW_TEST_LANES_HOLDER 'Ownership must restore the marker.'
    }
    Use-LaneEnvironment -Body {
        $previous = Enter-AhkFlowLaneOwnership
        Exit-AhkFlowLaneOwnership $previous
        Assert-True ([string]::IsNullOrEmpty($env:AHKFLOW_TEST_LANES_HOLDER)) 'Ownership must restore an absent marker.'
    }
}

Invoke-Case 'Proposal and every share are stable' {
    $savedActions = $env:GITHUB_ACTIONS
    try {
        Remove-Item Env:\GITHUB_ACTIONS -ErrorAction SilentlyContinue
        foreach ($cores in 1..12) {
            $expected = Get-DefaultSuiteWorkerCount -PhysicalCoreCount $cores
            Assert-Equal $expected (Get-AhkFlowLaneProposal -PhysicalCoreCount $cores) "Proposal differed for $cores cores."
        }
        $env:GITHUB_ACTIONS = 'true'
        Assert-Equal ([Environment]::ProcessorCount) (Get-AhkFlowLaneProposal -PhysicalCoreCount 1) 'Hosted Actions must use all available processors.'
    } finally {
        if ($null -eq $savedActions) { Remove-Item Env:\GITHUB_ACTIONS -ErrorAction SilentlyContinue } else { $env:GITHUB_ACTIONS = $savedActions }
    }
    foreach ($capacity in 1..7) {
        Assert-Equal 1 (Get-AhkFlowLaneShareCount One $capacity) 'One differed.'
        Assert-Equal ([Math]::Ceiling($capacity / 2.0)) (Get-AhkFlowLaneShareCount Half $capacity) 'Half differed.'
        Assert-Equal $capacity (Get-AhkFlowLaneShareCount Whole $capacity) 'Whole differed.'
    }
}

Invoke-Case 'Entry contention blocks until an acknowledged real-open failure clears' {
    $pool = New-PinnedLanePool -Capacity 1
    $entry = Open-AhkFlowLaneFile (Join-Path $pool.Root 'entry.lock')
    $child = $null
    try {
        $signals = @{ Acquired = Join-Path $pool.Root 'acquired'; Release = Join-Path $pool.Root 'release'; FailedAttempt = Join-Path $pool.Root 'failed' }
        $child = Start-LaneHolder -PoolRoot $pool.Root -Signals $signals -Tag B -Share One -Proposal 1 -ModulePath $ModulePath
        [void](Wait-LanePath -Path $signals.FailedAttempt -TimeoutSeconds 5 -Child $child)
        Assert-True (-not (Test-Path $signals.Acquired)) 'Child must not acquire while entry is held.'
        $entry.Dispose(); $entry = $null
        Assert-True ((Wait-LanePath -Path $signals.Acquired -TimeoutSeconds 5 -Child $child) -like 'B|1|1*') 'Child acquisition payload differed.'
        Publish-LaneSignal $signals.Release
        $result = Wait-LaneChildProcess $child 5
        Assert-Equal 0 $result.ExitCode "Child failed: $($result.Error)"
    } finally {
        if ($null -ne $entry) { $entry.Dispose() }
        Stop-LaneChildProcess $child
        Remove-PinnedLanePool $pool
    }
}

Invoke-Case 'Classifier accepts only the measured native code' {
    $contentionCode = if ([IO.Path]::DirectorySeparatorChar -eq '\') { -2147024864 } else { 11 }
    $contention = [IO.IOException]::new('contention'); $contention.HResult = $contentionCode
    Assert-True (Test-AhkFlowLaneContention $contention) 'Measured contention must match.'
    foreach ($code in @(-2147024893, -2147024891, -2146232800)) {
        $other = [IO.IOException]::new('other'); $other.HResult = $code
        Assert-True (-not (Test-AhkFlowLaneContention $other)) "Code $code must not match."
    }
    $nativeWithInner = [IO.IOException]::new('outer', $contention)
    Assert-True (-not (Test-AhkFlowLaneContention $nativeWithInner)) 'Classifier must not descend a native inner chain.'
}

Invoke-Case 'Missing parent throws and genuine contention returns null' {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('lane-open-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $root | Out-Null
    try {
        $path = Join-Path $root 'held.lock'; $held = Open-AhkFlowLaneFile $path
        try { Assert-True ($null -eq (Open-AhkFlowLaneFile $path)) 'Held file must report contention.' } finally { $held.Dispose() }
        $threw = $false; try { Open-AhkFlowLaneFile (Join-Path (Join-Path $root 'missing') 'x.lock') } catch { $threw = $true }
        Assert-True $threw 'Missing parent must throw.'
    } finally { Remove-Item -LiteralPath $root -Recurse -Force }
}

Invoke-Case 'Empty and occupied pools keep stable capacity' {
    $pool = New-PinnedLanePool -Capacity 6
    $pool.Pin.Dispose(); $pool.Pin = $null
    try {
        $a = Enter-AhkFlowLanes -PoolRoot $pool.Root -Share One -Proposal 2
        $b = Enter-AhkFlowLanes -PoolRoot $pool.Root -Share One -Proposal 6
        try {
            Assert-Equal 2 $a.Capacity 'Pool must adopt two.'
            Assert-Equal 2 $b.Capacity 'Occupied pool must retain two.'
            Assert-Equal 2 (Get-Content (Join-Path $pool.Root 'capacity.txt') -Raw).Trim() 'Record must remain two.'
            Assert-Equal 2 (Get-AhkFlowHeldLaneCount $pool.Root) 'Two reservations must be visible.'
        } finally { Exit-AhkFlowLanes $b; Exit-AhkFlowLanes $a }
    } finally { Remove-PinnedLanePool $pool }
}

Invoke-Case 'Partial acquisition failure releases entry and lanes' {
    $pool = New-PinnedLanePool -Capacity 3
    try {
        $realOpen = ${function:Open-AhkFlowLaneFile}
        $script:partialObserved = $false
        function Open-AhkFlowLaneFile {
            param([Parameter(Mandatory = $true)][string] $Path)
            if ($Path -like '*lane-1.lock') {
                Assert-True ($null -eq (& $realOpen (Join-Path $pool.Root 'lane-0.lock'))) 'Injection must occur after a partial Lane.'
                Assert-True ($null -eq (& $realOpen (Join-Path $pool.Root 'entry.lock'))) 'Injection must occur while entry is held.'
                $script:partialObserved = $true
                throw [IO.IOException]::new('injected unrelated failure')
            }
            & $realOpen -Path $Path
        }
        $threw = $false; try { Enter-AhkFlowLanes -PoolRoot $pool.Root -Share Whole -Proposal 3 } catch { $threw = $true }
        Assert-True $threw 'Injected failure must escape.'
        Assert-True $script:partialObserved 'Failure must follow an actual partial acquisition.'
        Remove-Item Function:\Open-AhkFlowLaneFile
        . (Join-Path $repoRoot 'scripts/test-lanes.common.ps1')
        $handle = Enter-AhkFlowLanes -PoolRoot $pool.Root -Share Whole -Proposal 3
        try { Assert-Equal 3 $handle.Streams.Count 'Every Lane must be free after failure.' } finally { Exit-AhkFlowLanes $handle }
    } finally { Remove-PinnedLanePool $pool }
}

Invoke-Case 'Half shares compose at six and wait at odd capacities' {
    foreach ($capacity in @(1, 3, 5, 6)) {
        $pool = New-PinnedLanePool -Capacity $capacity
        $a = $null; $b = $null; $child = $null
        try {
            $a = Enter-AhkFlowLanes $pool.Root Half $capacity
            if ($capacity -eq 6) {
                $b = Enter-AhkFlowLanes $pool.Root Half $capacity
                Assert-Equal 6 (Get-RunLaneCount $pool) 'Two halves must fill capacity six.'
            } else {
                Assert-Equal ([Math]::Ceiling($capacity / 2.0)) (Get-RunLaneCount $pool) "Odd capacity $capacity must expose one half."
            }
            $signals = @{ Acquired = Join-Path $pool.Root 'acquired'; Release = Join-Path $pool.Root 'release'; FailedAttempt = Join-Path $pool.Root 'failed' }
            $child = Start-LaneHolder $pool.Root $signals C Half $capacity
            [void](Wait-LanePath $signals.FailedAttempt 10 $child)
            Assert-True (-not (Test-Path "$($signals.Acquired).done")) 'Contender must wait for a complete Half.'
            Exit-AhkFlowLanes $a; $a = $null
            Assert-Equal "C|$capacity|$([Math]::Ceiling($capacity / 2.0))" ((Wait-LanePath $signals.Acquired 10 $child).Trim()) 'Contender Half differed.'
            $expectedHeld = if ($capacity -eq 6) { 6 } else { [Math]::Ceiling($capacity / 2.0) }
            Assert-Equal $expectedHeld (Get-RunLaneCount $pool) 'Active Half reservations must hold their complete shares.'
            Assert-Equal $capacity (Get-Content (Join-Path $pool.Root 'capacity.txt') -Raw).Trim() 'Capacity must remain stable.'
            Publish-LaneSignal $signals.Release
            Assert-Equal 0 (Wait-LaneChildProcess $child 10).ExitCode 'Half child failed.'
        } finally { Stop-LaneChildProcess $child; Exit-AhkFlowLanes $b; Exit-AhkFlowLanes $a; Remove-PinnedLanePool $pool }
    }
}

Invoke-Case 'Stopping a runspace releases its partial share in the same host' {
    $pool = New-PinnedLanePool -Capacity 2
    $blocker = Open-AhkFlowLaneFile (Join-Path $pool.Root 'lane-1.lock')
    $powerShell = $null
    try {
        $modulePath = Join-Path $repoRoot 'scripts/test-lanes.common.ps1'
        $code = { param($ModulePath, $Root); . $ModulePath; Enter-AhkFlowLanes -PoolRoot $Root -Share Whole -Proposal 2 | Out-Null }
        $powerShell = [PowerShell]::Create().AddScript($code).AddArgument($modulePath).AddArgument($pool.Root)
        $async = $powerShell.BeginInvoke()
        $deadline = [DateTime]::UtcNow.AddSeconds(5)
        while ([DateTime]::UtcNow -lt $deadline -and (Get-RunLaneCount $pool) -lt 2) { Start-Sleep -Milliseconds 20 }
        Assert-Equal 2 (Get-RunLaneCount $pool) 'Runspace must hold one partial Lane beside the blocker.'
        Assert-True (Test-AhkFlowLaneFileHeld (Join-Path $pool.Root 'entry.lock')) 'Partial runspace must hold entry before cancellation.'
        $powerShell.Stop(); try { [void]$powerShell.EndInvoke($async) } catch [Management.Automation.PipelineStoppedException] { }
        $powerShell.Dispose(); $powerShell = $null
        $blocker.Dispose(); $blocker = $null
        Assert-True (-not (Test-AhkFlowLaneFileHeld (Join-Path $pool.Root 'entry.lock'))) 'Cancellation must release entry in the same host.'
        Assert-Equal 0 (Get-RunLaneCount $pool) 'Cancellation must release the partial Lane in the same host.'
        $fresh = Enter-AhkFlowLanes $pool.Root Whole 2
        try { Assert-Equal 2 $fresh.Streams.Count 'Fresh caller must acquire every Lane after cancellation.' } finally { Exit-AhkFlowLanes $fresh }
    } finally {
        if ($null -ne $powerShell) { $powerShell.Stop(); $powerShell.Dispose() }
        if ($null -ne $blocker) { $blocker.Dispose() }
        Remove-PinnedLanePool $pool
    }
}

Invoke-Case 'Hosted proposal avoids hardware discovery and local proposal queries once' {
    $saved = $env:GITHUB_ACTIONS
    try {
        $script:hardwareQueries = 0
        function Get-PhysicalCoreCount { $script:hardwareQueries++; return 8 }
        $env:GITHUB_ACTIONS = 'true'
        Assert-Equal ([Environment]::ProcessorCount) (Get-AhkFlowLaneProposal) 'Hosted count differed.'
        Assert-Equal 0 $script:hardwareQueries 'Hosted proposal must not query hardware.'
        $env:GITHUB_ACTIONS = ''
        [void](Get-AhkFlowLaneProposal)
        Assert-Equal 1 $script:hardwareQueries 'Local proposal must query hardware once.'
    } finally { $env:GITHUB_ACTIONS = $saved }
}

foreach ($recordMode in @('malformed', 'missing', 'unreadable')) {
    Invoke-Case "$recordMode capacity releases entry before retry and resizes only when empty" {
        $pool = New-PinnedLanePool 2
        $pool.Pin.Dispose(); $pool.Pin = $null
        $held = Open-AhkFlowLaneFile (Join-Path $pool.Root 'lane-0.lock')
        $child = $null; $entry = $null; $record = $null
        $path = Join-Path $pool.Root 'capacity.txt'
        try {
            if ($recordMode -eq 'malformed') { Set-Content $path broken }
            elseif ($recordMode -eq 'missing') { Remove-Item $path }
            else { $record = [IO.File]::Open($path, 'Open', 'ReadWrite', 'None') }
            $signals = @{ Acquired = Join-Path $pool.Root 'acquired'; Release = Join-Path $pool.Root 'release'; CapacityWait = Join-Path $pool.Root 'capacity-wait'; Resume = Join-Path $pool.Root 'resume' }
            $child = Start-LaneHolder $pool.Root $signals B One 3
            [void](Wait-LanePath $signals.CapacityWait 10 $child)
            Assert-True (-not (Test-Path "$($signals.Acquired).done")) 'Invalid occupied record must prevent admission.'
            $entry = Open-AhkFlowLaneFile (Join-Path $pool.Root 'entry.lock')
            Assert-True ($null -ne $entry) 'Capacity retry must release entry before waiting.'
            $entry.Dispose(); $entry = $null
            if ($null -ne $record) { $record.Dispose(); $record = $null }
            $held.Dispose(); $held = $null
            Publish-LaneSignal $signals.Resume
            Assert-Equal 'B|3|1' ((Wait-LanePath $signals.Acquired 10 $child).Trim()) 'Empty pool must adopt three.'
            Assert-Equal 3 (Get-Content $path -Raw).Trim() 'Capacity record must become three.'
            Publish-LaneSignal $signals.Release
            Assert-Equal 0 (Wait-LaneChildProcess $child 10).ExitCode 'Capacity child failed.'
        } finally {
            Stop-LaneChildProcess $child
            if ($null -ne $entry) { $entry.Dispose() }
            if ($null -ne $record) { $record.Dispose() }
            if ($null -ne $held) { $held.Dispose() }
            Remove-PinnedLanePool $pool
        }
    }
}

foreach ($scenario in @(
    @{ Capacity = 1; Proposal = 1; Share = 'One'; Fill = 1 },
    @{ Capacity = 6; Proposal = 2; Share = 'Whole'; Fill = 1 },
    @{ Capacity = 2; Proposal = 6; Share = 'One'; Fill = 2 }
)) {
    Invoke-Case "Capacity $($scenario.Capacity) blocks $($scenario.Share) with proposal $($scenario.Proposal) until release" {
        $pool = New-PinnedLanePool $scenario.Capacity
        $holders = [Collections.Generic.List[object]]::new(); $child = $null
        try {
            foreach ($index in 1..$scenario.Fill) { $holders.Add((Enter-AhkFlowLanes $pool.Root One $scenario.Capacity)) }
            $signals = @{ Acquired = Join-Path $pool.Root 'acquired'; Release = Join-Path $pool.Root 'release'; FailedAttempt = Join-Path $pool.Root 'failed' }
            $child = Start-LaneHolder $pool.Root $signals B $scenario.Share $scenario.Proposal
            $failedPath = (Wait-LanePath $signals.FailedAttempt 10 $child).Trim()
            Assert-True ($failedPath -like '*lane-*.lock') 'Acknowledgment must follow a failed Lane acquisition.'
            Assert-True (-not (Test-Path "$($signals.Acquired).done")) 'Reservation must wait for a complete share.'
            Assert-Equal $scenario.Capacity (Get-Content (Join-Path $pool.Root 'capacity.txt') -Raw).Trim() 'Occupied capacity changed.'
            Exit-AhkFlowLanes $holders[0]; $holders.RemoveAt(0)
            $expectedCount = Get-AhkFlowLaneShareCount $scenario.Share $scenario.Capacity
            Assert-Equal "B|$($scenario.Capacity)|$expectedCount" ((Wait-LanePath $signals.Acquired 10 $child).Trim()) 'Acquired share differed.'
            Publish-LaneSignal $signals.Release
            Assert-Equal 0 (Wait-LaneChildProcess $child 10).ExitCode 'Reservation child failed.'
        } finally { Stop-LaneChildProcess $child; foreach ($holder in $holders) { Exit-AhkFlowLanes $holder }; Remove-PinnedLanePool $pool }
    }
}

Invoke-Case 'One proposing two joins an occupied capacity six without resizing' {
    $pool = New-PinnedLanePool 6; $a = $null; $b = $null
    try {
        $a = Enter-AhkFlowLanes $pool.Root One 6
        $b = Enter-AhkFlowLanes $pool.Root One 2
        Assert-Equal 6 $b.Capacity 'Occupied six must remain six.'
        Assert-Equal 6 (Get-Content (Join-Path $pool.Root 'capacity.txt') -Raw).Trim() 'Record must remain six.'
        Assert-Equal 2 (Get-RunLaneCount $pool) 'Both One reservations must remain held.'
    } finally { Exit-AhkFlowLanes $b; Exit-AhkFlowLanes $a; Remove-PinnedLanePool $pool }
}

Invoke-Case 'Killing a partial collector releases entry and its Lanes' {
    $pool = New-PinnedLanePool 2; $child = $null; $blocker = $null
    try {
        $blocker = Open-AhkFlowLaneFile (Join-Path $pool.Root 'lane-1.lock')
        $signals = @{ Acquired = Join-Path $pool.Root 'acquired'; Release = Join-Path $pool.Root 'release'; FailedAttempt = Join-Path $pool.Root 'failed' }
        $child = Start-LaneHolder $pool.Root $signals B Whole 2
        Assert-Equal (Join-Path $pool.Root 'lane-1.lock') ((Wait-LanePath $signals.FailedAttempt 10 $child).Trim()) 'Collector must fail after collecting Lane zero.'
        Assert-True (Test-AhkFlowLaneFileHeld (Join-Path $pool.Root 'lane-0.lock')) 'Collector must hold a partial Lane.'
        Assert-True (Test-AhkFlowLaneFileHeld (Join-Path $pool.Root 'entry.lock')) 'Collector must hold entry.'
        Stop-LaneChildProcess $child
        Assert-True (-not (Test-AhkFlowLaneFileHeld (Join-Path $pool.Root 'entry.lock'))) 'Killed collector must release entry.'
        Assert-True (-not (Test-AhkFlowLaneFileHeld (Join-Path $pool.Root 'lane-0.lock'))) 'Killed collector must release Lane zero.'
        $blocker.Dispose(); $blocker = $null
        $fresh = Enter-AhkFlowLanes $pool.Root Whole 2
        try { Assert-Equal 2 $fresh.Streams.Count 'Fresh caller must acquire both Lanes.' } finally { Exit-AhkFlowLanes $fresh }
    } finally { Stop-LaneChildProcess $child; if ($null -ne $blocker) { $blocker.Dispose() }; Remove-PinnedLanePool $pool }
}

Invoke-Case 'An early assertion still reaps a gated child and removes its pool' {
    $pool = New-PinnedLanePool 1; $child = $null; $childId = 0; $caught = $false
    try {
        try {
            $signals = @{ Acquired = Join-Path $pool.Root 'acquired'; Release = Join-Path $pool.Root 'release' }
            $child = Start-LaneHolder $pool.Root $signals A One 1
            [void](Wait-LanePath $signals.Acquired 10 $child)
            $childId = $child.Process.Id
            Assert-True $false 'intentional fixture failure'
        } finally { Stop-LaneChildProcess $child; Remove-PinnedLanePool $pool }
    } catch { if ($_.Exception.Message -ne 'intentional fixture failure') { throw }; $caught = $true }
    Assert-True $caught 'Fixture must exercise the failing assertion.'
    Assert-True $child.Stopped 'Child cleanup did not complete.'
    Assert-True ($null -eq (Get-Process -Id $childId -ErrorAction SilentlyContinue)) 'Child process survived cleanup.'
    Assert-True (-not (Test-Path $pool.Root)) 'Temporary pool survived cleanup.'
}

Invoke-Case 'Access failures throw without being classified as contention' {
    $pool = New-PinnedLanePool 1
    try {
        $threw = $false
        try { [void](Open-AhkFlowLaneFile $pool.Root) } catch { $threw = $true }
        Assert-True $threw 'Opening a directory as a file must throw an access failure.'
        Assert-True (-not (Test-AhkFlowLaneContention ([UnauthorizedAccessException]::new('denied')))) 'Access failure must not match contention.'
    } finally { Remove-PinnedLanePool $pool }
}

Invoke-Case 'Interval Suite publishes complete monotonic endpoints and waits for release' {
    $pool = New-PinnedLanePool 1; $child = $null
    try {
        $suites = [Collections.Generic.List[object]]::new()
        Add-LaneIntervalSuite $suites interval (Join-Path $pool.Root 'start') (Join-Path $pool.Root 'release') (Join-Path $pool.Root 'finish')
        $child = Start-LaneChildProcess @('-NoProfile', '-File', $suites[0].Path)
        $start = [long](Wait-LanePath $suites[0].StartPath 10 $child)
        Publish-LaneSignal $suites[0].ReleasePath
        $finish = [long](Wait-LanePath $suites[0].FinishPath 10 $child)
        Assert-True ($finish -ge $start) 'Monotonic finish must follow start.'
        Assert-Equal 0 (Wait-LaneChildProcess $child 10).ExitCode 'Interval Suite failed.'
        Assert-Equal 1 (Get-LanePeakOverlap @(@{ Start = 1; End = 2 }, @{ Start = 2; End = 3 })) 'Equal endpoints must not overlap.'
        Assert-Equal 2 (Get-LanePeakOverlap @(@{ Start = 1; End = 3 }, @{ Start = 2; End = 4 })) 'Overlapping intervals must count twice.'
    } finally { Stop-LaneChildProcess $child; Remove-PinnedLanePool $pool }
}

Invoke-Case 'Always-successful open mutation fails the actual contention cases' {
    $pool = New-PinnedLanePool 1; $child = $null
    try {
        $mutant = Join-Path $pool.Root 'test-lanes.common.ps1'
        $source = Get-Content $ModulePath -Raw
        $needle = "[System.IO.File]::Open(`$Path, 'OpenOrCreate', 'ReadWrite', 'None')"
        $replacement = "[System.IO.File]::Open((`$Path + '.bypass.' + [guid]::NewGuid().ToString('N')), 'OpenOrCreate', 'ReadWrite', 'None')"
        Assert-True ($source.Contains($needle)) 'Mutation target disappeared.'
        Set-Content $mutant $source.Replace($needle, $replacement)
        Copy-Item (Join-Path $repoRoot 'scripts/suite-worker-count.common.ps1') $pool.Root
        $child = Start-LaneChildProcess @('-NoProfile', '-File', $PSCommandPath, '-ModulePath', $mutant, '-ContentionOnly')
        $result = Wait-LaneChildProcess $child 20
        Assert-Equal 1 $result.ExitCode 'Always-successful mutation survived.'
        Assert-True ($result.Output -match 'FAIL  Entry contention') 'Mutation must fail entry contention.'
        Assert-True ($result.Output -match 'FAIL  Missing parent throws and genuine contention') 'Mutation must fail Lane contention.'
    } finally { Stop-LaneChildProcess $child; Remove-PinnedLanePool $pool }
}

Invoke-Case 'Advisory records announce peers once and ignore incomplete or stale files' {
    $pool = New-PinnedLanePool 2; $a = $null; $b = $null
    try {
        $a = Register-AhkFlowLaneRun $pool.Root Fast 'checkout A'
        Assert-Equal 0 @(Get-AhkFlowOtherLaneRuns $pool.Root $a.Id).Count 'A lone run must have no peers.'
        $lines = @(Write-AhkFlowLaneSharingLine $a 6>&1)
        Assert-Equal 0 $lines.Count 'A lone run must print nothing.'
        $b = Register-AhkFlowLaneRun $pool.Root Integration 'checkout B'
        $peers = @(Get-AhkFlowOtherLaneRuns $pool.Root $a.Id)
        Assert-Equal 1 $peers.Count 'Live sibling must be readable.'
        Assert-Equal Integration $peers[0].Mode 'Peer mode differed.'
        Assert-Equal $PID $peers[0].Pid 'Peer PID differed.'
        Assert-Equal 'checkout B' $peers[0].Checkout 'Peer checkout differed.'
        $lines = @(Write-AhkFlowLaneSharingLine $a 6>&1)
        Assert-Equal 1 $lines.Count 'First peer scan must print once.'
        Assert-Equal "Sharing the test Lane pool with: Integration run $PID in checkout B" ([string]$lines[0]) 'Sharing message differed.'
        Assert-Equal 0 @(Write-AhkFlowLaneSharingLine $a 6>&1).Count 'Second scan must not print.'
        $b.Stream.Dispose()
        Assert-Equal 0 @(Get-AhkFlowOtherLaneRuns $pool.Root $a.Id).Count 'Free record lock must be ignored.'
        $b.Stream = Open-AhkFlowLaneFile $b.LockPath
        Set-Content $b.RecordPath '{incomplete'
        Assert-Equal 0 @(Get-AhkFlowOtherLaneRuns $pool.Root $a.Id).Count 'Incomplete record must be ignored.'
        Set-Content $b.RecordPath '{}'
        Assert-Equal 0 @(Get-AhkFlowOtherLaneRuns $pool.Root $a.Id).Count 'Missing record fields must be ignored.'
        Remove-Item $b.RecordPath
        Assert-Equal 0 @(Get-AhkFlowOtherLaneRuns $pool.Root $a.Id).Count 'Disappeared record must be ignored.'
    } finally { Unregister-AhkFlowLaneRun $b; Unregister-AhkFlowLaneRun $a; Remove-PinnedLanePool $pool }
}

Invoke-Case 'Concurrent Workers share one diagnostic decision' {
    $pool = New-PinnedLanePool 2; $a = $null; $b = $null
    $workers = [Collections.Generic.List[object]]::new()
    $gate = [Threading.ManualResetEventSlim]::new($false)
    try {
        $a = Register-AhkFlowLaneRun $pool.Root Fast A
        $b = Register-AhkFlowLaneRun $pool.Root Fast B
        foreach ($index in 1..8) {
            $ps = [PowerShell]::Create().AddScript({ param($Module, $Run, $Gate); . $Module; if (-not $Gate.Wait(10000)) { throw 'Worker gate timed out.' }; Write-AhkFlowLaneSharingLine $Run }).AddArgument($ModulePath).AddArgument($a).AddArgument($gate)
            $workers.Add(@{ PowerShell = $ps; Async = $ps.BeginInvoke() })
        }
        $gate.Set()
        $printed = 0
        foreach ($worker in $workers) {
            Assert-True ($worker.Async.AsyncWaitHandle.WaitOne(10000)) 'Worker did not finish.'
            [void]$worker.PowerShell.EndInvoke($worker.Async)
            Assert-Equal 0 $worker.PowerShell.Streams.Error.Count 'Worker failed.'
            $printed += $worker.PowerShell.Streams.Information.Count
        }
        Assert-Equal 1 $printed 'Concurrent Workers must print exactly one line.'
    } finally {
        foreach ($worker in $workers) { $worker.PowerShell.Stop(); $worker.PowerShell.Dispose() }
        $gate.Dispose(); Unregister-AhkFlowLaneRun $b; Unregister-AhkFlowLaneRun $a; Remove-PinnedLanePool $pool
    }
}

Invoke-Case 'Registration publication failure releases its record handle' {
    $pool = New-PinnedLanePool 1
    try {
        $script:publishingHandle = $null
        $realOpen = ${function:Open-AhkFlowLaneFile}
        function Open-AhkFlowLaneFile { param($Path); $script:publishingHandle = & $realOpen $Path; $script:publishingHandle }
        function Set-Content {
            Assert-True ($null -ne $script:publishingHandle) 'Registration must open its lock before publication.'
            Assert-True ($null -eq (& $realOpen $script:publishingHandle.Name)) 'Record lock must remain held during publication.'
            throw 'record publication failed'
        }
        $threw = $false
        try { Register-AhkFlowLaneRun $pool.Root Fast A } catch { $threw = $_.Exception.Message -eq 'record publication failed' }
        Assert-True $threw 'Publication failure must escape registration.'
        Assert-True (-not $script:publishingHandle.CanRead) 'Failed publication must dispose its native record stream.'
        Assert-Equal 0 @(Get-ChildItem (Join-Path $pool.Root runs) -File).Count 'Failed publication must remove its files.'
    } finally { Remove-PinnedLanePool $pool }
}

Invoke-Case 'Owner lifecycle restores normal failed and nested marker state' {
    $pool = New-PinnedLanePool 2
    try {
        Use-LaneEnvironment -Value @{ AHKFLOW_TEST_LANES_ROOT = $pool.Root } -Body {
            function Get-AhkFlowLaneProposal { 2 }
            foreach ($iteration in 1..2) {
                $state = Enter-AhkFlowLaneRun Fast A Half
                try {
                    Assert-Equal owner $state.Role 'Fresh run must own its reservation.'
                    Assert-Equal $PID $env:AHKFLOW_TEST_LANES_HOLDER 'Owner must publish its marker.'
                    Assert-Equal 1 $state.Lanes.Streams.Count 'Half of two must acquire one Lane.'
                    $nested = Enter-AhkFlowLaneRun Nested A Whole
                    Assert-Equal nested $nested.Role 'Inherited run must be nested.'
                    Exit-AhkFlowLaneRun $nested
                    Assert-Equal $PID $env:AHKFLOW_TEST_LANES_HOLDER 'Nested exit must leave owner marker.'
                } finally { Exit-AhkFlowLaneRun $state }
                Assert-True ([string]::IsNullOrEmpty($env:AHKFLOW_TEST_LANES_HOLDER)) 'Normal exit must restore an absent marker.'
                Assert-Equal 0 (Get-RunLaneCount $pool) 'Normal exit must release all Lanes.'
                Assert-Equal 0 @(Get-ChildItem (Join-Path $pool.Root runs) -File).Count 'Normal exit must remove records.'
            }
            $realRegister = ${function:Register-AhkFlowLaneRun}
            function Register-AhkFlowLaneRun { throw 'register failed' }
            $threw = $false
            try { Enter-AhkFlowLaneRun Fast A Half } catch { $threw = $_.Exception.Message -eq 'register failed' }
            Assert-True $threw 'Registration failure must escape entry.'
            Assert-True ([string]::IsNullOrEmpty($env:AHKFLOW_TEST_LANES_HOLDER)) 'Registration failure must restore the marker.'
            Set-Item Function:\Register-AhkFlowLaneRun $realRegister
            $realEnter = ${function:Enter-AhkFlowLanes}
            function Enter-AhkFlowLanes { throw 'allocation failed' }
            $threw = $false
            try { Enter-AhkFlowLaneRun Fast A Half } catch { $threw = $_.Exception.Message -eq 'allocation failed' }
            Assert-True $threw 'Allocation failure must escape entry.'
            Assert-True ([string]::IsNullOrEmpty($env:AHKFLOW_TEST_LANES_HOLDER)) 'Allocation failure must restore the marker.'
            Assert-Equal 0 @(Get-ChildItem (Join-Path $pool.Root runs) -File).Count 'Allocation failure must remove its record.'
            Set-Item Function:\Enter-AhkFlowLanes $realEnter
            $fresh = Enter-AhkFlowLaneRun Fast A Whole
            try { Assert-Equal 2 $fresh.Lanes.Streams.Count 'The same host must acquire after failures.' } finally { Exit-AhkFlowLaneRun $fresh }
        }
        Use-LaneEnvironment -Value @{ AHKFLOW_TEST_LANES = 'off'; AHKFLOW_TEST_LANES_HOLDER = 'before' } -Body {
            $state = Enter-AhkFlowLaneRun Fast A Half
            Assert-Equal off $state.Role 'Opt-out must take precedence.'
            Assert-True ($null -eq $state.Lanes -and $null -eq $state.Run) 'Opt-out must not reserve or register.'
            Exit-AhkFlowLaneRun $state
            Assert-Equal before $env:AHKFLOW_TEST_LANES_HOLDER 'Opt-out must not alter inherited marker.'
        }
    } finally { Remove-PinnedLanePool $pool }
}

Invoke-Case 'A killed advisory owner is no longer named' {
    $pool = New-PinnedLanePool 1; $child = $null; $a = $null
    try {
        $a = Register-AhkFlowLaneRun $pool.Root Fast A
        $module = $ModulePath.Replace("'", "''"); $root = $pool.Root.Replace("'", "''")
        $common = (Join-Path $PSScriptRoot 'LanePool.Common.ps1').Replace("'", "''")
        $ready = Join-Path $pool.Root ready; $release = Join-Path $pool.Root release
        $code = ". '$module'; . '$common'; `$run=Register-AhkFlowLaneRun '$root' Killed B; Publish-LaneSignal '$ready' `$run.Id; Wait-LanePath '$release' 30 | Out-Null"
        $child = Start-LaneChildProcess @('-NoProfile', '-EncodedCommand', (ConvertTo-LaneEncodedCommand $code))
        [void](Wait-LanePath $ready 10 $child)
        $peers = @(Get-AhkFlowOtherLaneRuns $pool.Root $a.Id)
        Assert-Equal 1 $peers.Count 'Live child record must be visible.'
        Assert-Equal $child.Process.Id $peers[0].Pid 'Child record must name its actual PID.'
        Stop-LaneChildProcess $child
        Assert-Equal 0 @(Get-AhkFlowOtherLaneRuns $pool.Root $a.Id).Count 'Killed owner must no longer be named.'
        Assert-Equal 2 @(Get-ChildItem (Join-Path $pool.Root runs) -Filter '*.txt').Count 'Test must leave the killed owner record stale.'
    } finally { Stop-LaneChildProcess $child; Unregister-AhkFlowLaneRun $a; Remove-PinnedLanePool $pool }
}

foreach ($waitKind in @('entry', 'capacity', 'share')) {
    Invoke-Case "A late peer is announced during $waitKind retry before its Lane is released" {
        $pool = New-PinnedLanePool 2
        $a = $null; $c = $null; $cLanes = $null; $b = $null; $worker = $null
        $retryGate = [Threading.ManualResetEventSlim]::new($false)
        $atRetry = [Threading.ManualResetEventSlim]::new($false)
        $lines = [Collections.Concurrent.ConcurrentQueue[string]]::new()
        try {
            $a = Register-AhkFlowLaneRun $pool.Root Fast A
            Assert-Equal 0 @(Write-AhkFlowLaneSharingLine $a 6>&1).Count 'Initial A scan must see nobody.'
            $c = Register-AhkFlowLaneRun $pool.Root Integration C
            $cLanes = Enter-AhkFlowLanes $pool.Root One 2
            if ($waitKind -eq 'entry') {
                $signals = @{ Acquired = Join-Path $pool.Root 'b-acquired'; Release = Join-Path $pool.Root 'b-release'; FailedAttempt = Join-Path $pool.Root 'b-failed' }
                $b = Start-LaneHolder $pool.Root $signals B Whole 2
                [void](Wait-LanePath $signals.FailedAttempt 10 $b)
                Assert-True (Test-AhkFlowLaneFileHeld (Join-Path $pool.Root entry.lock)) 'B must hold entry while C owns a Lane.'
            } elseif ($waitKind -eq 'capacity') { Remove-Item (Join-Path $pool.Root capacity.txt) }
            $code = {
                param($Module, $Run, $Lines, $AtRetry, $RetryGate, $Share)
                . $Module
                function Write-Host { param($Object); $Lines.Enqueue([string]$Object) }
                $realWait = ${function:Wait-AhkFlowLaneRetry}
                function Wait-AhkFlowLaneRetry {
                    param($Run)
                    & $realWait -Run $Run
                    $AtRetry.Set()
                    if (-not $RetryGate.Wait(10000)) { throw 'Diagnostic retry gate timed out.' }
                }
                $lanes = $null
                try { $lanes = Enter-AhkFlowLanes $Run.PoolRoot $Share 2 -Run $Run }
                finally { Exit-AhkFlowLanes $lanes }
            }
            $share = if ($waitKind -eq 'share') { 'Whole' } else { 'One' }
            $worker = [PowerShell]::Create().AddScript($code).AddArgument($ModulePath).AddArgument($a).AddArgument($lines).AddArgument($atRetry).AddArgument($retryGate).AddArgument($share)
            $async = $worker.BeginInvoke()
            Assert-True ($atRetry.Wait(10000)) 'A never reached its diagnostic retry.'
            Assert-Equal 1 $lines.Count 'A must announce its late peer before C releases its Lane.'
            Assert-Equal "Sharing the test Lane pool with: Integration run $PID in C" $lines.ToArray()[0] 'Late peer message differed.'
            Assert-True (Test-AhkFlowLaneFileHeld $cLanes.Streams[0].Name) 'C must still own its Lane when A prints.'
            if ($waitKind -eq 'capacity') {
                Assert-True (-not (Test-AhkFlowLaneFileHeld (Join-Path $pool.Root entry.lock))) 'Missing-capacity retry must release entry.'
                Set-Content (Join-Path $pool.Root capacity.txt) 2
            }
            Exit-AhkFlowLanes $cLanes; $cLanes = $null
            if ($null -ne $b) {
                [void](Wait-LanePath $signals.Acquired 10 $b)
                Publish-LaneSignal $signals.Release
                Assert-Equal 0 (Wait-LaneChildProcess $b 10).ExitCode 'Whole contender failed.'
            }
            $retryGate.Set()
            Assert-True ($async.AsyncWaitHandle.WaitOne(10000)) 'A failed to acquire after release.'
            [void]$worker.EndInvoke($async)
            Assert-Equal 0 $worker.Streams.Error.Count 'Diagnostic worker failed.'
            Assert-Equal 0 (Get-RunLaneCount $pool) 'Workers must release their reservations.'
        } finally {
            $retryGate.Set()
            if ($null -ne $worker) { $worker.Stop(); $worker.Dispose() }
            Stop-LaneChildProcess $b; Exit-AhkFlowLanes $cLanes
            Unregister-AhkFlowLaneRun $c; Unregister-AhkFlowLaneRun $a
            $retryGate.Dispose(); $atRetry.Dispose(); Remove-PinnedLanePool $pool
        }
    }
}

Invoke-Case 'Stopped owner entry restores its marker and acquires again in the surviving runspace' {
    $pool = New-PinnedLanePool 2; $worker = $null; $blocker = $null
    try {
        Use-LaneEnvironment -Value @{ AHKFLOW_TEST_LANES_ROOT = $pool.Root; AHKFLOW_TEST_LANES_HOLDER = '  ' } -Body {
            $blocker = Open-AhkFlowLaneFile (Join-Path $pool.Root lane-1.lock)
            try {
                $worker = [PowerShell]::Create().AddScript({ param($Module); . $Module; function Get-AhkFlowLaneProposal { 2 }; Enter-AhkFlowLaneRun Fast A Whole | Out-Null }).AddArgument($ModulePath)
                $async = $worker.BeginInvoke()
                $watch = [Diagnostics.Stopwatch]::StartNew()
                while ($watch.Elapsed.TotalSeconds -lt 10 -and (Get-RunLaneCount $pool) -lt 2) { Start-Sleep -Milliseconds 20 }
                Assert-Equal 2 (Get-RunLaneCount $pool) 'Owner must collect a partial share before cancellation.'
                Assert-Equal $PID $env:AHKFLOW_TEST_LANES_HOLDER 'Waiting owner must publish its marker.'
                Assert-Equal 1 @(Get-ChildItem (Join-Path $pool.Root runs) -Filter '*.txt').Count 'Waiting owner must have a record.'
                $worker.Stop()
                try { [void]$worker.EndInvoke($async) } catch [Management.Automation.PipelineStoppedException] { }
                Assert-Equal '  ' $env:AHKFLOW_TEST_LANES_HOLDER 'Cancellation must restore the exact prior marker.'
                Assert-Equal 0 @(Get-ChildItem (Join-Path $pool.Root runs) -File).Count 'Cancellation must remove its record and lock.'
                Assert-Equal 1 (Get-RunLaneCount $pool) 'Cancellation must release its partial Lane.'
                Assert-True (-not (Test-AhkFlowLaneFileHeld (Join-Path $pool.Root entry.lock))) 'Cancellation must release entry.'
                $blocker.Dispose(); $blocker = $null
                $worker.Commands.Clear()
                [void]$worker.AddScript({ param($Module); . $Module; function Get-AhkFlowLaneProposal { 2 }; $state = Enter-AhkFlowLaneRun Fast A Whole; try { $state.Lanes.Streams.Count } finally { Exit-AhkFlowLaneRun $state } }).AddArgument($ModulePath)
                $fresh = $worker.BeginInvoke()
                Assert-True ($fresh.AsyncWaitHandle.WaitOne(10000)) 'Second reservation timed out in the surviving host.'
                $result = $worker.EndInvoke($fresh)
                Assert-Equal 2 $result[0] 'Surviving runspace must acquire the full share.'
                Assert-Equal '  ' $env:AHKFLOW_TEST_LANES_HOLDER 'Second reservation must restore the prior marker.'
            } finally {
                if ($null -ne $worker) { $worker.Stop(); $worker.Dispose(); $worker = $null }
                if ($null -ne $blocker) { $blocker.Dispose(); $blocker = $null }
            }
        }
    } finally { Remove-PinnedLanePool $pool }
}

Invoke-Case 'Unreadable advisory records cannot abort a valid reservation' {
    $pool = New-PinnedLanePool 2; $run = $null
    try {
        $run = Register-AhkFlowLaneRun $pool.Root Fast A
        function Get-AhkFlowOtherLaneRuns { throw [IO.IOException]::new('advisory read failed') }
        Write-AhkFlowLaneSharingLine $run
        Wait-AhkFlowLaneRetry $run
        $lanes = Enter-AhkFlowLanes $pool.Root Whole 2 -Run $run
        try { Assert-Equal 2 $lanes.Streams.Count 'Advisory failure must not affect admission.' }
        finally { Exit-AhkFlowLanes $lanes }
        Assert-Equal 0 $run.Printed.Count 'A failed scan must allow a later diagnostic retry.'
    } finally { Unregister-AhkFlowLaneRun $run; Remove-PinnedLanePool $pool }
}

if ($failures.Count -gt 0) { foreach ($failure in $failures) { Write-Host $failure -ForegroundColor Red }; exit 1 }
Write-Host 'PASSED|LanePool'
