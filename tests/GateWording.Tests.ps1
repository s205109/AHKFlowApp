#Requires -Version 7.0

# This repository hard-wraps prose, so the banned phrase usually straddles a line break. A
# line-by-line scan finds nothing and reports the file clean. Case 2 is what proves the scan
# is whole-file.
#
# Run it by hand with:  pwsh ./tests/GateWording.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$script = Join-Path $repoRoot 'scripts/check-gate-wording.ps1'
$failures = @()

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { $script:failures += $Message }
}

function Invoke-Check {
    param([string] $Body)
    $root = Join-Path ([System.IO.Path]::GetTempPath()) "gate-wording-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $root 'DOC.md') -Value $Body -Encoding utf8
    $output = & pwsh -NoProfile -File $script -ScanRoot $root 2>&1
    $code = $LASTEXITCODE
    Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{ ExitCode = $code; Output = ($output -join "`n") }
}

# --- Case 1: the spelled-out noun must be caught ---
$result = Invoke-Check -Body "Run the gate before opening a pull request."
Assert-True ($result.ExitCode -eq 1) '"before opening a pull request" must fail'

# --- Case 2: a phrase wrapped across a line break must be caught ---
$result = Invoke-Check -Body "Read every rule that says before you`ncreate a PR and act on it."
Assert-True ($result.ExitCode -eq 1) 'a phrase split across a line break must fail'

# --- Case 3: the ignore marker allows a legitimate use ---
$result = Invoke-Check -Body "Read every rule that says before you create a PR as ready. <!-- gate-wording:ignore -->"
Assert-True ($result.ExitCode -eq 0) 'the ignore marker must allow the sentence that defines the rule'

# --- Case 3b: the marker works when the phrase WRAPS onto the marked line ---
# This is the shape in workflow.md itself: the match starts on one line and the marker sits
# on the next. A single-line window would miss it and the check would stay red forever.
$result = Invoke-Check -Body "Read every rule that says before you`ncreate a PR as ready. <!-- gate-wording:ignore -->"
Assert-True ($result.ExitCode -eq 0) 'the marker must be found on any line the wrapped match spans'

# --- Case 4: the gate's own name is not banned ---
$result = Invoke-Check -Body "Follow the canonical pre-PR gate in testing-workflow.md."
Assert-True ($result.ExitCode -eq 0) "'pre-PR gate' is the gate's own anchor name and must not fail"

# --- Case 5: correct wording passes ---
$result = Invoke-Check -Body "The gate must be green before you mark the pull request ready."
Assert-True ($result.ExitCode -eq 0) 'correct wording must pass'

# --- Case 6: the real repository passes ---
$live = & pwsh -NoProfile -File $script 2>&1
Assert-True ($LASTEXITCODE -eq 0) "the real repository must pass:`n$($live -join "`n")"

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host ''; Write-Host $failure -ForegroundColor Red }
    Write-Host ''
    throw "Gate wording tests failed with $($failures.Count) problem(s). See the detail above."
}

Write-Host 'Gate wording tests passed. 7 cases.'
