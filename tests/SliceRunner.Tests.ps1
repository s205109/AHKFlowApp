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
. (Join-Path $repoRoot 'scripts/slice-runner.common.ps1')

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

Write-Host ''
if ($script:Failures.Count -gt 0) {
    Write-Host "$($script:Failures.Count) case(s) failed:" -ForegroundColor Red
    foreach ($failure in $script:Failures) { Write-Host "  $failure" -ForegroundColor Red }
    exit 1
}
Write-Host 'All SliceRunner cases passed.' -ForegroundColor Green
exit 0
