#Requires -Version 7.0

# Three earlier attempts each produced a confident wrong number. The fixtures below are the
# four record shapes that broke them: a tool result, injected content stored as role=user, a
# sidechain record, and the same message copied forward twice.
#
# Run it by hand with:  pwsh ./tests/ProcessFriction.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts/measure-process-friction.ps1') -AsModule

$failures = @()
function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { $script:failures += $Message }
}

$inWindow = '2026-07-20T10:00:00.000Z'
$outOfWindow = '2026-08-13T10:00:00.000Z'
$start = [datetime]::Parse('2026-07-15T14:14:32Z').ToUniversalTime()
$end = [datetime]::Parse('2026-08-12T14:14:32Z').ToUniversalTime()

function New-Record {
    param([hashtable] $Fields)
    return ([pscustomobject]$Fields)
}

# A real typed human turn.
$human = New-Record @{ type = 'user'; timestamp = $inWindow; isSidechain = $false; uuid = 'u1'
    promptSource = 'typed'; origin = [pscustomobject]@{ kind = 'human' }
    message = [pscustomobject]@{ content = 'what is the next step' }
}

# A tool result. type is user, but it carries no origin and no promptSource.
$toolResult = New-Record @{ type = 'user'; timestamp = $inWindow; isSidechain = $false; uuid = 'u2'
    toolUseResult = 'ok'; message = [pscustomobject]@{ content = 'what is the next step' }
}

# An accepted suggestion is a human turn too. Requiring typed AND human drops it.
$suggestion = New-Record @{ type = 'user'; timestamp = $inWindow; isSidechain = $false; uuid = 'u3'
    promptSource = 'suggestion_accepted'; origin = [pscustomobject]@{ kind = 'human' }
    message = [pscustomobject]@{ content = 'what should I do next' }
}

# A task notification is not a human turn.
$notification = New-Record @{ type = 'user'; timestamp = $inWindow; isSidechain = $false; uuid = 'u4'
    promptSource = 'system'; origin = [pscustomobject]@{ kind = 'task-notification' }
    message = [pscustomobject]@{ content = 'what is the next step' }
}

# A sidechain record must be excluded and counted separately.
$sidechain = New-Record @{ type = 'user'; timestamp = $inWindow; isSidechain = $true; uuid = 'u5'
    promptSource = 'typed'; origin = [pscustomobject]@{ kind = 'human' }
    message = [pscustomobject]@{ content = 'what is the next step' }
}

# Outside the window.
$late = New-Record @{ type = 'user'; timestamp = $outOfWindow; isSidechain = $false; uuid = 'u6'
    promptSource = 'typed'; origin = [pscustomobject]@{ kind = 'human' }
    message = [pscustomobject]@{ content = 'what is the next step' }
}

Assert-True (Test-HumanTurn -Record $human) 'a typed human turn must count'
Assert-True (-not (Test-HumanTurn -Record $toolResult)) 'a tool result must not count as a human turn'
Assert-True (Test-HumanTurn -Record $suggestion) 'an accepted suggestion must count'
Assert-True (-not (Test-HumanTurn -Record $notification)) 'a task notification must not count'

$selected = @(Select-FrictionRecord -Records @($human, $toolResult, $suggestion, $notification, $sidechain, $late) -Start $start -End $end)
Assert-True ($selected.Count -eq 4) "the window and sidechain filters should leave 4 records, got $($selected.Count)"
Assert-True (-not ($selected.uuid -contains 'u5')) 'a sidechain record must be excluded'
Assert-True (-not ($selected.uuid -contains 'u6')) 'an out-of-window record must be excluded'

# --- Metric 4: next-step asks ---
# The same user record copied forward twice deduplicates on uuid, because user records carry
# no message.id at all - verified against live transcripts.
$copied = @($human, $human, $suggestion)
$count = Get-FrictionCount -Records $copied -Metric 'next-step-asks'
Assert-True ($count.Items -eq 2) "copied-forward history must deduplicate to 2, got $($count.Items)"
Assert-True ($count.MatchSet.Count -gt 0) 'the match set must be published with the number'
Assert-True ($count.Sessions -ge 1) 'every metric must report a session count beside the item count'

# --- Metric 1: blocked-agent handoffs ---
# Assistant records, deduplicated on message.id, which exists on every assistant record.
function New-Assistant {
    param([string] $Id, [string] $Text, [string] $Session = 's1', [bool] $Side = $false)
    return ([pscustomobject]@{ type = 'assistant'; timestamp = $inWindow; isSidechain = $Side
            sessionId = $Session; uuid = "a-$Id"
            message = [pscustomobject]@{ id = $Id; content = @([pscustomobject]@{ type = 'text'; text = $Text }) }
        })
}

$handoffs = @(
    New-Assistant -Id 'msg_1' -Text 'Run this in your terminal, I cannot reach that worktree.'
    New-Assistant -Id 'msg_1' -Text 'Run this in your terminal, I cannot reach that worktree.'   # copied forward
    New-Assistant -Id 'msg_2' -Text 'I finished the change and committed it.'                     # not a handoff
    New-Assistant -Id 'msg_3' -Text 'You will need to run the migration yourself.'
)
$count = Get-FrictionCount -Records $handoffs -Metric 'handoffs'
Assert-True ($count.Items -eq 2) "handoffs must deduplicate on message.id to 2, got $($count.Items)"
Assert-True ($count.MatchSet.Count -gt 0) 'the handoff match set must be published'

# --- Metric 2: directory-bound commands, counted as COMMAND LINES ---
# One message can hand over several commands, so the unit is lines, not messages.
$twoCommands = New-Assistant -Id 'msg_4' -Text @'
Run these:

```powershell
cd C:\Dev\segocom-github\AHKFlowApp
git -C C:\Dev\segocom-github\AHKFlowApp status
Write-Host "no directory here"
```
'@
$count = Get-FrictionCount -Records @($twoCommands) -Metric 'directory-bound-commands'
Assert-True ($count.Items -eq 2) "one message with two directory-bound lines must count 2, got $($count.Items)"

# --- Metric 3: cleanup popups and blocked runs ---
$cleanup = @(
    ([pscustomobject]@{ type = 'user'; timestamp = $inWindow; isSidechain = $false; uuid = 'c1'
            sessionId = 's1'; toolUseResult = 'Watcher done (worktree removed; branch preserved).'
        })
    ([pscustomobject]@{ type = 'user'; timestamp = $inWindow; isSidechain = $false; uuid = 'c1'
            sessionId = 's1'; toolUseResult = 'Watcher done (worktree removed; branch preserved).'
        })
    ([pscustomobject]@{ type = 'user'; timestamp = $inWindow; isSidechain = $false; uuid = 'c2'
            sessionId = 's2'; toolUseResult = 'nothing interesting here'
        })
)
$count = Get-FrictionCount -Records $cleanup -Metric 'cleanup-events'
Assert-True ($count.Items -eq 1) "cleanup events must deduplicate on uuid to 1, got $($count.Items)"

# --- Metric 5: CI classification ---
# The resolver is injected, so this needs neither git nor the network.
$runs = @(
    [pscustomobject]@{ id = 1; head_sha = 'aaa'; created_at = $inWindow; run_duration_ms = 600000 }
    [pscustomobject]@{ id = 2; head_sha = 'bbb'; created_at = $inWindow; run_duration_ms = 300000 }
    [pscustomobject]@{ id = 3; head_sha = 'ccc'; created_at = $outOfWindow; run_duration_ms = 999000 }
    [pscustomobject]@{ id = 4; head_sha = 'ddd'; created_at = $inWindow; run_duration_ms = 120000 }
)
$resolver = {
    param([string] $Sha)
    switch ($Sha) {
        'aaa' { return @('docs/development/workflow.md', 'AGENTS.md') }       # no .NET
        'bbb' { return @('src/Backend/AHKFlowApp.API/Program.cs') }           # .NET
        'ddd' { return $null }                                               # not resolvable locally
        default { return @() }
    }
}
$ci = Get-CiClassification -Runs $runs -Start $start -End $end -Resolver $resolver
Assert-True ($ci.NonDotnetRuns -eq 1) "only run 1 is in-window and non-.NET, got $($ci.NonDotnetRuns)"
Assert-True ($ci.NonDotnetMinutes -eq 10) "run 1 is 600000 ms = 10 minutes, got $($ci.NonDotnetMinutes)"
Assert-True ($ci.Unresolved -eq 1) "run 4 cannot be resolved locally and must be reported, got $($ci.Unresolved)"
Assert-True ($ci.OutOfWindow -eq 1) 'run 3 is outside the window'

# --- Metric 5, live: the REAL first-parent resolver ---
# The injected resolver above proves the classification logic. Nothing would otherwise
# exercise the git call it depends on. d54cb915 is a merge commit on main whose first-parent
# diff returns the files that pull request changed, including workflow.md.
$known = 'd54cb91522c3af13776668d23159f2c8cbc52126'
& git -C $repoRoot cat-file -e "$known^{commit}" 2>$null
if ($LASTEXITCODE -eq 0) {
    $live = Get-ChangedFileFromFirstParent -RepoRoot $repoRoot -Sha $known
    Assert-True ($live -contains 'docs/development/workflow.md') "the live resolver must return workflow.md for $known, got: $($live -join ', ')"
    Assert-True ($live.Count -ge 5) "the live resolver returned only $($live.Count) file(s); the merge changed several"
}
else {
    Write-Host "SKIPPED: commit $known is not present locally, so the live resolver was not exercised."
}

# --- The file list must deduplicate case-insensitively ---
# On Windows a glob for 'C--...' also matches the lowercase 'c--...' directory, so the main
# project folder is read twice and every count it feeds is doubled.
$dedupRoot = Join-Path ([System.IO.Path]::GetTempPath()) "friction-dedup-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path (Join-Path $dedupRoot 'c--proj') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $dedupRoot 'c--proj/one.jsonl') -Value '{}' -Encoding utf8
$resolved = Resolve-TranscriptFile -Candidates @(
    (Join-Path $dedupRoot 'c--proj/one.jsonl')
    (Join-Path $dedupRoot 'C--PROJ/one.jsonl')
)
Assert-True ($resolved.Count -eq 1) "two spellings of one path must resolve to 1 file, got $($resolved.Count)"
Remove-Item $dedupRoot -Recurse -Force -ErrorAction SilentlyContinue

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host ''; Write-Host $failure -ForegroundColor Red }
    Write-Host ''
    throw "Process friction tests failed with $($failures.Count) problem(s). See the detail above."
}

Write-Host 'Process friction tests passed.'
