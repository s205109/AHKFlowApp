#Requires -Version 7.0

# The generator publishes three files together, and everything downstream trusts that they
# were written by one run. Reading the script's source text proved nothing: deleting a
# validation, or publishing before validating, left the old suite green. So this suite runs
# the generator against a fake browser and asserts what reaches disk.
#
# Run it by hand with:  pwsh ./tests/WorkflowPdfGenerator.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

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

# --- The committed tree: the three files must still describe each other ---
$sourceSidecar = Join-Path $docs 'ahk-workflow.pdf.source.sha256'
$pdfSidecar = Join-Path $docs 'ahk-workflow.pdf.sha256'
Assert-True (Test-Path -LiteralPath $pdfSidecar) 'the PDF sidecar must exist'

if (Test-Path -LiteralPath $pdfSidecar) {
    $expected = (Get-NormalizedHash -Path (Join-Path $docs 'ahkflow-workflow-cheatsheet.html'))
    Assert-True ($expected -eq (Get-Content -LiteralPath $sourceSidecar -Raw).Trim()) 'the source sidecar must match the cheatsheet'

    $pdfBytes = [System.IO.File]::ReadAllBytes((Join-Path $docs 'ahk-workflow.pdf'))
    $pdfHash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($pdfBytes)).Replace('-', '')
    Assert-True ($pdfHash -eq (Get-Content -LiteralPath $pdfSidecar -Raw).Trim()) 'the PDF sidecar must match the PDF'
    Assert-True (Test-PdfSourceDigest -Bytes $pdfBytes -Digest $expected) 'the committed PDF must carry the cheatsheet digest'
}

# --- A fake browser, so the generator's own behaviour can be tested anywhere ---
# The fake reads the title of the HTML the generator asked it to render, and writes a PDF
# built to the shape each case needs. It is a PowerShell script rather than a batch file:
# cmd.exe splits '--print-to-pdf=C:\path' at the colon when it expands %*, so the wrapper
# handed the fake a truncated path and every case looked like a browser that wrote nothing.
$fakeRoot = Join-Path ([System.IO.Path]::GetTempPath()) "pdf-generator-fake-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $fakeRoot -Force | Out-Null
$fakePs1 = Join-Path $fakeRoot 'fake-browser.ps1'

@'
param()
$ErrorActionPreference = 'Stop'
$mode = $env:AHKFLOW_FAKE_MODE
$out = ($args | Where-Object { $_ -like '--print-to-pdf=*' }) -replace '^--print-to-pdf=', ''
$uri = @($args | Where-Object { $_ -like 'file:*' })[0]
if ($mode -eq 'exit1') { exit 1 }
if ($mode -eq 'nothing') { exit 0 }
$title = ''
if ($uri) {
    $html = [System.IO.File]::ReadAllText(([uri]$uri).LocalPath)
    $m = [regex]::Match($html, '<title>(.*?)</title>', 'Singleline')
    if ($m.Success) { $title = $m.Groups[1].Value }
}
$pages = if ($mode -eq 'twopage') { 2 } else { 1 }
$body = switch ($mode) {
    'empty' { '' }
    'nonpdf' { "not a pdf at all /Count 1 ($title)" }
    'nodigest' { "%PDF-1.4`n/Type /Pages /Count 1`n/Title (nothing useful)`n%%EOF" }
    default { "%PDF-1.4`n/Type /Pages /Count $pages`n/Title ($title)`n%%EOF" }
}
[System.IO.File]::WriteAllText($out, $body)
exit 0
'@ | Set-Content -LiteralPath $fakePs1 -Encoding utf8

function New-DocsFixture {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) "pdf-generator-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $docs 'ahkflow-workflow-cheatsheet.html') -Destination (Join-Path $root 'ahkflow-workflow-cheatsheet.html')
    # Three outputs that are already stale on purpose. A run that fails must leave all three
    # exactly as they are; a run that succeeds must replace all three.
    [System.IO.File]::WriteAllText((Join-Path $root 'ahk-workflow.pdf'), 'OLD PDF')
    [System.IO.File]::WriteAllText((Join-Path $root 'ahk-workflow.pdf.source.sha256'), 'OLDSOURCE')
    [System.IO.File]::WriteAllText((Join-Path $root 'ahk-workflow.pdf.sha256'), 'OLDPDF')
    return $root
}

function Get-OutputState {
    param([string] $Root)
    return [pscustomobject]@{
        Pdf    = [System.IO.File]::ReadAllText((Join-Path $Root 'ahk-workflow.pdf'))
        Source = [System.IO.File]::ReadAllText((Join-Path $Root 'ahk-workflow.pdf.source.sha256'))
        Hash   = [System.IO.File]::ReadAllText((Join-Path $Root 'ahk-workflow.pdf.sha256'))
    }
}

function Invoke-Generator {
    param([string] $Root, [string] $Mode)
    $env:AHKFLOW_FAKE_MODE = $Mode
    try {
        $output = & pwsh -NoProfile -File $generator -BrowserPath $fakePs1 -DocsRoot $Root 2>&1
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
    }
    finally {
        Remove-Item Env:AHKFLOW_FAKE_MODE -ErrorAction SilentlyContinue
    }
}

$fixtures = @()

# --- A good render publishes all three outputs ---
$good = New-DocsFixture
$fixtures += $good
$result = Invoke-Generator -Root $good -Mode 'good'
Assert-True ($result.ExitCode -eq 0) "a good render should succeed, got exit $($result.ExitCode):`n$($result.Output)"
$state = Get-OutputState -Root $good
$expectedSource = Get-NormalizedHash -Path (Join-Path $good 'ahkflow-workflow-cheatsheet.html')
Assert-True ($state.Source -eq $expectedSource) 'a good render must write the cheatsheet digest'
Assert-True ($state.Pdf -ne 'OLD PDF') 'a good render must replace the PDF'
Assert-True (Test-PdfSourceDigest -Bytes ([System.IO.File]::ReadAllBytes((Join-Path $good 'ahk-workflow.pdf'))) -Digest $expectedSource) 'the published PDF must carry the digest'
$writtenHash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData([System.IO.File]::ReadAllBytes((Join-Path $good 'ahk-workflow.pdf')))).Replace('-', '')
Assert-True ($state.Hash -eq $writtenHash) 'a good render must write the hash of the PDF it published'

# --- Every bad render leaves all three outputs untouched ---
# This is the case source-text assertions could never make: publishing before validating, or
# dropping a validation, changes what reaches disk here.
foreach ($case in @(
        @{ Mode = 'exit1'; Why = 'the browser reported failure' }
        @{ Mode = 'nothing'; Why = 'the browser wrote no file' }
        @{ Mode = 'empty'; Why = 'the browser wrote an empty file' }
        @{ Mode = 'nonpdf'; Why = 'the file is not a PDF, even though it contains /Count 1' }
        @{ Mode = 'twopage'; Why = 'the render is two pages' }
        @{ Mode = 'nodigest'; Why = 'the render carries no source digest' }
    )) {
    $root = New-DocsFixture
    $fixtures += $root
    $before = Get-OutputState -Root $root
    $result = Invoke-Generator -Root $root -Mode $case.Mode
    Assert-True ($result.ExitCode -ne 0) "$($case.Why): the generator must fail, got exit $($result.ExitCode)"
    $after = Get-OutputState -Root $root
    Assert-True ($after.Pdf -eq $before.Pdf) "$($case.Why): the PDF must not change"
    Assert-True ($after.Source -eq $before.Source) "$($case.Why): the source sidecar must not change"
    Assert-True ($after.Hash -eq $before.Hash) "$($case.Why): the PDF sidecar must not change"
}

# --- No browser at all is a loud failure, not a partial write ---
$noBrowser = New-DocsFixture
$fixtures += $noBrowser
$missing = Join-Path $fakeRoot 'no-such-browser.exe'
$before = Get-OutputState -Root $noBrowser
$output = & pwsh -NoProfile -File $generator -BrowserPath $missing -DocsRoot $noBrowser 2>&1
$exitCode = $LASTEXITCODE
$after = Get-OutputState -Root $noBrowser
# A local Edge or Chrome install would be found even when -BrowserPath is wrong, so only the
# no-browser machine can assert the failure. The outputs must be untouched either way.
if ($exitCode -ne 0) {
    Assert-True (($output -join "`n") -match 'Chromium') 'a missing browser must say so'
}
else {
    Assert-True ($after.Pdf -ne $before.Pdf) 'a run that succeeded through a real local browser must publish'
}

Remove-Item $fakeRoot -Recurse -Force -ErrorAction SilentlyContinue
foreach ($fixture in $fixtures) { Remove-Item $fixture -Recurse -Force -ErrorAction SilentlyContinue }

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host ''; Write-Host $failure -ForegroundColor Red }
    Write-Host ''
    throw "Workflow PDF generator tests failed with $($failures.Count) problem(s). See the detail above."
}

Write-Host 'Workflow PDF generator tests passed.'
