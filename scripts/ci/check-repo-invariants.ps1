#Requires -Version 7.0
<#
.SYNOPSIS
    Runs the cheap repository-invariant suites in parallel, so ci.yml can gate the expensive jobs
    on them and still finish inside two minutes.

.DESCRIPTION
    Backlog 121. A duplicate backlog number, filed on one branch and unseen on another, used to
    fail CI only after the slowest job had run for minutes. This script runs the five suites that
    check repository invariants, each in its own pwsh child process, all at once. It waits for
    every suite, prints each one's output, then exits 1 if any failed - so one run lists every
    broken invariant.

    Run one after another the five take about 115 seconds, and CitationFreshness alone is about
    78. In parallel the wall time is about the slowest suite. This does not change
    scripts/run-powershell-suites.ps1; that job still runs every suite, now gated behind this one.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# A plain assignment to this variable is safe on every PowerShell version; only a read of it
# throws under Set-StrictMode before 7.3. run-powershell-suites.ps1 sets it the same way.
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$hostExe = [System.Diagnostics.Process]::GetCurrentProcess().Path

$suites = @(
    'BacklogNumbering.Tests.ps1'
    'BacklogPlanPointer.Tests.ps1'
    'BacklogStaleOpen.Tests.ps1'
    'CitationFreshness.Tests.ps1'
    'SkillParity.Tests.ps1'
)

foreach ($suite in $suites) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot "tests/$suite"))) {
        throw "Invariant suite not found: tests/$suite"
    }
}

$results = $suites | ForEach-Object -Parallel {
    $suite = $_
    $path = Join-Path $using:repoRoot "tests/$suite"
    # Fresh runspace: opt out again so a non-zero suite exit code is data, not a throw.
    $PSNativeCommandUseErrorActionPreference = $false
    $output = & $using:hostExe -NoProfile -File $path 2>&1 | Out-String
    [pscustomobject]@{ Suite = $suite; ExitCode = $LASTEXITCODE; Output = $output }
} -ThrottleLimit 5

foreach ($result in ($results | Sort-Object Suite)) {
    Write-Host "--- $($result.Suite) (exit $($result.ExitCode)) ---"
    Write-Host $result.Output
}

$failed = @($results | Where-Object { $_.ExitCode -ne 0 } | ForEach-Object { $_.Suite } | Sort-Object)

Write-Host ''
if ($failed.Count -gt 0) {
    Write-Host "$($failed.Count) of $($suites.Count) invariant suite(s) failed: $($failed -join ', ')" -ForegroundColor Red
    exit 1
}

Write-Host "All $($suites.Count) repository-invariant suites passed."
exit 0
