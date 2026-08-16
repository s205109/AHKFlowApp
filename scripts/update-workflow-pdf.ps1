#Requires -Version 7.0
<#
.SYNOPSIS
    Regenerates ahk-workflow.pdf from the cheatsheet and writes both hash sidecars.
.DESCRIPTION
    One command writes all three files, so they cannot be updated apart. That is what makes
    the freshness claim true: hashing the cheatsheet alone would pass when somebody edits the
    cheatsheet, refreshes the sidecar, and never regenerates the PDF.

    It needs a Chromium browser, so it runs locally. Only the checks run in CI.

    Two hashes alone would only prove the three files were written together, and a person can
    refresh a sidecar by hand. So the render also carries the cheatsheet's digest inside the
    PDF: the script renders a copy of the cheatsheet whose title holds the digest, and reads
    the digest back out of the finished PDF before it publishes anything. The check reads the
    same digest, which is what ties the PDF to one cheatsheet rather than to a sidecar.

    It still does not prove the rendered pages show the cheatsheet's contents; extracting text
    from a compressed PDF is deliberately out of scope.
.PARAMETER BrowserPath
    The Chromium browser to render with. Defaults to a local Edge or Chrome install.
.PARAMETER DocsRoot
    The folder holding the documents. Defaults to docs/development.
#>
[CmdletBinding()]
param(
    [string] $BrowserPath,
    [string] $DocsRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'process-workflow.common.ps1')

if (-not $DocsRoot) { $DocsRoot = Join-Path $repoRoot 'docs/development' }
$docs = $DocsRoot
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

# The source digest travels inside the PDF, through the title of a rendered copy. The
# cheatsheet on disk is never touched: the copy exists only for this render. The title is not
# printed, because the render passes --no-pdf-header-footer.
$sourceHash = Get-NormalizedHash -Path $sheet
$marker = Get-PdfSourceDigestMarker -Digest $sourceHash
$sheetText = Get-NormalizedText -Path $sheet
$patched = [regex]::Replace($sheetText, '<title>.*?</title>', "<title>$marker</title>", 'Singleline')
if ($patched -eq $sheetText) {
    throw "The cheatsheet has no <title> element to carry the source digest: $sheet"
}
$tempHtml = Join-Path ([System.IO.Path]::GetTempPath()) "ahk-workflow-$([guid]::NewGuid()).html"
[System.IO.File]::WriteAllText($tempHtml, $patched)

Write-Host "Rendering with: $browser"
& $browser --headless --disable-gpu --no-pdf-header-footer "--print-to-pdf=$temp" (([uri]$tempHtml).AbsoluteUri) | Out-Null
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
    # Read the digest back out. Without this the claim rests on the browser having stored the
    # title, and a browser that drops it would publish a PDF the check can never tie to a
    # cheatsheet.
    if (-not (Test-PdfSourceDigest -Bytes $pdfBytes -Digest $sourceHash)) {
        throw "The rendered PDF does not carry the source digest $sourceHash. Nothing was published."
    }

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
    Remove-Item -LiteralPath $tempHtml -Force -ErrorAction SilentlyContinue
}
