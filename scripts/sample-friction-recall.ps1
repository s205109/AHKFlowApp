#Requires -Version 7.0
<#
.SYNOPSIS
    Writes the stratified sample manifest that measures the recall of two friction match sets.
.DESCRIPTION
    Metrics 1 and 4 match on wording. A closed match set gives a repeatable number, but its
    recall is unknown, and a figure may only be called an upper bound when nothing real escapes
    the set.

    The sample is stratified. In-window there are tens of thousands of assistant messages and
    roughly a thousand human turns, while real handoffs number in the tens. A random draw over
    the whole population would contain almost no real cases: it would measure precision and say
    nothing at all about recall. So each metric is split in two - every flagged message, which
    gives exact precision, and a seeded random sample of the unflagged remainder, which bounds
    the miss rate.

    The manifest carries the FULL text of every sampled message, not an excerpt. A 160-character
    excerpt cannot be labelled honestly: the sentence that makes a message a handoff is often
    further in, and a reviewer cannot check a label against text that was thrown away.

    It reads the same logical messages the measurement reads, through
    scripts/measure-process-friction.ps1, so the sample cannot drift from the population.
.PARAMETER Metric
    'handoffs' or 'next-step-asks'.
.PARAMETER OutputPath
    Where to write the manifest CSV.
.PARAMETER Seed
    The seed that fixes the draw. Recorded in every row.
.PARAMETER SampleSize
    How many unflagged messages to draw. 200 bounds a zero-miss result at roughly 1.5 percent.
.PARAMETER ExistingManifest
    A manifest whose labels must survive. A row the draw selects again keeps its Id and its
    Label. It does not change WHICH rows are drawn - see the note below.
.PARAMETER ProjectRoot
    Where the session transcripts live. Defaults to ~/.claude/projects. Point it at a copy of
    the transcripts to draw from a population that retention has stopped deleting.
.NOTES
    The draw is a deterministic function of the seed and the message key: hash the pair and take
    the SampleSize lowest hashes. That is a uniform random sample, and it is also stable while
    the transcripts grow, so hand-written labels survive a re-run without the labels deciding
    the sample.

    The script also writes a selection record beside the manifest: the population count, a digest
    of the ordered keys, the drawn positions, and the drawn keys themselves. The positions are
    only meaningful against a list of the same length and digest; the keys identify the rows
    either way.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, ParameterSetName = 'Draw')][ValidateSet('handoffs', 'next-step-asks')][string] $Metric,
    [Parameter(Mandatory, ParameterSetName = 'Draw')][string] $OutputPath,
    [Parameter(ParameterSetName = 'Draw')][int] $Seed = 20260816,
    [Parameter(ParameterSetName = 'Draw')][int] $SampleSize = 200,
    [Parameter(ParameterSetName = 'Draw')][string] $ExistingManifest,
    [Parameter(ParameterSetName = 'Draw')][string] $ProjectRoot,
    # Dot-source the selection rule without reading a transcript, so a suite can test it.
    [Parameter(Mandatory, ParameterSetName = 'Module')][switch] $AsModule
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-HomeRelativePath {
    # A committed selection record must not carry an absolute path that names the local user,
    # such as C:/Users/<name>/... . Rewrite a path that sits under $HOME so it starts with '~',
    # matching the anonymized form the documentation uses. A path outside $HOME is returned
    # unchanged.
    param([string] $Path)

    if ([string]::IsNullOrEmpty($Path)) { return $Path }

    $homeNormalised = ($HOME -replace '\\', '/').TrimEnd('/')
    $pathNormalised = $Path -replace '\\', '/'

    if ($pathNormalised -ieq $homeNormalised) { return '~' }
    if ($pathNormalised.StartsWith($homeNormalised + '/', [System.StringComparison]::OrdinalIgnoreCase)) {
        return '~' + $pathNormalised.Substring($homeNormalised.Length)
    }
    return $Path
}

# The selection is a deterministic function of the seed and the message key: hash the pair and
# take the SampleSize lowest hashes. Two properties come from this, and the published interval
# needs both.
#
# It is a uniform random sample. Every unflagged message has the same chance of selection,
# whenever it was written. That is what an interval over the labels needs; it is not the whole
# story, because the draw takes a fixed number without replacement and a Wilson interval is a
# binomial one. For a draw with equal inclusion probabilities Wilson is then conservative -
# wider than the truth - by a factor of about sqrt((N-n)/(N-1)), which is 0.90 for 200 of 1,004.
# The doc says so rather than hiding it. That conclusion needs the equal probabilities: it
# describes THIS sampler, not the 2026-08-16 draw the published figures came from.
#
# It is stable while the transcripts grow. Keeping the previously drawn rows and topping the
# sample up did preserve labels, but it gave a row that was in the earlier population two
# chances of selection and a later row one - about 1.4 times the inclusion probability - and an
# unequal-probability sample is not what a Wilson interval describes. Here a row selected today
# is still selected tomorrow unless enough lower hashes arrive, so labels survive without the
# preservation deciding anything.
function Get-SelectionPriority {
    param([Parameter(Mandatory)][string] $Key, [Parameter(Mandatory)][int] $Seed)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes("$Seed`n$Key")
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    # The first eight bytes, big-endian, is enough spread for a population of this size.
    $value = [uint64]0
    for ($b = 0; $b -lt 8; $b++) { $value = ($value -shl 8) -bor [uint64]$hash[$b] }
    return $value
}

function Select-SampleKey {
    <#
    .SYNOPSIS
        The keys the draw selects, lowest hash priority first, then key.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $Keys,
        [Parameter(Mandatory)][int] $Seed,
        [Parameter(Mandatory)][int] $SampleSize
    )
    $take = [Math]::Min($SampleSize, $Keys.Count)
    return @($Keys |
            Sort-Object -Property @{ Expression = { Get-SelectionPriority -Key $_ -Seed $Seed } }, @{ Expression = { $_ } } |
            Select-Object -First $take)
}

# The interval the labels support, and the one figure this whole exercise publishes.
#
# Wilson is a binomial interval: it assumes each draw is independent, which is what sampling
# WITH replacement gives. This draw takes a fixed number of rows without replacement, so the
# variance of the sample proportion is smaller - p(1-p)/n times (N-n)/(N-1) rather than
# p(1-p)/n. For an equal-probability draw plain Wilson is therefore too wide: it errs safe, but
# a range wider than the evidence supports is still the wrong range. Where the inclusion
# probabilities are unequal, as in the committed draw, even that much cannot be claimed - the
# bias runs in whichever direction the over-represented rows happen to lean, and nobody measured
# it.
#
# An earlier fix kept the Wilson shape and changed only what it divides by: set the binomial
# variance p(1-p)/n_eff equal to the true one, solve n_eff = n(N-1)/(N-n), and feed that in as
# the sample size. It was withdrawn. Matching the variance is still a normal approximation, and
# it fails where the counts are small - see the note on Get-HypergeometricInterval below.
#
# What -Correct does instead is invert the hypergeometric tails directly, with no approximation
# at any step. Get-HypergeometricInterval holds that code and explains the arithmetic.
#
# What this does NOT fix: whether every row had the same chance of being drawn. That is a
# property of the draw, not of the arithmetic, and only a redraw settles it.
#
# So -Correct carries a precondition, and it is not a small one. The correction assumes a
# SIMPLE RANDOM SAMPLE without replacement: every row in the population had the same inclusion
# probability. Applied to a draw that did not, it returns a NARROWER interval resting on an
# assumption the data breaks - more exact-looking and less true, which is worse than the wide
# interval it replaced.
#
# The committed 2026-08-16 manifests are exactly such a draw. The sampler that produced them
# kept every previously selected row and filled the rest at random, so an older row had about
# 1.4 times the inclusion probability of a newer one; the selection records record it as
# carriedOverLabels, 57 of 200 and 58 of 200. -Correct MUST NOT be applied to those labels.
# Backlog 102 decided the published ranges stay plain Wilson and stay labelled approximate,
# because repairing unequal inclusion probabilities needs a design-based estimator and the
# records that estimator would need no longer exist.
#
# -Correct is here for the redraw that has not happened yet. Nothing in this repository passes
# it today.
function Get-HypergeometricInterval {
    <#
    .SYNOPSIS
        The 95 percent interval for how many misses a finite population holds.
    .DESCRIPTION
        Drawing n rows from N without replacement makes the count of misses hypergeometric, not
        binomial. This returns the set of population counts the observation does not rule out:
        the largest K whose P(X <= Hits) still exceeds 2.5 percent, and the smallest K whose
        P(X >= Hits) still does.

        Both tails are monotone in K, so each bound is found by bisection.

        This is what a normal approximation cannot do at the edges. Substituting an effective
        sample size into Wilson returned an upper bound of ZERO population misses for 0 of 200
        drawn from 220 - a claim of certainty that is wrong 20/220 of the time, because one miss
        among 220 escapes a 200-row draw 20/220 of the time. The exact answer there is 1.

        For 0 of 200 drawn from 1,004 the exact answer is 16: a population of 16 misses hides
        from the draw with probability 0.0278, which the 0.025 tail does not rule out, while 17
        gives 0.0221, which it does. That is the regime backlog 113 will publish from.
    #>
    param(
        [Parameter(Mandatory)][int] $Hits,
        [Parameter(Mandatory)][int] $Drawn,
        [Parameter(Mandatory)][int] $Population
    )

    # Every comparison below is exact integer arithmetic, and that is not a preference.
    #
    # An earlier version summed the terms as doubles rebuilt from log factorials. It was wrong on
    # any tail that lands exactly on the threshold. For 2 hits in a draw of 2 from 16, the tail
    # P(X >= 2 | K = 3) is C(3,2)/C(16,2) = 3/120 = 1/40, which is 0.025 to the last digit. The
    # rule is strict, so 3 is ruled out and the bound is 4. Through logs the same tail returned
    # 0.025000000000000012, cleared the strict comparison by one part in 10^17, and the bound came
    # back as 3. Widening the comparison with a tolerance only moves the tie somewhere else.
    #
    # So the tail is never turned into a probability at all. A count is admitted when
    #
    #     numerator / C(N, n) > 1/40      which is      40 * numerator > C(N, n)
    #
    # and both sides are BigIntegers. C(5472, 200) is about 960 bits, which BigInteger holds
    # exactly and a double cannot hold at all.
    function Get-Choose {
        param([int] $Of, [int] $Take)
        if ($Take -lt 0 -or $Of -lt 0 -or $Take -gt $Of) { return [System.Numerics.BigInteger]::Zero }
        if ($Take -gt ($Of - $Take)) { $Take = $Of - $Take }
        $result = [System.Numerics.BigInteger]::One
        for ($i = 1; $i -le $Take; $i++) {
            $result = $result * [System.Numerics.BigInteger]($Of - $Take + $i) / [System.Numerics.BigInteger]$i
        }
        return $result
    }

    $denominator = Get-Choose -Of $Population -Take $Drawn

    function Get-AtMostNumerator {
        # The count of draws yielding at most Upto misses, when the population holds Successes.
        # Divided by $denominator this is P(X <= Upto); it is left undivided so it stays exact.
        param([int] $Upto, [int] $Successes)
        $total = [System.Numerics.BigInteger]::Zero
        if ($Upto -lt 0) { return $total }
        for ($i = 0; $i -le $Upto; $i++) {
            $total += (Get-Choose -Of $Successes -Take $i) *
                      (Get-Choose -Of ($Population - $Successes) -Take ($Drawn - $i))
        }
        return $total
    }

    $forty = [System.Numerics.BigInteger]40

    # Upper bound: P(X <= Hits | K) falls as K rises, so bisect for the last K above the tail.
    $lowSearch = $Hits
    $highSearch = $Population
    while ($lowSearch -lt $highSearch) {
        $middle = [int][Math]::Ceiling(($lowSearch + $highSearch) / 2.0)
        $numerator = Get-AtMostNumerator -Upto $Hits -Successes $middle
        if (($forty * $numerator) -gt $denominator) { $lowSearch = $middle }
        else { $highSearch = $middle - 1 }
    }
    $upperCount = $lowSearch

    # Lower bound: P(X >= Hits | K) rises with K, so bisect for the first K above the tail.
    #
    # The search starts at Hits and runs to the population, not from zero to Hits. A population
    # holding fewer than Hits misses cannot yield Hits of them, and the bound usually sits far
    # ABOVE Hits: observing 11 misses in 200 of 5,457 rows puts the population count near 300,
    # so a search capped at 11 returned 11 and published a lower bound fifteen times too small.
    $lowSearch = $Hits
    $highSearch = $Population
    while ($lowSearch -lt $highSearch) {
        $middle = [int][Math]::Floor(($lowSearch + $highSearch) / 2.0)
        # P(X >= Hits) = 1 - P(X <= Hits - 1), kept as a count so nothing rounds.
        $atOrAbove = $denominator - (Get-AtMostNumerator -Upto ($Hits - 1) -Successes $middle)
        if (($forty * $atOrAbove) -gt $denominator) { $highSearch = $middle }
        else { $lowSearch = $middle + 1 }
    }
    $lowerCount = $lowSearch

    return [pscustomobject]@{ LowCount = $lowerCount; HighCount = $upperCount }
}

function Get-RecallInterval {
    <#
    .SYNOPSIS
        The 95 percent interval for a miss rate, and the count it implies over the population.
    .PARAMETER Hits
        Labelled misses in the sample.
    .PARAMETER Drawn
        Rows drawn. The denominator of the observed rate.
    .PARAMETER Population
        The unflagged population the sample was drawn from.
    .PARAMETER Correct
        Apply the finite-population correction described above. Valid ONLY when every row in
        the population had the same chance of being drawn. Never pass it for the committed
        2026-08-16 manifests, whose draw was not uniform - see the note above the function.
        Without it the result is plain Wilson, which is what every published figure uses.
    .NOTES
        PowerShell variable names are case-insensitive, so $n and $N name one variable. The
        parameters are spelled out for that reason; a draft written with $n and $N divided by
        zero and reported an interval of nothing.
    #>
    param(
        [Parameter(Mandatory)][ValidateRange(0, [int]::MaxValue)][int] $Hits,
        [Parameter(Mandatory)][ValidateRange(1, [int]::MaxValue)][int] $Drawn,
        [Parameter(Mandatory)][ValidateRange(1, [int]::MaxValue)][int] $Population,
        [switch] $Correct
    )

    if ($Hits -gt $Drawn) { throw "Hits ($Hits) cannot exceed Drawn ($Drawn)." }
    if ($Drawn -gt $Population) { throw "Drawn ($Drawn) cannot exceed Population ($Population)." }

    # 1.959963985 is the two-sided 95 percent normal quantile. Written out rather than computed,
    # because .NET has no inverse normal and an approximation here would move a published range.
    $z = 1.959963985
    $rate = $Hits / [double]$Drawn

    if ($Correct) {
        $exact = Get-HypergeometricInterval -Hits $Hits -Drawn $Drawn -Population $Population
        return [pscustomobject]@{
            Rate      = $rate
            Low       = $exact.LowCount / [double]$Population
            High      = $exact.HighCount / [double]$Population
            LowCount  = $exact.LowCount
            HighCount = $exact.HighCount
            Method    = 'hypergeometric'
            Corrected = $true
        }
    }

    $centre = ($rate + $z * $z / (2.0 * $Drawn)) / (1.0 + $z * $z / $Drawn)
    $half = $z / (1.0 + $z * $z / $Drawn) *
        [Math]::Sqrt($rate * (1.0 - $rate) / $Drawn + $z * $z / (4.0 * $Drawn * $Drawn))

    $low = [Math]::Max(0.0, $centre - $half)
    $high = [Math]::Min(1.0, $centre + $half)

    return [pscustomobject]@{
        Rate      = $rate
        Low       = $low
        High      = $high
        LowCount  = [int][Math]::Round($low * $Population)
        HighCount = [int][Math]::Round($high * $Population)
        Method    = 'wilson'
        Corrected = $false
    }
}

if ($AsModule) { return }

# measure-process-friction.ps1 declares its own $ProjectRoot parameter, and a dot-source runs in
# this scope, so the line below blanks ours. Keep the value under another name first. Written the
# obvious way, the run fails with "Cannot bind argument to parameter 'ProjectRoot' because it is
# an empty string."
$transcriptRoot = $ProjectRoot

. (Join-Path $PSScriptRoot 'measure-process-friction.ps1') -AsModule

if (-not $transcriptRoot) { $transcriptRoot = Join-Path $HOME '.claude/projects' }
$files = @(Get-TranscriptFile -ProjectRoot $transcriptRoot)
$all = New-Object System.Collections.Generic.List[object]
foreach ($file in $files) {
    foreach ($record in (Read-TranscriptRecord -Path $file)) { $all.Add($record) }
}

$selected = @(Select-FrictionRecord -Records $all.ToArray() -Start $script:WindowStart -End $script:WindowEnd)
$messages = @(ConvertTo-LogicalMessage -Records $selected)
$patterns = $script:MatchSets[$Metric]

# The same side of the conversation the metric reads, so the unflagged remainder is exactly
# what the metric could have missed.
$population = @($messages | Where-Object {
        if ($Metric -eq 'next-step-asks') { $_.IsHumanTurn } else { $_.Type -eq 'assistant' }
    } | Where-Object { $_.Text })

$flagged = New-Object System.Collections.Generic.List[object]
$unflagged = New-Object System.Collections.Generic.List[object]

foreach ($message in $population) {
    $hit = $false
    foreach ($pattern in $patterns) {
        if ($message.Text -match [regex]::Escape($pattern)) { $hit = $true; break }
    }
    if ($hit) { $flagged.Add($message) } else { $unflagged.Add($message) }
}

# Sort before sampling. Enumeration order over hundreds of files is not guaranteed stable, and
# a seed only reproduces a sample when the list it indexes into is in a fixed order.
$ordered = @($unflagged | Sort-Object -Property Key)

# The digest of the ordered keys. It is what tells a later reader whether the recorded positions
# still point at the same messages, which a seed on its own cannot say.
$keyText = ($ordered | ForEach-Object { $_.Key }) -join "`n"
$sha = [System.Security.Cryptography.SHA256]::Create()
try {
    $populationDigest = [System.BitConverter]::ToString(
        $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($keyText))).Replace('-', '').ToLowerInvariant()
}
finally { $sha.Dispose() }

# Labels already written are evidence. A row keeps its label and its id when the draw selects
# it again, but a written label must never decide the selection.
$existingLabels = @{}
$existingIds = @{}
if ($ExistingManifest) {
    if (-not (Test-Path -LiteralPath $ExistingManifest)) {
        throw "ExistingManifest not found: $ExistingManifest"
    }
    foreach ($row in (Import-Csv -LiteralPath $ExistingManifest)) {
        $existingLabels[$row.Key] = $row.Label
        $existingIds[$row.Key] = $row.Id
    }
}

$take = [Math]::Min($SampleSize, $ordered.Count)
$selectedKeySet = [System.Collections.Generic.HashSet[string]]::new(
    [string[]](Select-SampleKey -Keys ([string[]]($ordered | ForEach-Object { $_.Key })) -Seed $Seed -SampleSize $SampleSize),
    [System.StringComparer]::Ordinal)
$byPriority = @($ordered | Where-Object { $selectedKeySet.Contains($_.Key) })

$byKeyPosition = @{}
for ($i = 0; $i -lt $ordered.Count; $i++) { $byKeyPosition[$ordered[$i].Key] = $i }

$picked = [System.Collections.Generic.SortedSet[int]]::new()
foreach ($message in $byPriority) { [void]$picked.Add($byKeyPosition[$message.Key]) }

$carriedOver = 0
foreach ($message in $byPriority) {
    if ($existingLabels.ContainsKey($message.Key) -and $existingLabels[$message.Key]) { $carriedOver++ }
}

# A wide screen, run over the WHOLE text of every sampled message. It is deliberately far
# wider than the metric's own match set: its job is to find every message that could possibly
# be a case, so the ones it does not select carry evidence rather than an opinion. A label of
# 'not a case' on an unscreened row means no word associated with the concept appears anywhere
# in the message, which a reviewer can check against the Text column.
$screens = @{
    'handoffs'       = @(
        'yourself', 'manually', 'by hand', 'cannot', "can't", 'unable', 'blocked', 'refuse',
        'guard', 'permission', 'terminal', 'copy', 'paste', 'over to you', 'you run',
        'please run', 'need you', 'needs you', 'handover', 'hand over', 'login', 'auth'
    )
    'next-step-asks' = @(
        'next', 'suggest', 'proceed', 'what should', 'what do', 'which one', 'priority',
        'order', 'pick up', 'shall we', 'do we', 'should i', 'should we', 'options'
    )
}
$screen = $screens[$Metric]

function Get-ScreenHit {
    param([string] $Text)
    $hits = foreach ($word in $screen) {
        if ($Text -match [regex]::Escape($word)) { $word }
    }
    return (@($hits) -join '; ')
}

# A carried-over row keeps its Id, so a new row cannot simply be numbered by position: the
# earlier manifest already used those numbers, and two rows sharing an Id break every reference
# to a label. New rows are numbered above the highest one already in use.
function Get-NextId {
    param([Parameter(Mandatory)][string] $Prefix)
    $script:idCounters[$Prefix]++
    while ($script:usedIds.Contains("$Prefix$($script:idCounters[$Prefix])")) { $script:idCounters[$Prefix]++ }
    $id = "$Prefix$($script:idCounters[$Prefix])"
    [void]$script:usedIds.Add($id)
    return $id
}

$script:usedIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$script:idCounters = @{ 'F' = 0; 'U' = 0 }
foreach ($id in $existingIds.Values) { [void]$script:usedIds.Add($id) }

$rows = New-Object System.Collections.Generic.List[object]
foreach ($message in $flagged) {
    $rows.Add([pscustomobject]@{
            Id        = if ($existingIds.ContainsKey($message.Key)) { $existingIds[$message.Key] } else { (Get-NextId -Prefix 'F') }
            Metric    = $Metric
            Seed      = $Seed
            Stratum   = 'flagged'
            Key       = $message.Key
            Session   = $message.Session
            Timestamp = $message.Timestamp
            Fragments = $message.Fragments
            Screen    = (Get-ScreenHit -Text $message.Text)
            Label     = if ($existingLabels.ContainsKey($message.Key)) { $existingLabels[$message.Key] } else { '' }
            Text      = $message.Text
        })
}
$selectedPositions = @($picked)
$selectedKeys = New-Object System.Collections.Generic.List[string]
foreach ($position in $selectedPositions) {
    $message = $ordered[$position]
    $selectedKeys.Add($message.Key)
    $rows.Add([pscustomobject]@{
            Id        = if ($existingIds.ContainsKey($message.Key)) { $existingIds[$message.Key] } else { (Get-NextId -Prefix 'U') }
            Metric    = $Metric
            Seed      = $Seed
            Stratum   = 'unflagged'
            Key       = $message.Key
            Session   = $message.Session
            Timestamp = $message.Timestamp
            Fragments = $message.Fragments
            Screen    = (Get-ScreenHit -Text $message.Text)
            Label     = if ($existingLabels.ContainsKey($message.Key)) { $existingLabels[$message.Key] } else { '' }
            Text      = $message.Text
        })
}

$rows | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding utf8

# The selection record. A seed indexes into a list that changes while the script runs, so the
# list itself has to be described: how long it was, what it hashed to, and which positions and
# keys came out. With it a reader can say whether a redraw is the same draw.
$selectionPath = [System.IO.Path]::ChangeExtension($OutputPath, '.selection.json')
[pscustomobject]@{
    metric            = $Metric
    seed              = $Seed
    sampleSize        = $SampleSize
    windowStart       = $script:WindowStart.ToString('o')
    windowEnd         = $script:WindowEnd.ToString('o')
    transcriptFiles   = $files.Count
    transcriptRoot    = ConvertTo-HomeRelativePath $transcriptRoot
    recordsInWindow   = $selected.Count
    populationCount   = $population.Count
    flaggedCount      = $flagged.Count
    unflaggedCount    = $ordered.Count
    populationDigest  = $populationDigest
    selectionRule     = 'lowest-hash-priority: sha256("<seed>\n<key>"), first 8 bytes, ascending'
    carriedOverLabels = $carriedOver
    selectedPositions = $selectedPositions
    selectedKeys      = $selectedKeys.ToArray()
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $selectionPath -Encoding utf8

Write-Host "metric      : $Metric"
Write-Host "seed        : $Seed"
Write-Host "population  : $($population.Count) logical messages"
Write-Host "flagged     : $($flagged.Count)"
Write-Host "unflagged   : $($ordered.Count), of which $take sampled ($carriedOver already carry a label)"
Write-Host "digest      : $populationDigest"
Write-Host "manifest    : $OutputPath"
Write-Host "selection   : $selectionPath"
Write-Host ''
Write-Host 'Every row carries its full text. Fill in each empty Label, then commit the manifest'
Write-Host 'and the selection record together: the labels are the evidence for the published range.'
