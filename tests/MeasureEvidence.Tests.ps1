#Requires -Version 7.0

# Backlog 204. scripts/measure-evidence.common.ps1 reads the evidence a measured run kept: which
# test, Slice or run failed and why, the coverage figures of a run, whether a setting saves time,
# and whether a Soak failure is one the sequence already shows. scripts/measure-verdict.ps1 prints
# those answers as tables. Every case writes its own fixture files.
#
# The TRX fixtures copy the shape of a real TRX file written on 2026-11-16 by xUnit 2.9.3,
# xunit.runner.visualstudio 3.1.5, Microsoft.NET.Test.Sdk 18.4.0 and FluentAssertions 8.9.0. The
# Summary.json fixtures copy the fields of a real reportgenerator file.
#
# Run it by hand with:  pwsh -NoProfile -File ./tests/MeasureEvidence.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$hostExe = [System.Diagnostics.Process]::GetCurrentProcess().Path

. (Join-Path $repoRoot 'scripts/test-results.common.ps1')
. (Join-Path $repoRoot 'scripts/measure-evidence.common.ps1')

$script:Failures = New-Object System.Collections.Generic.List[string]
$script:Root = Join-Path ([System.IO.Path]::GetTempPath()) ('measure-evidence-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:Root -Force | Out-Null

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

function New-CaseFolder {
    $path = Join-Path $script:Root ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function Write-Utf8 {
    param([string] $Path, [string] $Text, [switch] $Bom)
    $folder = Split-Path -Parent $Path
    if ($folder) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding([bool]$Bom)))
}

function ConvertTo-XmlText {
    param([string] $Text)
    return [System.Security.SecurityElement]::Escape($Text)
}

# One TRX file. Each test is @{ Name; Outcome; Message }. A failed result carries its message in
# Output/ErrorInfo/Message, the way the real logger writes it. Each RunError text becomes one
# RunInfo with outcome Error inside ResultSummary, the shape a crashed test host left on 2026-11-24
# (backlog 219).
function New-TrxText {
    param([object[]] $Test = @(), [string[]] $RunError = @())
    $results = foreach ($t in $Test) {
        $id = [guid]::NewGuid().ToString()
        $inner = ''
        if ($t.Outcome -ne 'Passed') {
            $inner = "<Output><ErrorInfo><Message>$(ConvertTo-XmlText $t.Message)</Message><StackTrace>   at Probe.Run() in C:\src\Probe.cs:line 12</StackTrace></ErrorInfo></Output>"
        }
        "    <UnitTestResult executionId=""$id"" testId=""$id"" testName=""$($t.Name)"" computerName=""HOST"" duration=""00:00:00.0100000"" startTime=""2026-11-16T10:00:00.0000000+01:00"" endTime=""2026-11-16T10:00:00.0100000+01:00"" testType=""13cdc9d9-ddb5-4fa4-a97d-d965ccfc6d4b"" outcome=""$($t.Outcome)"" testListId=""8c84fa94-04c1-424b-9868-57a2d4851a1d"">$inner</UnitTestResult>"
    }
    $total = @($Test).Count
    $failed = @($Test | Where-Object { $_.Outcome -eq 'Failed' }).Count
    $runInfos = ''
    if (@($RunError).Count -gt 0) {
        $infos = foreach ($text in $RunError) {
            "      <RunInfo computerName=""HOST"" outcome=""Error"" timestamp=""2026-11-16T10:00:00.0000000+01:00""><Text>$(ConvertTo-XmlText $text)</Text></RunInfo>"
        }
        $runInfos = "`n    <RunInfos>`n$($infos -join "`n")`n    </RunInfos>"
    }
    return @"
<?xml version="1.0" encoding="utf-8"?>
<TestRun id="$([guid]::NewGuid())" name="probe" runUser="probe" xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010">
  <Results>
$($results -join "`n")
  </Results>
  <ResultSummary outcome="$(if ($failed -gt 0) { 'Failed' } else { 'Completed' })">
    <Counters total="$total" executed="$total" passed="$($total - $failed)" failed="$failed" error="0" timeout="0" aborted="0" inconclusive="0" passedButRunAborted="0" notRunnable="0" notExecuted="0" disconnected="0" warning="0" completed="0" inProgress="0" pending="0" />$runInfos
  </ResultSummary>
</TestRun>
"@
}

# A Summary.json. Each assembly is @{ Name; Classes = @(@{ Name; CoverableLines; CoveredLines;
# TotalBranches; CoveredBranches }) }. The assembly figures are the sums of its classes, unless the
# case passes its own.
function New-SummaryText {
    param([object[]] $Assembly)
    $assemblies = foreach ($a in $Assembly) {
        $classes = foreach ($c in $a.Classes) {
            [ordered]@{
                name = $c.Name; coverage = 0; coveredlines = $c.CoveredLines; coverablelines = $c.CoverableLines
                totallines = 0; branchcoverage = $null; coveredbranches = $c.CoveredBranches; totalbranches = $c.TotalBranches
            }
        }
        $sum = { param($field) ($a.Classes | ForEach-Object { $_[$field] } | Measure-Object -Sum).Sum }
        [ordered]@{
            name = $a.Name; classes = @($a.Classes).Count; coverage = 0
            coveredlines = $(if ($a.ContainsKey('CoveredLines')) { $a.CoveredLines } else { & $sum 'CoveredLines' })
            coverablelines = $(if ($a.ContainsKey('CoverableLines')) { $a.CoverableLines } else { & $sum 'CoverableLines' })
            totallines = 0; branchcoverage = 0
            coveredbranches = $(& $sum 'CoveredBranches')
            totalbranches = $(if ($a.ContainsKey('TotalBranches')) { $a.TotalBranches } else { & $sum 'TotalBranches' })
            classesinassembly = @($classes)
        }
    }
    return ([ordered]@{ summary = [ordered]@{ generatedon = '2026-11-16T10:00:00Z' }; coverage = [ordered]@{ assemblies = @($assemblies) } } |
            ConvertTo-Json -Depth 8)
}

function New-ClassFigure {
    param([string] $Name, [int] $Coverable = 20, [int] $Covered = 10, [int] $Branches = 4, [int] $CoveredBranches = 2)
    return @{ Name = $Name; CoverableLines = $Coverable; CoveredLines = $Covered; TotalBranches = $Branches; CoveredBranches = $CoveredBranches }
}

# One run folder as Task 5 writes it. Each Slice is @{ Name; ExitCode; Tests (or $null for no TRX);
# Log; Coverage ($true writes its line in coverage-files.txt); RunError (texts for New-TrxText) }.
function New-RunFolder {
    param(
        [string] $Path,
        [string] $Mode = 'Integration',
        [object[]] $Slice = @(),
        [bool] $Failed = $false,
        [string] $Message = $null,
        [object] $EvidenceOwned = $true,
        [string] $Summary = $null,
        [switch] $NoSlicesFile,
        [double] $Seconds = 10,
        [string] $Setting = '1',
        [string] $Label = 'run 1'
    )
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    $run = [ordered]@{ Label = $Label; Setting = $Setting; ElapsedSeconds = $Seconds; Failed = $Failed; Message = $Message; EvidenceOwned = $EvidenceOwned }
    Write-Utf8 (Join-Path $Path 'run.json') ($run | ConvertTo-Json)
    if ($EvidenceOwned -eq $false) { return $Path }

    $results = Join-Path $Path 'results'
    New-Item -ItemType Directory -Path $results -Force | Out-Null
    $rows = @()
    $coverageLines = @()
    foreach ($s in $Slice) {
        $folder = Join-Path $results $s.Name
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        $runError = if ($s.ContainsKey('RunError')) { $s.RunError } else { @() }
        if ($null -ne $s.Tests) { Write-Utf8 (Join-Path $folder "$($s.Name).trx") (New-TrxText -Test $s.Tests -RunError $runError) }
        $log = if ($s.ContainsKey('Log')) { $s.Log } else { 'Test run for probe.dll' }
        Write-Utf8 (Join-Path $folder "$($s.Name).log") $log
        $exit = if ($s.ContainsKey('ExitCode')) { $s.ExitCode } else { 0 }
        $rows += [ordered]@{ Name = $s.Name; ExitCode = $exit; Seconds = 1.5; Folder = $s.Name; Log = "$($s.Name).log" }
        if (-not $s.ContainsKey('Coverage') -or $s.Coverage) { $coverageLines += "$($s.Name)\0f1e\coverage.cobertura.xml" }
    }
    if (-not $NoSlicesFile) { Write-Utf8 (Join-Path $results 'slices.json') (ConvertTo-Json -InputObject @($rows) -Depth 3) }
    if ($Mode -eq 'Coverage') {
        Write-Utf8 (Join-Path $results 'coverage-files.txt') ($coverageLines -join "`r`n")
        if ($Summary) { Write-Utf8 (Join-Path $Path 'report\Summary.json') $Summary -Bom }
    }
    return $Path
}

$script:PassedTest = @{ Name = 'Probe.Tests.PassingTest'; Outcome = 'Passed' }
$script:ThrownMessage = "System.InvalidOperationException : first line 42`nsecond line"
$script:AssertMessage = 'Expected value to be 2 because the probe says so, but found 1.'
$script:CleanSummary = New-SummaryText -Assembly @(@{ Name = 'Probe'; Classes = @((New-ClassFigure 'Probe.A'), (New-ClassFigure 'Probe.B')) })

Write-Host "Testing $(Join-Path $repoRoot 'scripts\measure-evidence.common.ps1')"

Invoke-TestCase 'The cause is the first line, with GUIDs and numbers masked' {
    $thrown = Get-AhkFlowFailureCause -Message $script:ThrownMessage
    Assert-True ($thrown -eq 'System.InvalidOperationException : first line #') "Thrown: '$thrown'"
    $assert = Get-AhkFlowFailureCause -Message $script:AssertMessage
    Assert-True ($assert -eq 'Expected value to be # because the probe says so, but found #.') "Assert: '$assert'"
    $guid = Get-AhkFlowFailureCause -Message 'Database 3f2504e0-4f89-11d3-9a0c-0305e82c3301 is gone'
    Assert-True ($guid -eq 'Database <guid> is gone') "Guid: '$guid'"
    Assert-True ((Get-AhkFlowFailureCause -Message '') -eq '(no message)') 'An empty message does not give (no message).'
}

Invoke-TestCase 'A failing test is a test failure, named by its test and its cause' {
    $run = New-RunFolder -Path (New-CaseFolder) -Failed $true -Message 'dotnet test failed for: P.Tests.' -Slice @(
        @{ Name = 'P.Tests'; ExitCode = 1; Tests = @($script:PassedTest, @{ Name = 'Probe.Tests.Breaks'; Outcome = 'Failed'; Message = $script:ThrownMessage }) })
    $failures = @(Get-AhkFlowRunFailure -RunFolder $run -Mode 'Integration')
    Assert-True ($failures.Count -eq 1) "Expected one failure, got $($failures.Count): $($failures | ConvertTo-Json -Compress)"
    $f = $failures[0]
    Assert-True ($f.Kind -eq 'test' -and $f.Slice -eq 'P.Tests' -and $f.Test -eq 'Probe.Tests.Breaks') "Failure: $($f | ConvertTo-Json -Compress)"
    Assert-True ($f.Cause -eq 'System.InvalidOperationException : first line #') "Cause: $($f.Cause)"
    Assert-True ($f.Key -eq 'test|P.Tests|Probe.Tests.Breaks|System.InvalidOperationException : first line #') "Key: $($f.Key)"
}

Invoke-TestCase 'A Slice that failed with no failing test is a Slice failure, with the first error line of its log' {
    $crash = New-RunFolder -Path (New-CaseFolder) -Failed $true -Message 'x' -Slice @(
        @{ Name = 'P.Tests'; ExitCode = 1; Tests = @($script:PassedTest)
            Log = "Test run for probe.dll`nThe active test run was aborted. Reason: Test host process crashed`nError: later line" })
    $failures = @(Get-AhkFlowRunFailure -RunFolder $crash -Mode 'Integration')
    Assert-True ($failures.Count -eq 1 -and $failures[0].Kind -eq 'slice' -and $failures[0].Slice -eq 'P.Tests') "Failures: $($failures | ConvertTo-Json -Compress)"
    Assert-True ($failures[0].Cause -eq 'The active test run was aborted. Reason: Test host process crashed') "Cause: $($failures[0].Cause)"

    $plain = New-RunFolder -Path (New-CaseFolder) -Failed $true -Message 'x' -Slice @(
        @{ Name = 'P.Tests'; ExitCode = 1; Tests = @($script:PassedTest); Log = 'Test run for probe.dll' })
    $failures = @(Get-AhkFlowRunFailure -RunFolder $plain -Mode 'Integration')
    Assert-True ($failures.Count -eq 1 -and $failures[0].Cause -eq 'exit code 1') "Failures: $($failures | ConvertTo-Json -Compress)"
}

Invoke-TestCase 'A missing TRX file, a TRX file that counts no test, a missing coverage file and a missing report are evidence failures' {
    $cases = @(
        @{ Mode = 'Integration'; Cause = 'no TRX file'; Slice = @(@{ Name = 'P.Tests'; Tests = $null }); Summary = $null }
        @{ Mode = 'Integration'; Cause = 'TRX counts no test'; Slice = @(@{ Name = 'P.Tests'; Tests = @() }); Summary = $null }
        @{ Mode = 'Coverage'; Cause = 'no coverage file'; Slice = @(@{ Name = 'P.Tests'; Tests = @($script:PassedTest); Coverage = $false }); Summary = $null }
        @{ Mode = 'Coverage'; Cause = 'no merged report'; Slice = @(@{ Name = 'P.Tests'; Tests = @($script:PassedTest) }); Summary = $null }
    )
    foreach ($c in $cases) {
        $run = New-RunFolder -Path (New-CaseFolder) -Mode $c.Mode -Slice $c.Slice -Summary $c.Summary
        $failures = @(Get-AhkFlowRunFailure -RunFolder $run -Mode $c.Mode)
        Assert-True ($failures.Count -eq 1) "$($c.Cause): expected one failure, got $($failures.Count): $($failures | ConvertTo-Json -Compress)"
        Assert-True ($failures[0].Kind -eq 'evidence' -and $failures[0].Cause -eq $c.Cause) "$($c.Cause): got $($failures[0] | ConvertTo-Json -Compress)"
    }
}

Invoke-TestCase 'A run that failed before its Slices is an evidence failure' {
    $run = New-RunFolder -Path (New-CaseFolder) -Failed $true -Message 'Build failed.' -NoSlicesFile
    $failures = @(Get-AhkFlowRunFailure -RunFolder $run -Mode 'Integration')
    Assert-True ($failures.Count -eq 1 -and $failures[0].Kind -eq 'evidence') "Failures: $($failures | ConvertTo-Json -Compress)"
}

Invoke-TestCase 'A run whose results are not its own is an evidence failure, with the run''s message' {
    $run = New-RunFolder -Path (New-CaseFolder) -Failed $true -Message 'Another run holds the lock.' -EvidenceOwned $false
    $failures = @(Get-AhkFlowRunFailure -RunFolder $run -Mode 'Coverage')
    Assert-True ($failures.Count -eq 1) "Expected one failure, got $($failures.Count)."
    Assert-True ($failures[0].Kind -eq 'evidence' -and $failures[0].Cause -eq 'no evidence from this attempt: Another run holds the lock.') "Failure: $($failures[0] | ConvertTo-Json -Compress)"
}

Invoke-TestCase 'A failed run with clean evidence is a run failure, named by its message' {
    $message = 'Coverage thresholds not met. See the gate output above.'
    $run = New-RunFolder -Path (New-CaseFolder) -Mode 'Coverage' -Failed $true -Message $message -Summary $script:CleanSummary -Slice @(
        @{ Name = 'P.Tests'; Tests = @($script:PassedTest) }, @{ Name = 'Q.Tests'; Tests = @($script:PassedTest) })
    $failures = @(Get-AhkFlowRunFailure -RunFolder $run -Mode 'Coverage')
    Assert-True ($failures.Count -eq 1) "Expected one failure, got $($failures.Count): $($failures | ConvertTo-Json -Compress)"
    Assert-True ($failures[0].Kind -eq 'run' -and $failures[0].Cause -eq $message -and $failures[0].Key -eq "run|$message") "Failure: $($failures[0] | ConvertTo-Json -Compress)"
}

Invoke-TestCase 'A failed run that a Slice explains gives no run failure' {
    $run = New-RunFolder -Path (New-CaseFolder) -Mode 'Coverage' -Failed $true -Message 'dotnet test failed for: P.Tests.' -Summary $script:CleanSummary -Slice @(
        @{ Name = 'P.Tests'; ExitCode = 1; Tests = @(@{ Name = 'Probe.Tests.Breaks'; Outcome = 'Failed'; Message = $script:AssertMessage }) })
    $failures = @(Get-AhkFlowRunFailure -RunFolder $run -Mode 'Coverage')
    Assert-True ($failures.Count -eq 1 -and $failures[0].Kind -eq 'test') "Failures: $($failures | ConvertTo-Json -Compress)"
}

function New-FigureFile {
    param([object[]] $Assembly, [switch] $Bom)
    $path = Join-Path (New-CaseFolder) 'Summary.json'
    Write-Utf8 $path (New-SummaryText -Assembly $Assembly) -Bom:$Bom
    return Get-AhkFlowCoverageFigure -SummaryPath $path
}

Invoke-TestCase 'Completeness needs the same assemblies, classes, coverable lines and branches' {
    $reference = New-FigureFile -Bom -Assembly @(@{ Name = 'Probe'; Classes = @((New-ClassFigure 'Probe.A'), (New-ClassFigure 'Probe.B')) })
    $same = New-FigureFile -Assembly @(@{ Name = 'Probe'; Classes = @((New-ClassFigure 'Probe.A'), (New-ClassFigure 'Probe.B')) })
    Assert-True (@(Compare-AhkFlowCoverageFigure -Reference @(, $reference) -Candidate $same).Count -eq 0) 'The same figures give a difference.'

    $lacking = New-FigureFile -Assembly @(@{ Name = 'Probe'; CoverableLines = 40; TotalBranches = 8; Classes = @((New-ClassFigure 'Probe.A')) })
    $diff = @(Compare-AhkFlowCoverageFigure -Reference @(, $reference) -Candidate $lacking)
    Assert-True ($diff.Count -eq 1 -and $diff[0].Class -eq 'Probe.B') "Lacking a class: $($diff | ConvertTo-Json -Compress)"

    $more = New-FigureFile -Assembly @(@{ Name = 'Probe'; CoverableLines = 41; Classes = @((New-ClassFigure 'Probe.A'), (New-ClassFigure 'Probe.B')) })
    $diff = @(Compare-AhkFlowCoverageFigure -Reference @(, $reference) -Candidate $more)
    Assert-True ($diff.Count -eq 1 -and $diff[0].Field -eq 'CoverableLines' -and $diff[0].Expected -eq 40 -and $diff[0].Actual -eq 41) "One more line: $($diff | ConvertTo-Json -Compress)"
}

Invoke-TestCase 'Outcome allows only the range of the sequence runs' {
    $reference = @(foreach ($covered in 10, 10, 12) {
            , (New-FigureFile -Assembly @(@{ Name = 'Probe'; Classes = @((New-ClassFigure 'Probe.A' -Covered $covered)) }))
        })
    $inside = New-FigureFile -Assembly @(@{ Name = 'Probe'; Classes = @((New-ClassFigure 'Probe.A' -Covered 11)) })
    Assert-True (@(Compare-AhkFlowCoverageFigure -Reference $reference -Candidate $inside -Outcome).Count -eq 0) 'A value inside the range gives a difference.'
    $outside = New-FigureFile -Assembly @(@{ Name = 'Probe'; Classes = @((New-ClassFigure 'Probe.A' -Covered 13)) })
    $diff = @(Compare-AhkFlowCoverageFigure -Reference $reference -Candidate $outside -Outcome)
    Assert-True ($diff.Count -eq 1 -and $diff[0].Class -eq 'Probe.A' -and $diff[0].Field -eq 'CoveredLines') "Outside: $($diff | ConvertTo-Json -Compress)"
}

Invoke-TestCase 'A setting saves time only when every run beats every sequence run' {
    Assert-True (Test-AhkFlowTimeSaving -Sequence @(10, 11, 12) -Candidate @(8, 9, 9.9)) '8, 9, 9.9 does not save time.'
    Assert-True (-not (Test-AhkFlowTimeSaving -Sequence @(10, 11, 12) -Candidate @(8, 9, 10))) '8, 9, 10 saves time.'
    Assert-True (-not (Test-AhkFlowTimeSaving -Sequence @(10, 11, 12) -Candidate @(8, 9, 10.5))) '8, 9, 10.5 saves time.'
}

function New-Failure {
    param([string] $Kind = 'test', [string] $Key = 'test|P.Tests|Probe.Tests.Breaks|cause')
    return [pscustomobject]@{ Kind = $Kind; Slice = 'P.Tests'; Test = 'Probe.Tests.Breaks'; Cause = 'cause'; Key = $Key }
}

Invoke-TestCase 'A Soak failure is existing only when the sequence Soak shows it at least as often' {
    # '1..0' counts down to 0, so a count of 0 builds an empty list on purpose.
    $verdict = {
        param($candidate, $sequence)
        $sequenceFailures = @()
        if ($sequence -gt 0) { $sequenceFailures = @(1..$sequence | ForEach-Object { New-Failure }) }
        @(Get-AhkFlowSoakVerdict -Candidate @(1..$candidate | ForEach-Object { New-Failure }) -Sequence $sequenceFailures)[0].Verdict
    }
    Assert-True ((& $verdict 2 2) -eq 'existing') '2 and 2 is not existing.'
    Assert-True ((& $verdict 2 1) -eq 'not cleared') '2 and 1 is cleared.'
    Assert-True ((& $verdict 1 0) -eq 'not cleared') '1 and 0 is cleared.'
    foreach ($kind in 'evidence', 'run') {
        $key = "$kind|cause"
        $result = @(Get-AhkFlowSoakVerdict -Candidate @(New-Failure -Kind $kind -Key $key) -Sequence @(1..5 | ForEach-Object { New-Failure -Kind $kind -Key $key }))
        Assert-True ($result[0].Verdict -eq 'not cleared') "An $kind failure is $($result[0].Verdict)."
    }
    $alone = @(Get-AhkFlowSoakVerdict -Candidate @(New-Failure) -Sequence @())
    Assert-True ($alone[0].Verdict -eq 'not cleared' -and $alone[0].CandidateCount -eq 1 -and $alone[0].SequenceCount -eq 0) "No sequence: $($alone | ConvertTo-Json -Compress)"
}

# A timing session as Task 5 writes it. Each run is @{ Setting; Folder; Label; Kind; Seconds;
# Failed; Message; Slice }.
function New-SessionFolder {
    param([string] $Mode, [string] $Kind, [string[]] $Settings, [object[]] $Run, [string] $Revision = 'abc123')
    $session = Join-Path (New-CaseFolder) 'session-20261116-100000'
    $entries = @()
    foreach ($r in $Run) {
        $failed = [bool]$r.Failed
        $message = if ($r.ContainsKey('Message')) { $r.Message } else { $null }
        [void](New-RunFolder -Path (Join-Path $session $r.Folder) -Mode $Mode -Slice $r.Slice -Failed $failed -Message $message `
                -Summary $(if ($Mode -eq 'Coverage') { $script:CleanSummary } else { $null }) -Seconds $r.Seconds -Setting $r.Setting -Label $r.Label)
        $entries += [ordered]@{ Setting = $r.Setting; Label = $r.Label; Kind = $r.Kind; Folder = $r.Folder; ElapsedSeconds = $r.Seconds; Failed = $failed; Message = $message; EvidenceOwned = $true }
    }
    $record = [ordered]@{ Revision = $Revision; Mode = $Mode; Kind = $Kind; Settings = $Settings; Runs = $entries }
    Write-Utf8 (Join-Path $session 'record.json') ($record | ConvertTo-Json -Depth 6)
    return $session
}

function New-CleanRun {
    param([string] $Setting, [string] $Folder, [string] $Label, [string] $Kind, [double] $Seconds, [bool] $Failed = $false, [string] $Message = $null, [object[]] $Slice = $null)
    if ($null -eq $Slice) { $Slice = @(@{ Name = 'P.Tests'; Tests = @($script:PassedTest) }) }
    return @{ Setting = $Setting; Folder = $Folder; Label = $Label; Kind = $Kind; Seconds = $Seconds; Failed = $Failed; Message = $Message; Slice = $Slice }
}

function Invoke-Verdict {
    param([string[]] $Argument)
    $output = & $hostExe -NoProfile -File (Join-Path $repoRoot 'scripts/measure-verdict.ps1') @Argument 2>&1 | Out-String
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

Invoke-TestCase 'The verdict script prints the tables for a session' {
    $timing = New-SessionFolder -Mode 'Coverage' -Kind 'timing' -Settings @('1', 'Budget') -Run @(
        (New-CleanRun '1' 'at-1\run-1' 'run 1' 'counted' 10),
        (New-CleanRun 'Budget' 'at-budget\run-1' 'run 1' 'counted' 8),
        (New-CleanRun '1' 'at-1\run-2' 'run 2' 'counted' 11),
        (New-CleanRun 'Budget' 'at-budget\run-2' 'run 2' 'counted' 9))
    $soak = New-SessionFolder -Mode 'Coverage' -Kind 'soak' -Settings @('Budget') -Run @(
        (New-CleanRun 'Budget' 'at-budget\soak-1' 'soak 1' 'soak' 9),
        (New-CleanRun 'Budget' 'at-budget\soak-2' 'soak 2' 'soak' 9 $true 'dotnet test failed for: P.Tests.' @(
            @{ Name = 'P.Tests'; ExitCode = 1; Tests = @(@{ Name = 'Probe.Tests.Breaks'; Outcome = 'Failed'; Message = $script:AssertMessage }) })))
    $result = Invoke-Verdict @('-Timing', $timing, '-Soak', $soak)
    Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"
    Assert-True ($result.Output -match '\| Setting \|') "No seconds table. Output: $($result.Output)"
    Assert-True ($result.Output.Contains('Budget saves time: yes')) "No saves-time line. Output: $($result.Output)"
    Assert-True ($result.Output -match '(?m)^completeness: ') "No completeness line. Output: $($result.Output)"
    Assert-True ($result.Output -match '\| P\.Tests \| 1 \| 1 \|') "No Soak table row. Output: $($result.Output)"
    Assert-True ($result.Output -match 'Probe\.Tests\.Breaks.*not cleared') "No Soak verdict. Output: $($result.Output)"
}

Invoke-TestCase 'An unexplained failure in a timing session blocks that setting' {
    $timing = New-SessionFolder -Mode 'Integration' -Kind 'timing' -Settings @('1', 'Budget') -Run @(
        (New-CleanRun '1' 'at-1\run-1' 'run 1' 'counted' 10),
        (New-CleanRun 'Budget' 'at-budget\run-1' 'run 1' 'counted' 8 $true 'Something went wrong after the Slices.'),
        (New-CleanRun 'Budget' 'at-budget\run-2' 'run 2' 'counted' 8))
    $result = Invoke-Verdict @('-Timing', $timing)
    Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"
    Assert-True ($result.Output.Contains('Budget blocked: a run failed with no failing Slice or test.')) "Output: $($result.Output)"
}

Invoke-TestCase 'A test host crash in a Fast run blocks the setting, also next to a failing test' {
    # Backlog 219. One Fast call writes one TRX for every assembly. Without this, any failing test
    # in that TRX hides a crash, and a Soak then clears the run as an existing test failure.
    $crash = 'The active test run was aborted. Reason: Test host process crashed'
    $message = 'dotnet test failed for Fast[Category!=Integration].'
    $slice = @(@{ Name = 'Fast'; ExitCode = 1; RunError = @($crash); Tests = @(
                @{ Name = 'A.Tests.Passes'; Outcome = 'Passed' },
                @{ Name = 'B.Tests.Breaks'; Outcome = 'Failed'; Message = $script:AssertMessage }) })
    $run = New-RunFolder -Path (New-CaseFolder) -Mode 'Fast' -Failed $true -Message $message -Slice $slice
    $failures = @(Get-AhkFlowRunFailure -RunFolder $run -Mode 'Fast')
    Assert-True ($failures.Count -eq 2) "Expected two failures, got $($failures.Count): $($failures | ConvertTo-Json -Compress)"
    $test = @($failures | Where-Object { $_.Kind -eq 'test' })
    Assert-True ($test.Count -eq 1 -and $test[0].Test -eq 'B.Tests.Breaks') "Test failure: $($failures | ConvertTo-Json -Compress)"
    $crashFailure = @($failures | Where-Object { $_.Kind -eq 'run' })
    Assert-True ($crashFailure.Count -eq 1 -and $crashFailure[0].Cause -eq $crash -and $crashFailure[0].Key -eq "run|$crash") "Run failure: $($failures | ConvertTo-Json -Compress)"

    $timing = New-SessionFolder -Mode 'Fast' -Kind 'timing' -Settings @('1', 'Budget') -Run @(
        (New-CleanRun '1' 'at-1\run-1' 'run 1' 'counted' 10),
        (New-CleanRun 'Budget' 'at-budget\run-1' 'run 1' 'counted' 8 $true $message $slice))
    $result = Invoke-Verdict @('-Timing', $timing)
    Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"
    Assert-True ($result.Output.Contains('Budget blocked: a run failed with no failing Slice or test.')) "Output: $($result.Output)"
}

Invoke-TestCase 'The verdict script refuses a sequence Soak that does not match the Soak it judges' {
    # A failure is 'existing' only against the sequence at the same code. Any other session would
    # clear a failure by chance.
    $timing = New-SessionFolder -Mode 'Integration' -Kind 'timing' -Settings @('1', 'Budget') -Run @(
        (New-CleanRun '1' 'at-1\run-1' 'run 1' 'counted' 10),
        (New-CleanRun 'Budget' 'at-budget\run-1' 'run 1' 'counted' 8))
    $soak = New-SessionFolder -Mode 'Integration' -Kind 'soak' -Settings @('Budget') -Run @(
        (New-CleanRun 'Budget' 'at-budget\soak-1' 'soak 1' 'soak' 8))
    foreach ($case in @(
            @{ Why = 'a timing session'; Mode = 'Integration'; Kind = 'timing'; Setting = '1'; Revision = 'abc123' },
            @{ Why = 'another setting'; Mode = 'Integration'; Kind = 'soak'; Setting = 'Budget'; Revision = 'abc123' },
            @{ Why = 'another Mode'; Mode = 'Coverage'; Kind = 'soak'; Setting = '1'; Revision = 'abc123' },
            @{ Why = 'another revision'; Mode = 'Integration'; Kind = 'soak'; Setting = '1'; Revision = 'def456' })) {
        $sequence = New-SessionFolder -Mode $case.Mode -Kind $case.Kind -Settings @($case.Setting) -Revision $case.Revision -Run @(
            (New-CleanRun $case.Setting "at-$($case.Setting.ToLowerInvariant())\soak-1" 'soak 1' 'soak' 10))
        $result = Invoke-Verdict @('-Timing', $timing, '-Soak', $soak, '-SequenceSoak', $sequence)
        Assert-True ($result.ExitCode -ne 0) "$($case.Why): expected a refusal. Output: $($result.Output)"
        Assert-True ($result.Output.Contains('is not a sequence Soak for')) "$($case.Why): Output: $($result.Output)"
    }
    $match = New-SessionFolder -Mode 'Integration' -Kind 'soak' -Settings @('1') -Run @(
        (New-CleanRun '1' 'at-1\soak-1' 'soak 1' 'soak' 10))
    $result = Invoke-Verdict @('-Timing', $timing, '-Soak', $soak, '-SequenceSoak', $match)
    Assert-True ($result.ExitCode -eq 0) "A matching sequence Soak was refused. Output: $($result.Output)"
}

Remove-Item -LiteralPath $script:Root -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
if ($script:Failures.Count -gt 0) {
    Write-Host "$($script:Failures.Count) case(s) failed:" -ForegroundColor Red
    foreach ($failure in $script:Failures) { Write-Host "  $failure" -ForegroundColor Red }
    exit 1
}
Write-Host 'All MeasureEvidence cases passed.' -ForegroundColor Green
exit 0
