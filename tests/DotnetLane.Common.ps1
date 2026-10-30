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
    if (Test-Path (Join-Path $folder "fail-$number")) { exit 1 }
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
        $held = 0
        foreach ($file in Get-ChildItem $env:AHKFLOW_TEST_LANES_ROOT -Filter 'lane-*.lock') {
            if ($file.Name -eq 'lane-99.lock') { continue }
            try { $probe = [IO.File]::Open($file.FullName, 'OpenOrCreate', 'ReadWrite', 'None'); $probe.Dispose() }
            catch [IO.IOException] { $held++ }
        }
        if ($held -ne 0) {
            throw 'Lane ownership must release before checkout cleanup.'
        }
    }
    & $script:originalCheckoutExit $Handle
}
'@
}

function Test-DotnetLaneRoute {
    param([string] $Root, [string] $ScriptName, [hashtable] $Arguments, [int] $Calls = 1, [switch] $Fail)
    $pool = New-PinnedLanePool 4
    $handles = @{ Child = $null }
    $previousPath = $env:PATH
    try {
        Add-DotnetLaneGate $Root
        # The last gated call fails after its release, so the script throws inside its try.
        if ($Fail) { Set-Content (Join-Path $Root "stub/fail-$Calls") fail }
        $env:PATH = (Join-Path $Root stub) + [IO.Path]::PathSeparator + $previousPath
        Use-LaneEnvironment -Value @{ AHKFLOW_TEST_LANES_ROOT = $pool.Root; AHKFLOW_TEST_LANES_HOLDER = '  ' } -Body {
            $payload = @{ Root = $Root; Script = $ScriptName; Arguments = $Arguments } | ConvertTo-Json -Compress
            $code = @'
param($Json)
$ErrorActionPreference = 'Stop'
$p = $Json | ConvertFrom-Json -AsHashtable
$scriptPath = Join-Path $p.Root ('scripts/' + $p.Script)
$arguments = $p.Arguments
& $scriptPath @arguments
$after = Join-Path $p.Root 'stub/after-1'
Set-Content $after ('holder=' + $env:AHKFLOW_TEST_LANES_HOLDER)
Set-Content "$after.done" complete

'@
            $code = '& { ' + $code + " } '" + $payload.Replace("'", "''") + "'"
            $handles.Child = Start-LaneChildProcess @('-NoProfile', '-EncodedCommand', (ConvertTo-LaneEncodedCommand $code))
            $expected = [string]$handles.Child.Process.Id
            for ($call = 1; $call -le $Calls; $call++) {
                $marker = (Wait-LanePath (Join-Path $Root "stub/ready-$call") 15 $handles.Child).Trim()
                Assert-True ((Get-RunLaneCount $pool) -eq 2) "Expected exactly two of four Lanes during $ScriptName call $call."
                Assert-True ($marker -ceq $expected) "Expected holder '$expected', got '$marker'."
                Assert-True (Test-FileLockHeld (Join-Path $Root '.test-run.lock')) 'The checkout lock must be held at the gated call.'
                Publish-LaneSignal (Join-Path $Root "stub/release-$call")
            }
            $result = Wait-LaneChildProcess $handles.Child 15
            if ($Fail) {
                $output = $result.Output + $result.Error
                Assert-True ($result.ExitCode -ne 0) "The failed route must exit nonzero: $output"
                # A missing run end on the failure path makes the checkout-lock check throw here.
                Assert-True (-not $output.Contains('Lane ownership must release before checkout cleanup.')) 'Lane ownership must release before checkout cleanup.'
                Assert-True ($output.Contains('dotnet test failed')) "The failed route must report the failed test call: $output"
                Assert-True ((Get-RunLaneCount $pool) -eq 0) 'The failed route must release its Lanes.'
                $checkout = Enter-AhkFlowTestRunLock $Root Fresh
                Exit-AhkFlowTestRunLock $checkout
                return
            }
            Assert-True ($result.ExitCode -eq 0) ($result.Output + $result.Error)
            $audits = @(Get-Content (Join-Path $Root 'stub/lane-audit.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
            foreach ($audit in $audits) {
                Assert-True ($audit.Count -eq 2 -and $audit.Holder -ceq $expected) "Every phase must retain Half and its holder: $($audit.Command)."
            }
            if ($ScriptName -eq 'run-coverage.ps1' -or ($Arguments.ContainsKey('Mode') -and $Arguments.Mode -eq 'Coverage')) {
                $thresholdCommand = 'python ' + (Join-Path $Root 'scripts/ci/check-coverage-thresholds.py')
                $phases = [ordered]@{
                    restore = '^dotnet restore(?: |$)'
                    build = '^dotnet build(?: |$)'
                    report = '^reportgenerator(?: |$)'
                    footer = '^' + [regex]::Escape($thresholdCommand + ' --github-summary-footer') + '$'
                    threshold = '^' + [regex]::Escape($thresholdCommand) + '$'
                }
                foreach ($phase in $phases.Keys) {
                    $rows = @($audits | Where-Object { $_.Command -match $phases[$phase] })
                    Assert-True ($rows.Count -eq 1) "Coverage must execute the $phase phase exactly once; found $($rows.Count) audit rows."
                }
                $tests = @($audits | Where-Object { $_.Command -match '^dotnet test(?: |$)' })
                Assert-True ($tests.Count -eq $Calls) "Coverage must execute all $Calls project test phases; found $($tests.Count) audit rows."
            }
            $after = Wait-LanePath (Join-Path $Root 'stub/after-1') 2 $handles.Child
            Assert-True ($after.TrimEnd("`r", "`n") -ceq 'holder=  ') 'The completed route must restore its marker.'
            Assert-True ((Get-RunLaneCount $pool) -eq 0) 'The route must release its Lanes.'
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
        foreach ($call in 1..$Calls) { Publish-LaneSignal (Join-Path $Root "stub/release-$call") }
        Stop-LaneChildProcess $handles.Child
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
        foreach ($index in 1..3) { $blockers.Add([IO.File]::Open((Join-Path $pool.Root "lane-$index.lock"), 'OpenOrCreate', 'ReadWrite', 'None')) }
        Use-LaneEnvironment -Value @{ AHKFLOW_TEST_LANES_ROOT = $pool.Root; AHKFLOW_TEST_LANES_HOLDER = '  ' } -Body {
            try {
                [void]$worker.AddScript({
                    param($Root, $Name)
                    if ($Name -eq 'test-fast.ps1') { & (Join-Path $Root 'scripts/test-fast.ps1') -Mode Fast -NoBuild }
                    else { & (Join-Path $Root 'scripts/run-coverage.ps1') }
                }).AddArgument($Root).AddArgument($ScriptName)
                $invocation = $worker.BeginInvoke()
                # The route waits for its second Lane: it holds the checkout lock, the entry lock and lane 0.
                $watch = [Diagnostics.Stopwatch]::StartNew()
                while (-not ((Test-FileLockHeld (Join-Path $Root '.test-run.lock')) -and (Test-FileLockHeld (Join-Path $pool.Root 'entry.lock')) -and (Get-RunLaneCount $pool) -eq 4)) {
                    Assert-True ($watch.Elapsed.TotalSeconds -lt 10) 'The route never reached its waiting state.'
                    Assert-True ($invocation.IsCompleted -eq $false) 'The route ended before it waited for a Lane.'
                    Start-Sleep -Milliseconds 20
                }
                Assert-True (Test-FileLockHeld (Join-Path $Root '.test-run.lock')) 'The waiting route must retain its checkout lock.'
                Assert-True (Test-FileLockHeld (Join-Path $pool.Root 'entry.lock')) 'The waiting route must retain the admission lock.'
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
