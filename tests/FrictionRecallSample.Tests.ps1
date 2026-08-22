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

# --- 9. The corrected bounds are the exact hypergeometric ones ---

# -Correct answers a question about a FINITE population: how many misses are in the N rows,
# given x of the n drawn were misses. The exact distribution of that is hypergeometric, and the
# interval is the set of population counts the observation does not rule out at 95 percent.
#
# An earlier version substituted an effective sample size into Wilson instead. That is a
# large-population approximation, and it is anti-conservative at the boundary: for 0 of 200
# drawn from 220 it returned an upper bound of 0 population misses, which is a claim of
# certainty. One miss among 220 escapes a 200-row draw 20/220 of the time, so 0 was wrong
# nearly a tenth of the time it was stated. The cases below pin the exact answer.

function Get-HypergeometricAtMost {
    <#
    .SYNOPSIS
        P(X <= Observed) when Total holds Successes and Drawn rows are taken without replacement.
    .DESCRIPTION
        Written from the definition, summing C(K,i)C(N-K,n-i)/C(N,n) in log space. It shares no
        code with Get-RecallInterval, so agreement between them is evidence.
    #>
    param(
        [Parameter(Mandatory)][int] $Observed,
        [Parameter(Mandatory)][int] $Successes,
        [Parameter(Mandatory)][int] $Total,
        [Parameter(Mandatory)][int] $Drawn
    )
    $logFactorial = New-Object 'double[]' ($Total + 1)
    for ($i = 1; $i -le $Total; $i++) { $logFactorial[$i] = $logFactorial[$i - 1] + [Math]::Log($i) }
    $logChoose = {
        param([int] $a, [int] $b)
        if ($b -lt 0 -or $b -gt $a) { return [double]::NegativeInfinity }
        return $logFactorial[$a] - $logFactorial[$b] - $logFactorial[$a - $b]
    }
    $sum = 0.0
    $denominator = & $logChoose $Total $Drawn
    for ($i = 0; $i -le $Observed; $i++) {
        $term = (& $logChoose $Successes $i) + (& $logChoose ($Total - $Successes) ($Drawn - $i))
        if (-not [double]::IsNegativeInfinity($term)) { $sum += [Math]::Exp($term - $denominator) }
    }
    return $sum
}

# The regression case. It returned 0 before the fix.
$tight = Get-RecallInterval -Hits 0 -Drawn 200 -Population 220 -Correct
Assert-True ($tight.HighCount -eq 1) `
    ("0 misses in 200 drawn from 220 must leave 1 population miss possible, got $($tight.HighCount). " +
    'One miss escapes a 200-row draw 20/220 of the time, which is well above the 2.5 percent tail.')

# Each bound is the last population count the observation does not rule out, checked against a
# hypergeometric written separately in this file.
foreach ($case in @(@(11, 200, 5457), @(7, 200, 1004), @(0, 200, 220), @(0, 200, 1004), @(200, 200, 400), @(5, 5, 60))) {
    $hits, $drawn, $popSize = $case
    $interval = Get-RecallInterval -Hits $hits -Drawn $drawn -Population $popSize -Correct

    $atHigh = Get-HypergeometricAtMost -Observed $hits -Successes $interval.HighCount -Total $popSize -Drawn $drawn
    Assert-True ($atHigh -gt 0.025) `
        "the upper bound $($interval.HighCount) for $hits of $drawn from $popSize is ruled out: P(X<=$hits) = $atHigh"
    if ($interval.HighCount -lt $popSize) {
        $beyond = Get-HypergeometricAtMost -Observed $hits -Successes ($interval.HighCount + 1) -Total $popSize -Drawn $drawn
        Assert-True ($beyond -le 0.025) `
            "the upper bound is not tight: $($interval.HighCount + 1) is still possible at P(X<=$hits) = $beyond"
    }

    # The lower bound gets the same treatment from the other tail, and it needs it. Checking
    # only that it sits below the upper bound would accept the observed count itself: for 11 of
    # 200 from 5,457 the answer is 154, and a bound of 11 satisfies every ordering rule while
    # being fourteen times too small. P(X >= Hits) rises with the population count, so the bound
    # is the FIRST count the observation does not rule out.
    $atLow = 1.0 - (Get-HypergeometricAtMost -Observed ($hits - 1) -Successes $interval.LowCount -Total $popSize -Drawn $drawn)
    Assert-True ($atLow -gt 0.025) `
        "the lower bound $($interval.LowCount) for $hits of $drawn from $popSize is ruled out: P(X>=$hits) = $atLow"
    if ($interval.LowCount -gt 0) {
        $under = 1.0 - (Get-HypergeometricAtMost -Observed ($hits - 1) -Successes ($interval.LowCount - 1) -Total $popSize -Drawn $drawn)
        Assert-True ($under -le 0.025) `
            "the lower bound is not tight: $($interval.LowCount - 1) is still possible at P(X>=$hits) = $under"
    }

    Assert-True ($interval.LowCount -le $interval.HighCount) `
        "the lower bound must not exceed the upper for $hits of $drawn from $popSize"
    Assert-True ($interval.HighCount -ge $hits) `
        "the population cannot hold fewer misses than the $hits the draw found"
    Assert-True ($interval.LowCount -ge $hits) `
        "the population cannot hold fewer misses than the $hits the draw found, so neither can the lower bound"
}

# --- A tail that lands exactly on 0.025 ---
#
# This case is here because the log-based oracle above cannot catch it, and neither could the
# implementation while it shared that arithmetic. The numbers are small enough to settle by hand
# with no floating point anywhere:
#
#   P(X >= 2 | N = 16, n = 2, K = 3) = C(3,2) / C(16,2) = 3 / 120 = 1/40 = 0.025 exactly.
#
# The rule is strict: a count is ruled out unless its tail EXCEEDS 0.025. Three is therefore
# ruled out, and the lower bound is 4. Rebuilt through logarithms the same tail comes back as
# 0.025000000000000012, which clears a strict comparison by one part in 10^17, so the bound came
# back as 3. Exact integer arithmetic is the only fix that does not just move the threshold.
$tie = Get-RecallInterval -Hits 2 -Drawn 2 -Population 16 -Correct
Assert-True ($tie.LowCount -eq 4) `
    ('P(X>=2 | K=3) is exactly 3/120 = 0.025, which a strict tail does not admit, so the lower ' +
    "bound for 2 of 2 from 16 must be 4, got $($tie.LowCount)")

# The mirror of the same tie on the upper tail: P(X <= 0 | N = 16, n = 2, K = 13) =
# C(3,2) / C(16,2) = 3/120 = 0.025 exactly, so 13 is ruled out and the upper bound is 12.
$tieHigh = Get-RecallInterval -Hits 0 -Drawn 2 -Population 16 -Correct
Assert-True ($tieHigh.HighCount -eq 12) `
    ('P(X<=0 | K=13) is exactly 3/120 = 0.025, which a strict tail does not admit, so the upper ' +
    "bound for 0 of 2 from 16 must be 12, got $($tieHigh.HighCount)")

# A census answers exactly. Drawing every row makes both tails degenerate, so the interval must
# collapse onto the count that was seen rather than widening around it.
$whole = Get-RecallInterval -Hits 4 -Drawn 30 -Population 30 -Correct
Assert-True ($whole.LowCount -eq 4 -and $whole.HighCount -eq 4) `
    "drawing the whole population must return exactly 4, got $($whole.LowCount) to $($whole.HighCount)"

# --- 10. Plain Wilson reproduces the figures the document already published ---

# The external oracle. These numbers were computed before this function existed, so agreeing
# with them is evidence about the formula. The same read doubles as the drift guard: the inputs
# come from the committed manifests, so a relabelled row that nobody republished fails here.
$docPath = Join-Path $repoRoot 'docs/development/friction-recall-sample.md'
Assert-True (Test-Path -LiteralPath $docPath) "The sample document is missing: $docPath"

if (Test-Path -LiteralPath $docPath) {
    $docFlat = ((Get-Content -LiteralPath $docPath -Raw) -replace '\s+', ' ')

    # FinalNoun is the headline figure: the sampled misses PLUS the flagged rows labelled real.
    # Checking only the unflagged sub-range left the published totals unguarded, which is the
    # number every other document quotes.
    $specs = @(
        [pscustomobject]@{
            Name = 'handoffs'; Manifest = 'handoffs-sample'; Noun = 'missed handoffs'
            FinalPattern = '\*\*True count: roughly (\d+) to (\d+)\.\*\* The flagged'
            Row072 = '\| Blocked-agent handoffs \| \*\*(\d+) to (\d+)\*\* \|'
        },
        [pscustomobject]@{
            Name = 'next-step-asks'; Manifest = 'next-step-asks-sample'; Noun = 'missed asks'
            FinalPattern = '\*\*True count: roughly (\d+) to (\d+)\.\*\*(?! The flagged)'
            Row072 = '\| Next-step asks \| \*\*(\d+) to (\d+)\*\* \|'
        }
    )

    $item072Path = Join-Path $repoRoot 'backlog/done/072-process-wave-2-parity-drift-guard-templates.md'
    Assert-True (Test-Path -LiteralPath $item072Path) "Item 072 is missing: $item072Path"
    $item072Flat = if (Test-Path -LiteralPath $item072Path) {
        ((Get-Content -LiteralPath $item072Path -Raw) -replace '\s+', ' ')
    }
    else { '' }

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

        # --- The headline figure, which is the sub-range plus the flagged rows labelled real ---
        #
        # This is the number 072 quotes and the number a reader remembers. Guarding only the
        # unflagged sub-range above let the totals drift on their own.
        $realFlagged = @($rows | Where-Object { $_.Stratum -eq 'flagged' -and $_.Label -eq 'real' }).Count
        $expectedLow = $interval.LowCount + $realFlagged
        $expectedHigh = $interval.HighCount + $realFlagged

        $finalMatch = [regex]::Match($docFlat, $spec.FinalPattern)
        Assert-True $finalMatch.Success `
            "The document must publish a true count for $($spec.Name). Pattern did not match."
        if ($finalMatch.Success) {
            Assert-True ([int]$finalMatch.Groups[1].Value -eq $expectedLow -and [int]$finalMatch.Groups[2].Value -eq $expectedHigh) `
                ("The document publishes a $($spec.Name) true count of " +
                "$($finalMatch.Groups[1].Value) to $($finalMatch.Groups[2].Value); " +
                "$($interval.LowCount) to $($interval.HighCount) missed plus $realFlagged real flagged is $expectedLow to $expectedHigh.")
        }

        # --- Item 072 quotes the same figure, and must not drift from it ---
        $row072 = [regex]::Match($item072Flat, $spec.Row072)
        Assert-True $row072.Success `
            "Item 072 must carry a $($spec.Name) row with a published range. Pattern did not match."
        if ($row072.Success) {
            Assert-True ([int]$row072.Groups[1].Value -eq $expectedLow -and [int]$row072.Groups[2].Value -eq $expectedHigh) `
                ("Item 072 publishes $($spec.Name) as $($row072.Groups[1].Value) to $($row072.Groups[2].Value); " +
                "the labels give $expectedLow to $expectedHigh. A corrected figure belongs there as a dated " +
                'addition under "The withdrawn figures", never as a silent substitution.')
        }
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

# --- 14. Every interval contains the count the sample itself points at ---

# Not "the correction is narrower". An exact interval on a discrete distribution is
# conservative and may come out WIDER than the approximation it replaces, so asserting
# narrowness would forbid a correct answer. What must always hold is that the interval covers
# the population count the observed rate implies.
foreach ($switch in @($false, $true)) {
    foreach ($case in @(@(7, 200, 1004), @(11, 200, 5457), @(0, 200, 220))) {
        $hits, $drawn, $popSize = $case
        $interval = if ($switch) { Get-RecallInterval -Hits $hits -Drawn $drawn -Population $popSize -Correct }
        else { Get-RecallInterval -Hits $hits -Drawn $drawn -Population $popSize }
        $pointEstimate = [int][Math]::Round($hits / [double]$drawn * $popSize)
        Assert-True ($interval.LowCount -le $pointEstimate -and $pointEstimate -ge 0) `
            "the lower bound $($interval.LowCount) is above the point estimate $pointEstimate for $hits of $drawn from $popSize"
        Assert-True ($interval.HighCount -ge $pointEstimate) `
            "the upper bound $($interval.HighCount) is below the point estimate $pointEstimate for $hits of $drawn from $popSize"
        $expectedMethod = if ($switch) { 'hypergeometric' } else { 'wilson' }
        Assert-True ($interval.Method -eq $expectedMethod) `
            "the interval must name its method as $expectedMethod, got $($interval.Method)"
    }
}

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
# Parsed, not grepped. A regex needing both tokens on one physical line misses a call split
# across lines, and misses a splat entirely - `$args = @{ Correct = $true }` followed by
# `Get-RecallInterval @args` carries no literal `-Correct` anywhere. The parser sees those.
#
# What it CANNOT see, and what this case therefore does not promise:
#
#   Set-Alias gri Get-RecallInterval ; gri -Hits 1 -Drawn 2 -Population 3 -Correct
#   $name = 'Get-RecallInterval' ; & $name -Correct
#   Invoke-Expression 'Get-RecallInterval -Correct'
#
# A command name is only known statically when it is written literally, so each of these reaches
# the switch with the scan reporting nothing. The three shapes are reported below wherever they
# appear in a file that also names Get-RecallInterval, which turns a silent bypass into a
# failure a human has to clear. That is narrower than a proof: a script could still build the
# name from pieces, or reach the function through a module loaded at run time.
#
# So the claim this case supports is the modest one. Nothing in this repository passes -Correct
# today, and no ordinary edit can start doing so without failing here. It is not a guarantee
# that the switch is unreachable.
function Test-BindsToCorrect {
    <#
    .SYNOPSIS
        Whether a written parameter name binds to -Correct.
    .DESCRIPTION
        PowerShell binds any unambiguous prefix, so -C, -Co, -Cor and -Corr all reach -Correct:
        it is the only parameter of Get-RecallInterval that starts with C. A check for the whole
        word lets every one of those through, which is a guard that reads as if it works.

        Both directions are tested. A name that is a prefix of 'Correct' binds to it, and a name
        that starts with 'Correct' is either the parameter itself or a longer name that no longer
        binds - reported anyway, because a name that close to the prohibited switch is worth a
        human look.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Name)
    if ([string]::IsNullOrEmpty($Name)) { return $false }
    return 'Correct'.StartsWith($Name, [System.StringComparison]::OrdinalIgnoreCase) -or
    $Name.StartsWith('Correct', [System.StringComparison]::OrdinalIgnoreCase)
}

# The guard's own rule, checked before it is trusted to read the scripts. Each of these binds
# to -Correct when written at a call site; the earlier whole-word check caught only the first.
foreach ($name in @('Correct', 'correct', 'CORRECT', 'C', 'c', 'Co', 'Cor', 'Corr', 'Correctly')) {
    Assert-True (Test-BindsToCorrect -Name $name) "-$name reaches -Correct, so the guard must catch it"
}
foreach ($name in @('Hits', 'Drawn', 'Population', 'D', 'Population2', '')) {
    Assert-True (-not (Test-BindsToCorrect -Name $name)) "-$name does not reach -Correct, so the guard must not report it"
}

$scriptDir = Join-Path $repoRoot 'scripts'
$callers = New-Object System.Collections.Generic.List[string]

foreach ($file in (Get-ChildItem -LiteralPath $scriptDir -Filter '*.ps1' -Recurse)) {
    $parseErrors = $null
    $parsedTokens = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName, [ref]$parsedTokens, [ref]$parseErrors)
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        Assert-True $false "Could not parse $($file.Name) to check for -Correct callers: $($parseErrors[0].Message)"
        continue
    }

    # Only a file that names the function can reach it by any of the shapes below. Scanning every
    # script for a dynamic invocation would report Invoke-Expression across the whole repository,
    # which is a different rule and not this one.
    $mentionsFunction = (Get-Content -LiteralPath $file.FullName -Raw) -match 'Get-RecallInterval'

    if ($mentionsFunction) {
        # `& $name` and `. $name`, where the command is held in a variable. Reported because the
        # name could be Get-RecallInterval and nothing here can tell.
        #
        # A dot-source of a computed PATH is not this. `. (Join-Path $PSScriptRoot 'x.ps1')` also
        # hides its command name from the parser, and this file uses it at line 305 to load a
        # sibling script. Loading a file is not invoking the function, so flagging it would
        # report a pattern the repository depends on and teach the reader to ignore the failure.
        $opaque = $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                $null -eq $node.GetCommandName() -and
                $node.CommandElements.Count -gt 0 -and
                $node.CommandElements[0] -is [System.Management.Automation.Language.VariableExpressionAst]
            }, $true)
        foreach ($command in $opaque) {
            $callers.Add("$($file.Name):$($command.Extent.StartLineNumber) command name held in a variable")
        }

        $named = $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -in @('Set-Alias', 'New-Alias', 'Invoke-Expression', 'iex')
            }, $true)
        foreach ($command in $named) {
            $callers.Add("$($file.Name):$($command.Extent.StartLineNumber) $($command.GetCommandName()) in a file that names Get-RecallInterval")
        }
    }

    $commands = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -eq 'Get-RecallInterval'
        }, $true)

    foreach ($command in $commands) {
        foreach ($element in $command.CommandElements) {
            # A named switch, however the call is wrapped across lines, and however far it is
            # abbreviated. -C is enough to bind, so the whole word is not what to look for.
            if ($element -is [System.Management.Automation.Language.CommandParameterAst] -and
                (Test-BindsToCorrect -Name $element.ParameterName)) {
                $callers.Add("$($file.Name):$($element.Extent.StartLineNumber) -$($element.ParameterName)")
            }
            # A splat. What it holds cannot be resolved here, so any splat onto this command is
            # reported: a call nobody can read is not a call anybody can clear.
            if ($element -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $element.Splatted) {
                $callers.Add("$($file.Name):$($element.Extent.StartLineNumber) splat @$($element.VariablePath.UserPath)")
            }
        }
    }
}

Assert-True ($callers.Count -eq 0) `
    ('No script may pass -Correct while the published draw is the 2026-08-16 one. Also reported: ' +
    'a splat onto Get-RecallInterval, a command name held in a variable, and Set-Alias, New-Alias ' +
    'or Invoke-Expression in a file that names the function - each hides whether the switch is ' +
    'passed, and a call nobody can read is not a call anybody can clear: ' + ($callers -join '; '))

# --- 17. -ProjectRoot is honoured, not merely accepted ---
#
# The script returns at `if ($AsModule) { return }` before it reads a transcript, so a
# module-mode test cannot reach the parameter's only use. This one runs the script as a script
# against a fixture directory. If the parameter were ignored the run would read the live
# transcripts, and neither assertion below would hold.
#
# Get-TranscriptFile keeps only directories whose name matches 'AHKFlow', so the fixture folder
# is named accordingly. The timestamps sit inside the fixed window.

$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("friction-fixture-" + [guid]::NewGuid().ToString('n'))
$fixtureProject = Join-Path $fixtureRoot 'C--fixture-AHKFlowApp'
New-Item -ItemType Directory -Path $fixtureProject -Force | Out-Null

$fixtureRows = @(
    '{"type":"assistant","timestamp":"2026-08-01T10:00:00.000Z","uuid":"f0000000-0000-0000-0000-000000000001","sessionId":"fixture-a","message":{"id":"msg_fixture_001","content":[{"type":"text","text":"The token is corrupt, so please run it yourself in your terminal."}]}}'
    '{"type":"assistant","timestamp":"2026-08-01T10:01:00.000Z","uuid":"f0000000-0000-0000-0000-000000000002","sessionId":"fixture-a","message":{"id":"msg_fixture_002","content":[{"type":"text","text":"Fixture message two. It carries no handoff wording at all."}]}}'
    '{"type":"assistant","timestamp":"2026-08-01T10:02:00.000Z","uuid":"f0000000-0000-0000-0000-000000000003","sessionId":"fixture-a","message":{"id":"msg_fixture_003","content":[{"type":"text","text":"Fixture message three. It carries no handoff wording either."}]}}'
    '{"type":"assistant","timestamp":"2026-08-01T10:03:00.000Z","uuid":"f0000000-0000-0000-0000-000000000004","sessionId":"fixture-a","message":{"id":"msg_fixture_004","content":[{"type":"text","text":"Fixture message four. Also plain, also inside the window."}]}}'
)
Set-Content -LiteralPath (Join-Path $fixtureProject 'fixture-a.jsonl') -Value $fixtureRows -Encoding utf8

$fixtureManifest = Join-Path $fixtureRoot 'fixture-sample.csv'
$fixtureSelection = Join-Path $fixtureRoot 'fixture-sample.selection.json'

try {
    & (Join-Path $repoRoot 'scripts/sample-friction-recall.ps1') `
        -Metric handoffs `
        -ProjectRoot $fixtureRoot `
        -OutputPath $fixtureManifest `
        -SampleSize 2 | Out-Null

    Assert-True (Test-Path -LiteralPath $fixtureManifest) `
        "the sampler must write a manifest when -ProjectRoot names a fixture directory: $fixtureManifest"

    if (Test-Path -LiteralPath $fixtureManifest) {
        $fixtureRowsRead = @(Import-Csv -LiteralPath $fixtureManifest)
        $foreign = @($fixtureRowsRead | Where-Object { $_.Key -notlike 'msg:msg_fixture_*' })
        Assert-True ($foreign.Count -eq 0) `
        ("every row must come from the fixture, so -ProjectRoot was read rather than ignored. " +
            "Foreign keys: $(@($foreign | ForEach-Object { $_.Key }) -join ', ')")
        Assert-True ($fixtureRowsRead.Count -eq 3) `
            "the fixture holds 1 flagged and 3 unflagged rows, so a 2-row draw gives 3 rows, got $($fixtureRowsRead.Count)"
    }

    Assert-True (Test-Path -LiteralPath $fixtureSelection) `
        "the sampler must write a selection record beside the fixture manifest: $fixtureSelection"

    if (Test-Path -LiteralPath $fixtureSelection) {
        $fixtureRecord = Get-Content -LiteralPath $fixtureSelection -Raw | ConvertFrom-Json
        Assert-True ($fixtureRecord.transcriptRoot -eq $fixtureRoot) `
            "the selection record must name the transcript root it read, expected $fixtureRoot, got $($fixtureRecord.transcriptRoot)"
    }
}
finally {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host ''; Write-Host $failure -ForegroundColor Red }
    Write-Host ''
    throw "Friction recall sample tests failed with $($failures.Count) problem(s). See the detail above."
}

Write-Host 'Friction recall sample tests passed. 7 selection cases, 11 interval cases.'
