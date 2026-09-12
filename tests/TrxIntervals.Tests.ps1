#Requires -Version 7.0

# Backlog 140. The two interval readers the harness-overhead report needs, driven against a TRX
# written by this suite rather than by a test run.
#
# Run it by hand with:  pwsh ./tests/TrxIntervals.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts/test-results.common.ps1')

$failures = @()
$trxDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "ahkflow-trx-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $trxDirectory -Force | Out-Null

try {
    $trxPath = Join-Path $trxDirectory 'sample.trx'
    @'
<?xml version="1.0" encoding="UTF-8"?>
<TestRun id="00000000-0000-0000-0000-000000000001" name="sample" xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010">
  <Times creation="2026-09-12T10:00:00.0000000+00:00" queuing="2026-09-12T10:00:00.0000000+00:00" start="2026-09-12T10:00:00.0000000+00:00" finish="2026-09-12T10:00:12.0000000+00:00" />
  <Results>
    <UnitTestResult testId="11111111-1111-1111-1111-111111111111" testName="AlphaTest" outcome="Passed" duration="00:00:10.0000000" startTime="2026-09-12T10:00:01.0000000+00:00" endTime="2026-09-12T10:00:11.0000000+00:00" />
  </Results>
  <TestDefinitions>
    <UnitTest id="11111111-1111-1111-1111-111111111111" name="AlphaTest">
      <TestMethod className="Sample.AlphaTests" name="AlphaTest" />
    </UnitTest>
  </TestDefinitions>
</TestRun>
'@ | Set-Content -LiteralPath $trxPath -Encoding UTF8

    $runInterval = Get-AhkFlowTrxRunInterval -TrxPath $trxPath
    $runLength = ($runInterval.End - $runInterval.Start).TotalSeconds
    if ([math]::Abs($runLength - 12) -gt 0.001) {
        $failures += "run interval : expected 12 s, got $runLength s"
    }
    if ($runInterval.Start.Kind -ne [System.DateTimeKind]::Utc) {
        $failures += "run interval : expected a UTC start, got $($runInterval.Start.Kind)"
    }

    $results = @(Read-TrxResults -TrxPath $trxPath -ProjectName 'Sample')
    if ($results.Count -ne 1) {
        $failures += "results : expected 1 row, got $($results.Count)"
    }
    else {
        $testLength = ($results[0].EndUtc - $results[0].StartUtc).TotalSeconds
        if ([math]::Abs($testLength - 10) -gt 0.001) {
            $failures += "test interval : expected 10 s, got $testLength s"
        }
        if ($results[0].StartUtc.Kind -ne [System.DateTimeKind]::Utc) {
            $failures += "test interval : expected a UTC start, got $($results[0].StartUtc.Kind)"
        }
    }
}
finally {
    Remove-Item -LiteralPath $trxDirectory -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }
    Write-Host "$($failures.Count) failure(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'TrxIntervals.Tests.ps1: all cases passed.' -ForegroundColor Green
