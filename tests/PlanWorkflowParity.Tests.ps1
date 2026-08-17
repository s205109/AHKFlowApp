#Requires -Version 7.0

# CI cannot see the plans repository (.gitignore keeps docs/superpowers out), so this suite
# tests the checker against fixture plans. Pre-push applies it to the real plans.
#
# Run it by hand with:  pwsh ./tests/PlanWorkflowParity.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts/process-workflow.common.ps1')
$script = Join-Path $repoRoot 'scripts/check-plan-workflow-parity.ps1'
$failures = @()

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { $script:failures += $Message }
}

$workflowPath = Join-Path $repoRoot 'docs/development/workflow.md'
$workflow = Get-WorkflowStage -Path $workflowPath

# Builds an Appendix A from the source, so the fixture never drifts from what it models.
function New-PlansRoot {
    param([hashtable] $Override = @{})
    $root = Join-Path ([System.IO.Path]::GetTempPath()) "plan-source-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $root -Force | Out-Null

    $body = New-Object System.Text.StringBuilder
    [void]$body.AppendLine('# Fixture plan')
    [void]$body.AppendLine()
    [void]$body.AppendLine('## Appendix A')
    [void]$body.AppendLine()
    $n = 0
    foreach ($id in $workflow.Keys) {
        $exit = if ($Override.ContainsKey("exit:$id")) { $Override["exit:$id"] } else { $workflow[$id].Exit }
        [void]$body.AppendLine("#### Stage $n — Name (``stage-$id``)")
        [void]$body.AppendLine()
        [void]$body.AppendLine("Exit — $exit Next — whatever")
        $parts = foreach ($edge in $workflow[$id].Edges.Keys) {
            $target = if ($Override.ContainsKey("edge:${id}:$edge")) { $Override["edge:${id}:$edge"] } else { $workflow[$id].Edges[$edge] }
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
    $output = & pwsh -NoProfile -File $script -PlansRoot $PlansRoot -WorkflowPath $workflowPath 2>&1
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
$missing = Join-Path ([System.IO.Path]::GetTempPath()) "plan-source-absent-$([guid]::NewGuid())"
$result = Invoke-Check -PlansRoot $missing
Assert-True ($result.ExitCode -eq 0) 'an absent plans folder must skip, so CI stays green'
Assert-True ($result.Output -match 'skip') 'the skip must be printed, never silent'

# --- Case 5: a folder with no Appendix A plan skips ---
$empty = Join-Path ([System.IO.Path]::GetTempPath()) "plan-source-empty-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $empty -Force | Out-Null
Set-Content -LiteralPath (Join-Path $empty 'ordinary-plan.md') -Value '# no appendix here' -Encoding utf8
$result = Invoke-Check -PlansRoot $empty
Assert-True ($result.ExitCode -eq 0) 'a plan with no Appendix A must be skipped, not failed'

# --- Case 6: a stage written twice fails ---
# The plan side assigned stages by id, so a second Stage 0 block replaced the first and the
# count still read 11. An ambiguous stage machine passed the pre-push gate.
$twin = New-PlansRoot
$twinFile = Join-Path $twin 'fixture-plan.md'
$raw = Get-Content -LiteralPath $twinFile -Raw
$firstStage = [regex]::Match($raw, '(?s)#### Stage 0 —.*?(?=#### Stage 1 —)')
Assert-True ($firstStage.Success) 'fixture setup: the Stage 0 block must be findable'
Set-Content -LiteralPath $twinFile -Value ($raw -replace '(?s)(## Appendix B)', ($firstStage.Value + '$1')) -NoNewline
$result = Invoke-Check -PlansRoot $twin
Assert-True ($result.ExitCode -eq 1) 'a stage written twice must fail'
Assert-True ($result.Output -match 'repeat|REPEATED|twice') 'the message must say the stage repeats'

# --- Case 7: an edge name the machine does not have fails ---
# An unknown segment was skipped, so a plan could invent 'cancelled → stay' and stay green.
$invented = New-PlansRoot
$inventedFile = Join-Path $invented 'fixture-plan.md'
$raw = Get-Content -LiteralPath $inventedFile -Raw
Set-Content -LiteralPath $inventedFile -Value ($raw -replace '(?m)^(Edges: .+)$', '$1 · cancelled → `stay`') -NoNewline
$result = Invoke-Check -PlansRoot $invented
Assert-True ($result.ExitCode -eq 1) 'an edge name outside the five must fail'
Assert-True ($result.Output -match 'cancelled') 'the message must name the invented edge'

# --- Case 8: an indented Appendix A heading is still a plan ---
# Up to three leading spaces is a Markdown heading. Anchoring at column one meant such a plan
# was not discovered at all, and a run that compared nothing exited 0.
$indented = New-PlansRoot -Override @{ 'exit:0-intake' = 'Something else entirely' }
$indentedFile = Join-Path $indented 'fixture-plan.md'
$raw = Get-Content -LiteralPath $indentedFile -Raw
Set-Content -LiteralPath $indentedFile -Value ($raw -replace '(?m)^## Appendix', '  ## Appendix') -NoNewline
$result = Invoke-Check -PlansRoot $indented
Assert-True ($result.ExitCode -eq 1) 'an indented Appendix A heading must still be read, and its drift must fail'

# --- Case 9: a word that starts with an edge name is not that edge ---
# '^(success|...)' has no token boundary, so 'successfully → `stay`' read as the success edge.
$prefix = New-PlansRoot
$prefixFile = Join-Path $prefix 'fixture-plan.md'
$raw = Get-Content -LiteralPath $prefixFile -Raw
Set-Content -LiteralPath $prefixFile -Value ($raw -replace '(?m)^(Edges: .+)$', '$1 · successfully → `stay`') -NoNewline
$result = Invoke-Check -PlansRoot $prefix
Assert-True ($result.ExitCode -eq 1) "'successfully' must not read as the success edge"
Assert-True ($result.Output -match 'successfully') 'the message must name the segment that is not an edge'

# --- Case 10: -RequirePlans turns an empty discovery into a failure ---
# Pre-push has the plans repository in the checkout, so finding no Appendix A there means the
# discovery missed something. Without this the caller printed 'Plans agree with the source'
# having compared nothing.
$noAppendix = Join-Path ([System.IO.Path]::GetTempPath()) "plan-source-none-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $noAppendix -Force | Out-Null
Set-Content -LiteralPath (Join-Path $noAppendix 'ordinary-plan.md') -Value '# no appendix here' -Encoding utf8
$output = & pwsh -NoProfile -File $script -PlansRoot $noAppendix -WorkflowPath $workflowPath -RequirePlans 2>&1
Assert-True ($LASTEXITCODE -eq 1) '-RequirePlans must fail when no plan carries an Appendix A'
Assert-True ((($output -join "`n") -match 'discovery failure')) 'the message must say the discovery failed'

# --- Case 11: a trailing period on an exit string is tolerated on purpose ---
# Appendix A writes the exit as prose, so a plan ends the sentence and the source does not.
# Nothing else is trimmed; case 2 covers a real difference.
$period = New-PlansRoot -Override @{ 'exit:0-intake' = ($workflow['0-intake'].Exit + '.') }
Assert-True ((Invoke-Check -PlansRoot $period).ExitCode -eq 0) 'a trailing period alone must still pass'

Remove-Item $good, $driftExit, $driftEdge, $empty, $twin, $invented, $indented, $prefix, $noAppendix, $period -Recurse -Force -ErrorAction SilentlyContinue

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host ''; Write-Host $failure -ForegroundColor Red }
    Write-Host ''
    throw "Plan source parity tests failed with $($failures.Count) problem(s). See the detail above."
}

Write-Host 'Plan source parity tests passed. 11 cases.'
