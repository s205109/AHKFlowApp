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
