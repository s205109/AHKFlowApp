#Requires -Version 7.0
<#
.SYNOPSIS
    No document may say the canonical gate runs before a pull request is opened.
.DESCRIPTION
    The gate guards the pull request going ready, not its creation. The draft pull request
    opens at Pickup, long before the gate can run. This wording drifted back once already.

    The scan is whole-file with whitespace normalized, never line by line: this repository
    hard-wraps prose, so the phrase usually straddles a line break and a line scan misses it.

    'pre-PR gate' is NOT banned. It is the gate's own anchor name in testing-workflow.md.
    Only the timing claim is banned.

    backlog/done is skipped. Those are frozen records of finished work, and rewriting a shipped
    item to satisfy a present-day rule falsifies the record. backlog/blocked is NOT skipped: a
    blocked item is active work waiting on something outside this repository, and it will be
    picked up again.

    Put '<!-- gate-wording:ignore -->' on a line that must be allowed.
.PARAMETER ScanRoot
    The folder to scan. Defaults to the repository root.
#>
[CmdletBinding()]
param([string] $ScanRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'process-canon.common.ps1')

if (-not $ScanRoot) { $ScanRoot = $repoRoot }

# \s+ already spans a newline, so this matches a wrapped phrase in the ORIGINAL text. There
# is no need to flatten first, and flattening then mapping the offset back by counting words
# is both unnecessary and wrong: it reported the canon's own sentence 14 lines early, so the
# ignore marker was never found and the check stayed red.
#
# Two shapes, because the claim is made both ways round. Active: 'before you open a PR'.
# Passive: 'before a pull request is opened'. Reading only the active shape let the same
# sentence through when somebody wrote it the other way.
#
# 'PR' carries a word boundary. Without it the two letters matched the start of 'profile' and
# 'preview', so 'before creating a profile' failed a check about pull requests.
$noun = '(?:PRs?\b|pull\s+requests?\b)'
$activePattern = "before\s+(?:you\s+|anyone\s+|the\s+session\s+)?(?:open|opening|opens|create|creating|creates)\s+(?:a\s+|the\s+|any\s+)?$noun"
# The passive shape names the act of opening, never the state of existing. 'before the pull
# request exists' is an ordinary statement about a moment in time - the canon uses it twice to
# say what the durable record is until Pickup pushes - and it makes no claim about the gate.
$passivePattern = "before\s+(?:a\s+|the\s+|any\s+)?$noun\s+(?:is\s+|are\s+|has\s+been\s+|have\s+been\s+|gets\s+)?(?:opened|created)"
$pattern = "(?:$activePattern)|(?:$passivePattern)"
$problems = New-Object System.Collections.Generic.List[string]

# Tracked files only. The criterion says "no document", and an untracked scratch file is not
# a document this repository ships. Fixtures have no git repository, so fall back to walking
# the folder when git returns nothing.
$relativePaths = @()
if (Test-Path -LiteralPath (Join-Path $ScanRoot '.git')) {
    $relativePaths = @(& git -C $ScanRoot ls-files '*.md')
}
if (-not $relativePaths) {
    $relativePaths = @(Get-ChildItem -LiteralPath $ScanRoot -Filter '*.md' -File -Recurse |
            ForEach-Object { $_.FullName.Substring($ScanRoot.Length).Replace('\', '/').TrimStart('/') })
}

$relativePaths = @($relativePaths | Where-Object {
        $_ -notmatch '^backlog/done/' -and
        $_ -notmatch '^(node_modules|bin|obj|docs/superpowers)/' -and
        $_ -notmatch '/(node_modules|bin|obj)/'
    })

foreach ($relative in $relativePaths) {
    $full = Join-Path $ScanRoot $relative
    if (-not (Test-Path -LiteralPath $full)) { continue }

    $text = Get-NormalizedText -Path $full
    foreach ($m in [regex]::Matches($text, $pattern, 'IgnoreCase')) {
        # Exact: count the newlines before the match. No reconstruction, nothing to drift.
        $startLine = ($text.Substring(0, $m.Index) -split "`n").Count
        $endLine = ($text.Substring(0, $m.Index + $m.Length) -split "`n").Count

        # The marker may sit on any line the match spans, because the phrase wraps. Both bounds
        # are 1-based line numbers, so both convert to indexes: reading up to $endLine included
        # the line AFTER the match, and a marker there silenced a violation it had nothing to
        # do with.
        $sourceLines = $text -split "`n"
        $window = -join ($sourceLines[($startLine - 1)..([Math]::Min($endLine - 1, $sourceLines.Count - 1))])
        if ($window -match 'gate-wording:ignore') { continue }

        $shown = ($m.Value -replace '\s+', ' ')
        $problems.Add("${relative}:${startLine} says '$shown'. The gate guards the pull request going ready, not its creation.")
    }
}

''
if ($problems.Count) {
    $problems | ForEach-Object { $_ }
    ''
    "RESULT: $($problems.Count) document(s) claim the gate runs before a pull request opens."
    exit 1
}

'RESULT: no document claims the gate runs before a pull request opens'
