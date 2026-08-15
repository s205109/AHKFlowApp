#Requires -Version 7.0
<#
.SYNOPSIS
    Compares workflow.md, workflow.html and the cheatsheet, and checks the PDF is not stale.
.DESCRIPTION
    workflow.md wins every disagreement. Each message names the losing file and its line.

    It compares stage order, exit strings, and edge targets. It also compares every data-*
    attribute against its own element's visible text, because metadata can agree while the
    rendered page drifts.

    For the PDF it checks three things: both hash sidecars still describe their files, and the
    PDF carries the digest of the cheatsheet it was rendered from. The digest is what makes
    the freshness claim real; two sidecars alone can be brought back into agreement by hand
    while the PDF stays stale. It does not check that the rendered pages show the cheatsheet's
    contents, because reading text out of a compressed PDF is out of scope.
.PARAMETER DocsRoot
    The folder holding the documents. Defaults to docs/development.
#>
[CmdletBinding()]
param([string] $DocsRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'process-canon.common.ps1')

if (-not $DocsRoot) { $DocsRoot = Join-Path $repoRoot 'docs/development' }

$canonPath = Join-Path $DocsRoot 'workflow.md'
$treePath = Join-Path $DocsRoot 'workflow.html'
$sheetPath = Join-Path $DocsRoot 'ahkflow-workflow-cheatsheet.html'
$pdfPath = Join-Path $DocsRoot 'ahk-workflow.pdf'
$sourceHashPath = Join-Path $DocsRoot 'ahk-workflow.pdf.source.sha256'
$pdfHashPath = Join-Path $DocsRoot 'ahk-workflow.pdf.sha256'

$problems = New-Object System.Collections.Generic.List[string]
$expectedStageCount = 11

# Preflight. Reading a file before checking it is there produced an unhandled error and no
# RESULT: line, so a caller could not tell a missing input from a crash.
foreach ($required in @($canonPath, $treePath, $sheetPath, $pdfPath, $sourceHashPath, $pdfHashPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        $problems.Add("missing input: $required")
    }
}

if ($problems.Count) {
    ''
    'INPUTS:'
    $problems | ForEach-Object { "  $_" }
    ''
    'Fix: pwsh ./scripts/update-workflow-pdf.ps1 writes the PDF and both sidecars.'
    "RESULT: $($problems.Count) missing input(s). Nothing was compared."
    exit 1
}

$canon = Get-CanonStage -Path $canonPath
$tree = Get-HtmlStage -Path $treePath
$sheet = Get-HtmlStage -Path $sheetPath

# Read the PDF once, now that every input is known to be there.
$pdfBytes = [System.IO.File]::ReadAllBytes($pdfPath)
$pdfText = [System.Text.Encoding]::Latin1.GetString($pdfBytes)

# Vacuous passes are the failure this guards against: a drifted format extracts fewer
# stages, and comparing whatever survived proves nothing.
if ($canon.Count -ne $expectedStageCount) { $problems.Add("workflow.md: expected $expectedStageCount stages, extracted $($canon.Count)") }
if ($tree.Count -ne $expectedStageCount) { $problems.Add("workflow.html: expected $expectedStageCount stages, extracted $($tree.Count)") }
if ($sheet.Count -ne $expectedStageCount) { $problems.Add("cheatsheet: expected $expectedStageCount stages, extracted $($sheet.Count)") }

foreach ($id in $canon.Keys) {
    if ($canon[$id].ExitCount -ne 1) { $problems.Add("workflow.md/${id}: expected 1 Exit, found $($canon[$id].ExitCount)") }
    if ($canon[$id].Edges.Count -ne 5) { $problems.Add("workflow.md/${id}: expected 5 edges, found $($canon[$id].Edges.Count)") }
    if ($canon[$id].Duplicates.Count -gt 0) { $problems.Add("workflow.md/${id}: duplicate edge row(s): $($canon[$id].Duplicates -join ', ')") }
}

# A stage id that appears twice is a structural fault, not a difference: the count still
# reads 11 while one of the two blocks is never compared with anything.
foreach ($pair in @(
        @{ Name = 'workflow.md'; Doc = $canon }
        @{ Name = 'workflow.html'; Doc = $tree }
        @{ Name = 'cheatsheet'; Doc = $sheet }
    )) {
    foreach ($id in $pair.Doc.Keys) {
        if ($pair.Doc[$id].Occurrences -gt 1) {
            $problems.Add("$($pair.Name)/${id}: REPEATED stage id, found $($pair.Doc[$id].Occurrences) blocks")
        }
    }
}

if ($problems.Count) {
    ''
    'STRUCTURE:'
    $problems | ForEach-Object { "  $_" }
    ''
    "RESULT: $($problems.Count) structural problem(s). Nothing was compared."
    exit 1
}

# The legal target set is built from the stages actually found, never from a shape pattern:
# '^[0-9]+-[a-z-]+$' would pass 99-missing.
$legal = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($id in $canon.Keys) { [void]$legal.Add($id) }
foreach ($literal in @('2-design/3-plan/4-execute', 'stay', 'terminal', 'blocked/', 'none')) { [void]$legal.Add($literal) }

$differences = 0
function Add-Difference {
    param([string] $Message)
    $script:differences++
    Write-Host $Message
}

$canonIds = @($canon.Keys)
$treeIds = @($tree.Keys)
$sheetIds = @($sheet.Keys)

for ($i = 0; $i -lt $canonIds.Count; $i++) {
    $id = $canonIds[$i]

    if ($treeIds[$i] -cne $id) { Add-Difference "ORDER workflow.html position ${i}: canon=$id  html=$($treeIds[$i])" }
    if ($sheetIds[$i] -cne $id) { Add-Difference "ORDER cheatsheet position ${i}: canon=$id  sheet=$($sheetIds[$i])" }

    # Runs of white space collapse, because HTML wraps lines. Punctuation does not: trimming a
    # trailing period let one document end a sentence and another not, which is a difference
    # the canon is supposed to settle.
    $canonExit = ($canon[$id].Exit -replace '\s+', ' ').Trim()

    # The expected visible label is derived from the stage id, so a renamed heading is caught:
    # '0-intake' must render as '0 Intake'.
    $idParts = $id -split '-', 2
    $expectedLabel = "$($idParts[0]) $($idParts[1].Substring(0,1).ToUpperInvariant())$($idParts[1].Substring(1))"

    $pairs = @(
        @{ Name = 'workflow.html'; Doc = $tree; Expect = @($canon[$id].Edges.Keys) }
        @{ Name = 'cheatsheet'; Doc = $sheet; Expect = @('success', 'failure') }
    )

    foreach ($pair in $pairs) {
        $doc = $pair.Doc
        if (-not $doc.Contains($id)) { Add-Difference "MISSING $($pair.Name): stage $id"; continue }

        $node = $doc[$id]

        if ($node.Duplicates.Count -gt 0) {
            Add-Difference "DUPLICATE $($pair.Name):$($node.Line)  stage $id repeats edge(s): $($node.Duplicates -join ', ')"
        }

        # The rendered stage label must match the id. Parsing it and never comparing it was
        # the hole that let a renamed heading through.
        if ($node.VisibleStage -cne $expectedLabel) {
            Add-Difference "LABEL $($pair.Name):$($node.Line)  stage $id renders as '$($node.VisibleStage)', expected '$expectedLabel'"
        }

        $exit = ($node.Exit -replace '\s+', ' ').Trim()
        if ($exit -cne $canonExit) {
            Add-Difference "EXIT  $($pair.Name):$($node.ExitLine)  stage $id`n   canon ($canonPath`:$($canon[$id].ExitLine)): $canonExit`n   $($pair.Name): $exit"
        }

        $visibleExit = ($node.VisibleExit -replace '\s+', ' ').Trim()
        if ($visibleExit -cne $exit) {
            Add-Difference "VISIBLE $($pair.Name):$($node.ExitLine)  stage $id exit attribute and rendered text differ`n   attribute: $exit`n   rendered : $visibleExit"
        }

        # Compare the edge SETS before comparing values, and compare the names case-sensitively.
        # Iterating only the document's own edges means a deleted data-next simply vanishes
        # from the comparison and passes. Comparing names case-insensitively means 'Success'
        # answers for 'success', so the attribute matched the canon while the badge beside it
        # read something else.
        $nodeEdgeNames = @($node.Edges.Keys)
        foreach ($edge in $pair.Expect) {
            if ($nodeEdgeNames -cnotcontains $edge) {
                Add-Difference "EDGE-MISSING $($pair.Name):$($node.Line)  stage $id has no '$edge' edge; the canon has one"
            }
        }
        foreach ($edge in $nodeEdgeNames) {
            if ($pair.Expect -cnotcontains $edge) {
                # The cheatsheet's expected set is fixed at success and failure on purpose. A
                # derived set would accept a cheatsheet that quietly LOST an edge, which is
                # the defect this check exists to find. Widening it is a deliberate change
                # here, not a surprise there.
                Add-Difference "EDGE-EXTRA $($pair.Name):$($node.Line)  stage $id carries an unexpected '$edge' edge. The cheatsheet carries success and failure by design; widening it means changing the Expect set in this check on purpose."
            }
        }

        foreach ($edge in $nodeEdgeNames) {
            $target = $node.Edges[$edge]
            $edgeLine = $node.EdgeLines[$edge]
            if (-not $legal.Contains($target)) {
                Add-Difference "TARGET $($pair.Name):$edgeLine  stage $id edge '$edge' names '$target', which is not a stage or a legal literal"
            }
            $canonTarget = if ($canon[$id].Edges.Contains($edge)) { $canon[$id].Edges[$edge] } else { '<missing>' }
            if ($target -cne $canonTarget) {
                Add-Difference "EDGE  $($pair.Name):$edgeLine  stage $id / $edge   canon=$canonTarget   $($pair.Name)=$target"
            }
            $visibleTarget = $node.VisibleEdges[$edge]
            if ($visibleTarget -cne $target) {
                Add-Difference "VISIBLE $($pair.Name):$edgeLine  stage $id edge '$edge' attribute and rendered text differ`n   attribute: $target`n   rendered : $visibleTarget"
            }
        }
    }

    foreach ($edge in @($canon[$id].Edges.Keys)) {
        if (-not $legal.Contains($canon[$id].Edges[$edge])) {
            Add-Difference "TARGET workflow.md:$($canon[$id].EdgeLines[$edge])  stage $id edge '$edge' names '$($canon[$id].Edges[$edge])', which is not a stage or a legal literal"
        }
    }
}

# --- The PDF ---
# The digest inside the PDF is what ties it to one cheatsheet. The two sidecars alone only
# say the three files were written together, and a person can refresh a sidecar by hand: the
# cheatsheet changes, its sidecar is rewritten, the old PDF stays, and both pairs still agree.
$sourceHash = (Get-NormalizedHash -Path $sheetPath)
$recordedSource = (Get-Content -LiteralPath $sourceHashPath -Raw).Trim()
if ($sourceHash -ne $recordedSource) {
    Add-Difference "PDF  the cheatsheet changed and the PDF was not regenerated.`n   cheatsheet now: $sourceHash`n   sidecar       : $recordedSource`n   Fix: pwsh ./scripts/update-workflow-pdf.ps1"
}

$pdfHash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($pdfBytes)).Replace('-', '')
$recordedPdf = (Get-Content -LiteralPath $pdfHashPath -Raw).Trim()
if ($pdfHash -ne $recordedPdf) {
    Add-Difference "PDF  the PDF changed without going through the generator.`n   pdf now: $pdfHash`n   sidecar: $recordedPdf"
}

if ($pdfText -notmatch '^%PDF-') {
    Add-Difference "PDF  $pdfPath does not start with %PDF-, so it is not a PDF"
}
if ($pdfText -notmatch '/Count\s+1\b') { Add-Difference 'PDF  the page tree does not read /Count 1, so the cheatsheet is no longer one page' }
if (-not (Test-PdfSourceDigest -Bytes $pdfBytes -Digest $sourceHash)) {
    Add-Difference "PDF  the PDF does not carry the digest of this cheatsheet, so it was rendered from a different one.`n   cheatsheet digest: $sourceHash`n   Fix: pwsh ./scripts/update-workflow-pdf.ps1"
}

''
if ($differences) {
    "RESULT: $differences difference(s). workflow.md wins - fix the other file."
    exit 1
}

'RESULT: the three process documents agree, and the PDF is current'
