#Requires -Version 7.0

# The check must fail closed. Its first draft stopped at the next heading of any level, so a
# new sub-heading would have hidden every rule under it. Case 3 is what proves that is fixed.
#
# Run it by hand with:  pwsh ./tests/ProcessAnchors.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$script = Join-Path $repoRoot 'scripts/check-process-anchors.ps1'
$failures = @()

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { $script:failures += $Message }
}

function New-Fixture {
    param([string] $Body)
    $root = Join-Path ([System.IO.Path]::GetTempPath()) "process-anchors-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot 'docs/development/workflow.md') -Destination (Join-Path $root 'workflow.md')
    Set-Content -LiteralPath (Join-Path $root 'SCANNED.md') -Value $Body -Encoding utf8
    return $root
}

function Invoke-Check {
    param([string] $Root)
    $output = & pwsh -NoProfile -File $script -WorkflowPath (Join-Path $Root 'workflow.md') -ScanFile (Join-Path $Root 'SCANNED.md') -Section 'Git Workflow' 2>&1
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
}

$anchor = 'see [workflow.md#stage-9-ship](docs/development/workflow.md#stage-9-ship)'

# --- Case 1: an anchored top-level bullet passes ---
$ok = New-Fixture -Body @"
## Git Workflow

- A rule that carries its anchor — $anchor.
"@
Assert-True ((Invoke-Check -Root $ok).ExitCode -eq 0) 'an anchored bullet must pass'

# --- Case 2: an unanchored top-level bullet fails ---
$bad = New-Fixture -Body @"
## Git Workflow

- A rule with no anchor at all.
"@
$result = Invoke-Check -Root $bad
Assert-True ($result.ExitCode -eq 1) 'an unanchored top-level bullet must fail'
Assert-True ($result.Output -match 'SCANNED\.md:3') 'the message must name the file and line'

# --- Case 3: a sub-heading must NOT hide bullets under it ---
$hidden = New-Fixture -Body @"
## Git Workflow

- A rule that carries its anchor — $anchor.

### A new sub-heading

- A rule hidden under a sub-heading, with no anchor.
"@
Assert-True ((Invoke-Check -Root $hidden).ExitCode -eq 1) 'a sub-heading must not hide an unanchored bullet'

# --- Case 4: reference forms are ignored ---
$reference = New-Fixture -Body @"
## Git Workflow

- A rule that carries its anchor — $anchor.

| Column | Column |
|---|---|
| a table row carries no anchor | and must not fail |

1. A numbered item carries no anchor either.

  - A nested bullet is reference data.
"@
Assert-True ((Invoke-Check -Root $reference).ExitCode -eq 0) 'tables, numbered items and nested bullets must be ignored'

# --- Case 5: an anchor that does not exist in the source fails ---
$dead = New-Fixture -Body @"
## Git Workflow

- A rule pointing nowhere — see [x](docs/development/workflow.md#stage-99-missing).
"@
$result = Invoke-Check -Root $dead
Assert-True ($result.ExitCode -eq 1) 'a dead anchor must fail'
Assert-True ($result.Output -match 'stage-99-missing') 'the message must name the dead anchor'

# --- Case 7: a heading INSIDE a fence must not end the section ---
# The heading test ran before the fence test, so a fenced '## Example' ended the scan and
# every rule after it went unread. The check reported exit 0 on a file with an unanchored rule.
$fenced = New-Fixture -Body @"
## Git Workflow

- A rule that carries its anchor — $anchor.

``````markdown
## Example heading inside a fence
``````

- A rule after the fence, with no anchor.
"@
$result = Invoke-Check -Root $fenced
Assert-True ($result.ExitCode -eq 1) 'a heading inside a fence must not end the section'

# --- Case 8: a shorter fence inside a longer one must not close it ---
# One boolean flipped on every backtick run, so the inner three-backtick line closed the outer
# four-backtick block. The heading after it then ended the section, and the unanchored rule
# below went unread.
$nested = New-Fixture -Body @"
## Git Workflow

- A rule that carries its anchor — $anchor.

````````markdown
``````
## Example heading inside the inner block
``````
````````

- A rule after the fence, with no anchor.
"@
Assert-True ((Invoke-Check -Root $nested).ExitCode -eq 1) 'a shorter fence inside a longer one must not close it'

# --- Case 9: a tilde fence is a fence too ---
$tilde = New-Fixture -Body @"
## Git Workflow

- A rule that carries its anchor — $anchor.

~~~markdown
## Example heading inside a tilde fence
~~~

- A rule after the fence, with no anchor.
"@
Assert-True ((Invoke-Check -Root $tilde).ExitCode -eq 1) 'a tilde fence must hide its heading and no more'

# --- Case 10: a fenced heading BEFORE the real one is not the section ---
# The heading search ran before any fence state existed, so a fenced '## Git Workflow' became
# the section start. The real heading then ended that section on its first line, and every real
# rule below it went unchecked.
$decoy = New-Fixture -Body @"
# A document

``````markdown
## Git Workflow

- A sample rule with no anchor, inside a fence.
``````

## Git Workflow

- A real rule with no anchor.
"@
$result = Invoke-Check -Root $decoy
Assert-True ($result.ExitCode -eq 1) 'a fenced heading must not become the section, hiding every real rule'
Assert-True ($result.Output -match 'SCANNED\.md:11') "the message must name the real rule's line:`n$($result.Output)"

# --- Case 6: the real repository passes ---
$live = & pwsh -NoProfile -File $script 2>&1
Assert-True ($LASTEXITCODE -eq 0) "the real repository must pass:`n$($live -join "`n")"

Remove-Item $ok, $bad, $hidden, $reference, $dead, $fenced, $nested, $tilde, $decoy -Recurse -Force -ErrorAction SilentlyContinue

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host ''; Write-Host $failure -ForegroundColor Red }
    Write-Host ''
    throw "Process anchor tests failed with $($failures.Count) problem(s). See the detail above."
}

Write-Host 'Process anchor tests passed. 10 cases.'
