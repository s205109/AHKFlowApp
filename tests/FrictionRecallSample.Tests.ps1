#Requires -Version 7.0

# The draw decides what a published interval means. A sample that keeps the rows it drew last
# time and fills the rest at random is not a uniform sample: a row that was there earlier had
# two chances of selection and a later row one, so the Wilson interval over its labels describes
# a draw nobody made. These cases pin the two properties the interval needs - uniform, and
# stable while the population grows.
#
# Run it by hand with:  pwsh ./tests/FrictionRecallSample.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts/sample-friction-recall.ps1') -AsModule

$failures = @()
function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { $script:failures += $Message }
}

$population = @(0..4999 | ForEach-Object { 'session-{0:d4}:msg-{0:d4}' -f $_ })
$seed = 20260816
$size = 200

# --- The same seed and key always give the same priority ---
$first = Get-SelectionPriority -Key $population[7] -Seed $seed
$second = Get-SelectionPriority -Key $population[7] -Seed $seed
Assert-True ($first -eq $second) 'the priority of a key must not change between calls'
Assert-True ((Get-SelectionPriority -Key $population[7] -Seed ($seed + 1)) -ne $first) 'another seed must give another priority'

# --- The draw is the requested size, and holds no row twice ---
$sample = @(Select-SampleKey -Keys $population -Seed $seed -SampleSize $size)
Assert-True ($sample.Count -eq $size) "the draw must hold $size keys, got $($sample.Count)"
Assert-True ((@($sample | Sort-Object -Unique)).Count -eq $size) 'the draw must not hold a key twice'
Assert-True ((@($sample | Where-Object { $population -notcontains $_ })).Count -eq 0) 'every drawn key must come from the population'

# --- The draw does not depend on the order the population arrives in ---
$shuffled = @($population | Sort-Object { Get-Random })
$sameSample = @(Select-SampleKey -Keys $shuffled -Seed $seed -SampleSize $size)
Assert-True ((($sample | Sort-Object) -join '|') -eq (($sameSample | Sort-Object) -join '|')) 'the drawn set must not depend on the order of the population'

# --- A growing population keeps the rows it already drew, unless a lower hash arrives ---
# This is what lets a hand-written label survive a re-run without the label deciding the sample.
$grown = @($population + @(5000..5499 | ForEach-Object { 'session-{0:d4}:msg-{0:d4}' -f $_ }))
$after = @(Select-SampleKey -Keys $grown -Seed $seed -SampleSize $size)
$kept = @($sample | Where-Object { $after -contains $_ })
Assert-True ($kept.Count -ge ($size * 0.85)) "a population 10 percent larger must keep most of the draw, kept $($kept.Count) of $size"
$lost = @($sample | Where-Object { $after -notcontains $_ })
foreach ($key in $lost) {
    # A row leaves the draw only because enough new rows hash lower, never because it was
    # labelled or was not.
    Assert-True ($grown -contains $key) "a lost key must still be in the population: $key"
}

# --- Selection does not favour any part of the ordered population ---
# The old draw carried 57 of 200 rows from an earlier, smaller population, so early rows were
# over-represented. Four equal quarters of the ordered list must each get roughly a quarter.
$ordered = @($population | Sort-Object)
$positions = @($sample | ForEach-Object { [array]::IndexOf($ordered, $_) })
$quarters = @(0, 0, 0, 0)
foreach ($position in $positions) { $quarters[[Math]::Min(3, [int][Math]::Floor($position / ($ordered.Count / 4)))]++ }
foreach ($count in $quarters) {
    Assert-True ($count -ge 25 -and $count -le 75) "each quarter of the population must take roughly a quarter of the draw, got $($quarters -join ', ')"
}

# --- A population smaller than the sample size is drawn whole ---
$small = @(Select-SampleKey -Keys @($population[0..9]) -Seed $seed -SampleSize $size)
Assert-True ($small.Count -eq 10) "a population of 10 must draw 10, got $($small.Count)"

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host ''; Write-Host $failure -ForegroundColor Red }
    Write-Host ''
    throw "Friction recall sample tests failed with $($failures.Count) problem(s). See the detail above."
}

Write-Host 'Friction recall sample tests passed. 7 cases.'
