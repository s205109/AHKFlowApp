#Requires -Version 7.0
<#
.SYNOPSIS
    Compares workflow.md, workflow.html and the cheatsheet, and checks what the PDF carries.
.DESCRIPTION
    workflow.md wins every disagreement. Each message names the losing file and its line.

    It compares the canonical stage table in section 1 against the stage blocks below it -
    number, name and exit condition - then stage order, exit strings, and edge targets across
    the three documents. It also compares every data-* attribute against its own element's
    visible text, because metadata can agree while the rendered page drifts.

    For the PDF it checks three things: both hash sidecars still describe their files, and the
    PDF carries the digest of the cheatsheet it was rendered from. That is coherence, not
    freshness. Two sidecars alone can be brought back into agreement by hand, and the digest
    marker is a byte string that a person can append to a stale PDF. It also does not check
    that the rendered pages show the cheatsheet's contents, because reading text out of a
    compressed PDF is out of scope. So the result line says what was compared and never says
    the PDF is current.
.PARAMETER DocsRoot
    The folder holding the documents. Defaults to docs/development.
#>
[CmdletBinding()]
param([string] $DocsRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'process-workflow.common.ps1')

if (-not $DocsRoot) { $DocsRoot = Join-Path $repoRoot 'docs/development' }

$workflowPath = Join-Path $DocsRoot 'workflow.md'
$treePath = Join-Path $DocsRoot 'workflow.html'
$sheetPath = Join-Path $DocsRoot 'ahkflow-workflow-cheatsheet.html'
$pdfPath = Join-Path $DocsRoot 'ahk-workflow.pdf'
$sourceHashPath = Join-Path $DocsRoot 'ahk-workflow.pdf.source.sha256'
$pdfHashPath = Join-Path $DocsRoot 'ahk-workflow.pdf.sha256'

$problems = New-Object System.Collections.Generic.List[string]
$expectedStageCount = 11

# Preflight. Reading a file before checking it is there produced an unhandled error and no
# RESULT: line, so a caller could not tell a missing input from a crash.
foreach ($required in @($workflowPath, $treePath, $sheetPath, $pdfPath, $sourceHashPath, $pdfHashPath)) {
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

$workflow = Get-WorkflowStage -Path $workflowPath
$stageTable = @(Get-WorkflowStageTable -Path $workflowPath)
$tree = Get-HtmlStage -Path $treePath
$sheet = Get-HtmlStage -Path $sheetPath

# Read the PDF once, now that every input is known to be there.
$pdfBytes = [System.IO.File]::ReadAllBytes($pdfPath)
$pdfText = [System.Text.Encoding]::Latin1.GetString($pdfBytes)

# Vacuous passes are the failure this guards against: a drifted format extracts fewer
# stages, and comparing whatever survived proves nothing.
if ($workflow.Count -ne $expectedStageCount) { $problems.Add("workflow.md: expected $expectedStageCount stages, extracted $($workflow.Count)") }
if ($stageTable.Count -ne $expectedStageCount) { $problems.Add("workflow.md: the canonical stage table holds $($stageTable.Count) row(s), expected $expectedStageCount") }
if ($tree.Count -ne $expectedStageCount) { $problems.Add("workflow.html: expected $expectedStageCount stages, extracted $($tree.Count)") }
if ($sheet.Count -ne $expectedStageCount) { $problems.Add("cheatsheet: expected $expectedStageCount stages, extracted $($sheet.Count)") }

foreach ($id in $workflow.Keys) {
    if ($workflow[$id].ExitCount -ne 1) { $problems.Add("workflow.md/${id}: expected 1 Exit, found $($workflow[$id].ExitCount)") }
    if ($workflow[$id].Edges.Count -ne 5) { $problems.Add("workflow.md/${id}: expected 5 edges, found $($workflow[$id].Edges.Count)") }
    if ($workflow[$id].Duplicates.Count -gt 0) { $problems.Add("workflow.md/${id}: duplicate edge row(s): $($workflow[$id].Duplicates -join ', ')") }
}

# A stage id that appears twice is a structural fault, not a difference: the count still
# reads 11 while one of the two blocks is never compared with anything.
foreach ($pair in @(
        @{ Name = 'workflow.md'; Doc = $workflow }
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
foreach ($id in $workflow.Keys) { [void]$legal.Add($id) }
foreach ($literal in @('2-design/3-plan/4-execute', 'stay', 'terminal', 'blocked/', 'none')) { [void]$legal.Add($literal) }

$differences = 0
function Add-Difference {
    param([string] $Message)
    $script:differences++
    Write-Host $Message
}

$workflowIds = @($workflow.Keys)
$treeIds = @($tree.Keys)
$sheetIds = @($sheet.Keys)

for ($i = 0; $i -lt $workflowIds.Count; $i++) {
    $id = $workflowIds[$i]

    if ($treeIds[$i] -cne $id) { Add-Difference "ORDER workflow.html position ${i}: source=$id  html=$($treeIds[$i])" }
    if ($sheetIds[$i] -cne $id) { Add-Difference "ORDER cheatsheet position ${i}: source=$id  sheet=$($sheetIds[$i])" }

    # Runs of white space collapse, because HTML wraps lines. Punctuation does not: trimming a
    # trailing period let one document end a sentence and another not, which is a difference
    # the source is supposed to settle.
    $workflowExit = ($workflow[$id].Exit -replace '\s+', ' ').Trim()

    # The canonical table first. workflow.md calls the table canonical, so its row must agree
    # with the stage block it describes: same number, same name, same exit condition. Reading
    # only the blocks left the table free to drift, and the table is what most people read.
    $row = $stageTable[$i]
    $tableExit = ($row.Exit -replace '\s+', ' ').Trim()
    $expectedId = "$($row.Number)-$($row.Name.ToLowerInvariant())"
    if ($expectedId -cne $id) {
        Add-Difference "TABLE workflow.md:$($row.Line)  row $i reads '$($row.Number) $($row.Name)', which is stage id '$expectedId', but the block at that position is '$id'"
    }
    if ($workflow[$id].Number -ne $row.Number -or $workflow[$id].Name -cne $row.Name) {
        Add-Difference "TABLE workflow.md:$($workflow[$id].HeadingLine)  stage $id heading reads 'Stage $($workflow[$id].Number) — $($workflow[$id].Name)', the table row reads '$($row.Number) $($row.Name)'"
    }
    if ($tableExit -cne $workflowExit) {
        Add-Difference "TABLE workflow.md:$($row.Line)  stage $id exit condition differs between the table and the block`n   table: $tableExit`n   block ($workflowPath`:$($workflow[$id].ExitLine)): $workflowExit"
    }

    # The expected visible label comes from the canonical table, so a stage renamed there is
    # a difference in every rendered document until they are renamed too.
    $expectedLabel = "$($row.Number) $($row.Name)"

    $pairs = @(
        @{ Name = 'workflow.html'; Doc = $tree; Expect = @($workflow[$id].Edges.Keys) }
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
        if ($exit -cne $workflowExit) {
            Add-Difference "EXIT  $($pair.Name):$($node.ExitLine)  stage $id`n   source ($workflowPath`:$($workflow[$id].ExitLine)): $workflowExit`n   $($pair.Name): $exit"
        }

        $visibleExit = ($node.VisibleExit -replace '\s+', ' ').Trim()
        if ($visibleExit -cne $exit) {
            Add-Difference "VISIBLE $($pair.Name):$($node.ExitLine)  stage $id exit attribute and rendered text differ`n   attribute: $exit`n   rendered : $visibleExit"
        }

        # Compare the edge SETS before comparing values, and compare the names case-sensitively.
        # Iterating only the document's own edges means a deleted data-next simply vanishes
        # from the comparison and passes. Comparing names case-insensitively means 'Success'
        # answers for 'success', so the attribute matched the source while the badge beside it
        # read something else.
        $nodeEdgeNames = @($node.Edges.Keys)
        foreach ($edge in $pair.Expect) {
            if ($nodeEdgeNames -cnotcontains $edge) {
                Add-Difference "EDGE-MISSING $($pair.Name):$($node.Line)  stage $id has no '$edge' edge; the source has one"
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
            $workflowTarget = if ($workflow[$id].Edges.Contains($edge)) { $workflow[$id].Edges[$edge] } else { '<missing>' }
            if ($target -cne $workflowTarget) {
                Add-Difference "EDGE  $($pair.Name):$edgeLine  stage $id / $edge   source=$workflowTarget   $($pair.Name)=$target"
            }
            $visibleTarget = $node.VisibleEdges[$edge]
            if ($visibleTarget -cne $target) {
                Add-Difference "VISIBLE $($pair.Name):$edgeLine  stage $id edge '$edge' attribute and rendered text differ`n   attribute: $target`n   rendered : $visibleTarget"
            }
        }
    }

    foreach ($edge in @($workflow[$id].Edges.Keys)) {
        if (-not $legal.Contains($workflow[$id].Edges[$edge])) {
            Add-Difference "TARGET workflow.md:$($workflow[$id].EdgeLines[$edge])  stage $id edge '$edge' names '$($workflow[$id].Edges[$edge])', which is not a stage or a legal literal"
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

# What this line may claim is exactly what was compared. The PDF was never read as pages: the
# check proves both sidecars describe their files and the PDF carries this cheatsheet's digest.
# A PDF with the marker appended by hand and both sidecars refreshed passes, so 'current' is a
# claim this check cannot make.
'RESULT: the three process documents agree; the PDF matches both sidecars and carries this cheatsheet''s digest'
