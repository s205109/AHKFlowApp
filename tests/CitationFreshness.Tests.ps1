#Requires -Version 7.0
# citation-check:ignore-file
#
# The fixture strings below are canonical citations to paths this repository does not track, so
# the check must not read this file. The directive above is the supported way to say that, and it
# only counts because it stands alone inside the first five non-blank lines.
#
# A citation like docs/development/workflow.md:482 is a fragile address. An edit above line 482
# moves the target, the citation still looks right, and nothing notices. This suite proves the
# check that catches it. See backlog 097.
#
# Run it by hand with:  pwsh ./tests/CitationFreshness.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts/citation-freshness.common.ps1')

$failures = @()

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) {
        $script:failures += $Message
    }
}

# --- The parser: what counts as a citation ---

$accepted = @(
    @{ Line = 'See .github/workflows/ci.yml:105 here'; Path = '.github/workflows/ci.yml'; Start = 105 },
    @{ Line = 'See .githooks/pre-push:10 here';        Path = '.githooks/pre-push';        Start = 10 },
    @{ Line = 'See .editorconfig:5 here';              Path = '.editorconfig';             Start = 5 },
    @{ Line = 'See docs/development/workflow.md:482 here'; Path = 'docs/development/workflow.md'; Start = 482 },
    @{ Line = 'See Program.cs:40 here';                Path = 'Program.cs';                Start = 40 },
    @{ Line = 'See scripts/test-fast.ps1:182 here';    Path = 'scripts/test-fast.ps1';     Start = 182 }
)
foreach ($case in $accepted) {
    $found = @(Get-CitationOnLine -Line $case.Line)
    Assert-True ($found.Count -eq 1) "One citation expected in '$($case.Line)', found $($found.Count)"
    if ($found.Count -eq 1) {
        Assert-True ($found[0].Path -eq $case.Path) "Path must be $($case.Path), was $($found[0].Path)"
        Assert-True ($found[0].Start -eq $case.Start) "Start must be $($case.Start), was $($found[0].Start)"
    }
}

$rejected = @(
    'The contrast ratio is 4.5:1 which passes.',
    'A ratio of 21:1 is the maximum.',
    'Stand-up is at 12:30 tomorrow.',
    'Bound to //127.0.0.1:0 locally.'
)
foreach ($line in $rejected) {
    $found = @(Get-CitationOnLine -Line $line)
    Assert-True ($found.Count -eq 0) "'$line' is not a citation, found $($found.Count)"
}

# --- The parser: classification ---

$canonical = @(Get-CitationOnLine -Line 'See (`docs/x.md:12`, "hello world") for detail.')
Assert-True ($canonical.Count -eq 1) "One canonical citation expected, found $($canonical.Count)"
Assert-True ($canonical[0].Kind -eq 'Canonical') "Kind must be Canonical, was $($canonical[0].Kind)"
Assert-True ($canonical[0].End -eq 12) "End must equal Start for a single line, was $($canonical[0].End)"
Assert-True ($canonical[0].Phrase -eq 'hello world') "Phrase must be 'hello world', was $($canonical[0].Phrase)"

$range = @(Get-CitationOnLine -Line '(`docs/x.md:12-15`, "spans lines")')
Assert-True ($range.Count -eq 1) "One range citation expected, found $($range.Count)"
Assert-True ($range[0].Start -eq 12 -and $range[0].End -eq 15) "Range must be 12-15, was $($range[0].Start)-$($range[0].End)"

$legacy = @(Get-CitationOnLine -Line 'Proved at `docs/x.md:12` today.')
Assert-True ($legacy.Count -eq 1) "One legacy citation expected, found $($legacy.Count)"
Assert-True ($legacy[0].Kind -eq 'Legacy') "Kind must be Legacy, was $($legacy[0].Kind)"
Assert-True ($null -eq $legacy[0].Phrase) 'A legacy citation carries no phrase'

$nearMiss = @(Get-CitationOnLine -Line 'See `docs/x.md:12` "hello world" there.')
Assert-True ($nearMiss.Count -eq 1) "One near-miss expected, found $($nearMiss.Count)"
Assert-True ($nearMiss[0].Kind -eq 'NearMiss') "Kind must be NearMiss, was $($nearMiss[0].Kind)"

$bare = @(Get-CitationOnLine -Line 'Log said Program.cs:40 and then stopped.')
Assert-True ($bare[0].Kind -eq 'Legacy') "An unbackticked citation is Legacy, was $($bare[0].Kind)"

$backslash = @(Get-CitationOnLine -Line 'See `docs\development\workflow.md:5` here.')
Assert-True ($backslash.Count -eq 1 -and $backslash[0].Path -eq 'docs/development/workflow.md') `
    "A backslash path is normalized, was $($backslash[0].Path)"

# --- Whitespace normalization ---

Assert-True ((ConvertTo-CollapsedText -Text "  a   b `n c  ") -eq 'a b c') 'Whitespace collapses to single spaces'

# --- The ignore-file directive ---

Assert-True (Test-CitationIgnoreFile -Lines @('# citation-check:ignore-file', 'text')) `
    'A standalone directive behind a hash marker is honoured'
Assert-True (Test-CitationIgnoreFile -Lines @('', '', '<!-- citation-check:ignore-file -->', 'text')) `
    'Blank lines do not count towards the five-line window'
Assert-True (-not (Test-CitationIgnoreFile -Lines @('a', 'b', 'c', 'd', 'e', 'citation-check:ignore-file'))) `
    'A directive after five non-blank lines is ignored'
Assert-True (-not (Test-CitationIgnoreFile -Lines @('This file explains citation-check:ignore-file in prose.'))) `
    'A mention inside a sentence does not suppress the file'

# --- Fixture repositories ---

function New-FixtureRepository {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) "citation-tests-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    & git -C $root init --quiet
    & git -C $root config user.email 'fixture@example.com'
    & git -C $root config user.name 'Fixture'
    return $root
}

# Set-Content adds its own line terminator, so joining with a newline is enough. Adding one more
# leaves a trailing blank line, and then a fixture that claims to have six lines has seven.
function Add-FixtureFile {
    param(
        [Parameter(Mandatory)][string] $Root,
        [Parameter(Mandatory)][string] $RelativePath,
        [Parameter(Mandatory)][AllowEmptyString()][AllowEmptyCollection()][string[]] $Lines
    )

    $full = Join-Path $Root $RelativePath
    $parent = Split-Path -Parent $full
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Set-Content -LiteralPath $full -Value ($Lines -join "`n")
    & git -C $Root add -- $RelativePath
}

function Complete-FixtureCommit {
    param([Parameter(Mandatory)][string] $Root, [string] $Message = 'fixture')
    & git -C $Root commit --quiet -m $Message
}

# The target every case cites. Line 3 holds the phrase, lines 4 and 5 hold the wrapped one, and
# line 6 is the last line.
$targetLines = @(
    'line one',
    'line two',
    'the expected text lives here',
    'a phrase that wraps',
    'across two lines',
    'last line'
)

# --- Tier 1: range ---

$fixture = New-FixtureRepository
try {
    Add-FixtureFile -Root $fixture -RelativePath 'target.txt' -Lines $targetLines
    Add-FixtureFile -Root $fixture -RelativePath 'doc.md' -Lines @(
        'past the end `target.txt:99` here',
        'exactly the last line `target.txt:6` here',
        'a zero start `target.txt:0` here',
        'a reversed range `target.txt:5-2` here',
        'inside the file `target.txt:2` here'
    )
    Complete-FixtureCommit -Root $fixture

    # The fixture must really have six lines, or 'exactly the last line' proves nothing.
    $written = @(Get-Content -LiteralPath (Join-Path $fixture 'target.txt'))
    Assert-True ($written.Count -eq 6) "The fixture target must hold 6 lines, held $($written.Count)"

    $problems = @(Get-CitationProblem -ScanRoot $fixture -ResolveRoot $fixture)
    $tier1 = @($problems | Where-Object { $_ -like '*tier 1*' })

    Assert-True (@($tier1 | Where-Object { $_ -like 'doc.md:1 *' }).Count -eq 1) `
        'A cited line past the end of the target fails tier 1'
    Assert-True (@($tier1 | Where-Object { $_ -like 'doc.md:2 *' }).Count -eq 0) `
        'A cited line equal to the last line passes tier 1'
    Assert-True (@($tier1 | Where-Object { $_ -like 'doc.md:3 *' }).Count -eq 1) `
        'A start line of 0 fails tier 1'
    Assert-True (@($tier1 | Where-Object { $_ -like 'doc.md:4 *' }).Count -eq 1) `
        'A range whose end is below its start fails tier 1'
    Assert-True (@($tier1 | Where-Object { $_ -like 'doc.md:5 *' }).Count -eq 0) `
        'A cited line inside the file passes tier 1'
}
finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force
}

# --- Tier 2: expectation ---

$fixture = New-FixtureRepository
try {
    Add-FixtureFile -Root $fixture -RelativePath 'target.txt' -Lines $targetLines
    Add-FixtureFile -Root $fixture -RelativePath 'doc.md' -Lines @(
        'right (`target.txt:3`, "the expected text") here',
        'wrong (`target.txt:2`, "the expected text") here',
        'wrapped (`target.txt:4-5`, "that wraps across two") here',
        'case (`target.txt:3`, "The Expected Text") here',
        'missing path (`nope.txt:1`, "anything") here',
        'legacy missing path `nope.txt:1` here',
        'empty (`target.txt:3`, "") here',
        'blank (`target.txt:3`, "   ") here'
    )
    Complete-FixtureCommit -Root $fixture

    $problems = @(Get-CitationProblem -ScanRoot $fixture -ResolveRoot $fixture)
    $tier2 = @($problems | Where-Object { $_ -like '*tier 2*' })

    Assert-True (@($tier2 | Where-Object { $_ -like 'doc.md:1 *' }).Count -eq 0) `
        'A canonical citation whose phrase is on the cited line passes'
    Assert-True (@($tier2 | Where-Object { $_ -like 'doc.md:2 *' }).Count -eq 1) `
        'A canonical citation whose phrase is absent fails'
    Assert-True (@($tier2 | Where-Object { $_ -like 'doc.md:3 *' }).Count -eq 0) `
        'A phrase that wraps across a cited range passes, which proves whitespace normalization'
    Assert-True (@($tier2 | Where-Object { $_ -like 'doc.md:4 *' }).Count -eq 1) `
        'A phrase that differs only in case fails'
    Assert-True (@($tier2 | Where-Object { $_ -like 'doc.md:5 *' }).Count -eq 1) `
        'A canonical citation whose path is not tracked fails'
    Assert-True (@($problems | Where-Object { $_ -like 'doc.md:6 *' }).Count -eq 0) `
        'A legacy citation whose path is not tracked is ignored'
    Assert-True (@($tier2 | Where-Object { $_ -like 'doc.md:7 *' }).Count -eq 1) `
        'An empty expectation fails, because every line contains the empty string'
    Assert-True (@($tier2 | Where-Object { $_ -like 'doc.md:8 *' }).Count -eq 1) `
        'A whitespace-only expectation fails for the same reason'
}
finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force
}

# --- Scope and suppression ---

$fixture = New-FixtureRepository
try {
    Add-FixtureFile -Root $fixture -RelativePath 'target.txt' -Lines $targetLines
    Add-FixtureFile -Root $fixture -RelativePath 'doc.md' -Lines @(
        'suppressed (`target.txt:2`, "the expected text") citation-check:ignore',
        'not suppressed (`target.txt:2`, "the expected text") here'
    )
    Add-FixtureFile -Root $fixture -RelativePath 'skipped.md' -Lines @(
        '<!-- citation-check:ignore-file -->',
        'broken (`target.txt:99`, "the expected text") here'
    )
    Add-FixtureFile -Root $fixture -RelativePath 'explains.md' -Lines @(
        'one', 'two', 'three', 'four', 'five',
        'This paragraph mentions citation-check:ignore-file in prose.',
        'broken (`target.txt:99`, "the expected text") here'
    )
    # A data file's cells are quoted records, not claims somebody wrote. The friction sample
    # manifests hold transcript text verbatim, and 76 of those quotes read as broken citations
    # that nobody is asserting. A CSV cannot carry the ignore-file marker either: its first line
    # has to be the header.
    Add-FixtureFile -Root $fixture -RelativePath 'evidence.csv' -Lines @(
        'Id,Text',
        'U1,"a transcript quoted (`target.txt:99`, ""the expected text"") inside a cell"'
    )
    Complete-FixtureCommit -Root $fixture

    # An untracked file must never be scanned and never be accepted as a target.
    $untrackedLine = 'broken (`target.txt:99`, "the expected text") here'
    Set-Content -LiteralPath (Join-Path $fixture 'untracked.md') -Value $untrackedLine

    $problems = @(Get-CitationProblem -ScanRoot $fixture -ResolveRoot $fixture)

    Assert-True (@($problems | Where-Object { $_ -like 'doc.md:1 *' }).Count -eq 0) `
        'A line carrying citation-check:ignore is skipped'
    Assert-True (@($problems | Where-Object { $_ -like 'doc.md:2 *' }).Count -eq 1) `
        'The next line is still checked'
    Assert-True (@($problems | Where-Object { $_ -like 'skipped.md*' }).Count -eq 0) `
        'A standalone ignore-file directive skips the whole file'
    Assert-True (@($problems | Where-Object { $_ -like 'explains.md*' }).Count -eq 1) `
        'A file that only mentions the token in prose is still checked'
    Assert-True (@($problems | Where-Object { $_ -like 'untracked.md*' }).Count -eq 0) `
        'An untracked file is not scanned'
    Assert-True (@($problems | Where-Object { $_ -like 'evidence.csv*' }).Count -eq 0) `
        'A data file holds quoted records, not claims, so it is not scanned'
}
finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force
}

# --- Tier 3: adoption ---

$fixture = New-FixtureRepository
try {
    Add-FixtureFile -Root $fixture -RelativePath 'target.txt' -Lines $targetLines
    Add-FixtureFile -Root $fixture -RelativePath 'old.md' -Lines @(
        'grandfathered `target.txt:2` here',
        'also grandfathered `target.txt:3` here'
    )
    Complete-FixtureCommit -Root $fixture -Message 'base'
    $base = (& git -C $fixture rev-parse HEAD).Trim()

    # One new file, and one edit to a line that already carried a legacy citation.
    Add-FixtureFile -Root $fixture -RelativePath 'new.md' -Lines @(
        'added legacy `target.txt:2` here',
        'added near-miss `target.txt:2` "the expected text" here',
        'added canonical (`target.txt:3`, "the expected text") here',
        'added legacy with an unknown path `nope.txt:2` here'
    )
    Add-FixtureFile -Root $fixture -RelativePath 'old.md' -Lines @(
        'grandfathered `target.txt:2` here',
        'edited, still legacy `target.txt:3` here'
    )
    Complete-FixtureCommit -Root $fixture -Message 'work'

    $changed = Get-ChangedLine -Root $fixture -BaseRef $base
    $problems = @(Get-CitationProblem -ScanRoot $fixture -ResolveRoot $fixture -ChangedLine $changed)
    $tier3 = @($problems | Where-Object { $_ -like '*tier 3*' })

    Assert-True (@($tier3 | Where-Object { $_ -like 'new.md:1 *' }).Count -eq 1) `
        'An added line carrying a legacy citation fails tier 3'
    Assert-True (@($tier3 | Where-Object { $_ -like 'new.md:2 *' }).Count -eq 1) `
        'An added line carrying a near-miss fails tier 3'
    Assert-True (@($tier3 | Where-Object { $_ -like 'new.md:3 *' }).Count -eq 0) `
        'An added line carrying a canonical citation passes tier 3'
    Assert-True (@($tier3 | Where-Object { $_ -like 'new.md:4 *' }).Count -eq 0) `
        'An added line citing an untracked path is not forced into the canonical form'
    Assert-True (@($tier3 | Where-Object { $_ -like 'old.md:1 *' }).Count -eq 0) `
        'An unchanged legacy citation stays grandfathered'
    Assert-True (@($tier3 | Where-Object { $_ -like 'old.md:2 *' }).Count -eq 1) `
        'Editing a line converts its grandfathered citation'

    $stateOnly = @(Get-CitationProblem -ScanRoot $fixture -ResolveRoot $fixture)
    Assert-True (@($stateOnly | Where-Object { $_ -like '*tier 3*' }).Count -eq 0) `
        'Without a changed-line set the check reports no tier 3 problem'
}
finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force
}

# --- Tier 3: content that looks like a diff header ---

# git prints an added line '++ b/evil.md' as '+++ b/evil.md' in the diff body. Reading that as a
# file header sends every later hunk to the wrong file.
$fixture = New-FixtureRepository
try {
    Add-FixtureFile -Root $fixture -RelativePath 'target.txt' -Lines $targetLines
    Add-FixtureFile -Root $fixture -RelativePath 'a.md' -Lines @('base line')
    Add-FixtureFile -Root $fixture -RelativePath 'z.md' -Lines @('base line')
    Complete-FixtureCommit -Root $fixture -Message 'base'
    $base = (& git -C $fixture rev-parse HEAD).Trim()

    Add-FixtureFile -Root $fixture -RelativePath 'a.md' -Lines @(
        'base line',
        '++ b/evil.md',
        'legacy `target.txt:2` here'
    )
    Add-FixtureFile -Root $fixture -RelativePath 'z.md' -Lines @(
        'base line',
        'legacy `target.txt:3` here'
    )
    Complete-FixtureCommit -Root $fixture -Message 'work'

    $changed = Get-ChangedLine -Root $fixture -BaseRef $base
    Assert-True ($changed.Contains('a.md:3')) 'The line after the fake header still belongs to a.md'
    Assert-True ($changed.Contains('z.md:2')) 'The next file is not mistaken for evil.md'
    Assert-True (-not ($changed | Where-Object { $_ -like 'evil.md*' })) `
        'No changed line is attributed to the fake header path'
}
finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force
}

# --- This repository ---

# One scan of this repository (~1450 tracked files) covers both assertions below. Tier 3 needs a
# base ref, and this suite must pass on any checkout, including a shallow CI clone with no merge
# base, so ChangedLine is $null there — Get-CitationProblem then reports no tier 3 problem at all.
#
# The measured baseline for this repository counted citations with a looser pattern that missed
# hidden and extensionless paths. The engine finds more than the baseline did, so treat a new
# failure here as a real one, not as drift in the count.
$mergeBase = & git -C $repoRoot merge-base HEAD origin/main 2>$null
$changedHere = if ($LASTEXITCODE -eq 0 -and $mergeBase) {
    Get-ChangedLine -Root $repoRoot -BaseRef ([string] $mergeBase).Trim()
} else {
    $null
}

# A moved citation only warns here, the way the check itself warns (backlog 188). CI shows each
# one and stays green; `pwsh ./scripts/check-citation-freshness.ps1 -Fix` rewrites them.
$liveMoved = [System.Collections.Generic.List[object]]::new()
$live = @(Get-CitationProblem -ScanRoot $repoRoot -ResolveRoot $repoRoot -ChangedLine $changedHere -Moved $liveMoved)
foreach ($one in $liveMoved) {
    Write-Host "WARNING $($one.Where): $($one.Path):$($one.OldStart) moved to line $($one.NewStart)." -ForegroundColor Yellow
}
$tier12 = @($live | Where-Object { $_ -notlike '*tier 3*' })
Assert-True ($tier12.Count -eq 0) `
    "This repository must hold no stale citation, found $($tier12.Count): $($tier12 -join ' | ')"

# Tier 3 over this repository, when a merge base exists. A shallow clone reports the skip and
# passes, which is the documented behaviour, not a hole.
if ($changedHere) {
    $tier3Here = @($live | Where-Object { $_ -like '*tier 3*' })
    Assert-True ($tier3Here.Count -eq 0) `
        "Every citation this branch adds or edits must be canonical: $($tier3Here -join ' | ')"
} else {
    Write-Host 'Tier 3 skipped: no merge base with origin/main.'
}

# --- The runner ---

$runner = Join-Path $repoRoot 'scripts/check-citation-freshness.ps1'
Assert-True (Test-Path -LiteralPath $runner) 'scripts/check-citation-freshness.ps1 must exist'

# The runner calls 'exit', so it has to run as a child process. Calling it with '&' would end
# this test process and silently drop every assertion below - see scripts/run-powershell-suites.ps1
# lines 8 to 14, and the same pattern at tests/CiPowerShellSuiteRunner.Tests.ps1 lines 113 to 144.
function Invoke-Runner {
    param([Parameter(Mandatory)][string[]] $Arguments)

    $hostExe = (Get-Process -Id $PID).Path
    $output = & $hostExe -NoProfile -File $runner @Arguments 2>&1 | Out-String
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

$fixture = New-FixtureRepository
try {
    Add-FixtureFile -Root $fixture -RelativePath 'target.txt' -Lines $targetLines
    # The phrase is on no line of the target. A phrase found on one other line is a moved
    # citation, which only warns (backlog 188).
    Add-FixtureFile -Root $fixture -RelativePath 'doc.md' -Lines @('broken (`target.txt:99`, "text found on no line") here')
    Complete-FixtureCommit -Root $fixture

    $run = Invoke-Runner -Arguments @('-ScanRoot', $fixture, '-ResolveRoot', $fixture, '-NoAdoptionTier')
    Assert-True ($run.ExitCode -eq 1) "The runner must exit 1 on a broken citation, exited $($run.ExitCode)"

    Add-FixtureFile -Root $fixture -RelativePath 'doc.md' -Lines @('fixed (`target.txt:3`, "the expected text") here')
    Complete-FixtureCommit -Root $fixture -Message 'fix'

    $run = Invoke-Runner -Arguments @('-ScanRoot', $fixture, '-ResolveRoot', $fixture, '-NoAdoptionTier')
    Assert-True ($run.ExitCode -eq 0) "The runner must exit 0 on a clean repository, exited $($run.ExitCode)"

    # The fixture has no origin/main, so tier 3 has no merge base. The runner must say so and
    # still exit 0, rather than pass tier 3 by assuming an empty diff.
    $run = Invoke-Runner -Arguments @('-ScanRoot', $fixture, '-ResolveRoot', $fixture)
    Assert-True ($run.ExitCode -eq 0) "The runner must exit 0 when tier 3 has no base ref, exited $($run.ExitCode)"
    Assert-True ($run.Output -match 'Tier 3 skipped') "The runner must report the tier 3 skip, printed: $($run.Output)"
}
finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force
}

# --- Citation drift: a moved text warns (backlog 188) ---
#
# The typical CitationFreshness failure in CI was a line inserted above a cited line: the text is
# still in the file, one line lower. That is a warning now, with a command that fixes it. A text
# that is gone, or that now sits on two lines, is still a problem, because no tool can tell which
# line the author meant.

$fixture = New-FixtureRepository
try {
    Add-FixtureFile -Root $fixture -RelativePath 'target.txt' -Lines $targetLines
    Add-FixtureFile -Root $fixture -RelativePath 'twice.txt' -Lines @('same words', 'other words', 'same words')
    Add-FixtureFile -Root $fixture -RelativePath 'doc.md' -Lines @(
        'moved (`target.txt:2`, "the expected text") here',
        'past the end (`target.txt:40`, "across two lines") here',
        'nowhere (`target.txt:2`, "text found on no line") here',
        'range (`target.txt:1-2`, "the expected text") here',
        'twice (`twice.txt:2`, "same words") here'
    )
    Complete-FixtureCommit -Root $fixture

    $moved = [System.Collections.Generic.List[object]]::new()
    # A failed call must fail the claims below by name, not end the Suite.
    try { $problems = @(Get-CitationProblem -ScanRoot $fixture -ResolveRoot $fixture -Moved $moved) }
    catch { $problems = @("call failed: $($_.Exception.Message)") }
    $first = @($moved | Where-Object { $_.Where -eq 'doc.md:1' })
    $second = @($moved | Where-Object { $_.Where -eq 'doc.md:2' })

    Assert-True ($first.Count -eq 1 -and $first[0].OldStart -eq 2 -and $first[0].NewStart -eq 3 -and
        @($problems | Where-Object { $_ -like 'doc.md:1 *' }).Count -eq 0) `
        'A cited text that moved to one other line is a warning, not a problem'
    Assert-True ($first.Count -eq 1 -and $first[0].CitingPath -eq 'doc.md' -and $first[0].CitingLine -eq 1 -and
        $first[0].Path -eq 'target.txt' -and $first[0].Text -like '*target.txt:2*') `
        'A moved citation records where it is, what it cites, and its text'
    Assert-True ($second.Count -eq 1 -and $second[0].OldStart -eq 40 -and $second[0].NewStart -eq 5 -and
        @($problems | Where-Object { $_ -like 'doc.md:2 *' }).Count -eq 0) `
        'A cited text that moved past the old end of the file is found the same way'
    Assert-True (@($problems | Where-Object { $_ -like 'doc.md:3 *' -and $_ -like '*on no line of target.txt*' }).Count -eq 1) `
        'A cited text found on no line is a problem that says so'
    Assert-True (@($problems | Where-Object { $_ -like 'doc.md:5 *' -and $_ -like '*on lines 1, 3*' }).Count -eq 1) `
        'A cited text found on two lines is a problem that names both lines'
    Assert-True (@($problems | Where-Object { $_ -like 'doc.md:4 *' -and $_ -like '*does not match. The target holds*' }).Count -eq 1 -and
        @($moved | Where-Object { $_.Where -eq 'doc.md:4' }).Count -eq 0) `
        'A range citation that no longer matches stays a problem'

    $noList = @(Get-CitationProblem -ScanRoot $fixture -ResolveRoot $fixture)
    Assert-True (@($noList | Where-Object { $_ -like 'doc.md:1 *' -and $_ -like '*line 3*' }).Count -eq 1) `
        'A caller that passes no Moved list gets the moved citation as a problem'
}
finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force
}

$fixture = New-FixtureRepository
try {
    Add-FixtureFile -Root $fixture -RelativePath 'target.txt' -Lines $targetLines
    Add-FixtureFile -Root $fixture -RelativePath 'doc.md' -Lines @('moved (`target.txt:2`, "the expected text") here')
    Complete-FixtureCommit -Root $fixture

    $run = Invoke-Runner -Arguments @('-ScanRoot', $fixture, '-ResolveRoot', $fixture, '-NoAdoptionTier')
    Assert-True ($run.ExitCode -eq 0 -and
        $run.Output -match 'WARNING doc\.md:1: target\.txt:2 moved to line 3\.' -and
        $run.Output -match 'check-citation-freshness\.ps1.* -Fix' -and
        $run.Output -match 'RESULT: .*1 warning') `
        "The check exits 0 on warnings alone and prints the -Fix command. Exit $($run.ExitCode), printed: $($run.Output)"
}
finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force
}

# -Fix rewrites only files the branch changed. A base commit, then a branch commit that inserts a
# line at the top of the target and edits one of the two citing files.
function New-FixFixture {
    $root = New-FixtureRepository
    & git -C $root config core.autocrlf false
    Add-FixtureFile -Root $root -RelativePath 'target.txt' -Lines $targetLines
    Add-FixtureFile -Root $root -RelativePath 'other.md' -Lines @('see (`target.txt:3`, "the expected text") here')
    # A CRLF file with a byte order mark, written as bytes so nothing normalizes it.
    $bom = [byte[]] (0xEF, 0xBB, 0xBF)
    $text = "intro`r`nsee (``target.txt:3``, `"the expected text`") here`r`n"
    [System.IO.File]::WriteAllBytes((Join-Path $root 'changed.md'), $bom + [System.Text.Encoding]::UTF8.GetBytes($text))
    & git -C $root add -- changed.md
    Complete-FixtureCommit -Root $root -Message 'base'
    $base = ((& git -C $root rev-parse HEAD) -join '').Trim()

    Add-FixtureFile -Root $root -RelativePath 'target.txt' -Lines (@('a new first line') + $targetLines)
    $text = "intro, edited on the branch`r`nsee (``target.txt:3``, `"the expected text`") here`r`n"
    [System.IO.File]::WriteAllBytes((Join-Path $root 'changed.md'), $bom + [System.Text.Encoding]::UTF8.GetBytes($text))
    & git -C $root add -- changed.md
    Complete-FixtureCommit -Root $root -Message 'branch'
    return [pscustomobject]@{ Root = $root; Base = $base; Bom = $bom; BranchText = $text }
}

$fix = New-FixFixture
try {
    $otherBefore = [System.IO.File]::ReadAllBytes((Join-Path $fix.Root 'other.md'))
    $run = Invoke-Runner -Arguments @('-ScanRoot', $fix.Root, '-ResolveRoot', $fix.Root, '-BaseRef', $fix.Base, '-Fix')

    $changedAfter = [System.IO.File]::ReadAllBytes((Join-Path $fix.Root 'changed.md'))
    $otherAfter = [System.IO.File]::ReadAllBytes((Join-Path $fix.Root 'other.md'))
    $expected = $fix.Bom + [System.Text.Encoding]::UTF8.GetBytes($fix.BranchText.Replace('target.txt:3', 'target.txt:4'))

    Assert-True ([Convert]::ToBase64String($otherAfter) -eq [Convert]::ToBase64String($otherBefore) -and
        $run.Output -match 'NOT FIXED other\.md:1' -and
        [System.Text.Encoding]::UTF8.GetString($changedAfter).Contains('target.txt:4')) `
        "-Fix rewrites only files the branch changed and lists the rest. Printed: $($run.Output)"
    Assert-True ([Convert]::ToBase64String($changedAfter) -eq [Convert]::ToBase64String($expected)) `
        '-Fix keeps the line endings and the byte order mark'
    Assert-True ($run.ExitCode -eq 0) "-Fix exits with the result of the check it runs again: one warning left, so 0. Exit $($run.ExitCode)"
}
finally {
    Remove-Item -LiteralPath $fix.Root -Recurse -Force
}

$fix = New-FixFixture
try {
    $before = [System.IO.File]::ReadAllBytes((Join-Path $fix.Root 'changed.md'))
    # The fixture has no origin/main, so with no -BaseRef there is no base to compare against.
    $run = Invoke-Runner -Arguments @('-ScanRoot', $fix.Root, '-ResolveRoot', $fix.Root, '-Fix')
    $after = [System.IO.File]::ReadAllBytes((Join-Path $fix.Root 'changed.md'))
    Assert-True ($run.ExitCode -eq 1 -and $run.Output -match 'cannot tell which files' -and
        [Convert]::ToBase64String($after) -eq [Convert]::ToBase64String($before)) `
        "-Fix with no base ref changes nothing. Exit $($run.ExitCode), printed: $($run.Output)"
}
finally {
    Remove-Item -LiteralPath $fix.Root -Recurse -Force
}

# --- OnlyPath narrows which files are scanned ---

# The plans repository is one shared working tree with a single branch, linked into every worktree.
# So a scan of it reads plans another branch is part-way through writing, whose citations resolve
# against that branch's files and not against these. Measured on 2026-08-21: the same plans scored
# 82 problems from one worktree and 104 from another, and the second saw zero problems in the very
# plan the first saw twenty in. Pre-push therefore scans only the plans this branch owns, and this
# is the parameter that lets it (backlog 112).
$fixture = New-FixtureRepository
try {
    Add-FixtureFile -Root $fixture -RelativePath 'target.txt' -Lines @('one line')
    Add-FixtureFile -Root $fixture -RelativePath 'kept.md' -Lines @('(`target.txt:99`, "nope")')
    Add-FixtureFile -Root $fixture -RelativePath 'skipped.md' -Lines @('(`target.txt:99`, "nope")')
    Complete-FixtureCommit -Root $fixture

    $all = @(Get-CitationProblem -ScanRoot $fixture -ResolveRoot $fixture)
    Assert-True ($all.Count -eq 2) "No filter must read both files, got $($all.Count)"

    $only = @(Get-CitationProblem -ScanRoot $fixture -ResolveRoot $fixture -OnlyPath @('kept.md'))
    Assert-True ($only.Count -eq 1) "One path must read one file, got $($only.Count)"
    Assert-True ($only[0] -like 'kept.md:*') "The surviving problem must be kept.md, got $($only[0])"

    $absent = @(Get-CitationProblem -ScanRoot $fixture -ResolveRoot $fixture -OnlyPath @('absent.md'))
    Assert-True ($absent.Count -eq 0) "A path matching nothing must report nothing, got $($absent.Count)"

    # An empty filter must mean "no filter", not "scan nothing". A branch with no plan of its own
    # passes an empty set, and silently scanning everything would put the whole problem back.
    $empty = @(Get-CitationProblem -ScanRoot $fixture -ResolveRoot $fixture -OnlyPath @())
    Assert-True ($empty.Count -eq 2) "An empty filter must mean no filter, got $($empty.Count)"

    # A backslashed path must match, because a caller building paths on Windows produces them.
    $slash = @(Get-CitationProblem -ScanRoot $fixture -ResolveRoot $fixture -OnlyPath @('KEPT.MD'))
    Assert-True ($slash.Count -eq 1) "The filter must be case-insensitive, got $($slash.Count)"

    # The filter must narrow what is scanned, never what counts as a valid citation target.
    # target.txt is not in OnlyPath, and the citation must still resolve against it.
    Add-FixtureFile -Root $fixture -RelativePath 'good.md' -Lines @('(`target.txt:1`, "one line")')
    Complete-FixtureCommit -Root $fixture -Message 'good'
    $good = @(Get-CitationProblem -ScanRoot $fixture -ResolveRoot $fixture -OnlyPath @('good.md'))
    Assert-True ($good.Count -eq 0) "A target outside OnlyPath must still resolve, got: $($good -join ', ')"
}
finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force
}

# --- OnlyPathFile crosses the child-process boundary ---

# The in-process cases above never touch how the hook actually calls this script. `pwsh -File`
# cannot carry an array: two paths bind the second to the wrong parameter and drop it silently,
# three fail with "A positional parameter cannot be found". Both were live defects, found in review
# on 2026-08-22 and invisible to a test that calls Get-CitationProblem directly. So this case runs
# the real runner, through a real file, with three paths (backlog 112).
$fixture = New-FixtureRepository
$manifest = [System.IO.Path]::GetTempFileName()
try {
    Add-FixtureFile -Root $fixture -RelativePath 'target.txt' -Lines @('one line')
    Add-FixtureFile -Root $fixture -RelativePath 'a.md' -Lines @('(`target.txt:99`, "nope")')
    Add-FixtureFile -Root $fixture -RelativePath 'b.md' -Lines @('(`target.txt:99`, "nope")')
    Add-FixtureFile -Root $fixture -RelativePath 'c.md' -Lines @('(`target.txt:1`, "one line")')
    Add-FixtureFile -Root $fixture -RelativePath 'd.md' -Lines @('(`target.txt:99`, "nope")')
    Complete-FixtureCommit -Root $fixture

    # Three paths. Two are broken, one is clean, and d.md is broken but left out of the manifest.
    Set-Content -LiteralPath $manifest -Value @('a.md', 'b.md', 'c.md')

    $run = Invoke-Runner -Arguments @(
        '-ScanRoot', $fixture, '-ResolveRoot', $fixture, '-NoAdoptionTier', '-OnlyPathFile', $manifest)
    Assert-True ($run.ExitCode -eq 1) "Three paths must reach the child process, exited $($run.ExitCode): $($run.Output)"
    Assert-True ($run.Output -notmatch 'positional parameter') `
        "The array must not be passed on the command line: $($run.Output)"
    Assert-True ($run.Output -match 'a\.md' -and $run.Output -match 'b\.md') `
        "Both broken listed files must be reported: $($run.Output)"
    Assert-True ($run.Output -notmatch 'd\.md') `
        "A file outside the manifest must not be scanned: $($run.Output)"

    # An empty manifest must fail closed, never widen to the whole repository.
    Set-Content -LiteralPath $manifest -Value @()
    $run = Invoke-Runner -Arguments @(
        '-ScanRoot', $fixture, '-ResolveRoot', $fixture, '-NoAdoptionTier', '-OnlyPathFile', $manifest)
    Assert-True ($run.ExitCode -ne 0) "An empty manifest must fail, exited $($run.ExitCode)"
    Assert-True ($run.Output -match 'empty') "The empty-manifest error must say so: $($run.Output)"

    # A manifest path that does not exist must fail, not scan everything.
    $run = Invoke-Runner -Arguments @(
        '-ScanRoot', $fixture, '-ResolveRoot', $fixture, '-NoAdoptionTier',
        '-OnlyPathFile', (Join-Path $fixture 'no-such-manifest.txt'))
    Assert-True ($run.ExitCode -ne 0) "A missing manifest must fail, exited $($run.ExitCode)"
}
finally {
    Remove-Item -LiteralPath $manifest -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $fixture -Recurse -Force
}

# --- The pre-push decision ---

# Never test this by renaming docs/superpowers. Every worktree links to that folder, and the
# workflow refuses renaming or deleting it (`docs/development/workflow.md:716`, "Two paths stay refused"). Inject a
# fixture path instead.
. (Join-Path $repoRoot 'scripts/plans-citation-scan.common.ps1')

$plansFixture = New-FixtureRepository
$plainFolder = Join-Path ([System.IO.Path]::GetTempPath()) "citation-plain-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $plainFolder -Force | Out-Null
try {
    $run = Get-PlansCitationScanPlan -PlansRoot $plansFixture -PwshPath 'C:\fake\pwsh.exe'
    Assert-True ($run.Action -eq 'Run') "A git repository plus a pwsh path must run, got $($run.Action)"

    $noRepo = Get-PlansCitationScanPlan -PlansRoot $plainFolder -PwshPath 'C:\fake\pwsh.exe'
    Assert-True ($noRepo.Action -eq 'SkipNoRepository') "A folder that is not a repository must skip, got $($noRepo.Action)"
    Assert-True ($noRepo.Reason -like 'Skipped:*') 'A skip must carry a reason to print'

    $noPwsh = Get-PlansCitationScanPlan -PlansRoot $plansFixture -PwshPath ''
    Assert-True ($noPwsh.Action -eq 'SkipNoPwsh') "No pwsh means skip, got $($noPwsh.Action)"
    Assert-True ($noPwsh.Reason -like 'Skipped:*') 'A skip must carry a reason to print'
}
finally {
    Remove-Item -LiteralPath $plansFixture -Recurse -Force
    Remove-Item -LiteralPath $plainFolder -Recurse -Force
}

# --- Report ---

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Host ''
        Write-Host $failure -ForegroundColor Red
    }
    Write-Host ''
    throw "Citation freshness tests failed with $($failures.Count) problem(s). See the detail above."
}

Write-Host 'Citation freshness tests passed.'
