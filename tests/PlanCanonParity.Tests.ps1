#Requires -Version 7.0

# CI cannot see the plans repository (.gitignore keeps docs/superpowers out), so this suite
# tests the checker against fixture plans. Pre-push applies it to the real plans.
#
# Run it by hand with:  pwsh ./tests/PlanCanonParity.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts/process-canon.common.ps1')
$script = Join-Path $repoRoot 'scripts/check-plan-canon-parity.ps1'
$failures = @()

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { $script:failures += $Message }
}

$canonPath = Join-Path $repoRoot 'docs/development/workflow.md'
$canon = Get-CanonStage -Path $canonPath

# Builds an Appendix A from the canon, so the fixture never drifts from what it models.
function New-PlansRoot {
    param([hashtable] $Override = @{})
    $root = Join-Path ([System.IO.Path]::GetTempPath()) "plan-canon-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $root -Force | Out-Null

    $body = New-Object System.Text.StringBuilder
    [void]$body.AppendLine('# Fixture plan')
    [void]$body.AppendLine()
    [void]$body.AppendLine('## Appendix A')
    [void]$body.AppendLine()
    $n = 0
    foreach ($id in $canon.Keys) {
        $exit = if ($Override.ContainsKey("exit:$id")) { $Override["exit:$id"] } else { $canon[$id].Exit }
        [void]$body.AppendLine("#### Stage $n — Name (``stage-$id``)")
        [void]$body.AppendLine()
        [void]$body.AppendLine("Exit — $exit Next — whatever")
        $parts = foreach ($edge in $canon[$id].Edges.Keys) {
            $target = if ($Override.ContainsKey("edge:${id}:$edge")) { $Override["edge:${id}:$edge"] } else { $canon[$id].Edges[$edge] }
            "$edge → ``$target``"
        }
        [void]$body.AppendLine('Edges: ' + ($parts -join ' · '))
        [void]$body.AppendLine()
        $n++
    }
    [void]$body.AppendLine('## Appendix B')
    [void]$body.AppendLine()
    [void]$body.AppendLine('nothing')

    Set-Content -LiteralPath (Join-Path $root 'fixture-plan.md') -Value $body.ToString() -Encoding utf8
    return $root
}

function Invoke-Check {
    param([string] $PlansRoot)
    $output = & pwsh -NoProfile -File $script -PlansRoot $PlansRoot -CanonPath $canonPath 2>&1
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
}

# --- Case 1: a faithful Appendix A passes ---
$good = New-PlansRoot
$result = Invoke-Check -PlansRoot $good
Assert-True ($result.ExitCode -eq 0) "a faithful appendix must pass:`n$($result.Output)"

# --- Case 2: a drifted exit string fails ---
$driftExit = New-PlansRoot -Override @{ 'exit:0-intake' = 'Something else entirely' }
Assert-True ((Invoke-Check -PlansRoot $driftExit).ExitCode -eq 1) 'a drifted exit string must fail'

# --- Case 3: a drifted edge target fails ---
$driftEdge = New-PlansRoot -Override @{ 'edge:0-intake:success' = '7-document' }
$result = Invoke-Check -PlansRoot $driftEdge
Assert-True ($result.ExitCode -eq 1) 'a drifted edge target must fail'
Assert-True ($result.Output -match '0-intake') 'the message must name the stage'

# --- Case 4: an absent plans folder skips, and does not fail ---
$missing = Join-Path ([System.IO.Path]::GetTempPath()) "plan-canon-absent-$([guid]::NewGuid())"
$result = Invoke-Check -PlansRoot $missing
Assert-True ($result.ExitCode -eq 0) 'an absent plans folder must skip, so CI stays green'
Assert-True ($result.Output -match 'skip') 'the skip must be printed, never silent'

# --- Case 5: a folder with no Appendix A plan skips ---
$empty = Join-Path ([System.IO.Path]::GetTempPath()) "plan-canon-empty-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $empty -Force | Out-Null
Set-Content -LiteralPath (Join-Path $empty 'ordinary-plan.md') -Value '# no appendix here' -Encoding utf8
$result = Invoke-Check -PlansRoot $empty
Assert-True ($result.ExitCode -eq 0) 'a plan with no Appendix A must be skipped, not failed'

Remove-Item $good, $driftExit, $driftEdge, $empty -Recurse -Force -ErrorAction SilentlyContinue

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host ''; Write-Host $failure -ForegroundColor Red }
    Write-Host ''
    throw "Plan canon parity tests failed with $($failures.Count) problem(s). See the detail above."
}

Write-Host 'Plan canon parity tests passed. 5 cases.'
