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
    [string] $OnlyPathFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
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

$changed = $null
if ($NoAdoptionTier) {
    'Tier 3 skipped: -NoAdoptionTier was passed.'
} else {
    if (-not $BaseRef) {
        $candidate = & git -C $ScanRoot merge-base HEAD origin/main 2>$null
        if ($LASTEXITCODE -eq 0 -and $candidate) { $BaseRef = ([string] $candidate).Trim() }
    }

    if ($BaseRef) {
        $changed = Get-ChangedLine -Root $ScanRoot -BaseRef $BaseRef
    } else {
        # Never pass tier 3 by assuming an empty diff. A shallow clone has no merge base, and a
        # silent pass there is how an adoption gate quietly stops existing.
        'Tier 3 skipped: no merge base with origin/main. A shallow clone or a missing remote does this.'
    }
}

$problems = @(Get-CitationProblem -ScanRoot $ScanRoot -ResolveRoot $ResolveRoot -ChangedLine $changed -OnlyPath $OnlyPath)

if ($problems.Count -gt 0) {
    ''
    foreach ($problem in $problems) { "  $problem" }
    ''
    "RESULT: $($problems.Count) citation problem(s). A cited line moved, or a new citation needs the canonical form."
    exit 1
}

"RESULT: every citation checks out. Scanned $ScanRoot against $ResolveRoot."
