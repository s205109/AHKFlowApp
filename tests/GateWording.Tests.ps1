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
    param([string] $Body, [string] $RelativePath = 'DOC.md')
    $root = Join-Path ([System.IO.Path]::GetTempPath()) "gate-wording-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $target = Join-Path $root $RelativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Set-Content -LiteralPath $target -Value $Body -Encoding utf8
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

# --- Case 7: the passive form must be caught ---
# The pattern read verb-then-noun only, so the same claim written the other way round passed.
$result = Invoke-Check -Body "Run the gate before a pull request is opened."
Assert-True ($result.ExitCode -eq 1) 'the passive "before a pull request is opened" must fail'
$result = Invoke-Check -Body "The gate runs before the PR is created."
Assert-True ($result.ExitCode -eq 1) 'the passive "before the PR is created" must fail'

# --- Case 8: an unrelated word starting with 'pr' is not a pull request ---
# 'PR' matched the first two letters of 'profile', so an ordinary sentence failed the check.
$result = Invoke-Check -Body "Validate the name before creating a profile."
Assert-True ($result.ExitCode -eq 0) "'profile' must not read as 'PR':`n$($result.Output)"
$result = Invoke-Check -Body "Read the notes before opening a preview build."
Assert-True ($result.ExitCode -eq 0) "'preview' must not read as 'PR':`n$($result.Output)"

# --- Case 9: a marker on the NEXT line does not excuse a violation ---
# The window ran one line too far, so a marker outside the match silenced it.
$result = Invoke-Check -Body "Run the gate before opening a pull request.`n<!-- gate-wording:ignore -->"
Assert-True ($result.ExitCode -eq 1) 'a marker on a later line must not suppress a violation'

# --- Case 10: a blocked item is active work and is scanned ---
# backlog/blocked holds items waiting on an external prerequisite, so the wording rule applies
# to them. Only backlog/done is a finished record.
$result = Invoke-Check -Body "Run the gate before opening a pull request." -RelativePath 'backlog/blocked/099-x.md'
Assert-True ($result.ExitCode -eq 1) 'a blocked item is active work and must be scanned'
$result = Invoke-Check -Body "Run the gate before opening a pull request." -RelativePath 'backlog/done/099-x.md'
Assert-True ($result.ExitCode -eq 0) 'a finished item is a frozen record and stays out of scope'

# --- Case 11: the subject does not decide the verdict ---
# The pattern listed three subjects - you, anyone, the session - so the same claim about any
# other subject passed. The claim is about when the gate runs, not about who runs it.
foreach ($body in @(
        'Run the gate before we open a PR.'
        'The gate runs before the agent opens a pull request.'
        'Everything must be green before a reviewer creates the PR.'
        # Four words, and a word with a digit: three alphabetic words was still a shape rule.
        'The gate runs before the automated review agent opens a PR.'
        'Run it before agent 2 opens a pull request.'
    )) {
    $result = Invoke-Check -Body $body
    Assert-True ($result.ExitCode -eq 1) "the timing claim must fail whoever the subject is: '$body'"
}

# --- Case 12: only the directive suppresses, never the words ---
# The window was searched for the bare substring, so a sentence that merely names the marker
# silenced a real violation beside it.
$result = Invoke-Check -Body "Run the gate before opening a pull request. Add gate-wording:ignore to allow a line."
Assert-True ($result.ExitCode -eq 1) 'the bare words must not suppress a violation; only the HTML comment does'

# --- Case 6: the real repository passes ---
$live = & pwsh -NoProfile -File $script 2>&1
Assert-True ($LASTEXITCODE -eq 0) "the real repository must pass:`n$($live -join "`n")"

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host ''; Write-Host $failure -ForegroundColor Red }
    Write-Host ''
    throw "Gate wording tests failed with $($failures.Count) problem(s). See the detail above."
}

Write-Host 'Gate wording tests passed. 21 cases.'
