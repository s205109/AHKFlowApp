#Requires -Version 7.0

# One parser feeds every process check. If it silently extracts fewer stages, every check
# passes while proving nothing - the failure mode backlog 071 review round 7 found by hand.
#
# Run it by hand with:  pwsh ./tests/ProcessCanon.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts/process-canon.common.ps1')

$failures = @()
function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { $script:failures += $Message }
}

$canon = Get-CanonStage -Path (Join-Path $repoRoot 'docs/development/workflow.md')
Assert-True ($canon.Count -eq 11) "canon: expected 11 stages, got $($canon.Count)"
Assert-True ($canon.Contains('0-intake')) 'canon: 0-intake missing'
Assert-True ($canon['0-intake'].Edges.Count -eq 5) 'canon: 0-intake should have 5 edges'
Assert-True ($canon['0-intake'].Edges['success'] -ceq '1-pickup') 'canon: 0-intake success should target 1-pickup'

$tree = Get-HtmlStage -Path (Join-Path $repoRoot 'docs/development/workflow.html')
Assert-True ($tree.Count -eq 11) "workflow.html: expected 11 stages, got $($tree.Count)"
Assert-True ($tree['0-intake'].Edges.Count -eq 5) 'workflow.html: 0-intake should have 5 edges'

$sheet = Get-HtmlStage -Path (Join-Path $repoRoot 'docs/development/ahkflow-workflow-cheatsheet.html')
Assert-True ($sheet.Count -eq 11) "cheatsheet: expected 11 stages, got $($sheet.Count)"
Assert-True ($sheet['0-intake'].Edges.Count -eq 2) 'cheatsheet: 0-intake should carry success and failure only'

# The cheatsheet writes the Difficulty split with two <wbr> tags inside it. A tag-to-space
# strip turns that cell into '2-design/ 3-plan/ 4-execute' and fails a correct cell.
Assert-True ($sheet['1-pickup'].VisibleEdges['success'] -ceq '2-design/3-plan/4-execute') "cheatsheet: the wbr tags must vanish, got '$($sheet['1-pickup'].VisibleEdges['success'])'"

# The visible text must come back decoded and tag-free, or the parity check compares markup.
Assert-True ($tree['0-intake'].VisibleEdges['success'] -ceq '1-pickup') 'workflow.html: visible success target should decode to 1-pickup'
Assert-True ($tree['0-intake'].VisibleStage -ceq '0 Intake') "workflow.html: visible stage should be '0 Intake', got '$($tree['0-intake'].VisibleStage)'"

# A duplicate edge row must be reported, not silently overwritten. The original checker
# guarded this; sharing the parser must not drop it.
foreach ($id in $canon.Keys) {
    Assert-True ($canon[$id].Duplicates.Count -eq 0) "canon/${id}: unexpected duplicate edge rows: $($canon[$id].Duplicates -join ', ')"
}
$dupeFile = Join-Path ([System.IO.Path]::GetTempPath()) "canon-dupe-$([guid]::NewGuid()).md"
@'
<a id="stage-0-intake"></a>

- **Exit** — Something

| Edge | Condition | Target |
|---|---|---|
| success | first row | 1-pickup |
| success | second row wins today | 9-ship |
| failure | x | stay |
| blocked | x | blocked/ |
| not applicable | x | 1-pickup |
| resume | x | stay |
'@ | Set-Content -LiteralPath $dupeFile -Encoding utf8
$dupe = Get-CanonStage -Path $dupeFile
Assert-True ($dupe['0-intake'].Duplicates.Count -eq 1) 'a duplicate edge row must be recorded'
Assert-True ($dupe['0-intake'].Edges['success'] -ceq '1-pickup') 'the first row must win, so the duplicate is visible rather than silently replacing it'
Remove-Item $dupeFile -Force

# A repeated stage id must be counted, never overwritten. Assigning by key hid a second
# 0-intake block: the dictionary still held 11 keys and every comparison passed.
$twinFile = Join-Path ([System.IO.Path]::GetTempPath()) "canon-twin-$([guid]::NewGuid()).md"
@'
<a id="stage-0-intake"></a>

- **Exit** — First block

| Edge | Condition | Target |
|---|---|---|
| success | x | 1-pickup |

<a id="stage-0-intake"></a>

- **Exit** — Second block

| Edge | Condition | Target |
|---|---|---|
| success | x | 9-ship |
'@ | Set-Content -LiteralPath $twinFile -Encoding utf8
$twin = Get-CanonStage -Path $twinFile
Assert-True ($twin.Count -eq 1) "a repeated stage id must not add a key, got $($twin.Count)"
Assert-True ($twin['0-intake'].Occurrences -eq 2) "a repeated stage id must be counted, got $($twin['0-intake'].Occurrences)"
Assert-True ($twin['0-intake'].Exit -ceq 'First block') 'the first block must win, so the repeat is visible rather than replacing it'
Remove-Item $twinFile -Force

foreach ($id in $canon.Keys) {
    Assert-True ($canon[$id].Occurrences -eq 1) "canon/${id}: stage id appears $($canon[$id].Occurrences) times"
}
foreach ($id in $tree.Keys) {
    Assert-True ($tree[$id].Occurrences -eq 1) "workflow.html/${id}: stage id appears $($tree[$id].Occurrences) times"
}

# Edge names are case-sensitive. A case-insensitive dictionary reads 'Success' as 'success',
# so a drifted attribute matched the canon and the check passed.
$caseFile = Join-Path ([System.IO.Path]::GetTempPath()) "canon-case-$([guid]::NewGuid()).html"
@'
<section data-stage="0-intake">
  <summary><span class="num">0</span>Intake</summary>
  <p class="field" data-exit="Something"><b>Exit:</b> Something</p>
  <ul class="edges">
    <li data-next="Success:1-pickup">a <span class="target">&rarr; 1-pickup</span></li>
  </ul>
</section>
'@ | Set-Content -LiteralPath $caseFile -Encoding utf8
$cased = Get-HtmlStage -Path $caseFile
Assert-True ($cased['0-intake'].Edges.Contains('Success')) 'the parser must keep the edge name as written'
Assert-True (-not $cased['0-intake'].Edges.Contains('success')) "an edge dictionary must be case-sensitive, so 'success' must not find 'Success'"
Remove-Item $caseFile -Force

# Every value carries its own line, so a message names the line that is actually wrong
# rather than the line the stage starts on.
$canonLines = [System.IO.File]::ReadAllLines((Join-Path $repoRoot 'docs/development/workflow.md'))
$exitLine = $canon['0-intake'].ExitLine
Assert-True ($canonLines[$exitLine - 1] -match '^\- \*\*Exit\*\*') "canon: ExitLine $exitLine should name the Exit line, holds '$($canonLines[$exitLine - 1])'"
$edgeLine = $canon['0-intake'].EdgeLines['success']
Assert-True ($canonLines[$edgeLine - 1] -match '^\| success \|') "canon: EdgeLines[success] $edgeLine should name that row, holds '$($canonLines[$edgeLine - 1])'"

$treeLines = [System.IO.File]::ReadAllLines((Join-Path $repoRoot 'docs/development/workflow.html'))
$treeEdgeLine = $tree['0-intake'].EdgeLines['success']
Assert-True ($treeLines[$treeEdgeLine - 1] -match 'data-next="success:') "workflow.html: EdgeLines[success] $treeEdgeLine should name that element, holds '$($treeLines[$treeEdgeLine - 1])'"
$treeExitLine = $tree['0-intake'].ExitLine
Assert-True ($treeLines[$treeExitLine - 1] -match 'data-exit=') "workflow.html: ExitLine $treeExitLine should name the exit element, holds '$($treeLines[$treeExitLine - 1])'"

# Normalized hashing must ignore line endings.
$tempLf = Join-Path ([System.IO.Path]::GetTempPath()) "canon-lf-$([guid]::NewGuid()).txt"
$tempCrLf = Join-Path ([System.IO.Path]::GetTempPath()) "canon-crlf-$([guid]::NewGuid()).txt"
[System.IO.File]::WriteAllText($tempLf, "a`nb`n")
[System.IO.File]::WriteAllText($tempCrLf, "a`r`nb`r`n")
Assert-True ((Get-NormalizedHash -Path $tempLf) -eq (Get-NormalizedHash -Path $tempCrLf)) 'hash: LF and CRLF must hash the same'
Remove-Item $tempLf, $tempCrLf -Force

# The PDF carries the digest of the cheatsheet it was rendered from. A PDF writer may store
# that string as plain bytes or as UTF-16, so both forms must be found.
$digest = 'ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789'
$plain = [System.Text.Encoding]::Latin1.GetBytes("junk /Title (AHKFLOW-SOURCE-SHA256:$digest) junk")
Assert-True (Test-PdfSourceDigest -Bytes $plain -Digest $digest) 'a digest stored as plain bytes must be found'
$wide = [System.Text.Encoding]::BigEndianUnicode.GetBytes("AHKFLOW-SOURCE-SHA256:$digest")
Assert-True (Test-PdfSourceDigest -Bytes $wide -Digest $digest) 'a digest stored as UTF-16 must be found'
$other = [System.Text.Encoding]::Latin1.GetBytes('AHKFLOW-SOURCE-SHA256:0000000000000000000000000000000000000000000000000000000000000000')
Assert-True (-not (Test-PdfSourceDigest -Bytes $other -Digest $digest)) 'a different digest must not be found'

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host ''; Write-Host $failure -ForegroundColor Red }
    Write-Host ''
    throw "Process canon parser tests failed with $($failures.Count) problem(s). See the detail above."
}

Write-Host 'Process canon parser tests passed.'
