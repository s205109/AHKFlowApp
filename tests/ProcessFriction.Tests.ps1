#Requires -Version 7.0

# Four earlier attempts each produced a confident wrong number. The fixtures below carry the
# record shapes that broke them: a tool result, injected content stored as role=user, a
# sidechain record, the same message copied forward twice, and - the one that survived three
# rounds of review - an assistant message split across several records, where the first record
# carries no text at all.
#
# Run it by hand with:  pwsh ./tests/ProcessFriction.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

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

function New-Assistant {
    param([string] $Id, [string] $Text, [string] $Session = 's1', [bool] $Side = $false)
    $content = if ($null -eq $Text) { @() } else { @([pscustomobject]@{ type = 'text'; text = $Text }) }
    return ([pscustomobject]@{ type = 'assistant'; timestamp = $inWindow; isSidechain = $Side
            sessionId = $Session; uuid = "a-$Id-$([guid]::NewGuid())"
            message = [pscustomobject]@{ id = $Id; content = $content }
        })
}

# --- Human turns ---

$human = New-Record @{ type = 'user'; timestamp = $inWindow; isSidechain = $false; uuid = 'u1'
    promptSource = 'typed'; origin = [pscustomobject]@{ kind = 'human' }
    message = [pscustomobject]@{ content = 'what is the next step' }
}
$toolResult = New-Record @{ type = 'user'; timestamp = $inWindow; isSidechain = $false; uuid = 'u2'
    toolUseResult = 'ok'; message = [pscustomobject]@{ content = 'what is the next step' }
}
$suggestion = New-Record @{ type = 'user'; timestamp = $inWindow; isSidechain = $false; uuid = 'u3'
    promptSource = 'suggestion_accepted'; origin = [pscustomobject]@{ kind = 'human' }
    message = [pscustomobject]@{ content = 'what should I do next' }
}
$notification = New-Record @{ type = 'user'; timestamp = $inWindow; isSidechain = $false; uuid = 'u4'
    promptSource = 'system'; origin = [pscustomobject]@{ kind = 'task-notification' }
    message = [pscustomobject]@{ content = 'what is the next step' }
}
$sidechain = New-Record @{ type = 'user'; timestamp = $inWindow; isSidechain = $true; uuid = 'u5'
    promptSource = 'typed'; origin = [pscustomobject]@{ kind = 'human' }
    message = [pscustomobject]@{ content = 'what is the next step' }
}
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
$selectedUuids = @($selected | ForEach-Object { $_.uuid })
Assert-True (-not ($selectedUuids -contains 'u5')) 'a sidechain record must be excluded'
Assert-True (-not ($selectedUuids -contains 'u6')) 'an out-of-window record must be excluded'

# --- Normalization: one logical message per message.id ---
# An assistant message arrives as several records that share one message.id, and the FIRST of
# them often carries no text. Deduplicating before reading the text kept that empty first
# record and threw the rest away. Measured on 2026-08-16: 3,171 message ids in this window
# have an empty first record and text in a later one.

$split = @(
    New-Assistant -Id 'msg_split' -Text $null
    New-Assistant -Id 'msg_split' -Text 'I cannot reach that worktree, so'
    New-Assistant -Id 'msg_split' -Text 'run this in your terminal instead.'
)
$logical = @(ConvertTo-LogicalMessage -Records $split)
Assert-True ($logical.Count -eq 1) "three records of one message must fold into 1, got $($logical.Count)"
Assert-True ($logical[0].Text -match 'run this in your terminal') 'the assembled text must contain the later fragment'
Assert-True ($logical[0].Text -match 'I cannot reach') 'the assembled text must contain the earlier fragment'

$countSplit = Get-FrictionCount -Messages $logical -Metric 'handoffs'
Assert-True ($countSplit.Items -eq 1) "a handoff whose wording spans fragments must count once, got $($countSplit.Items)"

# A user record has no message.id, so it folds on its own uuid instead.
$userLogical = @(ConvertTo-LogicalMessage -Records @($human, $human, $suggestion))
Assert-True ($userLogical.Count -eq 2) "copied-forward user history must fold to 2, got $($userLogical.Count)"

# --- Metric 4: next-step asks ---
$count = Get-FrictionCount -Messages $userLogical -Metric 'next-step-asks'
Assert-True ($count.Items -eq 2) "two distinct asks must count 2, got $($count.Items)"
Assert-True ($count.MatchSet.Count -gt 0) 'the match set must be published with the number'
Assert-True ($count.Sessions -ge 1) 'every metric must report a session count beside the item count'
Assert-True ($count.Rows.Count -eq 2) 'every metric must return one ledger row per counted item'

# --- Metric 1: blocked-agent handoffs ---
$handoffs = @(ConvertTo-LogicalMessage -Records @(
        New-Assistant -Id 'msg_1' -Text 'Run this in your terminal, I cannot reach that worktree.'
        New-Assistant -Id 'msg_1' -Text 'Run this in your terminal, I cannot reach that worktree.'
        New-Assistant -Id 'msg_2' -Text 'I finished the change and committed it.'
        New-Assistant -Id 'msg_3' -Text 'You will need to run the migration yourself.'
    ))
$count = Get-FrictionCount -Messages $handoffs -Metric 'handoffs'
Assert-True ($count.Items -eq 2) "handoffs must fold on message.id to 2, got $($count.Items)"
Assert-True ($count.MatchSet.Count -gt 0) 'the handoff match set must be published'

# --- Each metric reads one side of the conversation ---
# A 'continue' inside a PowerShell switch leaves the switch, not the loop, so an earlier draft
# counted every message for every metric: metric 4 reported 338 asks instead of 36. Fixtures
# that hold one record type cannot catch that, so this one mixes them.
# Each side carries the OTHER metric's wording, so a filter that leaks counts twice.
$humanHandoffWords = New-Record @{ type = 'user'; timestamp = $inWindow; isSidechain = $false; uuid = 'u-mixed'
    promptSource = 'typed'; origin = [pscustomobject]@{ kind = 'human' }
    message = [pscustomobject]@{ content = 'you will need to run the migration yourself, I think' }
}
$mixed = @(ConvertTo-LogicalMessage -Records @(
        $humanHandoffWords
        New-Assistant -Id 'msg_mixed' -Text 'The next step is to open the pull request.'
    ))
$asks = Get-FrictionCount -Messages $mixed -Metric 'next-step-asks'
Assert-True ($asks.Items -eq 0) "an assistant message saying 'next step' is not an ask, got $($asks.Items)"
$hands = Get-FrictionCount -Messages $mixed -Metric 'handoffs'
Assert-True ($hands.Items -eq 0) "a human turn quoting handoff wording is not a handoff, got $($hands.Items)"

# --- Metric 2: directory-bound commands ---
# The rule is a line inside a powershell or bash fence that names a directory. Prose that
# mentions cd is not a handed-over command, and the same line repeated inside one message is
# one command, not two.
$fenced = @(ConvertTo-LogicalMessage -Records @(New-Assistant -Id 'msg_4' -Text @'
First, cd into the repository - that sentence is prose and must not count.

```powershell
cd C:\Dev\segocom-github\AHKFlowApp
git -C C:\Dev\segocom-github\AHKFlowApp status
cd C:\Dev\segocom-github\AHKFlowApp
Write-Host "no directory here"
```

```bash
cd /c/Dev/segocom-github/AHKFlowApp
```

```text
cd C:\Dev\segocom-github\AHKFlowApp
```
'@))
$count = Get-FrictionCount -Messages $fenced -Metric 'directory-bound-commands'
Assert-True ($count.Items -eq 3) "fenced, deduplicated, directory-naming lines must count 3, got $($count.Items)"
Assert-True (-not ($count.Rows.Line -contains 'Write-Host "no directory here"')) 'a fenced line that names no directory must not count'

$unfencedOnly = @(ConvertTo-LogicalMessage -Records @(New-Assistant -Id 'msg_5' -Text 'Run cd C:\Dev\segocom-github\AHKFlowApp and then build.'))
$count = Get-FrictionCount -Messages $unfencedOnly -Metric 'directory-bound-commands'
Assert-True ($count.Items -eq 0) "a command outside a fence is prose and must not count, got $($count.Items)"

# --- Metric 3: cleanup events, over ANY record ---
# The specification says any record. Reading only type=user dropped every cleanup line the
# agent itself reported.
$cleanup = @(ConvertTo-LogicalMessage -Records @(
        ([pscustomobject]@{ type = 'user'; timestamp = $inWindow; isSidechain = $false; uuid = 'c1'
                sessionId = 's1'; toolUseResult = 'Watcher done (worktree removed; branch preserved).'
            })
        ([pscustomobject]@{ type = 'user'; timestamp = $inWindow; isSidechain = $false; uuid = 'c1'
                sessionId = 's1'; toolUseResult = 'Watcher done (worktree removed; branch preserved).'
            })
        ([pscustomobject]@{ type = 'user'; timestamp = $inWindow; isSidechain = $false; uuid = 'c2'
                sessionId = 's2'; toolUseResult = 'nothing interesting here'
            })
        (New-Assistant -Id 'msg_cleanup' -Text 'The sweep reported: worktree removed, branch preserved.')
    ))
$count = Get-FrictionCount -Messages $cleanup -Metric 'cleanup-events'
Assert-True ($count.Items -eq 2) "cleanup must fold to 2 and must read assistant records too, got $($count.Items)"

# --- File discovery reads nested transcripts ---
# Subagent transcripts live in subdirectories. Reading only the top level hid every sidechain
# record, so the exclusion count printed zero and proved nothing.
$discoveryRoot = Join-Path ([System.IO.Path]::GetTempPath()) "friction-discovery-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path (Join-Path $discoveryRoot 'AHKFlow-proj/nested') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $discoveryRoot 'AHKFlow-proj/top.jsonl') -Value '{}' -Encoding utf8
Set-Content -LiteralPath (Join-Path $discoveryRoot 'AHKFlow-proj/nested/deep.jsonl') -Value '{}' -Encoding utf8
$found = @(Get-TranscriptFile -ProjectRoot $discoveryRoot)
Assert-True ($found.Count -eq 2) "discovery must find the nested transcript too, got $($found.Count)"
Remove-Item $discoveryRoot -Recurse -Force -ErrorAction SilentlyContinue

# --- The file list must deduplicate case-insensitively ---
$dedupRoot = Join-Path ([System.IO.Path]::GetTempPath()) "friction-dedup-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path (Join-Path $dedupRoot 'c--proj') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $dedupRoot 'c--proj/one.jsonl') -Value '{}' -Encoding utf8
$resolved = @(Resolve-TranscriptFile -Candidates @(
        (Join-Path $dedupRoot 'c--proj/one.jsonl')
        (Join-Path $dedupRoot 'C--PROJ/one.jsonl')
    ))
Assert-True ($resolved.Count -eq 1) "two spellings of one path must resolve to 1 file, got $($resolved.Count)"
Remove-Item $dedupRoot -Recurse -Force -ErrorAction SilentlyContinue

# --- Metric 5: CI classification ---
$runs = @(
    [pscustomobject]@{ id = 1; head_sha = 'aaa'; created_at = $inWindow; run_duration_ms = 600000 }
    [pscustomobject]@{ id = 1; head_sha = 'aaa'; created_at = $inWindow; run_duration_ms = 600000 }  # repeated id
    [pscustomobject]@{ id = 2; head_sha = 'bbb'; created_at = $inWindow; run_duration_ms = 300000 }
    [pscustomobject]@{ id = 3; head_sha = 'ccc'; created_at = $outOfWindow; run_duration_ms = 999000 }
    [pscustomobject]@{ id = 4; head_sha = 'ddd'; created_at = $inWindow; run_duration_ms = 120000 }
    [pscustomobject]@{ id = 5; head_sha = 'eee'; created_at = $inWindow; run_duration_ms = 0 }       # timing missing
)
$resolver = {
    param([string] $Sha)
    switch ($Sha) {
        'aaa' { return @{ Files = @('docs/development/workflow.md', 'AGENTS.md'); Base = 'base-aaa' } }
        'bbb' { return @{ Files = @('src/Backend/AHKFlowApp.API/Program.cs'); Base = 'base-bbb' } }
        'eee' { return @{ Files = @('README.md'); Base = 'base-eee' } }
        'ddd' { return $null }
        default { return $null }
    }
}
$ci = Get-CiClassification -Runs $runs -Start $start -End $end -Resolver $resolver
Assert-True ($ci.NonDotnetRuns -eq 2) "runs 1 and 5 are in-window and non-.NET, got $($ci.NonDotnetRuns)"
Assert-True ($ci.NonDotnetMinutes -eq 10) "only run 1 has a duration, so 10 minutes, got $($ci.NonDotnetMinutes)"
Assert-True ($ci.Unresolved -eq 1) "run 4 cannot be resolved and must be reported, got $($ci.Unresolved)"
Assert-True ($ci.OutOfWindow -eq 1) 'run 3 is outside the window'
Assert-True ($ci.DuplicateIds -eq 1) "the repeated run id must be reported, got $($ci.DuplicateIds)"
Assert-True ($ci.MissingTiming -eq 1) "run 5 has no duration and must be reported, got $($ci.MissingTiming)"
Assert-True ($ci.Rows.Count -eq 2) 'the classification must return one ledger row per counted run'
Assert-True (@($ci.Rows | Where-Object { $_.Base -eq 'base-aaa' }).Count -eq 1) 'each ledger row must record the base it was classified against'

# --- Metric 5, live: a pull-request head resolves to the WHOLE pull request ---
# CI runs on pull_request, so head_sha is the branch head, not a merge commit. The first-parent
# diff of that commit is one commit's change, not the pull request's. Measured on 2026-08-16:
# for 15076435 the first-parent diff returns 0 files and the real pull request changed 10,
# one of them a .NET file - so the run was classified non-.NET when it is not.
$prHead = '1507643550b4906d8d1c165ae7626a7490286066'
& git -C $repoRoot cat-file -e "$prHead^{commit}" 2>$null
if ($LASTEXITCODE -eq 0) {
    $resolved = Get-ChangedFileForRun -RepoRoot $repoRoot -Sha $prHead
    Assert-True ($null -ne $resolved) 'a pull-request head that is present locally must resolve'
    if ($resolved) {
        Assert-True ($resolved.Files.Count -ge 10) "the pull request changed 10 files; got $($resolved.Files.Count)"
        $dotnet = @($resolved.Files | Where-Object { Test-DotnetPath -Path $_ })
        Assert-True ($dotnet.Count -ge 1) 'the pull request touches a .NET file, so the run is not a non-.NET run'
        Assert-True ($resolved.Base -and $resolved.Base -ne $prHead) 'the resolved base must be the branch point, not the head itself'
    }
}
else {
    Write-Host "SKIPPED: commit $prHead is not present locally, so the live resolver was not exercised."
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host ''; Write-Host $failure -ForegroundColor Red }
    Write-Host ''
    throw "Process friction tests failed with $($failures.Count) problem(s). See the detail above."
}

Write-Host 'Process friction tests passed.'
