#Requires -Version 7.0

# Backlog 121. A duplicate backlog number, or a stale citation, used to surface only deep inside
# the powershell-suites job while the .NET build ran for minutes beside it. ci.yml now runs the
# cheap repository-invariant suites first, and every other job waits on them. This suite proves
# that wiring stays in place.
#
# Run it by hand with:  pwsh ./tests/RepoInvariantsCiJob.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$failures = @()
function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { $script:failures += $Message }
}

$expectedSuites = @(
    'BacklogNumbering.Tests.ps1'
    'BacklogPlanPointer.Tests.ps1'
    'BacklogStaleOpen.Tests.ps1'
    'CitationFreshness.Tests.ps1'
    'SkillParity.Tests.ps1'
)

# --- The check script names every invariant suite, and each suite file exists ---

$checkScript = Join-Path $repoRoot 'scripts/ci/check-repo-invariants.ps1'
Assert-True (Test-Path -LiteralPath $checkScript) 'scripts/ci/check-repo-invariants.ps1 must exist'

if (Test-Path -LiteralPath $checkScript) {
    $checkText = Get-Content -LiteralPath $checkScript -Raw
    foreach ($suite in $expectedSuites) {
        Assert-True ($checkText -match [regex]::Escape($suite)) "check-repo-invariants.ps1 must run $suite"
    }
}
foreach ($suite in $expectedSuites) {
    Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot "tests/$suite")) "tests/$suite must exist"
}

# --- ci.yml defines repo-invariants, and every other job waits on it ---

$ciPath = Join-Path $repoRoot '.github/workflows/ci.yml'
Assert-True (Test-Path -LiteralPath $ciPath) '.github/workflows/ci.yml must exist'

$ciLines = Get-Content -LiteralPath $ciPath
$jobNames = @()
$inJobs = $false
foreach ($line in $ciLines) {
    if ($line -match '^jobs:\s*$') { $inJobs = $true; continue }
    if (-not $inJobs) { continue }
    if ($line -match '^[^\s#]') { break }
    if ($line -match '^  (?<name>[A-Za-z0-9_-]+):\s*$') { $jobNames += $Matches.name }
}

Assert-True ($jobNames -contains 'repo-invariants') "ci.yml must define a 'repo-invariants' job. Found: $($jobNames -join ', ')"
Assert-True ($jobNames.Count -ge 5) "Expected at least five ci.yml jobs, found: $($jobNames -join ', ')"

$ciRaw = $ciLines -join "`n"
foreach ($job in ($jobNames | Where-Object { $_ -ne 'repo-invariants' })) {
    $pattern = "(?ms)^  $([regex]::Escape($job)):\s*$.*?(?=^  [A-Za-z0-9_-]+:\s*$|\z)"
    $block = [regex]::Match($ciRaw, $pattern).Value
    Assert-True ($block -match '(?m)^\s{4}needs:') "Job '$job' must declare a needs: key"
    Assert-True ($block -match 'repo-invariants') "Job '$job' needs: must include repo-invariants"
}

# --- The runner runs the suites in parallel ---

if (Test-Path -LiteralPath $checkScript) {
    Assert-True ($checkText -match 'ForEach-Object\s+-Parallel') 'check-repo-invariants.ps1 must run the suites in parallel'
}

# --- The job runs on ubuntu-latest ---

$invariantBlock = [regex]::Match($ciRaw, "(?ms)^  repo-invariants:\s*$.*?(?=^  [A-Za-z0-9_-]+:\s*$|\z)").Value
Assert-True ($invariantBlock -match '(?m)^\s{4}runs-on:\s*ubuntu-latest\s*$') 'repo-invariants must run on ubuntu-latest'

# --- Report ---

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host ''; Write-Host $failure -ForegroundColor Red }
    Write-Host ''
    throw "RepoInvariantsCiJob tests failed with $($failures.Count) problem(s)."
}

Write-Host 'RepoInvariantsCiJob tests passed.'
