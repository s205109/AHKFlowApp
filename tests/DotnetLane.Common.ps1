#Requires -Version 7.0

. (Join-Path $PSScriptRoot 'LanePool.Common.ps1')
. (Join-Path $PSScriptRoot '../scripts/test-lanes.common.ps1')
. (Join-Path $PSScriptRoot '../scripts/test-run-lock.common.ps1')

function Add-DotnetLaneGate {
    param([string] $Root)
    $stub = Join-Path $Root 'stub/dotnet.ps1'
    $prefix = @'
if ($args[0] -eq 'test') {
    $folder = Split-Path $PSCommandPath -Parent
    $counter = Join-Path $folder 'gate-count'
    $number = if (Test-Path $counter) { 1 + [int](Get-Content $counter -Raw) } else { 1 }
    Set-Content $counter $number
    $ready = Join-Path $folder "ready-$number"
    Set-Content $ready $env:AHKFLOW_TEST_LANES_HOLDER
    Set-Content "$ready.done" complete
    $watch = [Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Path (Join-Path $folder "release-$number.done"))) {
        if ($watch.Elapsed.TotalSeconds -gt 30) { throw 'The dotnet fixture release deadline expired.' }
        Start-Sleep -Milliseconds 20
    }
}
'@
    Set-Content $stub ($prefix + [Environment]::NewLine + (Get-Content $stub -Raw))
    $audit = @'
$pool = $env:AHKFLOW_TEST_LANES_ROOT
$count = 0
foreach ($file in Get-ChildItem $pool -Filter 'lane-*.lock') {
    if ($file.Name -eq 'lane-99.lock') { continue }
    try { $probe = [IO.File]::Open($file.FullName, 'OpenOrCreate', 'ReadWrite', 'None'); $probe.Dispose() }
    catch [IO.IOException] { $count++ }
}
$record = @{ Command = ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath) + ' ' + ($args -join ' ')); Count = $count; Holder = $env:AHKFLOW_TEST_LANES_HOLDER }
Add-Content (Join-Path (Split-Path $PSCommandPath -Parent) 'lane-audit.jsonl') ($record | ConvertTo-Json -Compress)
'@
    foreach ($name in @('dotnet', 'reportgenerator', 'python')) {
        $path = Join-Path $Root "stub/$name.ps1"
        if (Test-Path $path) { Set-Content $path ($audit + [Environment]::NewLine + (Get-Content $path -Raw)) }
    }
    Add-Content (Join-Path $Root 'scripts/test-run-lock.common.ps1') @'
$script:originalCheckoutExit = ${function:Exit-AhkFlowTestRunLock}
function Exit-AhkFlowTestRunLock {
    param($Handle)
    if ($null -ne $Handle) {
        $expected = if ($env:AHKFLOW_TEST_LANES_HOLDER -eq 'existing-holder') { 2 } else { 0 }
        if (((Get-AhkFlowHeldLaneCount $env:AHKFLOW_TEST_LANES_ROOT) - 1) -ne $expected) {
            throw 'Lane ownership must release before checkout cleanup.'
        }
    }
    & $script:originalCheckoutExit $Handle
}
'@
}

function Test-DotnetLaneRoute {
    param([string] $Root, [string] $ScriptName, [hashtable] $Arguments, [int] $Calls = 1, [switch] $Nested, [switch] $Repeat)
    $pool = New-PinnedLanePool 4
    $handles = @{ Child = $null; Contender = $null; Held = $null }
    $previousPath = $env:PATH
    try {
        Add-DotnetLaneGate $Root
        $env:PATH = (Join-Path $Root stub) + [IO.Path]::PathSeparator + $previousPath
        Use-LaneEnvironment -Value @{ AHKFLOW_TEST_LANES_ROOT = $pool.Root; AHKFLOW_TEST_LANES_HOLDER = $(if ($Nested) { 'existing-holder' } else { '  ' }) } -Body {
            if ($Nested) { $handles.Held = Enter-AhkFlowLanes -PoolRoot $pool.Root -Share Half -Proposal 4 }
            $payload = @{ Root = $Root; Script = $ScriptName; Arguments = $Arguments; Repeat = [bool]$Repeat } | ConvertTo-Json -Compress
            $code = @'
param($Json)
$ErrorActionPreference = 'Stop'
$p = $Json | ConvertFrom-Json -AsHashtable
$scriptPath = Join-Path $p.Root ('scripts/' + $p.Script)
$arguments = $p.Arguments
foreach ($iteration in 1..$(if ($p.Repeat) { 2 } else { 1 })) {
    & $scriptPath @arguments
    $after = Join-Path $p.Root "stub/after-$iteration"
    Set-Content $after ('holder=' + $env:AHKFLOW_TEST_LANES_HOLDER)
    Set-Content "$after.done" complete
}

'@
            $code = '& { ' + $code + " } '" + $payload.Replace("'", "''") + "'"
            $handles.Child = Start-LaneChildProcess @('-NoProfile', '-EncodedCommand', (ConvertTo-LaneEncodedCommand $code))
            $total = $Calls * $(if ($Repeat) { 2 } else { 1 })
            for ($call = 1; $call -le $total; $call++) {
                $marker = (Wait-LanePath (Join-Path $Root "stub/ready-$call") 15 $handles.Child).Trim()
                Assert-True ((Get-RunLaneCount $pool) -eq 2) "Expected exactly two of four Lanes during $ScriptName call $call."
                $expected = if ($Nested) { 'existing-holder' } else { [string]$handles.Child.Process.Id }
                Assert-True ($marker -ceq $expected) "Expected holder '$expected', got '$marker'."
                # A second real entry point must fail on the checkout lock, even when nested.
                if ($call -eq 1) {
                    $handles.Contender = Start-LaneChildProcess @('-NoProfile', '-File', (Join-Path $Root 'scripts/test-fast.ps1'), '-Mode', 'Fast', '-NoBuild')
                    $refused = Wait-LaneChildProcess $handles.Contender 10
                    Assert-True ($refused.ExitCode -ne 0 -and ($refused.Output + $refused.Error).Contains('holds the test-run lock')) 'A real contender must be refused by the checkout lock.'
                    Stop-LaneChildProcess $handles.Contender
                    $handles.Contender = $null
                }
                Publish-LaneSignal (Join-Path $Root "stub/release-$call")
                if ($Repeat) {
                    $after = Wait-LanePath (Join-Path $Root "stub/after-$call") 15 $handles.Child
                    Assert-True ($after.TrimEnd("`r", "`n") -ceq 'holder=  ') 'The surviving host must restore its exact marker between runs.'
                }
            }
            $result = Wait-LaneChildProcess $handles.Child 15
            Assert-True ($result.ExitCode -eq 0) ($result.Output + $result.Error)
            foreach ($line in Get-Content (Join-Path $Root 'stub/lane-audit.jsonl')) {
                $audit = $line | ConvertFrom-Json
                Assert-True ($audit.Count -eq 2 -and $audit.Holder -ceq $expected) "Every phase must retain Half and its holder: $($audit.Command)."
            }
            $after = Wait-LanePath (Join-Path $Root "stub/after-$(if ($Repeat) { 2 } else { 1 })") 2 $handles.Child
            $expectedAfter = if ($Nested) { 'holder=existing-holder' } else { 'holder=  ' }
            Assert-True ($after.TrimEnd("`r", "`n") -ceq $expectedAfter) 'The completed route must restore its marker.'
            Assert-True ((Get-RunLaneCount $pool) -eq $(if ($Nested) { 2 } else { 0 })) 'The route must release only its own Lanes.'
            $checkout = Enter-AhkFlowTestRunLock $Root Fresh
            Exit-AhkFlowTestRunLock $checkout
        }
    } catch {
        if ($null -ne $handles.Child -and $handles.Child.Process.HasExited) {
            $details = Wait-LaneChildProcess $handles.Child 2
            throw ($_.Exception.Message + ' Child output: ' + $details.Output + $details.Error)
        }
        throw
    } finally {
        foreach ($call in 1..($Calls * 2)) { Publish-LaneSignal (Join-Path $Root "stub/release-$call") }
        Stop-LaneChildProcess $handles.Contender
        Stop-LaneChildProcess $handles.Child
        Exit-AhkFlowLanes $handles.Held
        $env:PATH = $previousPath
        Remove-PinnedLanePool $pool
    }
}

function Test-DotnetLaneCancellation {
    param([string] $Root, [string] $ScriptName = 'test-fast.ps1')
    $pool = New-PinnedLanePool 4
    $worker = [PowerShell]::Create()
    $blockers = [Collections.Generic.List[IDisposable]]::new()
    $previousPath = $env:PATH
    $invocation = $null
    try {
        $env:PATH = (Join-Path $Root stub) + [IO.Path]::PathSeparator + $previousPath
        foreach ($index in 1..3) { $blockers.Add((Open-AhkFlowLaneFile (Join-Path $pool.Root "lane-$index.lock"))) }
        # This fixture seam acknowledges a real failed acquisition after capacity resolution.
        # It does not replace the locking operation or decide whether contention exists.
        Add-Content (Join-Path $Root 'scripts/test-lanes.common.ps1') @'
$script:realLaneOpen = ${function:Open-AhkFlowLaneFile}
$script:realLaneResolve = ${function:Resolve-AhkFlowLaneCapacity}
$script:resolvingLaneCapacity = $false
function Resolve-AhkFlowLaneCapacity {
    param($PoolRoot, $Proposal)
    $script:resolvingLaneCapacity = $true
    try { & $script:realLaneResolve $PoolRoot $Proposal }
    finally { $script:resolvingLaneCapacity = $false }
}
function Open-AhkFlowLaneFile {
    param([string] $Path)
    $stream = & $script:realLaneOpen $Path
    if ($null -eq $stream -and -not $script:resolvingLaneCapacity -and $Path -like '*lane-*.lock') {
        $signal = Join-Path $env:AHKFLOW_TEST_LANES_ROOT 'failed-open'
        Set-Content $signal $Path
        Set-Content "$signal.done" complete
    }
    $stream
}
'@
        Use-LaneEnvironment -Value @{ AHKFLOW_TEST_LANES_ROOT = $pool.Root; AHKFLOW_TEST_LANES_HOLDER = '  ' } -Body {
            try {
                [void]$worker.AddScript({
                    param($Root, $Name)
                    if ($Name -eq 'test-fast.ps1') { & (Join-Path $Root 'scripts/test-fast.ps1') -Mode Fast -NoBuild }
                    else { & (Join-Path $Root 'scripts/run-coverage.ps1') }
                }).AddArgument($Root).AddArgument($ScriptName)
                $invocation = $worker.BeginInvoke()
                [void](Wait-LanePath (Join-Path $pool.Root 'failed-open') 10)
                Assert-True (Test-AhkFlowLaneFileHeld (Join-Path $Root '.test-run.lock')) 'The waiting route must retain its checkout lock.'
                Assert-True (Test-AhkFlowLaneFileHeld (Join-Path $pool.Root 'entry.lock')) 'The waiting route must retain the admission lock.'
                Assert-True ((Get-RunLaneCount $pool) -eq 4) 'The waiting route must hold one partial Lane beside three blockers.'
                $stopping = $worker.BeginStop($null, $null)
                Assert-True ($stopping.AsyncWaitHandle.WaitOne(10000)) 'Cancellation must finish within ten seconds.'
                $worker.EndStop($stopping)
                try { [void]$worker.EndInvoke($invocation) } catch [Management.Automation.PipelineStoppedException] { }
                Assert-True ($env:AHKFLOW_TEST_LANES_HOLDER -ceq '  ') 'Cancellation must restore the exact marker in the surviving host.'
                Assert-True ((Get-RunLaneCount $pool) -eq 3) 'Cancellation must release the partial Lane.'
                foreach ($path in @((Join-Path $Root '.test-run.lock'), (Join-Path $pool.Root 'entry.lock'), (Join-Path $pool.Root 'lane-0.lock'))) {
                    $probe = [IO.File]::Open($path, 'OpenOrCreate', 'ReadWrite', 'None')
                    $probe.Dispose()
                }
                foreach ($blocker in $blockers) { $blocker.Dispose() }
                $blockers.Clear()
                $worker.Commands.Clear()
                [void]$worker.AddScript({
                    param($Root)
                    . (Join-Path $Root 'scripts/test-lanes.common.ps1')
                    . (Join-Path $Root 'scripts/test-run-lock.common.ps1')
                    $checkout = Enter-AhkFlowTestRunLock $Root Fresh
                    $run = $null
                    try { $run = Enter-AhkFlowLaneRun Fresh $Root Half; $run.Lanes.Streams.Count }
                    finally { Exit-AhkFlowLaneRun $run; Exit-AhkFlowTestRunLock $checkout }
                }).AddArgument($Root)
                $fresh = $worker.BeginInvoke()
                Assert-True ($fresh.AsyncWaitHandle.WaitOne(10000)) 'The surviving runspace must acquire again.'
                $result = $worker.EndInvoke($fresh)
                Assert-True ($result[-1] -eq 2) 'The fresh reservation must hold Half.'
                Assert-True ($env:AHKFLOW_TEST_LANES_HOLDER -ceq '  ') 'The fresh reservation must restore the marker.'
            } finally {
                if ($worker.InvocationStateInfo.State -eq 'Running') {
                    $stop = $worker.BeginStop($null, $null)
                    if (-not $stop.AsyncWaitHandle.WaitOne(10000)) { throw 'The fixture runspace did not stop.' }
                    $worker.EndStop($stop)
                }
                $worker.Dispose()
            }
        }
    } finally {
        $worker.Dispose()
        foreach ($blocker in $blockers) { $blocker.Dispose() }
        $env:PATH = $previousPath
        Remove-PinnedLanePool $pool
    }
}
