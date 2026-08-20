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

$live = @(Get-CitationProblem -ScanRoot $repoRoot -ResolveRoot $repoRoot -ChangedLine $changedHere)
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
    Add-FixtureFile -Root $fixture -RelativePath 'doc.md' -Lines @('broken (`target.txt:99`, "the expected text") here')
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

# --- The pre-push decision ---

# Never test this by renaming docs/superpowers. Every worktree links to that folder, and the
# workflow refuses renaming or deleting it (`docs/development/workflow.md:719`, "Two paths stay refused"). Inject a
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
