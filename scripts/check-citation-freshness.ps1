#Requires -Version 7.0
<#
.SYNOPSIS
    Checks that every file:line citation still points at what it claims.

.DESCRIPTION
    A line number stops being true the moment somebody edits above it, and the citation still
    looks right. Backlog 087 shipped six citations that were wrong on the day they landed.

    Three tiers. Tier 1 checks that a cited line exists. Tier 2 checks that a canonical citation
    finds its quoted text on the cited line. Tier 3 checks that a citation on an added or edited
    line uses the canonical form, so the notation spreads without a bulk rewrite.

    Exits 1 on any problem, so it works as a gate step. Call it as its own process: a caller that
    dot-sources it, or runs it inline, ends with it.

    A single-line canonical citation whose text moved to exactly one other line of its target is a
    warning, not a problem (backlog 188). That is what an edit above a cited line does. The check
    prints each one, then the command that fixes them, and warnings alone exit 0. A text found on
    no line, or on two or more lines, is still a problem, and so is a range citation that no longer
    matches.

.PARAMETER ScanRoot
    The repository whose files are read. Defaults to this repository.

.PARAMETER ResolveRoot
    The repository a cited path resolves against. Defaults to this repository. Point ScanRoot at
    docs/superpowers and leave this at the default to check the private plans repository, because
    a plan writes its paths against the public root.

.PARAMETER BaseRef
    The ref tier 3 compares against. Defaults to the merge base with origin/main.

.PARAMETER NoAdoptionTier
    Turns tier 3 off.

.PARAMETER OnlyPath
    Scan only these paths, relative to ScanRoot. Leave it empty to scan everything. Pre-push passes
    the plans this branch owns, because the plans repository is one shared working tree: another
    branch's live plan cites lines that are right on that branch and wrong on this one.

.PARAMETER Fix
    Rewrites the line number of every moved citation, in the files this branch changed. It needs
    the same base ref tier 3 uses; with none it changes nothing and exits 1. A moved citation in a
    file the branch did not change is listed as not fixed. Each file keeps its encoding, byte order
    mark and line endings. Then the check runs again, and its result is the exit code.

.PARAMETER OnlyPathFile
    A file holding one path per line, added to OnlyPath. Use this from another process. `pwsh -File`
    cannot carry an array: two paths silently bind the second to the wrong parameter, and three fail
    outright with "A positional parameter cannot be found". A file has no quoting or arity failure
    mode. An empty file throws rather than scanning everything, because a filter that silently turns
    into "no filter" is how a narrow check becomes a whole-repository one again.

.EXAMPLE
    pwsh ./scripts/check-citation-freshness.ps1
#>
[CmdletBinding()]
param(
    [string] $ScanRoot,
    [string] $ResolveRoot,
    [string] $BaseRef,
    [switch] $NoAdoptionTier,
    [string[]] $OnlyPath,
    [string] $OnlyPathFile,
    [switch] $Fix
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

# The arguments as the caller gave them, before OnlyPathFile adds to OnlyPath. The -Fix command
# line is built from these.
$script:BoundAtStart = @{} + $PSBoundParameters
. (Join-Path $PSScriptRoot 'citation-freshness.common.ps1')

if (-not $ScanRoot) { $ScanRoot = $repoRoot }
if (-not $ResolveRoot) { $ResolveRoot = $repoRoot }

if ($OnlyPathFile) {
    if (-not (Test-Path -LiteralPath $OnlyPathFile -PathType Leaf)) {
        throw "OnlyPathFile does not exist: $OnlyPathFile"
    }

    $fromFile = @(Get-Content -LiteralPath $OnlyPathFile |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ })

    # Fail closed. An empty manifest would leave the filter empty, which means "scan everything",
    # and the caller asked for the opposite.
    if ($fromFile.Count -eq 0) {
        throw "OnlyPathFile is empty, so nothing would be filtered: $OnlyPathFile"
    }

    $OnlyPath = @($OnlyPath) + $fromFile
}

# The command line that ran, with -Fix added. Printed once after the warnings, so a reader can
# copy it as it stands.
function Get-FixCommand {
    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add('pwsh')
    $parts.Add("'$PSCommandPath'")
    foreach ($name in $script:BoundAtStart.Keys) {
        if ($name -eq 'Fix') { continue }
        $value = $script:BoundAtStart[$name]
        if ($value -is [switch]) {
            if ($value.IsPresent) { $parts.Add("-$name") }
        } else {
            $parts.Add("-$name " + ((@($value) | ForEach-Object { "'" + ([string] $_).Replace("'", "''") + "'" }) -join ','))
        }
    }
    $parts.Add('-Fix')
    return $parts -join ' '
}

# Rewrites path:<old> to path:<new> inside the citation on its citing line. The file is read and
# written as bytes, so its byte order mark and its line endings survive.
function Set-MovedCitation {
    param([string] $FullPath, [object[]] $Move)
    $bytes = [System.IO.File]::ReadAllBytes($FullPath)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $start = if ($bom) { 3 } else { 0 }
    $text = [System.Text.Encoding]::UTF8.GetString($bytes, $start, $bytes.Length - $start)

    # Split after each newline, so every piece keeps its own ending.
    $lines = [regex]::Split($text, '(?<=\n)')
    foreach ($one in $Move) {
        $index = $one.CitingLine - 1
        $newText = $one.Text.Replace(('{0}:{1}`' -f $one.Path, $one.OldStart), ('{0}:{1}`' -f $one.Path, $one.NewStart))
        $at = $lines[$index].IndexOf($one.Text, [System.StringComparison]::Ordinal)
        if ($at -lt 0) { throw "The citation $($one.Text) is no longer on line $($one.CitingLine) of $FullPath." }
        $lines[$index] = $lines[$index].Substring(0, $at) + $newText + $lines[$index].Substring($at + $one.Text.Length)
    }

    $out = [System.Text.Encoding]::UTF8.GetBytes(($lines -join ''))
    if ($bom) { $out = [byte[]] (0xEF, 0xBB, 0xBF) + $out }
    [System.IO.File]::WriteAllBytes($FullPath, $out)
}

if (-not $BaseRef -and (-not $NoAdoptionTier -or $Fix)) {
    $candidate = & git -C $ScanRoot merge-base HEAD origin/main 2>$null
    if ($LASTEXITCODE -eq 0 -and $candidate) { $BaseRef = ([string] $candidate).Trim() }
}

if ($Fix -and -not $BaseRef) {
    '-Fix cannot tell which files this branch changed: there is no base ref. Pass -BaseRef, or fetch origin/main. Nothing was changed.'
    exit 1
}

$changed = $null
if ($NoAdoptionTier) {
    'Tier 3 skipped: -NoAdoptionTier was passed.'
} elseif ($BaseRef) {
    $changed = Get-ChangedLine -Root $ScanRoot -BaseRef $BaseRef
} else {
    # Never pass tier 3 by assuming an empty diff. A shallow clone has no merge base, and a
    # silent pass there is how an adoption gate quietly stops existing.
    'Tier 3 skipped: no merge base with origin/main. A shallow clone or a missing remote does this.'
}

$moved = [System.Collections.Generic.List[object]]::new()
$problems = @(Get-CitationProblem -ScanRoot $ScanRoot -ResolveRoot $ResolveRoot -ChangedLine $changed -OnlyPath $OnlyPath -Moved $moved)

if ($Fix -and $moved.Count -gt 0) {
    # Only the files this branch changed. A citation in any other file belongs to work that is not
    # this branch's to edit.
    $branchLines = if ($null -ne $changed) { $changed } else { Get-ChangedLine -Root $ScanRoot -BaseRef $BaseRef }
    $branchFiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $branchLines) { [void] $branchFiles.Add($entry.Substring(0, $entry.LastIndexOf(':'))) }

    foreach ($group in ($moved | Group-Object CitingPath)) {
        if ($branchFiles.Contains($group.Name)) {
            Set-MovedCitation -FullPath (Join-Path $ScanRoot $group.Name) -Move @($group.Group)
            foreach ($one in $group.Group) { "FIXED $($one.Where): $($one.Path):$($one.OldStart) now reads $($one.Path):$($one.NewStart)." }
        } else {
            foreach ($one in $group.Group) { "NOT FIXED $($one.Where): $($one.Path):$($one.OldStart) moved to line $($one.NewStart), but this branch did not change $($group.Name)." }
        }
    }

    # The check again, on the rewritten files. Its result is this run's result.
    if ($null -ne $changed) { $changed = Get-ChangedLine -Root $ScanRoot -BaseRef $BaseRef }
    $moved = [System.Collections.Generic.List[object]]::new()
    $problems = @(Get-CitationProblem -ScanRoot $ScanRoot -ResolveRoot $ResolveRoot -ChangedLine $changed -OnlyPath $OnlyPath -Moved $moved)
}

if ($moved.Count -gt 0) {
    ''
    foreach ($one in $moved) { "WARNING $($one.Where): $($one.Path):$($one.OldStart) moved to line $($one.NewStart)." }
    ''
    'Fix them with:'
    "  $(Get-FixCommand)"
}

if ($problems.Count -gt 0) {
    ''
    foreach ($problem in $problems) { "  $problem" }
    ''
    "RESULT: $($problems.Count) citation problem(s), $($moved.Count) warning(s). A cited line moved, or a new citation needs the canonical form."
    exit 1
}

if ($moved.Count -gt 0) {
    "RESULT: no citation problem, $($moved.Count) warning(s). Scanned $ScanRoot against $ResolveRoot."
    exit 0
}

"RESULT: every citation checks out. Scanned $ScanRoot against $ResolveRoot."
