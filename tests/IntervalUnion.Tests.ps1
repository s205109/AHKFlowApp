#Requires -Version 7.0

# Backlog 140. The interval union the harness-overhead report rests on, driven against fixed
# values. No git, no dotnet, no clock: the function is pure, and that is why it has its own file.
#
# Run it by hand with:  pwsh ./tests/IntervalUnion.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts/test-results.common.ps1')

$failures = @()
$epoch = [datetime]::new(2026, 9, 12, 0, 0, 0, [System.DateTimeKind]::Utc)

function New-Interval {
    param([double] $StartSeconds, [double] $EndSeconds)
    return [pscustomobject]@{
        Start = $epoch.AddSeconds($StartSeconds)
        End   = $epoch.AddSeconds($EndSeconds)
    }
}

function Assert-Union {
    param([string] $Name, [object[]] $Interval, [double] $ClipStartSeconds, [double] $ClipEndSeconds, [double] $ExpectedMilliseconds)
    $actual = Get-AhkFlowIntervalUnionMilliseconds `
        -Interval $Interval `
        -ClipStart $epoch.AddSeconds($ClipStartSeconds) `
        -ClipEnd $epoch.AddSeconds($ClipEndSeconds)
    if ([math]::Abs($actual - $ExpectedMilliseconds) -gt 0.001) {
        $script:failures += "$Name : expected $ExpectedMilliseconds ms, got $actual ms"
    }
}

# --- Overlap: four ten-second steps starting together inside a twelve-second run ---
# Adding durations would give 40 s and a residual of minus 28 s. The union is 10 s.
Assert-Union -Name 'four identical overlapping intervals' -ClipStartSeconds 0 -ClipEndSeconds 12 -ExpectedMilliseconds 10000 -Interval @(
    (New-Interval -StartSeconds 0 -EndSeconds 10)
    (New-Interval -StartSeconds 0 -EndSeconds 10)
    (New-Interval -StartSeconds 0 -EndSeconds 10)
    (New-Interval -StartSeconds 0 -EndSeconds 10)
)

# --- Nesting: a parent holding four children end to end ---
# Adding durations would count the parent's ten seconds twice. The union is the parent.
Assert-Union -Name 'parent with four nested children' -ClipStartSeconds 0 -ClipEndSeconds 12 -ExpectedMilliseconds 10000 -Interval @(
    (New-Interval -StartSeconds 0 -EndSeconds 10)
    (New-Interval -StartSeconds 0 -EndSeconds 2.5)
    (New-Interval -StartSeconds 2.5 -EndSeconds 5)
    (New-Interval -StartSeconds 5 -EndSeconds 7.5)
    (New-Interval -StartSeconds 7.5 -EndSeconds 10)
)

# --- Clipping: an interval running past the end of the run counts only up to the end ---
Assert-Union -Name 'interval overhanging both ends' -ClipStartSeconds 2 -ClipEndSeconds 8 -ExpectedMilliseconds 6000 -Interval @(
    (New-Interval -StartSeconds 0 -EndSeconds 20)
)

# --- Disjoint: two separated intervals add up, and the gap is not counted ---
Assert-Union -Name 'two disjoint intervals' -ClipStartSeconds 0 -ClipEndSeconds 10 -ExpectedMilliseconds 2000 -Interval @(
    (New-Interval -StartSeconds 1 -EndSeconds 2)
    (New-Interval -StartSeconds 3 -EndSeconds 4)
)

# --- Touching: intervals that meet exactly merge into one, with no double count ---
Assert-Union -Name 'two touching intervals' -ClipStartSeconds 0 -ClipEndSeconds 10 -ExpectedMilliseconds 2000 -Interval @(
    (New-Interval -StartSeconds 1 -EndSeconds 2)
    (New-Interval -StartSeconds 2 -EndSeconds 3)
)

# --- Nothing to merge ---
Assert-Union -Name 'no intervals at all' -ClipStartSeconds 0 -ClipEndSeconds 10 -ExpectedMilliseconds 0 -Interval @()

# --- Entirely outside the run window contributes nothing ---
Assert-Union -Name 'interval wholly after the clip window' -ClipStartSeconds 0 -ClipEndSeconds 5 -ExpectedMilliseconds 0 -Interval @(
    (New-Interval -StartSeconds 6 -EndSeconds 9)
)

# --- An interval that ends before it starts is a bug in the caller, not a zero ---
$threw = $false
try {
    Get-AhkFlowIntervalUnionMilliseconds `
        -Interval @([pscustomobject]@{ Start = $epoch.AddSeconds(5); End = $epoch.AddSeconds(1) }) `
        -ClipStart $epoch -ClipEnd $epoch.AddSeconds(10) | Out-Null
}
catch {
    $threw = $true
}
if (-not $threw) {
    $failures += 'backwards interval : expected a throw, got a value'
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }
    Write-Host "$($failures.Count) failure(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'IntervalUnion.Tests.ps1: all cases passed.' -ForegroundColor Green
