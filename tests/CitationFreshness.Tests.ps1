#Requires -Version 7.0
# citation-check:ignore-file
#
# The fixture strings below are canonical citations to paths this repository does not track, so
# the check must not read this file. The directive above is the supported way to say that, and it
# only counts because it stands alone inside the first five non-blank lines.
#
# A citation like docs/development/workflow.md:482 is a fragile address. An edit above line 482
# moves the target, the citation still looks right, and nothing notices. This suite proves the
# check that catches it. See backlog 096.
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
