#Requires -Version 7.0

# Backlog 204. scripts/slice-runner.common.ps1 starts one 'dotnet test' process per Slice, keeps at
# most N of them running, and writes one log per Slice. This suite pins the decisions the runner
# makes before it starts anything: the budget, the number of Slices at once, the start order, and
# how a command and its arguments reach the child process. It also pins the processes themselves:
# every Slice runs to the end, each one writes its own log, and a run that stops early ends every
# process it started before the caller releases anything.
#
# Run it by hand with:  pwsh -NoProfile -File ./tests/SliceRunner.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# A non-zero exit code from a child process is data here, not a terminating error.
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$hostExe = [System.Diagnostics.Process]::GetCurrentProcess().Path

. (Join-Path $repoRoot 'scripts/test-lanes.common.ps1')
. (Join-Path $repoRoot 'scripts/progress.common.ps1')
. (Join-Path $repoRoot 'scripts/progress.parallel.ps1')
. (Join-Path $repoRoot 'scripts/slice-runner.common.ps1')

$script:OnWindows = [System.IO.Path]::DirectorySeparatorChar -eq '\'

$script:Failures = New-Object System.Collections.Generic.List[string]

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-TestCase {
    param([string] $Name, [scriptblock] $Body)
    try {
        & $Body
        Write-Host "  PASS  $Name" -ForegroundColor Green
    }
    catch {
        $script:Failures.Add("$Name :: $($_.Exception.Message)")
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        Write-Host "        $($_.Exception.Message)" -ForegroundColor DarkRed
    }
}

function New-TempFolder {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ('slice-runner-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

# The seven argument values. Each one breaks a naive join: a space, an empty value, a ';', a
# trailing backslash, a quote, and the coverage collector name that 'pwsh -File' splits in two.
$script:HardValue = @(
    'plain',
    'two words',
    '',
    'trx;LogFileName=a.trx',
    'C:\dir with space\',
    'say "hi"',
    '--collect:XPlat Code Coverage'
)

function Get-Order {
    param([string[]] $Name, [System.Collections.IDictionary] $History, [int] $SlicesAtOnce)
    $slices = @($Name | ForEach-Object { New-AhkFlowSlice -Name $_ -Command 'dotnet' -Argument @('test') -LogPath "$_.log" })
    return (@(Get-AhkFlowSliceOrder -Slice $slices -History $History -SlicesAtOnce $SlicesAtOnce) | ForEach-Object { $_.Name }) -join ','
}

function Invoke-Started {
    param([object] $Start, [string] $WorkingDirectory)
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $Start.FilePath
    $info.Arguments = $Start.Arguments
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    if ($WorkingDirectory) { $info.WorkingDirectory = $WorkingDirectory }
    $process = [System.Diagnostics.Process]::Start($info)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    return [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $stdout.Result; Error = $stderr.Result }
}

function Use-StubOnPath {
    param([string] $StubBody, [scriptblock] $Body)
    $folder = New-TempFolder
    Set-Content -LiteralPath (Join-Path $folder 'dotnet.ps1') -Value $StubBody -Encoding UTF8
    $previous = $env:PATH
    try {
        $env:PATH = $folder + [System.IO.Path]::PathSeparator + $previous
        & $Body $folder
    }
    finally {
        $env:PATH = $previous
        Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host 'SliceRunner tests'

# --- The budget and the number of Slices at once ---

Invoke-TestCase 'The budget of an owner run is the Lanes it holds' {
    $state = [pscustomobject]@{ Role = 'owner'; Lanes = [pscustomobject]@{ Streams = @('a', 'b', 'c') } }
    $budget = Get-AhkFlowSliceBudget -LaneRun $state
    Assert-True ($budget -eq 3) "Expected 3, got $budget."
}

Invoke-TestCase 'A nested run and a run with Lanes off use half the proposal, rounded up' {
    $nested = Get-AhkFlowSliceBudget -LaneRun ([pscustomobject]@{ Role = 'nested'; Lanes = $null }) -Proposal 6
    $off = Get-AhkFlowSliceBudget -LaneRun ([pscustomobject]@{ Role = 'off'; Lanes = $null }) -Proposal 5
    $one = Get-AhkFlowSliceBudget -LaneRun ([pscustomobject]@{ Role = 'nested'; Lanes = $null }) -Proposal 1
    Assert-True ($nested -eq 3) "nested 6: expected 3, got $nested."
    Assert-True ($off -eq 3) "off 5: expected 3, got $off."
    Assert-True ($one -eq 1) "nested 1: expected 1, got $one."
}

Invoke-TestCase 'SlicesAtOnce never goes above the budget' {
    foreach ($case in @(@('Budget', 3, 3), @('budget', 2, 2), @('2', 3, 2), @('8', 3, 3), @('1', 3, 1))) {
        $value = Resolve-AhkFlowSlicesAtOnce -Requested $case[0] -Budget $case[1] 6>$null
        Assert-True ($value -eq $case[2]) "($($case[0]), $($case[1])): expected $($case[2]), got $value."
    }
}

Invoke-TestCase 'SlicesAtOnce refuses any other value' {
    foreach ($value in @('0', '-1', 'abc', '', '2.5')) {
        $message = $null
        try { Resolve-AhkFlowSlicesAtOnce -Requested $value -Budget 3 6>$null | Out-Null }
        catch { $message = $_.Exception.Message }
        Assert-True ($null -ne $message -and $message.Contains('-SlicesAtOnce takes a whole number of at least 1, or Budget.')) "'$value' was not refused with the expected message. Got: $message"
    }
}

Invoke-TestCase 'SlicesAtOnce prints the value it chose' {
    $output = (Resolve-AhkFlowSlicesAtOnce -Requested 'Budget' -Budget 3 6>&1 | Out-String)
    Assert-True ($output.Contains('Slices at once: 3 (asked for Budget, budget 3)')) "Output: $output"
}

# --- The start order ---

Invoke-TestCase 'At the value 1 the order is the given order' {
    $order = Get-Order -Name @('A', 'B', 'C') -History @{ C = 90.0; A = 10.0 } -SlicesAtOnce 1
    Assert-True ($order -eq 'A,B,C') "Got $order."
}

Invoke-TestCase 'Side by side the longest Slice starts first, and a Slice with no history counts as longest' {
    $order = Get-Order -Name @('A', 'B', 'C') -History @{ C = 90.0; A = 10.0 } -SlicesAtOnce 2
    Assert-True ($order -eq 'B,C,A') "Got $order."
}

Invoke-TestCase 'Equal seconds keep the given order' {
    $order = Get-Order -Name @('A', 'B', 'C') -History @{ A = 5.0; B = 5.0; C = 5.0 } -SlicesAtOnce 3
    Assert-True ($order -eq 'A,B,C') "Equal: got $order."
    $empty = Get-Order -Name @('A', 'B', 'C') -History @{} -SlicesAtOnce 3
    Assert-True ($empty -eq 'A,B,C') "Empty history: got $empty."
}

Invoke-TestCase 'A stored name that no longer exists changes nothing' {
    $order = Get-Order -Name @('A', 'B', 'C') -History @{ Z = 999.0; A = 10.0; B = 20.0; C = 30.0 } -SlicesAtOnce 2
    Assert-True ($order -eq 'C,B,A') "Got $order."
}

# --- How a command and its arguments reach the child ---

Invoke-TestCase 'An argument reaches a native child process whole' {
    $folder = New-TempFolder
    try {
        $argv = Join-Path $folder 'argv.ps1'
        Set-Content -LiteralPath $argv -Value '[Environment]::GetCommandLineArgs() | ForEach-Object { [Console]::Out.WriteLine($_) }' -Encoding UTF8
        $arguments = ConvertTo-AhkFlowArgumentString -Argument (@('-NoProfile', '-File', $argv) + $script:HardValue)
        $result = Invoke-Started -Start ([pscustomobject]@{ FilePath = $hostExe; Arguments = $arguments })
        $lines = @($result.Output -split '\r?\n')
        if ($lines.Count -gt 0 -and $lines[-1] -eq '') { $lines = @($lines[0..($lines.Count - 2)]) }
        $last = @($lines | Select-Object -Last $script:HardValue.Count)
        for ($i = 0; $i -lt $script:HardValue.Count; $i++) {
            Assert-True ($last[$i] -ceq $script:HardValue[$i]) "Value $i expected [$($script:HardValue[$i])], got [$($last[$i])]. Arguments: $arguments"
        }
    }
    finally { Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue }
}

Invoke-TestCase 'A PowerShell stub on PATH runs as the script, with every argument whole' {
    $stub = @'
$path = Join-Path $PSScriptRoot 'args.txt'
[System.IO.File]::WriteAllText($path, (($args | ForEach-Object { [string]$_ }) -join "`n"))
exit 0
'@
    Use-StubOnPath -StubBody $stub -Body {
        param($folder)
        $start = Resolve-AhkFlowSliceStart -Command 'dotnet' -Argument $script:HardValue
        Assert-True ($start.FilePath -eq $hostExe) "FilePath was $($start.FilePath), not the current host."
        $result = Invoke-Started -Start $start
        Assert-True ($result.ExitCode -eq 0) "Exit code $($result.ExitCode). Error: $($result.Error)"
        $written = @([System.IO.File]::ReadAllText((Join-Path $folder 'args.txt')) -split "`n")
        Assert-True ($written.Count -eq $script:HardValue.Count) "Expected $($script:HardValue.Count) values, got $($written.Count): $($written -join '|')"
        for ($i = 0; $i -lt $script:HardValue.Count; $i++) {
            Assert-True ($written[$i] -ceq $script:HardValue[$i]) "Value $i expected [$($script:HardValue[$i])], got [$($written[$i])]."
        }
    }
}

Invoke-TestCase "A stub's exit code comes through, and a stub that throws exits 1" {
    Use-StubOnPath -StubBody 'exit 3' -Body {
        $result = Invoke-Started -Start (Resolve-AhkFlowSliceStart -Command 'dotnet' -Argument @('test'))
        Assert-True ($result.ExitCode -eq 3) "exit 3 gave $($result.ExitCode)."
    }
    Use-StubOnPath -StubBody "throw 'boom'" -Body {
        $result = Invoke-Started -Start (Resolve-AhkFlowSliceStart -Command 'dotnet' -Argument @('test'))
        Assert-True ($result.ExitCode -eq 1) "throw gave $($result.ExitCode)."
    }
}

Invoke-TestCase 'A command that cannot be found names itself' {
    $message = $null
    try { Resolve-AhkFlowSliceStart -Command 'no-such-command-204' -Argument @('x') | Out-Null }
    catch { $message = $_.Exception.Message }
    Assert-True ($message -eq "Cannot find the command 'no-such-command-204' for a Slice.") "Got: $message"
}

# --- The processes ---

# A fake Slice. It must also run in Windows PowerShell 5.1, because the 5.1 case below starts it
# with powershell.exe. It marks its start and its end with UTC ticks, writes one line to each
# output stream, and can leave a grandchild behind. The grandchild gets all three streams
# redirected, so it does not hold the Slice's output pipe open.
$script:FakeBody = @'
param(
    [string] $Name,
    [string] $Marker,
    [int] $ExitCode = 0,
    [int] $SleepMs = 0,
    [switch] $Grandchild,
    [switch] $Intermediate,
    [switch] $StartGrandchildOnly,
    [string] $WaitFor = ''
)
$ErrorActionPreference = 'Stop'
$hostPath = [System.Diagnostics.Process]::GetCurrentProcess().Path
function Write-Marker([string] $File, [string] $Text) {
    [System.IO.File]::WriteAllText((Join-Path $Marker $File), $Text)
}
function Start-Hidden([string] $Arguments) {
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $hostPath
    $info.Arguments = $Arguments
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    return [System.Diagnostics.Process]::Start($info)
}
function Start-Grandchild {
    $p = Start-Hidden '-NoProfile -NonInteractive -Command Start-Sleep 300'
    Write-Marker "grandchild-$Name.txt" ([string]$p.Id)
}
if ($StartGrandchildOnly) {
    Start-Grandchild
    Write-Marker "intermediate-$Name.txt" ([string]$PID)
    exit 0
}
$start = "$PID $([DateTime]::UtcNow.Ticks)"
if ([System.IO.Path]::DirectorySeparatorChar -ne '\') {
    $start += ' ' + ((& ps -o ppid=,pgid= -p $PID) -join ' ').Trim()
}
Write-Marker "start-$Name.txt" $start
[Console]::Out.WriteLine("out-$Name")
[Console]::Error.WriteLine("err-$Name")
if ($Grandchild) { Start-Grandchild }
if ($Intermediate) {
    $self = $MyInvocation.MyCommand.Path
    $middle = Start-Hidden ("-NoProfile -NonInteractive -File `"$self`" -Name $Name -Marker `"$Marker`" -StartGrandchildOnly")
    $middle.WaitForExit()
}
if ($WaitFor) {
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    while (-not (Test-Path -LiteralPath $WaitFor) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 50 }
}
if ($SleepMs -gt 0) { Start-Sleep -Milliseconds $SleepMs }
Write-Marker "end-$Name.txt" ([string][DateTime]::UtcNow.Ticks)
exit $ExitCode
'@

$script:FakeFolder = New-TempFolder
$script:FakePath = Join-Path $script:FakeFolder 'fake.ps1'
Set-Content -LiteralPath $script:FakePath -Value $script:FakeBody -Encoding UTF8

function New-FakeArgument {
    param(
        [string] $Name, [string] $Folder, [int] $ExitCode = 0, [int] $SleepMs = 0,
        [switch] $Grandchild, [switch] $Intermediate, [string] $WaitFor = ''
    )
    $list = @('-NoProfile', '-NonInteractive', '-File', $script:FakePath, '-Name', $Name, '-Marker', $Folder,
        '-ExitCode', [string]$ExitCode, '-SleepMs', [string]$SleepMs)
    if ($Grandchild) { $list += '-Grandchild' }
    if ($Intermediate) { $list += '-Intermediate' }
    if ($WaitFor) { $list += @('-WaitFor', $WaitFor) }
    return , $list
}

function New-FakeSlice {
    param(
        [string] $Name, [string] $Folder, [int] $ExitCode = 0, [int] $SleepMs = 0,
        [switch] $Grandchild, [switch] $Intermediate, [string] $WaitFor = '', [string] $Command = $hostExe
    )
    $argument = New-FakeArgument -Name $Name -Folder $Folder -ExitCode $ExitCode -SleepMs $SleepMs -Grandchild:$Grandchild -Intermediate:$Intermediate -WaitFor $WaitFor
    return New-AhkFlowSlice -Name $Name -Command $Command -Argument $argument -LogPath (Join-Path (Join-Path $Folder $Name) "$Name.log")
}

function New-TestTracker {
    param([string[]] $Unit)
    return New-ProgressTracker -RunnerKey 'slice-runner-tests' -Unit $Unit -NoStore
}

function Read-Marker {
    param([string] $Folder, [string] $File)
    $path = Join-Path $Folder $File
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return [System.IO.File]::ReadAllText($path).Trim()
}

function Get-MarkerId {
    param([string] $Folder, [string] $File)
    $text = Read-Marker -Folder $Folder -File $File
    if ($null -eq $text) { return $null }
    return [int](($text -split '\s+')[0])
}

function Get-StartTick { param([string] $Folder, [string] $Name) return [long]((Read-Marker $Folder "start-$Name.txt") -split '\s+')[1] }
function Get-EndTick { param([string] $Folder, [string] $Name) return [long](Read-Marker $Folder "end-$Name.txt") }

function Test-ProcessGone {
    param([int] $Id, [int] $Seconds = 2)
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    while ($null -ne (Get-Process -Id $Id -ErrorAction SilentlyContinue)) {
        if ([DateTime]::UtcNow -gt $deadline) { return $false }
        Start-Sleep -Milliseconds 100
    }
    return $true
}

function Wait-ForPath {
    param([string[]] $Path, [int] $Seconds = 30)
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    while (@($Path | Where-Object { -not (Test-Path -LiteralPath $_) }).Count -gt 0) {
        if ([DateTime]::UtcNow -gt $deadline) { throw "Timed out waiting for: $($Path -join ', ')" }
        Start-Sleep -Milliseconds 100
    }
}

# Ends every process a case's markers name, so no case leaves a 300 s sleep behind.
function Stop-MarkedProcess {
    param([string] $Folder)
    foreach ($file in @(Get-ChildItem -LiteralPath $Folder -Filter '*.txt' -File -ErrorAction SilentlyContinue)) {
        if ($file.Name -notmatch '^(start|grandchild|intermediate)-') { continue }
        $id = Get-MarkerId -Folder $Folder -File $file.Name
        if ($id) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
    }
}

function Split-SliceOutput {
    param([object[]] $Item)
    $lines = New-Object System.Collections.Generic.List[string]
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($entry in @($Item)) {
        if ($entry -is [System.Management.Automation.InformationRecord]) { $lines.Add([string]$entry.MessageData) }
        elseif ($entry -is [string]) { $lines.Add($entry) }
        else { $results.Add($entry) }
    }
    return [pscustomobject]@{ Lines = $lines.ToArray(); Results = $results.ToArray() }
}

Invoke-TestCase 'Every Slice runs to the end after another Slice fails' {
    $folder = New-TempFolder
    try {
        $slices = @(
            (New-FakeSlice -Name 'A' -Folder $folder -ExitCode 1),
            (New-FakeSlice -Name 'B' -Folder $folder -ExitCode 0),
            (New-FakeSlice -Name 'C' -Folder $folder -ExitCode 3))
        $results = @(Invoke-AhkFlowSliceSet -Slice $slices -SlicesAtOnce 1 -WorkingDirectory $folder -Tracker (New-TestTracker @('A', 'B', 'C')) 6>$null)
        Assert-True (($results | ForEach-Object { $_.ExitCode }) -join ',' -eq '1,0,3') "Exit codes: $(($results | ForEach-Object { $_.ExitCode }) -join ',')"
        foreach ($name in @('A', 'B', 'C')) {
            Assert-True (Test-Path -LiteralPath (Join-Path $folder "end-$name.txt")) "Slice $name did not run to the end."
        }
    }
    finally { Stop-MarkedProcess $folder; Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue }
}

Invoke-TestCase 'No more Slices run at once than the number allows' {
    $folder = New-TempFolder
    try {
        $names = @('A', 'B', 'C', 'D')
        $slices = @($names | ForEach-Object { New-FakeSlice -Name $_ -Folder $folder -SleepMs 3000 })
        [void](Invoke-AhkFlowSliceSet -Slice $slices -SlicesAtOnce 2 -WorkingDirectory $folder -Tracker (New-TestTracker $names) 6>$null)
        $most = 0
        foreach ($name in $names) {
            $moment = Get-StartTick $folder $name
            $running = @($names | Where-Object { (Get-StartTick $folder $_) -le $moment -and (Get-EndTick $folder $_) -gt $moment }).Count
            if ($running -gt $most) { $most = $running }
        }
        Assert-True ($most -eq 2) "The most Slices running at one moment was $most, not 2."
    }
    finally { Stop-MarkedProcess $folder; Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue }
}

Invoke-TestCase 'At the value 1 the Slices run one after another, in the given order' {
    $folder = New-TempFolder
    try {
        $names = @('A', 'B', 'C')
        $slices = @($names | ForEach-Object { New-FakeSlice -Name $_ -Folder $folder -SleepMs 200 })
        [void](Invoke-AhkFlowSliceSet -Slice $slices -SlicesAtOnce 1 -WorkingDirectory $folder -Tracker (New-TestTracker $names) 6>$null)
        Assert-True ((Get-StartTick $folder 'B') -gt (Get-EndTick $folder 'A')) 'B started before A ended.'
        Assert-True ((Get-StartTick $folder 'C') -gt (Get-EndTick $folder 'B')) 'C started before B ended.'
    }
    finally { Stop-MarkedProcess $folder; Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue }
}

Invoke-TestCase 'Each Slice writes its output and its errors to its own log' {
    $folder = New-TempFolder
    try {
        $slices = @((New-FakeSlice -Name 'A' -Folder $folder), (New-FakeSlice -Name 'B' -Folder $folder))
        $results = @(Invoke-AhkFlowSliceSet -Slice $slices -SlicesAtOnce 2 -WorkingDirectory $folder -Tracker (New-TestTracker @('A', 'B')) 6>$null)
        $logA = [System.IO.File]::ReadAllText($results[0].LogPath)
        $logB = [System.IO.File]::ReadAllText($results[1].LogPath)
        $out = $logA.IndexOf('out-A'); $marker = $logA.IndexOf('--- standard error ---'); $err = $logA.IndexOf('err-A')
        Assert-True ($out -ge 0 -and $marker -gt $out -and $err -gt $marker) "A.log is not in the order out, marker, err: $logA"
        Assert-True (-not (Test-Path -LiteralPath ($results[0].LogPath + '.stderr'))) 'A.log.stderr was left behind.'
        Assert-True (-not $logB.Contains('out-A')) "B.log holds the output of A: $logB"
    }
    finally { Stop-MarkedProcess $folder; Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue }
}

Invoke-TestCase 'The console names the log at the start and gives the result at the end' {
    $folder = New-TempFolder
    try {
        $slice = New-FakeSlice -Name 'A' -Folder $folder -ExitCode 1
        $output = Split-SliceOutput @(Invoke-AhkFlowSliceSet -Slice @($slice) -SlicesAtOnce 1 -WorkingDirectory $folder -Tracker (New-TestTracker @('A')) 6>&1)
        Assert-True ($output.Lines -contains "start A  log $($slice.LogPath)") "No start line. Lines: $($output.Lines -join ' | ')"
        $done = @($output.Lines | Where-Object { $_ -match '^\[\d+/\d+ done\] A\s+\d+[.,]\ds\s+elapsed \S+\s+FAILED \(exit 1\)$' })
        Assert-True ($done.Count -eq 1) "No done line. Lines: $($output.Lines -join ' | ')"
    }
    finally { Stop-MarkedProcess $folder; Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue }
}

Invoke-TestCase 'The done count goes on from the units before the Slices' {
    $folder = New-TempFolder
    try {
        $tracker = New-TestTracker @('build', 'A', 'B', 'report')
        Start-ProgressUnit -Tracker $tracker -Name 'build' 6>$null
        Stop-ProgressUnit -Tracker $tracker
        $slices = @((New-FakeSlice -Name 'A' -Folder $folder), (New-FakeSlice -Name 'B' -Folder $folder))
        $output = Split-SliceOutput @(Invoke-AhkFlowSliceSet -Slice $slices -SlicesAtOnce 1 -WorkingDirectory $folder -Tracker $tracker 6>&1)
        Assert-True (@($output.Lines | Where-Object { $_.StartsWith('[2/4 done] A') }).Count -eq 1) "No [2/4 done] A line. Lines: $($output.Lines -join ' | ')"
        Assert-True (@($output.Lines | Where-Object { $_.StartsWith('[3/4 done] B') }).Count -eq 1) "No [3/4 done] B line. Lines: $($output.Lines -join ' | ')"
        Assert-True ($tracker.Index -eq 3) "Index is $($tracker.Index), not 3."
        Assert-True ($tracker.Completed.Contains('A') -and $tracker.Completed.Contains('B')) 'Completed does not hold A and B.'
    }
    finally { Stop-MarkedProcess $folder; Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue }
}

Invoke-TestCase 'A Slice that cannot start stops the run, and every started process has exited first' {
    $folder = New-TempFolder
    try {
        $slices = @(
            (New-FakeSlice -Name 'A' -Folder $folder -SleepMs 60000 -Grandchild),
            (New-FakeSlice -Name 'Q' -Folder $folder -SleepMs 100 -WaitFor (Join-Path $folder 'grandchild-A.txt')),
            (New-AhkFlowSlice -Name 'B' -Command 'no-such-command-204' -Argument @('test') -LogPath (Join-Path $folder 'B/B.log')))
        $message = $null
        try { [void](Invoke-AhkFlowSliceSet -Slice $slices -SlicesAtOnce 2 -WorkingDirectory $folder -Tracker (New-TestTracker @('A', 'Q', 'B')) 6>$null) }
        catch {
            $message = $_.Exception.Message
            $fake = Get-MarkerId $folder 'start-A.txt'
            $grandchild = Get-MarkerId $folder 'grandchild-A.txt'
            Assert-True ($null -ne $fake -and (Test-ProcessGone $fake)) "The fake A ($fake) still runs."
            Assert-True ($null -ne $grandchild -and (Test-ProcessGone $grandchild)) "The grandchild of A ($grandchild) still runs."
        }
        Assert-True ($null -ne $message -and $message.Contains('Slice B could not start')) "Message: $message"
    }
    finally { Stop-MarkedProcess $folder; Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue }
}

Invoke-TestCase 'A process that a finished Slice left behind is ended when a later Slice cannot start' {
    $folder = New-TempFolder
    try {
        $slices = @(
            (New-FakeSlice -Name 'A' -Folder $folder -SleepMs 100 -Grandchild),
            (New-AhkFlowSlice -Name 'B' -Command 'no-such-command-204' -Argument @('test') -LogPath (Join-Path $folder 'B/B.log')))
        $collected = New-Object System.Collections.Generic.List[object]
        $message = $null
        try {
            Invoke-AhkFlowSliceSet -Slice $slices -SlicesAtOnce 1 -WorkingDirectory $folder -Tracker (New-TestTracker @('A', 'B')) 6>&1 |
                ForEach-Object { $collected.Add($_) }
        }
        catch {
            $message = $_.Exception.Message
            $grandchild = Get-MarkerId $folder 'grandchild-A.txt'
            Assert-True ($null -ne $grandchild -and (Test-ProcessGone $grandchild)) "The grandchild of A ($grandchild) still runs."
        }
        $output = Split-SliceOutput $collected.ToArray()
        $grandchild = Get-MarkerId $folder 'grandchild-A.txt'
        Assert-True (@($output.Lines | Where-Object { $_.Contains('Slice A left 1 process running') -and $_.Contains([string]$grandchild) }).Count -eq 1) "No left-behind line for $grandchild. Lines: $($output.Lines -join ' | ')"
        Assert-True ($null -ne $message -and $message.Contains('Slice B could not start')) "Message: $message"
        Assert-True (Test-Path -LiteralPath (Join-Path $folder 'end-A.txt')) 'A had not ended before B was tried.'
    }
    finally { Stop-MarkedProcess $folder; Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue }
}

# Runs Slices in a runspace of their own, so the case can stop that runspace the way Ctrl+C stops
# a script. The script's 'finally' stands for the caller's release of the lock and the Lanes: it
# writes every marked process that still runs to released.txt.
function Start-StopRunspace {
    param([object[]] $Slice, [int] $SlicesAtOnce, [string] $Folder, [int] $RoundSeconds = 30, [string] $Wrapper = '')
    $worker = [PowerShell]::Create()
    [void]$worker.AddScript({
        param($Repo, $Slice, $SlicesAtOnce, $Folder, $RoundSeconds, $Wrapper)
        $ErrorActionPreference = 'Stop'
        . (Join-Path $Repo 'scripts/test-lanes.common.ps1')
        . (Join-Path $Repo 'scripts/progress.common.ps1')
        . (Join-Path $Repo 'scripts/progress.parallel.ps1')
        . (Join-Path $Repo 'scripts/slice-runner.common.ps1')
        $global:SliceTestRealKill = ${function:Invoke-AhkFlowOwnerKill}
        $global:SliceTestFolder = $Folder
        if ($Wrapper -eq 'record') {
            function Invoke-AhkFlowOwnerKill {
                param([object] $Owner)
                Add-Content -LiteralPath (Join-Path $global:SliceTestFolder 'kill-calls.txt') -Value ([string]$Owner.Kind)
                & $global:SliceTestRealKill -Owner $Owner
            }
        }
        if ($Wrapper -eq 'skip-first') {
            function Invoke-AhkFlowOwnerKill {
                param([object] $Owner)
                $first = Join-Path $global:SliceTestFolder 'kill-1.txt'
                if (-not (Test-Path -LiteralPath $first)) { Set-Content -LiteralPath $first -Value 'skipped'; return }
                Add-Content -LiteralPath (Join-Path $global:SliceTestFolder 'kill-calls.txt') -Value ([string]$Owner.Kind)
                & $global:SliceTestRealKill -Owner $Owner
            }
        }
        $tracker = New-ProgressTracker -RunnerKey 'slice-runner-tests' -Unit @($Slice | ForEach-Object { $_.Name }) -NoStore
        try {
            Invoke-AhkFlowSliceSet -Slice $Slice -SlicesAtOnce $SlicesAtOnce -WorkingDirectory $Folder -Tracker $tracker -StopRoundSeconds $RoundSeconds
        }
        finally {
            $running = New-Object System.Collections.Generic.List[string]
            foreach ($file in @(Get-ChildItem -LiteralPath $Folder -Filter '*.txt' -File)) {
                if ($file.Name -notmatch '^(start|grandchild|intermediate)-') { continue }
                $id = [int](([System.IO.File]::ReadAllText($file.FullName).Trim() -split '\s+')[0])
                if ($null -ne (Get-Process -Id $id -ErrorAction SilentlyContinue)) { $running.Add([string]$id) }
            }
            [System.IO.File]::WriteAllText((Join-Path $Folder 'released.txt'), ($running -join ' '))
        }
    }).AddArgument($repoRoot).AddArgument($Slice).AddArgument($SlicesAtOnce).AddArgument($Folder).AddArgument($RoundSeconds).AddArgument($Wrapper)
    $invocation = $worker.BeginInvoke()
    return [pscustomobject]@{ Worker = $worker; Invocation = $invocation }
}

function Stop-StopRunspace {
    param([object] $Run, [int] $Seconds = 90)
    $stopping = $Run.Worker.BeginStop($null, $null)
    $stopped = $stopping.AsyncWaitHandle.WaitOne($Seconds * 1000)
    if ($stopped) { $Run.Worker.EndStop($stopping) }
    return $stopped
}

function Get-RunspaceText {
    param([object] $Run)
    return (@($Run.Worker.Streams.Information | ForEach-Object { [string]$_.MessageData }) -join "`n")
}

Invoke-TestCase 'A process whose parent already exited is ended by the stop' {
    $folder = New-TempFolder
    $run = $null
    try {
        $run = Start-StopRunspace -Slice @(New-FakeSlice -Name 'A' -Folder $folder -SleepMs 300000 -Intermediate) -SlicesAtOnce 1 -Folder $folder
        Wait-ForPath @((Join-Path $folder 'grandchild-A.txt'), (Join-Path $folder 'intermediate-A.txt'))
        $intermediate = Get-MarkerId $folder 'intermediate-A.txt'
        $grandchild = Get-MarkerId $folder 'grandchild-A.txt'
        Assert-True (Test-ProcessGone $intermediate 10) "The intermediate ($intermediate) did not exit."
        if (-not $script:OnWindows) {
            $parent = ((& ps -o ppid= -p $grandchild) -join '').Trim()
            Assert-True ($parent -ne [string]$intermediate) 'The grandchild still names the intermediate as its parent.'
        }
        Assert-True (Stop-StopRunspace $run) 'The runspace did not stop within 90 s.'
        Assert-True ((Read-Marker $folder 'released.txt') -eq '') "released.txt: '$(Read-Marker $folder 'released.txt')'"
        Assert-True (Test-ProcessGone $grandchild) "The grandchild ($grandchild) still runs."
    }
    finally {
        if ($null -ne $run) { $run.Worker.Dispose() }
        Stop-MarkedProcess $folder; Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$script:StopCase = $null

Invoke-TestCase 'Stopping the run ends every Slice it started before the caller releases anything' {
    $folder = New-TempFolder
    $run = $null
    $unrelated = $null
    try {
        $unrelated = Start-Process -FilePath $hostExe -ArgumentList '-NoProfile -NonInteractive -Command Start-Sleep 300' -PassThru -WindowStyle Hidden
        $slices = @(
            (New-FakeSlice -Name 'A' -Folder $folder -SleepMs 100 -Grandchild),
            (New-FakeSlice -Name 'B' -Folder $folder -SleepMs 300000 -Grandchild),
            (New-FakeSlice -Name 'C' -Folder $folder -SleepMs 300000 -Grandchild))
        $run = Start-StopRunspace -Slice $slices -SlicesAtOnce 2 -Folder $folder -Wrapper 'record'
        Wait-ForPath @('A', 'B', 'C' | ForEach-Object { Join-Path $folder "grandchild-$_.txt" }) 60
        $marked = @('start-A', 'start-B', 'start-C', 'grandchild-A', 'grandchild-B', 'grandchild-C' | ForEach-Object { Get-MarkerId $folder "$_.txt" })
        Assert-True (Stop-StopRunspace $run) 'The runspace did not stop within 90 s.'
        Assert-True ((Read-Marker $folder 'released.txt') -eq '') "released.txt: '$(Read-Marker $folder 'released.txt')'"
        foreach ($id in $marked) { Assert-True (Test-ProcessGone $id) "Marked process $id still runs." }
        $script:StopCase = [pscustomobject]@{
            UnrelatedAlive = ($null -ne (Get-Process -Id $unrelated.Id -ErrorAction SilentlyContinue))
            Calls = @(Get-Content -LiteralPath (Join-Path $folder 'kill-calls.txt') -ErrorAction SilentlyContinue)
        }
    }
    finally {
        if ($null -ne $run) { $run.Worker.Dispose() }
        if ($null -ne $unrelated) { Stop-Process -Id $unrelated.Id -Force -ErrorAction SilentlyContinue }
        Stop-MarkedProcess $folder; Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-TestCase 'The stop never ends a process that the run did not start' {
    Assert-True ($null -ne $script:StopCase) 'The stop case did not get far enough to tell.'
    Assert-True $script:StopCase.UnrelatedAlive 'The stop ended a process the run did not start.'
    Assert-True ($script:StopCase.Calls.Count -gt 0) 'The kill wrapper recorded no call.'
    foreach ($kind in $script:StopCase.Calls) {
        Assert-True ($kind -eq 'job' -or $kind -eq 'group') "The kill took '$kind', not an owner."
    }
}

Invoke-TestCase 'A process that outlives the first kill keeps the run from returning' {
    $folder = New-TempFolder
    $run = $null
    try {
        $run = Start-StopRunspace -Slice @(New-FakeSlice -Name 'A' -Folder $folder -SleepMs 300000 -Grandchild) -SlicesAtOnce 1 -Folder $folder -RoundSeconds 3 -Wrapper 'skip-first'
        Wait-ForPath @(Join-Path $folder 'grandchild-A.txt')
        $grandchild = Get-MarkerId $folder 'grandchild-A.txt'
        $stopping = $run.Worker.BeginStop($null, $null)
        Wait-ForPath @(Join-Path $folder 'kill-1.txt')
        $until = [DateTime]::UtcNow.AddSeconds(2)
        while ([DateTime]::UtcNow -lt $until) {
            Assert-True (-not (Test-Path -LiteralPath (Join-Path $folder 'released.txt'))) 'released.txt appeared while a process still ran.'
            Assert-True ($null -ne (Get-Process -Id $grandchild -ErrorAction SilentlyContinue)) 'The grandchild ended before the second kill.'
            Start-Sleep -Milliseconds 200
        }
        Assert-True ($stopping.AsyncWaitHandle.WaitOne(30000)) 'The runspace did not stop within 30 s.'
        $run.Worker.EndStop($stopping)
        Assert-True ((Read-Marker $folder 'released.txt') -eq '') "released.txt: '$(Read-Marker $folder 'released.txt')'"
        $text = Get-RunspaceText $run
        Assert-True ($text.Contains('The run keeps the test-run lock and its Lanes until they exit.')) "Output: $text"
        $calls = @(Get-Content -LiteralPath (Join-Path $folder 'kill-calls.txt') -ErrorAction SilentlyContinue)
        Assert-True ($calls.Count -ge 1) 'The real kill never ran after the skipped one.'
    }
    finally {
        if ($null -ne $run) { $run.Worker.Dispose() }
        Stop-MarkedProcess $folder; Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($script:OnWindows) {
    Invoke-TestCase 'On Windows every process of a Slice is in its job' {
        $folder = New-TempFolder
        $owner = $null
        try {
            $owner = New-AhkFlowSliceOwner
            $start = Resolve-AhkFlowSliceStart -Command $hostExe -Argument (New-FakeArgument -Name 'A' -Folder $folder -SleepMs 60000 -Grandchild)
            [void](Start-AhkFlowOwnedProcess -Start $start -Owner $owner -WorkingDirectory $folder)
            Wait-ForPath @(Join-Path $folder 'grandchild-A.txt')
            foreach ($id in @((Get-MarkerId $folder 'grandchild-A.txt'), (Get-MarkerId $folder 'start-A.txt'))) {
                $inJob = $false
                [void][AhkFlow.SliceJob]::IsProcessInJob((Get-Process -Id $id).Handle, $owner.Job, [ref]$inJob)
                Assert-True $inJob "Process $id is not in the job."
            }
            $self = $false
            [void][AhkFlow.SliceJob]::IsProcessInJob([System.Diagnostics.Process]::GetCurrentProcess().Handle, $owner.Job, [ref]$self)
            Assert-True (-not $self) "The test's own process is in the job."
            Invoke-AhkFlowOwnerKill -Owner $owner
            $deadline = [DateTime]::UtcNow.AddSeconds(10)
            while ((Test-AhkFlowOwnerActive -Owner $owner) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
            Assert-True (-not (Test-AhkFlowOwnerActive -Owner $owner)) 'The job still has a process 10 s after the kill.'
        }
        finally {
            if ($null -ne $owner) { Close-AhkFlowSliceOwner -Owner $owner }
            Stop-MarkedProcess $folder; Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
else {
    Write-Host '  SKIP  On Windows every process of a Slice is in its job (this is not Windows)' -ForegroundColor Yellow
}

if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Linux)) {
    Invoke-TestCase 'On Linux a Slice is its own process group, and setsid does not fork' {
        $folder = New-TempFolder
        try {
            [void](Invoke-AhkFlowSliceSet -Slice @(New-FakeSlice -Name 'A' -Folder $folder) -SlicesAtOnce 1 -WorkingDirectory $folder -Tracker (New-TestTracker @('A')) 6>$null)
            $fields = (Read-Marker $folder 'start-A.txt') -split '\s+'
            Assert-True ($fields[3] -eq $fields[0]) "The process group $($fields[3]) is not the fake's own id $($fields[0])."
            Assert-True ($fields[2] -eq [string]$PID) "The parent $($fields[2]) is not the test's own id $PID."
        }
        finally { Stop-MarkedProcess $folder; Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
else {
    Write-Host '  SKIP  On Linux a Slice is its own process group, and setsid does not fork (this is not Linux)' -ForegroundColor Yellow
}

$script:WindowsPowerShell = $null
if ($script:OnWindows) {
    $candidate = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { $script:WindowsPowerShell = $candidate }
}
if ($script:WindowsPowerShell) {
    Invoke-TestCase 'Windows PowerShell 5.1 runs the Slice runner' {
        $folder = New-TempFolder
        try {
            $driver = Join-Path $folder 'driver.ps1'
            $driverBody = @'
param([string] $Repo, [string] $Folder, [string] $Fake)
$ErrorActionPreference = 'Stop'
. (Join-Path $Repo 'scripts\test-lanes.common.ps1')
. (Join-Path $Repo 'scripts\progress.common.ps1')
. (Join-Path $Repo 'scripts\progress.parallel.ps1')
. (Join-Path $Repo 'scripts\slice-runner.common.ps1')
$hostPath = [System.Diagnostics.Process]::GetCurrentProcess().Path
function New-Fake([string] $Name, [int] $ExitCode, [int] $SleepMs, [switch] $Grandchild, [string] $WaitFor) {
    $list = @('-NoProfile', '-NonInteractive', '-File', $Fake, '-Name', $Name, '-Marker', $Folder, '-ExitCode', [string]$ExitCode, '-SleepMs', [string]$SleepMs)
    if ($Grandchild) { $list += '-Grandchild' }
    if ($WaitFor) { $list += @('-WaitFor', $WaitFor) }
    return New-AhkFlowSlice -Name $Name -Command $hostPath -Argument $list -LogPath (Join-Path (Join-Path $Folder $Name) "$Name.log")
}
$tracker = New-ProgressTracker -RunnerKey 'slice-runner-tests' -Unit @('P', 'F') -NoStore
$results = @(Invoke-AhkFlowSliceSet -Slice @((New-Fake 'P' 0 0), (New-Fake 'F' 1 0)) -SlicesAtOnce 2 -WorkingDirectory $Folder -Tracker $tracker 6>$null)
$codes = @($results | ForEach-Object { $_.ExitCode })
$logs = @($results | ForEach-Object { [System.IO.File]::ReadAllText($_.LogPath) })
$message = ''
$survivors = @()
$slices = @(
    (New-Fake 'A' 0 60000 -Grandchild),
    (New-Fake 'Q' 0 100 -WaitFor (Join-Path $Folder 'grandchild-A.txt')),
    (New-AhkFlowSlice -Name 'B' -Command 'no-such-command-204' -Argument @('test') -LogPath (Join-Path $Folder 'B\B.log')))
try { [void](Invoke-AhkFlowSliceSet -Slice $slices -SlicesAtOnce 2 -WorkingDirectory $Folder -Tracker (New-ProgressTracker -RunnerKey 'slice-runner-tests' -Unit @('A', 'Q', 'B') -NoStore) 6>$null) }
catch {
    $message = $_.Exception.Message
    foreach ($file in @('start-A.txt', 'grandchild-A.txt')) {
        $id = [int](([System.IO.File]::ReadAllText((Join-Path $Folder $file)).Trim() -split '\s+')[0])
        $deadline = [DateTime]::UtcNow.AddSeconds(2)
        while ($null -ne (Get-Process -Id $id -ErrorAction SilentlyContinue) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
        if ($null -ne (Get-Process -Id $id -ErrorAction SilentlyContinue)) { $survivors += $id }
    }
}
[Console]::Out.WriteLine((ConvertTo-Json -Compress -InputObject ([pscustomobject]@{ Codes = $codes; Logs = $logs; Message = $message; Survivors = $survivors })))
'@
            Set-Content -LiteralPath $driver -Value $driverBody -Encoding UTF8
            $text = & $script:WindowsPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $driver -Repo $repoRoot -Folder $folder -Fake $script:FakePath 2>&1 | Out-String
            $json = @($text -split '\r?\n' | Where-Object { $_.StartsWith('{') }) | Select-Object -Last 1
            Assert-True ($null -ne $json) "The 5.1 driver printed no JSON: $text"
            $data = $json | ConvertFrom-Json
            Assert-True ((@($data.Codes) -join ',') -eq '0,1') "Exit codes: $(@($data.Codes) -join ',')"
            Assert-True ($data.Logs[0].Contains('out-P') -and $data.Logs[1].Contains('out-F')) "Logs: $($data.Logs -join ' | ')"
            Assert-True ($data.Message.Contains('could not start')) "Message: $($data.Message)"
            Assert-True (@($data.Survivors).Count -eq 0) "Survivors: $(@($data.Survivors) -join ',')"
        }
        finally { Stop-MarkedProcess $folder; Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
else {
    Write-Host '  SKIP  Windows PowerShell 5.1 runs the Slice runner (no powershell.exe on this machine)' -ForegroundColor Yellow
}

Invoke-TestCase 'A typographic single quote survives the quoting' {
    # PowerShell reads U+2018 to U+201B as single quotes too, so a path that holds one must not
    # end the quoted string in the launcher or the stub.
    foreach ($code in @(0x27, 0x2018, 0x2019, 0x201A, 0x201B)) {
        $mark = [string][char]$code
        $value = "a${mark}b${mark}"
        $quoted = ConvertTo-AhkFlowSingleQuoted $value
        $back = $null
        try { $back = & ([scriptblock]::Create("return $quoted")) } catch { }
        Assert-True ($back -ceq $value) ("U+{0:X4}: got '{1}'." -f $code, $back)
    }
}

if ($script:OnWindows) {
    Invoke-TestCase 'The launcher starts nothing when its input closes without the start line' {
        $folder = New-TempFolder
        try {
            $marker = Join-Path $folder 'started.txt'
            $start = Resolve-AhkFlowSliceStart -Command $hostExe -Argument @('-NoProfile', '-NonInteractive', '-Command', "Set-Content -LiteralPath '$marker' -Value started")
            $text = Get-AhkFlowSliceLauncherText -Start $start -WorkingDirectory $folder
            $info = New-Object System.Diagnostics.ProcessStartInfo
            $info.FileName = $hostExe
            $info.Arguments = '-NoProfile -NonInteractive -EncodedCommand ' + (ConvertTo-AhkFlowEncodedCommand -Text $text)
            $info.UseShellExecute = $false
            $info.CreateNoWindow = $true
            $info.RedirectStandardInput = $true
            $launcher = [System.Diagnostics.Process]::Start($info)
            $launcher.StandardInput.Close()
            Assert-True ($launcher.WaitForExit(60000)) 'The launcher did not exit within 60 s.'
            Assert-True ($launcher.ExitCode -ne 0) "The launcher exited with $($launcher.ExitCode)."
            Assert-True (-not (Test-Path -LiteralPath $marker)) 'The launcher started the program without the start line.'
        }
        finally { Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue }
    }

    Invoke-TestCase 'Killing the runner host ends every process of its Slices' {
        # A closed terminal or a killed host runs no 'finally'. The job must still end the Slice,
        # or a test host outlives the test-run lock (D7).
        $folder = New-TempFolder
        $runner = $null
        try {
            $slice = New-FakeSlice -Name 'A' -Folder $folder -SleepMs 120000 -Grandchild
            [ordered]@{ Command = $slice.Command; Argument = @($slice.Argument); LogPath = $slice.LogPath } |
                ConvertTo-Json | Set-Content -LiteralPath (Join-Path $folder 'slice.json') -Encoding UTF8
            $driver = Join-Path $folder 'driver.ps1'
            Set-Content -LiteralPath $driver -Encoding UTF8 -Value @'
param([string] $Repo, [string] $Folder)
$ErrorActionPreference = 'Stop'
. (Join-Path $Repo 'scripts\test-lanes.common.ps1')
. (Join-Path $Repo 'scripts\progress.common.ps1')
. (Join-Path $Repo 'scripts\progress.parallel.ps1')
. (Join-Path $Repo 'scripts\slice-runner.common.ps1')
$s = Get-Content -LiteralPath (Join-Path $Folder 'slice.json') -Raw | ConvertFrom-Json
$slice = New-AhkFlowSlice -Name 'A' -Command $s.Command -Argument @($s.Argument) -LogPath $s.LogPath
$tracker = New-ProgressTracker -RunnerKey 'slice-runner-tests' -Unit @('A') -NoStore
Invoke-AhkFlowSliceSet -Slice @($slice) -SlicesAtOnce 1 -WorkingDirectory $Folder -Tracker $tracker | Out-Null
'@
            $runner = Start-Process -FilePath $hostExe -WindowStyle Hidden -PassThru -ArgumentList @(
                '-NoProfile', '-NonInteractive', '-File', "`"$driver`"", '-Repo', "`"$repoRoot`"", '-Folder', "`"$folder`"")
            $deadline = [DateTime]::UtcNow.AddSeconds(60)
            while (-not (Test-Path -LiteralPath (Join-Path $folder 'grandchild-A.txt')) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
            $fake = Get-MarkerId $folder 'start-A.txt'
            $grandchild = Get-MarkerId $folder 'grandchild-A.txt'
            Assert-True ($null -ne $fake -and $null -ne $grandchild) 'The Slice did not start its processes within 60 s.'
            Stop-Process -Id $runner.Id -Force
            Assert-True (Test-ProcessGone $fake -Seconds 10) "The fake A ($fake) still runs after its host was killed."
            Assert-True (Test-ProcessGone $grandchild -Seconds 10) "The grandchild of A ($grandchild) still runs after its host was killed."
        }
        finally {
            if ($null -ne $runner) { Stop-Process -Id $runner.Id -Force -ErrorAction SilentlyContinue }
            Stop-MarkedProcess $folder
            Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Remove-Item -LiteralPath $script:FakeFolder -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
if ($script:Failures.Count -gt 0) {
    Write-Host "$($script:Failures.Count) case(s) failed:" -ForegroundColor Red
    foreach ($failure in $script:Failures) { Write-Host "  $failure" -ForegroundColor Red }
    exit 1
}
Write-Host 'All SliceRunner cases passed.' -ForegroundColor Green
exit 0
