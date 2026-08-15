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

# Normalized hashing must ignore line endings.
$tempLf = Join-Path ([System.IO.Path]::GetTempPath()) "canon-lf-$([guid]::NewGuid()).txt"
$tempCrLf = Join-Path ([System.IO.Path]::GetTempPath()) "canon-crlf-$([guid]::NewGuid()).txt"
[System.IO.File]::WriteAllText($tempLf, "a`nb`n")
[System.IO.File]::WriteAllText($tempCrLf, "a`r`nb`r`n")
Assert-True ((Get-NormalizedHash -Path $tempLf) -eq (Get-NormalizedHash -Path $tempCrLf)) 'hash: LF and CRLF must hash the same'
Remove-Item $tempLf, $tempCrLf -Force

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host ''; Write-Host $failure -ForegroundColor Red }
    Write-Host ''
    throw "Process canon parser tests failed with $($failures.Count) problem(s). See the detail above."
}

Write-Host 'Process canon parser tests passed.'
