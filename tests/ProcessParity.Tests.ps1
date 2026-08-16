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
    . (Join-Path $repoRoot 'scripts/process-workflow.common.ps1')
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

# A mutation that silently matches nothing turns a case into a second clean run that proves
# nothing. This helper requires exactly one replacement.
function Replace-Required {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $From,
        [Parameter(Mandatory)][string] $To
    )
    $raw = Get-Content -LiteralPath $Path -Raw
    $count = ([regex]::Matches($raw, [regex]::Escape($From))).Count
    if ($count -ne 1) { throw "fixture setup: '$From' appears $count time(s) in $Path, expected exactly 1" }
    Set-Content -LiteralPath $Path -Value ($raw.Replace($From, $To)) -NoNewline
}

# --- Case 1: the untouched tree passes ---
$clean = New-Fixture
$result = Invoke-Check -Root $clean
Assert-True ($result.ExitCode -eq 0) "clean tree should pass, got exit $($result.ExitCode):`n$($result.Output)"

# --- Case 2: an exit string drifts in the cheatsheet ---
$drift = New-Fixture
$path = Join-Path $drift 'ahkflow-workflow-cheatsheet.html'
Replace-Required -Path $path -From 'data-exit="Item filed with the script, summary written, Difficulty set"' -To 'data-exit="Item filed, summary written"'
$result = Invoke-Check -Root $drift
Assert-True ($result.ExitCode -eq 1) 'a drifted exit string must fail'
Assert-True ($result.Output -match 'cheatsheet') 'the message must name the losing file'

# --- Case 3: an edge target names a stage that does not exist ---
$bogus = New-Fixture
$path = Join-Path $bogus 'workflow.html'
Replace-Required -Path $path -From 'data-next="success:1-pickup"' -To 'data-next="success:99-missing"'
$result = Invoke-Check -Root $bogus
Assert-True ($result.ExitCode -eq 1) 'an unknown edge target must fail'
Assert-True ($result.Output -match '99-missing') 'the message must name the bad target'

# --- Case 4: ONLY the rendered text drifts; every attribute is untouched ---
$visible = New-Fixture
$path = Join-Path $visible 'workflow.html'
Replace-Required -Path $path -From '<b>Exit:</b> Item filed with the script, summary written, Difficulty set' -To '<b>Exit:</b> Item filed and that is all'
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
Replace-Required -Path $path -From '<span class="num">0</span>Intake' -To '<span class="num">0</span>Triage'
$result = Invoke-Check -Root $relabelled
Assert-True ($result.ExitCode -eq 1) 'a renamed stage label must fail'
Assert-True ($result.Output -match 'LABEL') 'the message must name the label difference'

# --- Case 9: a stage id appears twice ---
# The parser assigned by key, so a second block replaced the first and the count still read
# 11. The document held 12 stage blocks and the check compared 11 of them.
$twin = New-Fixture
$path = Join-Path $twin 'workflow.md'
$raw = Get-Content -LiteralPath $path -Raw
$block = [regex]::Match($raw, '<a id="stage-0-intake"></a>.*?(?=<a id="stage-1-pickup"></a>)', 'Singleline')
Assert-True ($block.Success) 'fixture setup: the 0-intake block must be findable'
Set-Content -LiteralPath $path -Value ($raw + "`n" + $block.Value) -NoNewline
$result = Invoke-Check -Root $twin
Assert-True ($result.ExitCode -eq 1) 'a repeated stage id must fail'
Assert-True ($result.Output -match 'REPEATED|repeat') 'the message must say the stage id repeats'

# --- Case 10: an edge name changes case only ---
# A case-insensitive dictionary read 'Success' as 'success', so the attribute agreed with the
# source and the badge beside it did not.
$cased = New-Fixture
$path = Join-Path $cased 'workflow.html'
Replace-Required -Path $path -From 'data-next="success:1-pickup"' -To 'data-next="Success:1-pickup"'
$result = Invoke-Check -Root $cased
Assert-True ($result.ExitCode -eq 1) "an edge name that differs only in case must fail"

# --- Case 11: a trailing period is added to an exit string ---
# The check trimmed a trailing period from both sides, so this drift passed while the
# requirement says any disagreement fails.
$punctuated = New-Fixture
$path = Join-Path $punctuated 'ahkflow-workflow-cheatsheet.html'
Replace-Required -Path $path -From 'data-exit="Item filed with the script, summary written, Difficulty set"' -To 'data-exit="Item filed with the script, summary written, Difficulty set."'
$result = Invoke-Check -Root $punctuated
Assert-True ($result.ExitCode -eq 1) 'an added period must fail'

# --- Case 12: an input file is missing ---
# Reading before validating threw an unhandled error and printed no RESULT: line, so a
# caller could not tell a missing file from a crash.
$incomplete = New-Fixture
Remove-Item -LiteralPath (Join-Path $incomplete 'ahk-workflow.pdf.source.sha256') -Force
$result = Invoke-Check -Root $incomplete
Assert-True ($result.ExitCode -eq 1) 'a missing input must fail'
Assert-True ($result.Output -match 'RESULT:') 'a missing input must still print a RESULT: line'
Assert-True ($result.Output -notmatch 'Exception|Cannot find path') "a missing input must be reported, not thrown:`n$($result.Output)"

# --- Case 13: the cheatsheet changed and only its sidecar was refreshed ---
# Two hash pairs alone cannot see this: both pairs agree, and the PDF is still the old one.
$handRefreshed = New-Fixture
$path = Join-Path $handRefreshed 'ahkflow-workflow-cheatsheet.html'
Add-Content -LiteralPath $path -Value '<!-- edited -->'
. (Join-Path $repoRoot 'scripts/process-workflow.common.ps1')
Set-Content -LiteralPath (Join-Path $handRefreshed 'ahk-workflow.pdf.source.sha256') -Value (Get-NormalizedHash -Path $path) -Encoding utf8 -NoNewline
$result = Invoke-Check -Root $handRefreshed
Assert-True ($result.ExitCode -eq 1) 'a hand-refreshed sidecar must not make a stale PDF look current'
Assert-True ($result.Output -match 'digest') 'the message must name the digest inside the PDF'

# --- Case 14: the PDF is replaced by a file that merely looks like one ---
$notAPdf = New-Fixture
$path = Join-Path $notAPdf 'ahk-workflow.pdf'
[System.IO.File]::WriteAllText($path, "not a pdf /Count 1")
$bytes = [System.IO.File]::ReadAllBytes($path)
Set-Content -LiteralPath (Join-Path $notAPdf 'ahk-workflow.pdf.sha256') -Value ([System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($bytes)).Replace('-', '')) -Encoding utf8 -NoNewline
$result = Invoke-Check -Root $notAPdf
Assert-True ($result.ExitCode -eq 1) 'a file that is not a PDF must fail even when its sidecar matches'

Remove-Item $clean, $drift, $bogus, $visible, $stale, $crlf, $dropped, $relabelled, $twin, $cased, $punctuated, $incomplete, $handRefreshed, $notAPdf -Recurse -Force -ErrorAction SilentlyContinue

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host ''; Write-Host $failure -ForegroundColor Red }
    Write-Host ''
    throw "Process parity tests failed with $($failures.Count) problem(s). See the detail above."
}

Write-Host 'Process parity tests passed. 14 cases.'
