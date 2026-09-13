#Requires -Version 7.0

# Backlog 140. The harness-overhead report, driven against a run folder this suite writes. It
# starts no test run, which is the property the report itself must have.
#
# Run it by hand with:  pwsh ./tests/HarnessOverheadReport.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$reportScript = Join-Path $repoRoot 'scripts/report-harness-overhead.ps1'

$failures = @()
$runDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "ahkflow-run-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null

try {
    # A twelve-second run holding four ten-second tests that all ran at the same time, plus one
    # two-second setup step nested inside the first second. Adding durations would give 42 s and a
    # residual of minus 30 s. The union is 10 s, so the overhead is 2 s.
    @'
<?xml version="1.0" encoding="UTF-8"?>
<TestRun id="00000000-0000-0000-0000-000000000001" name="sample" xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010">
  <Times creation="2026-09-12T10:00:00.0000000+00:00" queuing="2026-09-12T10:00:00.0000000+00:00" start="2026-09-12T10:00:00.0000000+00:00" finish="2026-09-12T10:00:12.0000000+00:00" />
  <Results>
    <UnitTestResult testId="11111111-1111-1111-1111-111111111111" testName="A" outcome="Passed" duration="00:00:10.0000000" startTime="2026-09-12T10:00:01.0000000+00:00" endTime="2026-09-12T10:00:11.0000000+00:00" />
    <UnitTestResult testId="22222222-2222-2222-2222-222222222222" testName="B" outcome="Passed" duration="00:00:10.0000000" startTime="2026-09-12T10:00:01.0000000+00:00" endTime="2026-09-12T10:00:11.0000000+00:00" />
    <UnitTestResult testId="33333333-3333-3333-3333-333333333333" testName="C" outcome="Passed" duration="00:00:10.0000000" startTime="2026-09-12T10:00:01.0000000+00:00" endTime="2026-09-12T10:00:11.0000000+00:00" />
    <UnitTestResult testId="44444444-4444-4444-4444-444444444444" testName="D" outcome="Passed" duration="00:00:10.0000000" startTime="2026-09-12T10:00:01.0000000+00:00" endTime="2026-09-12T10:00:11.0000000+00:00" />
  </Results>
  <TestDefinitions>
    <UnitTest id="11111111-1111-1111-1111-111111111111" name="A"><TestMethod className="Sample.Tests" name="A" /></UnitTest>
    <UnitTest id="22222222-2222-2222-2222-222222222222" name="B"><TestMethod className="Sample.Tests" name="B" /></UnitTest>
    <UnitTest id="33333333-3333-3333-3333-333333333333" name="C"><TestMethod className="Sample.Tests" name="C" /></UnitTest>
    <UnitTest id="44444444-4444-4444-4444-444444444444" name="D"><TestMethod className="Sample.Tests" name="D" /></UnitTest>
  </TestDefinitions>
</TestRun>
'@ | Set-Content -LiteralPath (Join-Path $runDirectory 'e2e.trx') -Encoding UTF8

    $timingDirectory = Join-Path $runDirectory 'fixture-timing'
    New-Item -ItemType Directory -Path $timingDirectory -Force | Out-Null

    # Records that overlap the tests, so only interval accounting gets the answer right. Every
    # record sits inside 10:00:00 to 10:00:01, so the coverage figures below do not move.
    #
    # The gate records are mixed on purpose. Two come from stack fixtures, one from a test that
    # called the gate itself, and one predates the caller field. A report that groups only by
    # component and operation folds all four into one median, and that median measures nobody.
    @(
        '{"timestampUtc":"2026-09-12T10:00:01.0000000+00:00","startedUtc":"2026-09-12T10:00:00.0000000+00:00","finishedUtc":"2026-09-12T10:00:01.0000000+00:00","testAssembly":"Sample","processId":1,"component":"StackFixture","fixture":"Sample.StackFixture","operation":"SpaHostStart","elapsedMilliseconds":1000}'
        '{"timestampUtc":"2026-09-12T10:00:01.0000000+00:00","startedUtc":"2026-09-12T10:00:00.5000000+00:00","finishedUtc":"2026-09-12T10:00:00.9000000+00:00","testAssembly":"Sample","processId":1,"component":"HostStartGate","fixture":"Sample.HostStartGate","operation":"GatedWork","elapsedMilliseconds":400,"caller":"StackFixture"}'
        '{"timestampUtc":"2026-09-12T10:00:01.0000000+00:00","startedUtc":"2026-09-12T10:00:00.2000000+00:00","finishedUtc":"2026-09-12T10:00:00.8000000+00:00","testAssembly":"Sample","processId":1,"component":"HostStartGate","fixture":"Sample.HostStartGate","operation":"GatedWork","elapsedMilliseconds":600,"caller":"StackFixture"}'
        '{"timestampUtc":"2026-09-12T10:00:01.0000000+00:00","startedUtc":"2026-09-12T10:00:00.1000000+00:00","finishedUtc":"2026-09-12T10:00:00.3000000+00:00","testAssembly":"Sample","processId":1,"component":"HostStartGate","fixture":"Sample.HostStartGate","operation":"GatedWork","elapsedMilliseconds":200,"caller":"Unattributed"}'
        '{"timestampUtc":"2026-09-12T10:00:01.0000000+00:00","startedUtc":"2026-09-12T10:00:00.5000000+00:00","finishedUtc":"2026-09-12T10:00:01.0000000+00:00","testAssembly":"Sample","processId":1,"component":"HostStartGate","fixture":"Sample.HostStartGate","operation":"GatedWork","elapsedMilliseconds":500}'
    ) | Set-Content -LiteralPath (Join-Path $timingDirectory 'fixture-timings-1.jsonl') -Encoding UTF8

    $report = & $reportScript -RunDirectory $runDirectory

    $gateRows = @($report.Step | Where-Object { $_.Component -eq 'HostStartGate' -and $_.Operation -eq 'GatedWork' })
    $stackStart = @($gateRows | Where-Object { $_.PSObject.Properties['Caller'] -and $_.Caller -eq 'StackFixture' })
    if ($stackStart.Count -ne 1) {
        $failures += "caller : expected one GatedWork row for caller StackFixture, got $($stackStart.Count)"
    }
    else {
        if ($stackStart[0].Count -ne 2) {
            $failures += "caller : the StackFixture row must count only the 2 stack starts, got $($stackStart[0].Count)"
        }
        if ([math]::Abs($stackStart[0].MedianMilliseconds - 500) -gt 0.001) {
            $failures += "caller : the StackFixture median must use 400 and 600 only, expected 500, got $($stackStart[0].MedianMilliseconds)"
        }
    }

    $unattributed = @($gateRows | Where-Object { $_.PSObject.Properties['Caller'] -and $_.Caller -eq 'Unattributed' })
    if ($unattributed.Count -ne 1 -or ($unattributed.Count -eq 1 -and $unattributed[0].Count -ne 1)) {
        $failures += 'caller : expected one Unattributed GatedWork row holding one record'
    }

    $legacy = @($gateRows | Where-Object { $_.PSObject.Properties['Caller'] -and $_.Caller -eq '' })
    if ($legacy.Count -ne 1 -or ($legacy.Count -eq 1 -and $legacy[0].Count -ne 1)) {
        $failures += 'caller : a record with no caller field must get its own row, never join a stack start'
    }

    if ([math]::Abs($report.RunIntervalMilliseconds - 12000) -gt 0.001) {
        $failures += "run interval : expected 12000 ms, got $($report.RunIntervalMilliseconds) ms"
    }

    # Tests cover 10:00:01 to 10:00:11. The setup covers 10:00:00 to 10:00:01, and the gated work
    # nests inside it. Together they cover 11 s of the 12 s run.
    if ([math]::Abs($report.CoveredMilliseconds - 11000) -gt 0.001) {
        $failures += "covered : expected 11000 ms, got $($report.CoveredMilliseconds) ms"
    }

    if ([math]::Abs($report.HarnessOverheadMilliseconds - 1000) -gt 0.001) {
        $failures += "overhead : expected 1000 ms, got $($report.HarnessOverheadMilliseconds) ms"
    }

    if ($report.HarnessOverheadMilliseconds -lt 0) {
        $failures += 'overhead : a residual must never be negative'
    }

    $stepNames = @($report.Step | ForEach-Object { $_.Operation })
    foreach ($expected in @('SpaHostStart', 'GatedWork')) {
        if ($stepNames -notcontains $expected) {
            $failures += "steps : expected an entry named $expected"
        }
    }
}
finally {
    Remove-Item -LiteralPath $runDirectory -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }
    Write-Host "$($failures.Count) failure(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'HarnessOverheadReport.Tests.ps1: all cases passed.' -ForegroundColor Green
