#Requires -Version 7.0
<#
.SYNOPSIS
    Regenerates ahk-workflow.pdf from the cheatsheet and writes both hash sidecars.
.DESCRIPTION
    One command writes all three files, so they cannot be updated apart. That is what makes
    the freshness claim true: hashing the cheatsheet alone would pass when somebody edits the
    cheatsheet, refreshes the sidecar, and never regenerates the PDF.

    It needs a Chromium browser, so it runs locally. Only the checks run in CI.

    Two hashes together prove the three files were last written by this script. They do not
    prove the rendered PDF matches the cheatsheet; extracting text from a compressed PDF is
    deliberately out of scope.
#>
[CmdletBinding()]
param([string] $BrowserPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'process-canon.common.ps1')

$docs = Join-Path $repoRoot 'docs/development'
$sheet = Join-Path $docs 'ahkflow-workflow-cheatsheet.html'
$pdf = Join-Path $docs 'ahk-workflow.pdf'

$candidates = @(
    $BrowserPath
    'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'
    'C:/Program Files/Microsoft/Edge/Application/msedge.exe'
    'C:/Program Files/Google/Chrome/Application/chrome.exe'
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

if (-not $candidates) {
    throw 'No Chromium browser found. Pass -BrowserPath, or install Microsoft Edge. The existing PDF was produced by headless Edge.'
}
$browser = $candidates[0]

# Render to a temporary file, never over the committed PDF. Writing straight to $pdf makes
# every check below meaningless: if the browser writes nothing, Test-Path still sees the OLD
# PDF, and the script then records the NEW cheatsheet hash beside it. That is precisely the
# stale-PDF state the sidecars exist to prevent, blessed by the tool meant to prevent it.
$temp = Join-Path ([System.IO.Path]::GetTempPath()) "ahk-workflow-$([guid]::NewGuid()).pdf"

Write-Host "Rendering with: $browser"
& $browser --headless --disable-gpu --no-pdf-header-footer "--print-to-pdf=$temp" (([uri]$sheet).AbsoluteUri) | Out-Null
$browserExit = $LASTEXITCODE

try {
    if ($browserExit -ne 0) { throw "The browser exited with code $browserExit and wrote nothing usable." }
    if (-not (Test-Path -LiteralPath $temp)) { throw "The browser wrote no PDF to $temp" }

    $pdfBytes = [System.IO.File]::ReadAllBytes($temp)
    if ($pdfBytes.Length -eq 0) { throw 'The browser wrote an empty PDF.' }

    $pdfText = [System.Text.Encoding]::Latin1.GetString($pdfBytes)
    if ($pdfText -notmatch '^%PDF-') { throw 'The rendered file is not a PDF.' }
    if ($pdfText -notmatch '/Count\s+1\b') {
        throw 'The rendered PDF is not one page. Fix the cheatsheet layout before recording its hash.'
    }

    $sourceHash = Get-NormalizedHash -Path $sheet
    $pdfHash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($pdfBytes)).Replace('-', '')

    # Only now, with a validated render in hand, replace all three outputs.
    Copy-Item -LiteralPath $temp -Destination $pdf -Force
    Set-Content -LiteralPath (Join-Path $docs 'ahk-workflow.pdf.source.sha256') -Value $sourceHash -Encoding utf8 -NoNewline
    Set-Content -LiteralPath (Join-Path $docs 'ahk-workflow.pdf.sha256') -Value $pdfHash -Encoding utf8 -NoNewline

    Write-Host "cheatsheet: $sourceHash"
    Write-Host "pdf       : $pdfHash"
    'RESULT: PDF regenerated and both sidecars written'
}
finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
}
