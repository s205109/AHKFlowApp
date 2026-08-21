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

# =====================================================================================
# Get-RecallInterval
# =====================================================================================
#
# The published range is the one figure this whole exercise produces, so the function behind
# it needs an oracle that is not itself. Asserting that a document contains whatever the
# function computed would pass just as happily with a sign error in the formula: the wrong
# number would be written to both sides.
#
# Two oracles are used instead. The first is the definition of a Wilson bound, evaluated by
# test code that shares no arrangement of terms with the implementation. The second is the
# committed document, whose figures were produced by an earlier, separate implementation.

$z = 1.959963985

function Test-WilsonRoot {
    <#
    .SYNOPSIS
        How far a bound is from satisfying the equation that defines it.
    .DESCRIPTION
        A Wilson bound is a value of p where the score statistic reaches +/- z, that is where
        (phat - p)^2 = z^2 * p * (1 - p) / n. This returns the two sides' difference, so a
        correct bound returns roughly zero.

        Written from the definition on purpose. Get-RecallInterval uses the closed-form root of
        the same equation, so agreement between the two is evidence and not a tautology.
    #>
    param(
        [Parameter(Mandatory)][double] $Bound,
        [Parameter(Mandatory)][double] $Observed,
        [Parameter(Mandatory)][double] $SampleSize
    )
    $left = ($Observed - $Bound) * ($Observed - $Bound)
    $right = $z * $z * $Bound * (1.0 - $Bound) / $SampleSize
    return [Math]::Abs($left - $right)
}

# --- 8. Both plain bounds satisfy the equation that defines a Wilson bound ---

foreach ($case in @(@(11, 200, 5457), @(7, 200, 1004), @(3, 40, 900), @(19, 63, 2000))) {
    $hits, $drawn, $popSize = $case
    $interval = Get-RecallInterval -Hits $hits -Drawn $drawn -Population $popSize
    $observed = $hits / [double]$drawn
    foreach ($pair in @(@('lower', $interval.Low), @('upper', $interval.High))) {
        $residual = Test-WilsonRoot -Bound $pair[1] -Observed $observed -SampleSize $drawn
        Assert-True ($residual -lt 1e-12) `
            "the $($pair[0]) bound for $hits of $drawn does not solve the Wilson equation, residual $residual"
    }
}

# --- 9. The corrected bounds solve the same equation at the effective sample size ---

# This is what the correction claims to be: the same interval, computed at n_eff. If -Correct
# ever became an ad-hoc narrowing instead, this case fails.
foreach ($case in @(@(11, 200, 5457), @(7, 200, 1004))) {
    $hits, $drawn, $popSize = $case
    $interval = Get-RecallInterval -Hits $hits -Drawn $drawn -Population $popSize -Correct
    $observed = $hits / [double]$drawn
    $effective = $drawn * ($popSize - 1.0) / ($popSize - $drawn)
    Assert-True ([Math]::Abs($interval.Effective - $effective) -lt 1e-9) `
        "n_eff for $drawn of $popSize must be $effective, got $($interval.Effective)"
    foreach ($pair in @(@('lower', $interval.Low), @('upper', $interval.High))) {
        $residual = Test-WilsonRoot -Bound $pair[1] -Observed $observed -SampleSize $effective
        Assert-True ($residual -lt 1e-12) `
            "the corrected $($pair[0]) bound for $hits of $drawn does not solve the Wilson equation at n_eff, residual $residual"
    }
}

# --- 10. Plain Wilson reproduces the figures the document already published ---

# The external oracle. These numbers were computed before this function existed, so agreeing
# with them is evidence about the formula. The same read doubles as the drift guard: the inputs
# come from the committed manifests, so a relabelled row that nobody republished fails here.
$docPath = Join-Path $repoRoot 'docs/development/friction-recall-sample.md'
Assert-True (Test-Path -LiteralPath $docPath) "The sample document is missing: $docPath"

if (Test-Path -LiteralPath $docPath) {
    $docFlat = ((Get-Content -LiteralPath $docPath -Raw) -replace '\s+', ' ')

    $specs = @(
        [pscustomobject]@{ Name = 'handoffs'; Manifest = 'handoffs-sample'; Noun = 'missed handoffs' },
        [pscustomobject]@{ Name = 'next-step-asks'; Manifest = 'next-step-asks-sample'; Noun = 'missed asks' }
    )

    foreach ($spec in $specs) {
        $manifestPath = Join-Path $repoRoot "docs/development/friction-samples/$($spec.Manifest).csv"
        $selectionPath = Join-Path $repoRoot "docs/development/friction-samples/$($spec.Manifest).selection.json"
        Assert-True (Test-Path -LiteralPath $manifestPath) "The manifest is missing: $manifestPath"
        Assert-True (Test-Path -LiteralPath $selectionPath) "The selection record is missing: $selectionPath"
        if (-not (Test-Path -LiteralPath $manifestPath) -or -not (Test-Path -LiteralPath $selectionPath)) { continue }

        $rows = @(Import-Csv -LiteralPath $manifestPath)
        $unflagged = @($rows | Where-Object { $_.Stratum -eq 'unflagged' })
        $missed = @($unflagged | Where-Object { $_.Label -eq 'missed' })
        $population = [int](Get-Content -LiteralPath $selectionPath -Raw | ConvertFrom-Json).unflaggedCount

        # The document states its own inputs. If the manifest and the prose disagree about how
        # many rows were drawn or how many were missed, the range describes neither.
        $pattern = "$($missed.Count) in $($unflagged.Count) is a [\d.]+ percent miss rate, " +
        '95 percent Wilson interval ([\d.]+) to ([\d.]+) percent\. Across ([\d,]+) ' +
        "unflagged messages that is \*\*(\d+) to (\d+) $([regex]::Escape($spec.Noun))\*\*"

        $match = [regex]::Match($docFlat, $pattern)
        Assert-True $match.Success `
            ("The document must state the $($spec.Name) range with the manifest's own inputs: " +
            "$($missed.Count) missed in $($unflagged.Count) drawn. Pattern did not match.")
        if (-not $match.Success) { continue }

        $statedPopulation = [int](($match.Groups[3].Value) -replace ',', '')
        Assert-True ($statedPopulation -eq $population) `
            "The document says $statedPopulation unflagged $($spec.Name) messages; the selection record says $population."

        $interval = Get-RecallInterval -Hits $missed.Count -Drawn $unflagged.Count -Population $population

        $statedLowRate = [double]$match.Groups[1].Value
        $statedHighRate = [double]$match.Groups[2].Value
        Assert-True ([Math]::Abs([Math]::Round($interval.Low * 100, 1) - $statedLowRate) -lt 0.05) `
            "The document publishes a $($spec.Name) lower rate of $statedLowRate percent; the function computes $([Math]::Round($interval.Low * 100, 1))."
        Assert-True ([Math]::Abs([Math]::Round($interval.High * 100, 1) - $statedHighRate) -lt 0.05) `
            "The document publishes a $($spec.Name) upper rate of $statedHighRate percent; the function computes $([Math]::Round($interval.High * 100, 1))."

        Assert-True ([int]$match.Groups[4].Value -eq $interval.LowCount) `
            "The document publishes $($match.Groups[4].Value) as the $($spec.Name) low count; the function computes $($interval.LowCount)."
        Assert-True ([int]$match.Groups[5].Value -eq $interval.HighCount) `
            "The document publishes $($match.Groups[5].Value) as the $($spec.Name) high count; the function computes $($interval.HighCount)."
    }

    # --- 11. The document still says the interval is an approximation ---

    # Backlog 102 decided the ranges stay plain Wilson and stay labelled approximate, because
    # the draw had unequal inclusion probabilities and the records a design-based estimator
    # would need are deleted. An edit that dropped this sentence while keeping the numbers
    # would publish a figure that looks exact and is not.
    Assert-True ($docFlat -match 'drawn the old way, and its intervals are approximate') `
        'The document must still say the committed sample was drawn the old way and its intervals are approximate.'
}

# --- 12. A census is exact, and does not divide by zero ---

$census = Get-RecallInterval -Hits 3 -Drawn 10 -Population 10 -Correct
Assert-True ($census.LowCount -eq 3 -and $census.HighCount -eq 3) `
    "drawing the whole population must give the exact count, got $($census.LowCount) to $($census.HighCount)"
Assert-True ($census.Low -eq $census.High) 'a census must have no width'

# --- 13. The bounds stay inside 0 and 1 at both extremes ---

foreach ($hits in @(0, 200)) {
    $interval = Get-RecallInterval -Hits $hits -Drawn 200 -Population 1004
    Assert-True ($interval.Low -ge 0.0 -and $interval.High -le 1.0) `
        "a rate of $hits in 200 must stay inside 0 and 1, got $($interval.Low) to $($interval.High)"
    Assert-True ($interval.Low -le $interval.High) "the lower bound must not exceed the upper for $hits in 200"
}

# --- 14. The correction narrows the interval, and never widens it ---

$plain = Get-RecallInterval -Hits 7 -Drawn 200 -Population 1004
$corrected = Get-RecallInterval -Hits 7 -Drawn 200 -Population 1004 -Correct
Assert-True (($corrected.High - $corrected.Low) -lt ($plain.High - $plain.Low)) `
    'the correction must narrow the interval when the sample is a real share of the population'

# --- 15. Impossible inputs throw rather than returning a number ---

foreach ($bad in @(@{ Hits = 5; Drawn = 2; Population = 10 }, @{ Hits = 1; Drawn = 20; Population = 10 })) {
    $threw = $false
    try { Get-RecallInterval @bad | Out-Null } catch { $threw = $true }
    Assert-True $threw "Get-RecallInterval must throw for Hits=$($bad.Hits) Drawn=$($bad.Drawn) Population=$($bad.Population)"
}

# --- 16. No script applies the correction to the committed draw ---

# -Correct is valid only for an equal-probability draw. The committed 2026-08-16 manifests are
# not one, so a script that passed the switch would publish a narrower range resting on an
# assumption the data breaks. Nothing passes it today, and this case keeps it that way.
$scriptDir = Join-Path $repoRoot 'scripts'
$callers = @(Get-ChildItem -LiteralPath $scriptDir -Filter '*.ps1' -Recurse |
        Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match 'Get-RecallInterval[^\r\n]*-Correct' })
Assert-True ($callers.Count -eq 0) `
    ("No script may pass -Correct while the published draw is the 2026-08-16 one: " +
    "$(($callers | ForEach-Object { $_.Name }) -join ', ')")

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host ''; Write-Host $failure -ForegroundColor Red }
    Write-Host ''
    throw "Friction recall sample tests failed with $($failures.Count) problem(s). See the detail above."
}

Write-Host 'Friction recall sample tests passed. 7 selection cases, 9 interval cases.'
