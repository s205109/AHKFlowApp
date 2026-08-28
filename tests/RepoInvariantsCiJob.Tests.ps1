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

    # Read the $suites array itself, not the file text. A suite name in a comment, or in the
    # description block at the top, must not count as the script running that suite.
    $suitesBlock = [regex]::Match($checkText, '(?ms)^\$suites\s*=\s*@\((?<body>.*?)^\)').Groups['body'].Value
    Assert-True (-not [string]::IsNullOrWhiteSpace($suitesBlock)) 'check-repo-invariants.ps1 must define a $suites = @( ... ) array'

    $declaredSuites = @([regex]::Matches($suitesBlock, "'(?<name>[^']+)'") | ForEach-Object { $_.Groups['name'].Value })
    foreach ($suite in $expectedSuites) {
        Assert-True ($declaredSuites -contains $suite) "The `$suites array in check-repo-invariants.ps1 must list $suite. Found: $($declaredSuites -join ', ')"
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

$ciRaw = $ciLines -join "`n"
foreach ($job in ($jobNames | Where-Object { $_ -ne 'repo-invariants' })) {
    $pattern = "(?ms)^  $([regex]::Escape($job)):\s*$.*?(?=^  [A-Za-z0-9_-]+:\s*$|\z)"
    $block = [regex]::Match($ciRaw, $pattern).Value

    # Read the needs: value, not the job block. The words 'repo-invariants' appear in step names
    # and comments too, and matching those would pass a job that waits on nothing.
    $needsMatch = [regex]::Match($block, '(?m)^\s{4}needs:\s*(?<value>.*)$')
    Assert-True ($needsMatch.Success) "Job '$job' must declare a needs: key"
    if ($needsMatch.Success) {
        $needsValue = $needsMatch.Groups['value'].Value.Trim().Trim('[', ']')
        if ([string]::IsNullOrWhiteSpace($needsValue)) {
            # The block form: needs: on its own line, then one '- job' line per dependency.
            $listMatch = [regex]::Match($block, '(?ms)^\s{4}needs:\s*$(?<items>(\s*\n)*(^\s{6}-\s.*$\n?)+)')
            $needsValue = ($listMatch.Groups['items'].Value -split "`n" |
                ForEach-Object { $_.Trim() -replace '^-\s*', '' } | Where-Object { $_ }) -join ','
        }
        $needsJobs = @($needsValue -split ',' | ForEach-Object { $_.Trim().Trim("'", '"') } | Where-Object { $_ })
        Assert-True ($needsJobs -contains 'repo-invariants') "Job '$job' needs: must name repo-invariants. Found: '$needsValue'"
    }
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
