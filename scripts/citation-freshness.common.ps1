#Requires -Version 7.0
# Shared helpers for the citation freshness check. Dot-sourced by
# scripts/check-citation-freshness.ps1 and tests/CitationFreshness.Tests.ps1.
#
# This repository proves claims with file:line citations, and a line number stops being true the
# moment somebody edits above it. See backlog 096.
#
# This file mentions the ignore tokens in its own code. That is exactly why the file-level token
# must be a standalone directive near the top of a file and not a plain substring match.

Set-StrictMode -Version Latest

# A citation core: a path, a colon, a start line, and an optional end line. Three path shapes are
# accepted, and the order matters because the first alternative that matches wins:
#
#   1. Anything with an extension that starts with a letter:  scripts/test-fast.ps1, Program.cs
#   2. Anything containing a slash, extension optional:       .githooks/pre-push
#   3. A hidden file with no extension:                       .editorconfig
#
# The extension must start with a letter, which is what keeps '4.5:1' out. A contrast ratio, a
# clock time, and a host with a port all match shape 1 without that rule.
$script:CitationCore =
    '(?<path>' +
    '\.?[A-Za-z0-9_][A-Za-z0-9_./\\-]*\.[A-Za-z][A-Za-z0-9]*' +
    '|\.?[A-Za-z0-9_][A-Za-z0-9_.\\-]*/[A-Za-z0-9_.-]+' +
    '|\.[A-Za-z][A-Za-z0-9_-]*' +
    '):(?<start>\d+)(?:-(?<end>\d+))?'

# The canonical form. Round brackets, backticks, one comma, one space, straight double quotes.
$script:CanonicalPattern = '\(`' + $script:CitationCore + '`, "(?<phrase>[^"]*)"\)'

function ConvertTo-CollapsedText {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)
    return (($Text -replace '\s+', ' ').Trim())
}

function New-CitationRecord {
    param(
        [Parameter(Mandatory)][string] $Kind,
        [Parameter(Mandatory)][System.Text.RegularExpressions.Match] $Match,
        # Untyped: a [string]-typed parameter coerces an explicit $null argument to '', which
        # breaks the Legacy/NearMiss "no phrase" contract this check relies on.
        $Phrase
    )

    $end = if ($Match.Groups['end'].Success) { [int] $Match.Groups['end'].Value }
           else { [int] $Match.Groups['start'].Value }

    return [pscustomobject]@{
        Kind   = $Kind
        Path   = ($Match.Groups['path'].Value -replace '\\', '/')
        Start  = [int] $Match.Groups['start'].Value
        End    = $end
        Phrase = $Phrase
        Text   = $Match.Value
    }
}

# Returns every citation on one source line. A canonical match wins its span, so the same text is
# never reported twice.
function Get-CitationOnLine {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Line)

    $found = [System.Collections.Generic.List[object]]::new()
    $claimed = [System.Collections.Generic.List[object]]::new()

    foreach ($match in [regex]::Matches($Line, $script:CanonicalPattern)) {
        $found.Add((New-CitationRecord -Kind 'Canonical' -Match $match -Phrase $match.Groups['phrase'].Value))
        $claimed.Add([pscustomobject]@{ Start = $match.Index; End = $match.Index + $match.Length })
    }

    foreach ($match in [regex]::Matches($Line, $script:CitationCore)) {
        $inside = $false
        foreach ($span in $claimed) {
            if ($match.Index -ge $span.Start -and $match.Index -lt $span.End) {
                $inside = $true
                break
            }
        }
        if ($inside) { continue }

        # A near-miss is a visible attempt at the canonical form: backticked, with a quote close
        # behind it. The distinction only changes the message, because tier 3 rejects both.
        $kind = 'Legacy'
        $tailStart = $match.Index + $match.Length
        $backticked = $match.Index -gt 0 -and $Line[$match.Index - 1] -eq '`' -and
                      $tailStart -lt $Line.Length -and $Line[$tailStart] -eq '`'
        if ($backticked) {
            $window = $Line.Substring($tailStart + 1)
            if ($window.Length -gt 20) { $window = $window.Substring(0, 20) }
            if ($window.Contains('"')) { $kind = 'NearMiss' }
        }

        $found.Add((New-CitationRecord -Kind $kind -Match $match -Phrase $null))
    }

    return $found
}

# True when the file opts out in full. The directive must stand alone on its own line, inside the
# first five non-blank lines. A "contains anywhere" rule fails open: any file that documents the
# token would silently stop being checked, including this one.
function Test-CitationIgnoreFile {
    # AllowEmptyString matters: a mandatory [string[]] refuses an array that holds an empty line,
    # and a file's blank lines are exactly that.
    param([Parameter(Mandatory)][AllowEmptyString()][AllowEmptyCollection()][string[]] $Lines)

    $seen = 0
    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $seen++
        if ($seen -gt 5) { break }

        $stripped = ($line -replace '^\s*(#|//|--|<!--)\s*', '') -replace '\s*-->\s*$', ''
        if ($stripped.Trim() -eq 'citation-check:ignore-file') { return $true }
    }

    return $false
}

# Every path git tracks in a repository, forward-slashed. Untracked files are invisible to the
# check on both sides: they are never scanned, and they are never accepted as a citation target.
# Without this, build output and scratch copies make two runs on one commit disagree. A path that
# climbs out of the root with '..' is never in this set either, so it fails rather than escapes.
function Get-TrackedFile {
    param([Parameter(Mandatory)][string] $Root)

    $output = & git -C $Root ls-files
    if ($LASTEXITCODE -ne 0) { throw "git ls-files failed in $Root" }
    return @($output | ForEach-Object { $_ -replace '\\', '/' })
}

$script:BinaryExtension = '\.(png|jpg|jpeg|gif|ico|svg|pdf|zip|dll|exe|pfx|snk|woff|woff2|ttf|eot|mp4|bin)$'

# Walks ScanRoot and returns one string per problem. ChangedLine enables tier 3; leave it null and
# the check reads state only.
function Get-CitationProblem {
    param(
        [Parameter(Mandatory)][string] $ScanRoot,
        [Parameter(Mandatory)][string] $ResolveRoot,
        [System.Collections.Generic.HashSet[string]] $ChangedLine
    )

    $scanPath = (Resolve-Path -LiteralPath $ScanRoot).Path
    $resolvePath = (Resolve-Path -LiteralPath $ResolveRoot).Path

    # Case-insensitive: Windows resolves paths that way, and a case difference is not this
    # check's defect to report.
    $tracked = [System.Collections.Generic.HashSet[string]]::new(
        [string[]] (Get-TrackedFile -Root $resolvePath),
        [System.StringComparer]::OrdinalIgnoreCase)

    $targetCache = @{}
    $problems = [System.Collections.Generic.List[string]]::new()

    foreach ($relative in (Get-TrackedFile -Root $scanPath)) {
        if ($relative -match $script:BinaryExtension) { continue }

        $full = Join-Path $scanPath $relative
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }

        $lines = @(Get-Content -LiteralPath $full -ErrorAction SilentlyContinue)
        if (Test-CitationIgnoreFile -Lines $lines) { continue }

        for ($index = 0; $index -lt $lines.Count; $index++) {
            $line = $lines[$index]
            if ($line -match 'citation-check:ignore') { continue }

            $lineNumber = $index + 1
            $where = '{0}:{1}' -f $relative, $lineNumber

            foreach ($citation in (Get-CitationOnLine -Line $line)) {
                $isTracked = $tracked.Contains($citation.Path)

                if ($ChangedLine -and $ChangedLine.Contains($where) -and
                    $citation.Kind -ne 'Canonical' -and $isTracked) {
                    $problems.Add(('{0} tier 3: {1} sits on an added or edited line, so it must use the canonical form (`path:line`, "expected text")' -f $where, $citation.Text))
                }

                if (-not $isTracked) {
                    # A legacy citation with an unresolved path is out of scope by design: most of
                    # them are bare file names and invented examples. A canonical one is different,
                    # because its author claims the check can read the target.
                    if ($citation.Kind -eq 'Canonical') {
                        $problems.Add(('{0} tier 2: {1} names a path that git does not track under {2}' -f $where, $citation.Text, $resolvePath))
                    }
                    continue
                }

                if (-not $targetCache.ContainsKey($citation.Path)) {
                    $targetCache[$citation.Path] = @(Get-Content -LiteralPath (Join-Path $resolvePath $citation.Path) -ErrorAction SilentlyContinue)
                }
                $targetLines = $targetCache[$citation.Path]

                if ($citation.Start -lt 1) {
                    $problems.Add(('{0} tier 1: {1} starts below line 1' -f $where, $citation.Text))
                    continue
                }
                if ($citation.End -lt $citation.Start) {
                    $problems.Add(('{0} tier 1: {1} ends before it starts' -f $where, $citation.Text))
                    continue
                }
                if ($citation.End -gt $targetLines.Count) {
                    $problems.Add(('{0} tier 1: {1} points past the end of {2}, which has {3} lines' -f $where, $citation.Text, $citation.Path, $targetLines.Count))
                    continue
                }

                if ($citation.Kind -ne 'Canonical') { continue }

                # An empty expectation would pass against every line, because every string
                # contains the empty string. That is a silent hole, so reject it outright.
                $phrase = ConvertTo-CollapsedText -Text $citation.Phrase
                if ([string]::IsNullOrEmpty($phrase)) {
                    $problems.Add(('{0} tier 2: {1} carries an empty expectation, which would match any line' -f $where, $citation.Text))
                    continue
                }

                $slice = ConvertTo-CollapsedText -Text (($targetLines[($citation.Start - 1)..($citation.End - 1)]) -join ' ')
                if (-not $slice.Contains($phrase)) {
                    $problems.Add(('{0} tier 2: {1} does not match. The target holds: {2}' -f $where, $citation.Text, $slice))
                }
            }
        }
    }

    return $problems
}

# Every line the working tree adds or changes against BaseRef, as 'path:line'. The diff runs
# against the working tree, not against HEAD, so an uncommitted edit is caught too.
function Get-ChangedLine {
    param(
        [Parameter(Mandatory)][string] $Root,
        [Parameter(Mandatory)][string] $BaseRef
    )

    $changed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # --no-ext-diff and --no-textconv stop a configured external differ from replacing this
    # output. -U0 asks for no context lines, so every line a hunk covers is a changed line.
    $diff = & git -C $Root --no-pager diff -U0 --no-color --no-ext-diff --no-textconv $BaseRef
    if ($LASTEXITCODE -ne 0) { throw "git diff against $BaseRef failed in $Root" }

    # '+++ ' names the new file only inside the header block that follows 'diff --git'. Inside a
    # hunk it is content: a source line beginning with '++ ' prints exactly that way, and reading
    # it as a header sends every later hunk to the wrong file.
    #
    # A hunk header needs no such guard. Every line inside a hunk carries a one-character prefix,
    # so a body line always starts with '+', '-', or '\', and never with '@@'.
    $inHeader = $false
    $file = $null

    foreach ($line in $diff) {
        if ($line.StartsWith('diff --git ')) {
            $inHeader = $true
            $file = $null
            continue
        }

        if ($inHeader -and $line.StartsWith('+++ ')) {
            $value = $line.Substring(4).Trim()
            $file = if ($value -eq '/dev/null') { $null }
                    else { ($value -replace '^b/', '') -replace '\\', '/' }
            continue
        }

        if (-not $line.StartsWith('@@')) { continue }
        $inHeader = $false
        if (-not $file) { continue }

        # A hunk header names the new file's start line and how many lines it covers. A hunk that
        # only deletes lines reports a count of 0, and then there is nothing to force.
        $header = [regex]::Match($line, '^@@ -\d+(?:,\d+)? \+(?<start>\d+)(?:,(?<count>\d+))? @@')
        if (-not $header.Success) { continue }

        $start = [int] $header.Groups['start'].Value
        $count = if ($header.Groups['count'].Success) { [int] $header.Groups['count'].Value } else { 1 }
        for ($offset = 0; $offset -lt $count; $offset++) {
            [void] $changed.Add(('{0}:{1}' -f $file, ($start + $offset)))
        }
    }

    return $changed
}
