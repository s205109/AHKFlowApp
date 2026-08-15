#Requires -Version 7.0

# The sidecars are the whole point: they prove the PDF and the cheatsheet were last written
# together. This suite checks they still match. It never runs the generator, which needs a
# browser the CI runner should not depend on.
#
# Run it by hand with:  pwsh ./tests/WorkflowPdfGenerator.Tests.ps1

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

$docs = Join-Path $repoRoot 'docs/development'
$generator = Join-Path $repoRoot 'scripts/update-workflow-pdf.ps1'

Assert-True (Test-Path -LiteralPath $generator) 'the generator script must exist'

$sourceSidecar = Join-Path $docs 'ahk-workflow.pdf.source.sha256'
$pdfSidecar = Join-Path $docs 'ahk-workflow.pdf.sha256'
Assert-True (Test-Path -LiteralPath $pdfSidecar) 'the PDF sidecar must exist'

if (Test-Path -LiteralPath $pdfSidecar) {
    $expected = (Get-NormalizedHash -Path (Join-Path $docs 'ahkflow-workflow-cheatsheet.html'))
    Assert-True ($expected -eq (Get-Content -LiteralPath $sourceSidecar -Raw).Trim()) 'the source sidecar must match the cheatsheet'

    $pdfBytes = [System.IO.File]::ReadAllBytes((Join-Path $docs 'ahk-workflow.pdf'))
    $pdfHash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($pdfBytes)).Replace('-', '')
    Assert-True ($pdfHash -eq (Get-Content -LiteralPath $pdfSidecar -Raw).Trim()) 'the PDF sidecar must match the PDF'
}

# The generator must fail loudly when no browser is present, never write a partial result.
$content = Get-Content -LiteralPath $generator -Raw
Assert-True ($content -match 'throw') 'the generator must throw when it cannot find a browser'

# It must render to a temporary file and validate before replacing anything. Rendering
# straight onto the committed PDF means a failed render leaves the OLD pdf in place while the
# NEW cheatsheet hash is written beside it - the exact stale state the sidecars exist to stop.
Assert-True ($content -match 'print-to-pdf=\$temp') 'the generator must render to a temporary file, never over the committed PDF'
Assert-True ($content -match '\$browserExit') 'the generator must check the browser exit code'
Assert-True ($content -notmatch 'print-to-pdf=\$pdf') 'the generator must not render directly onto the committed PDF'

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host ''; Write-Host $failure -ForegroundColor Red }
    Write-Host ''
    throw "Workflow PDF generator tests failed with $($failures.Count) problem(s). See the detail above."
}

Write-Host 'Workflow PDF generator tests passed.'
