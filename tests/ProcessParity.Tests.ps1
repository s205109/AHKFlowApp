#Requires -Version 7.0

# A parity check that has never been seen to fail is not known to work. Each case below
# breaks exactly one thing and asserts the check notices.
#
# Run it by hand with:  pwsh ./tests/ProcessParity.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$script = Join-Path $repoRoot 'scripts/check-process-parity.ps1'
$failures = @()

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { $script:failures += $Message }
}

function New-Fixture {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) "process-parity-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    foreach ($name in @('workflow.md', 'workflow.html', 'ahkflow-workflow-cheatsheet.html', 'ahk-workflow.pdf')) {
        Copy-Item -LiteralPath (Join-Path $repoRoot "docs/development/$name") -Destination (Join-Path $root $name)
    }
    # Both sidecars are GENERATED for the fixture, never copied. Copying them makes this
    # suite depend on Task 3 having already run, so the clean case would fail while Task 2
    # is being written - which is exactly backwards for a test-first task.
    . (Join-Path $repoRoot 'scripts/process-canon.common.ps1')
    $sourceHash = Get-NormalizedHash -Path (Join-Path $root 'ahkflow-workflow-cheatsheet.html')
    Set-Content -LiteralPath (Join-Path $root 'ahk-workflow.pdf.source.sha256') -Value $sourceHash -Encoding utf8 -NoNewline
    $pdfBytes = [System.IO.File]::ReadAllBytes((Join-Path $root 'ahk-workflow.pdf'))
    $pdfHash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($pdfBytes)).Replace('-', '')
    Set-Content -LiteralPath (Join-Path $root 'ahk-workflow.pdf.sha256') -Value $pdfHash -Encoding utf8 -NoNewline
    return $root
}

function Invoke-Check {
    param([string] $Root)
    $output = & pwsh -NoProfile -File $script -DocsRoot $Root 2>&1
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
}

# --- Case 1: the untouched tree passes ---
$clean = New-Fixture
$result = Invoke-Check -Root $clean
Assert-True ($result.ExitCode -eq 0) "clean tree should pass, got exit $($result.ExitCode):`n$($result.Output)"

# --- Case 2: an exit string drifts in the cheatsheet ---
$drift = New-Fixture
$path = Join-Path $drift 'ahkflow-workflow-cheatsheet.html'
(Get-Content -LiteralPath $path -Raw).Replace('data-exit="Item filed with the script, summary written, Difficulty set"', 'data-exit="Item filed, summary written"') |
    Set-Content -LiteralPath $path -NoNewline
$result = Invoke-Check -Root $drift
Assert-True ($result.ExitCode -eq 1) 'a drifted exit string must fail'
Assert-True ($result.Output -match 'cheatsheet') 'the message must name the losing file'

# --- Case 3: an edge target names a stage that does not exist ---
$bogus = New-Fixture
$path = Join-Path $bogus 'workflow.html'
(Get-Content -LiteralPath $path -Raw).Replace('data-next="success:1-pickup"', 'data-next="success:99-missing"') |
    Set-Content -LiteralPath $path -NoNewline
$result = Invoke-Check -Root $bogus
Assert-True ($result.ExitCode -eq 1) 'an unknown edge target must fail'
Assert-True ($result.Output -match '99-missing') 'the message must name the bad target'

# --- Case 4: ONLY the rendered text drifts; every attribute is untouched ---
$visible = New-Fixture
$path = Join-Path $visible 'workflow.html'
(Get-Content -LiteralPath $path -Raw).Replace('<b>Exit:</b> Item filed with the script, summary written, Difficulty set', '<b>Exit:</b> Item filed and that is all') |
    Set-Content -LiteralPath $path -NoNewline
$result = Invoke-Check -Root $visible
Assert-True ($result.ExitCode -eq 1) 'rendered text drifting alone must fail - this is the metadata-agrees case'

# --- Case 5: the cheatsheet changed but the PDF was not regenerated ---
$stale = New-Fixture
$path = Join-Path $stale 'ahkflow-workflow-cheatsheet.html'
Add-Content -LiteralPath $path -Value '<!-- edited -->'
$result = Invoke-Check -Root $stale
Assert-True ($result.ExitCode -eq 1) 'a stale PDF sidecar must fail'

# --- Case 6: line endings must not change the verdict ---
$crlf = New-Fixture
$path = Join-Path $crlf 'ahkflow-workflow-cheatsheet.html'
$text = (Get-Content -LiteralPath $path -Raw) -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($path, ($text -replace "`n", "`r`n"))
$result = Invoke-Check -Root $crlf
Assert-True ($result.ExitCode -eq 0) "CRLF must not change the verdict, got exit $($result.ExitCode):`n$($result.Output)"

# --- Case 7: a whole edge is deleted from the HTML ---
# Iterating only the document's own edges would let this vanish from the comparison entirely.
$dropped = New-Fixture
$path = Join-Path $dropped 'workflow.html'
$raw = Get-Content -LiteralPath $path -Raw
$li = [regex]::Match($raw, '<li[^>]*data-next="blocked:[^"]*".*?</li>', 'Singleline')
Assert-True ($li.Success) 'fixture setup: a blocked edge must exist to delete'
Set-Content -LiteralPath $path -Value ($raw.Remove($li.Index, $li.Length)) -NoNewline
$result = Invoke-Check -Root $dropped
Assert-True ($result.ExitCode -eq 1) 'a deleted edge must fail, not disappear from the comparison'
Assert-True ($result.Output -match 'EDGE-MISSING') 'the message must say the edge is missing'

# --- Case 8: the rendered stage label is changed ---
# VisibleStage was parsed but never compared in the first draft, so this passed.
$relabelled = New-Fixture
$path = Join-Path $relabelled 'workflow.html'
(Get-Content -LiteralPath $path -Raw).Replace('<span class="num">0</span>Intake', '<span class="num">0</span>Triage') |
    Set-Content -LiteralPath $path -NoNewline
$result = Invoke-Check -Root $relabelled
Assert-True ($result.ExitCode -eq 1) 'a renamed stage label must fail'
Assert-True ($result.Output -match 'LABEL') 'the message must name the label difference'

Remove-Item $clean, $drift, $bogus, $visible, $stale, $crlf, $dropped, $relabelled -Recurse -Force -ErrorAction SilentlyContinue

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host ''; Write-Host $failure -ForegroundColor Red }
    Write-Host ''
    throw "Process parity tests failed with $($failures.Count) problem(s). See the detail above."
}

Write-Host 'Process parity tests passed. 8 cases.'
