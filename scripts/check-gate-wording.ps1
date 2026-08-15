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

    backlog/done and backlog/blocked are skipped. They are frozen records of finished work,
    and rewriting a shipped item to satisfy a present-day rule falsifies the record.

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
$pattern = 'before\s+(?:you\s+|anyone\s+)?(?:open|opening|opens|create|creating|creates)\s+(?:a\s+)?(?:PR|pull\s+request)'
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
        $_ -notmatch '^backlog/(done|blocked)/' -and
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

        # The marker may sit on any line the match spans, because the phrase wraps.
        $sourceLines = $text -split "`n"
        $window = -join ($sourceLines[($startLine - 1)..([Math]::Min($endLine, $sourceLines.Count - 1))])
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
