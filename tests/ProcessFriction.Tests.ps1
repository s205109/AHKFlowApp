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

# --- Timestamps keep their zone ---
# ConvertFrom-Json turns an ISO string into a DateTime whose Kind is Utc. Handing that object
# back to [datetime]::Parse stringifies it in local time and parses the result as Unspecified,
# so ToUniversalTime subtracts the offset a second time. Measured on 2026-08-16: 10:00Z became
# 08:00Z, a two-hour shift that moved records and CI runs across the window edge.
$parsedRecord = '{"type":"user","timestamp":"2026-07-20T10:00:00.000Z","isSidechain":false,"uuid":"j1","promptSource":"typed","message":{"content":"what is the next step"}}' | ConvertFrom-Json
Assert-True ((Get-RecordTimestamp -Record $parsedRecord).ToString('o') -eq '2026-07-20T10:00:00.0000000Z') `
    "a DateTime from ConvertFrom-Json must stay 10:00Z, got $((Get-RecordTimestamp -Record $parsedRecord).ToString('o'))"

$stringRecord = New-Record @{ type = 'user'; timestamp = '2026-07-20T10:00:00.000Z'; isSidechain = $false; uuid = 'j2' }
Assert-True ((Get-RecordTimestamp -Record $stringRecord).ToString('o') -eq '2026-07-20T10:00:00.0000000Z') `
    'a string timestamp must parse to the same instant'

# A record one minute inside the window's first hour must survive a two-hour shift test.
$edge = '{"type":"user","timestamp":"2026-07-15T15:00:00.000Z","isSidechain":false,"uuid":"j3","promptSource":"typed","message":{"content":"x"}}' | ConvertFrom-Json
$edgeSelected = @(Select-FrictionRecord -Records @($edge) -Start $start -End $end)
Assert-True ($edgeSelected.Count -eq 1) 'a record 45 minutes after the window opens must be inside it'

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

# A record copied forward is the SAME record, not a second fragment. Appending it again both
# doubled the text and inflated the count of messages that span several records.
Assert-True ($userLogical[0].Fragments -eq 1) "a copied-forward record must not add a fragment, got $($userLogical[0].Fragments)"
Assert-True (@([regex]::Matches($userLogical[0].Text, 'what is the next step')).Count -eq 1) `
    'a copied-forward record must not repeat its text inside the assembled message'

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

# Prose can sit INSIDE a powershell fence, inside a here-string. A pull request body passed as
# @' ... '@ is text, not commands, and two of its sentences counted because they contain
# 'git -C' and a Windows path. A line only counts when it is a command line: outside a
# here-string, and beginning with a command.
# Built line by line: the fixture contains a here-string, so it cannot itself be one.
$hereStringText = @(
    '```powershell'
    'git -C C:\Dev\segocom-github\AHKFlowApp status'
    ('$body = @' + "'")
    'Records the `git -C docs/superpowers` form for plan and spec commits.'
    ''
    'Hit today while committing the spec, in C:\Dev\segocom-github\AHKFlowApp.'
    ("'" + '@')
    'gh pr create --body "$body"'
    '```'
) -join "`n"
$hereString = @(ConvertTo-LogicalMessage -Records @(New-Assistant -Id 'msg_here' -Text $hereStringText))
$count = Get-FrictionCount -Messages $hereString -Metric 'directory-bound-commands'
Assert-True ($count.Items -eq 1) "only the git -C command line counts, not the here-string prose, got $($count.Items)"
Assert-True (-not (@($count.Rows.Line) -match 'Records the')) 'a here-string sentence must never reach the ledger'

# A sentence that merely names a path, with no command at the head of the line, is prose even
# inside a fence.
$fencedProse = @(ConvertTo-LogicalMessage -Records @(New-Assistant -Id 'msg_prose' -Text @'
```bash
The worktree lives under C:\Dev\segocom-github\AHKFlowApp and is not yet removed.
```
'@))
$count = Get-FrictionCount -Messages $fencedProse -Metric 'directory-bound-commands'
Assert-True ($count.Items -eq 0) "a fenced sentence that names a path is not a command, got $($count.Items)"

# The published rule names five fence tags, because pwsh, sh and shell blocks are shell blocks
# too. Naming only powershell and bash while accepting five was the documentation defect.
$tags = @(ConvertTo-LogicalMessage -Records @(New-Assistant -Id 'msg_tags' -Text @'
```pwsh
cd C:\Dev\one
```

```sh
cd /c/Dev/two
```

```shell
cd /c/Dev/three
```

```json
cd C:\Dev\four
```
'@))
$count = Get-FrictionCount -Messages $tags -Metric 'directory-bound-commands'
Assert-True ($count.Items -eq 3) "pwsh, sh and shell count and json does not, got $($count.Items)"

# --- Metric 3: cleanup events, over ANY record ---
# The specification says any record. Reading only type=user dropped every cleanup line the
# agent itself reported.
#
# The unit is a LOG LINE, not a message. Every cleanup outcome reaches a transcript through
# Write-WorktreeLog, which stamps each line 'yyyy-MM-dd HH:mm:ss  <worktree>  <message>'
# (`scripts/worktree-log.common.ps1:22`, "    $line = '{0}  {1}  {2}' -f $stamp, $Worktree, $Message").
# Matching the wording anywhere in a message instead
# counted the script's own source, injected skill instructions, and reviews discussing a
# cleanup: measured on 2026-08-16, 65 of 75 rows were one of those.
$cleanup = @(ConvertTo-LogicalMessage -Records @(
        ([pscustomobject]@{ type = 'user'; timestamp = $inWindow; isSidechain = $false; uuid = 'c1'
                sessionId = 's1'; toolUseResult = '2026-07-20 11:02:31  wt-alpha  Watcher done (worktree removed; branch preserved).'
            })
        ([pscustomobject]@{ type = 'user'; timestamp = $inWindow; isSidechain = $false; uuid = 'c1'
                sessionId = 's1'; toolUseResult = '2026-07-20 11:02:31  wt-alpha  Watcher done (worktree removed; branch preserved).'
            })
        ([pscustomobject]@{ type = 'user'; timestamp = $inWindow; isSidechain = $false; uuid = 'c2'
                sessionId = 's2'; toolUseResult = 'nothing interesting here'
            })
        (New-Assistant -Id 'msg_cleanup' -Text "The sweep reported:`n2026-07-20 11:40:02  wt-beta  Worktree was preserved (not removed): folder is locked")
    ))
$count = Get-FrictionCount -Messages $cleanup -Metric 'cleanup-events'
Assert-True ($count.Items -eq 2) "cleanup must fold to 2 and must read assistant records too, got $($count.Items)"
Assert-True ($count.Rows.Count -eq 2) 'each counted cleanup line must return its own ledger row'
Assert-True (@($count.Rows | Where-Object { $_.Line -match 'Watcher done' }).Count -eq 1) `
    'the ledger row must carry the log line itself as the evidence'

# The metric counts events, not mentions. A sentence naming the cleanup script is discussion:
# the bare term 'remove-worktree' produced 180 of 233 rows, which is a lexical count wearing an
# event count's label.
$discussion = @(ConvertTo-LogicalMessage -Records @(
        New-Assistant -Id 'msg_talk' -Text 'The hook lives in scripts/remove-worktree.ps1 and I will read it next.'
    ))
$count = Get-FrictionCount -Messages $discussion -Metric 'cleanup-events'
Assert-True ($count.Items -eq 0) "naming the cleanup script is discussion, not an event, got $($count.Items)"

# Removing the bare script name was not enough. Every remaining phrase still matched anywhere in
# a message, so the script's own source, an injected skill file, and a review that quotes an
# outcome all counted as events. Only a stamped log line is one.
$notEvents = @(ConvertTo-LogicalMessage -Records @(
        New-Assistant -Id 'msg_src' -Text "    Write-Log 'Watcher done (worktree removed; branch preserved).'"
        New-Assistant -Id 'msg_review' -Text 'Round 7: the watcher done wording is fine, and the worktree removed cleanly in every run.'
        ([pscustomobject]@{ type = 'user'; timestamp = $inWindow; isSidechain = $false; uuid = 'c3'
                sessionId = 's3'
                message = [pscustomobject]@{ content = '## Your Task

You need to execute the following commands, removing worktree folders that are stale.' }
            })
    ))
$count = Get-FrictionCount -Messages $notEvents -Metric 'cleanup-events'
Assert-True ($count.Items -eq 0) `
    "source code, a review, and injected instructions are not cleanup events, got $($count.Items)"

# A stamped line inside a longer message still counts, because that is how a tool result
# carrying the worktree log arrives.
$embedded = @(ConvertTo-LogicalMessage -Records @(
        New-Assistant -Id 'msg_embedded' -Text "Here is the tail of the log:`n2026-07-20 09:15:44  wt-gamma  REFUSING: WorktreePath is not a registered linked worktree under MainCheckout.`nThat is the blocked run."
    ))
$count = Get-FrictionCount -Messages $embedded -Metric 'cleanup-events'
Assert-True ($count.Items -eq 1) "a stamped log line inside a longer message is an event, got $($count.Items)"

# The same log line echoed into two tool results is one event. The stamp, the worktree and the
# process id are all in the line, so two identical lines cannot be two events.
$echoed = @(ConvertTo-LogicalMessage -Records @(
        New-Assistant -Id 'msg_echo_a' -Text '2026-07-25 14:30:54  hotkey-ui-plan  Watcher started. PID=13500 Worktree=C:\wt'
        New-Assistant -Id 'msg_echo_b' -Text "Reading the log again:`n2026-07-25 14:30:54  hotkey-ui-plan  Watcher started. PID=13500 Worktree=C:\wt"
    ))
$count = Get-FrictionCount -Messages $echoed -Metric 'cleanup-events'
Assert-True ($count.Items -eq 1) "one log line echoed twice is one event, got $($count.Items)"

# Metric 2 must NOT do that. A command handed over in two messages is two handovers.
$repeatedCommand = @(ConvertTo-LogicalMessage -Records @(
        New-Assistant -Id 'msg_cmd_a' -Text "``````powershell`ncd C:\Dev\segocom-github\AHKFlowApp`n``````"
        New-Assistant -Id 'msg_cmd_b' -Text "``````powershell`ncd C:\Dev\segocom-github\AHKFlowApp`n``````"
    ))
$count = Get-FrictionCount -Messages $repeatedCommand -Metric 'directory-bound-commands'
Assert-True ($count.Items -eq 2) "the same command handed over twice is two handovers, got $($count.Items)"

# --- Session attribution does not depend on the order the files were read ---
# A message copied into a second transcript appears twice. Taking the session from whichever
# copy was read first made the per-metric session totals depend on enumeration order, which
# Get-ChildItem does not fix.
$copyA = New-Assistant -Id 'msg_sess' -Text 'You will need to run the migration yourself.' -Session 'zzz-session'
$copyB = New-Assistant -Id 'msg_sess' -Text 'You will need to run the migration yourself.' -Session 'aaa-session'
$forward = @(ConvertTo-LogicalMessage -Records @($copyA, $copyB))
$backward = @(ConvertTo-LogicalMessage -Records @($copyB, $copyA))
Assert-True ($forward[0].Session -eq $backward[0].Session) `
    "session attribution must not depend on read order, got $($forward[0].Session) and $($backward[0].Session)"
Assert-True ($forward[0].Session -eq 'aaa-session') `
    "the lowest session name is the stable choice, got $($forward[0].Session)"

# --- Every transcript ledger row carries its own evidence ---
# A ledger of keys and session names cannot be re-read. The row has to say when the message
# was written and which line of it matched.
$evidence = @(ConvertTo-LogicalMessage -Records @(
        New-Assistant -Id 'msg_evidence' -Text "I checked the branch.`nYou will need to run the migration yourself.`nThen the gate is green."
    ))
$count = Get-FrictionCount -Messages $evidence -Metric 'handoffs'
Assert-True ($count.Rows.Count -eq 1) 'one handoff, one row'
Assert-True ($count.Rows[0].Timestamp -eq $inWindow) "the ledger row must carry the message timestamp, got $($count.Rows[0].Timestamp)"
Assert-True ($count.Rows[0].Matched -eq 'you will need to run') "the ledger row must name the phrase that matched, got $($count.Rows[0].Matched)"
Assert-True ($count.Rows[0].Line -eq 'You will need to run the migration yourself.') `
    "the ledger row must carry the matching line as evidence, got $($count.Rows[0].Line)"

# --- The sidechain count is inside the window ---
# Counting sidechain records over every record read, while the metrics count only in-window
# ones, published an exclusion figure for a different population: 21,040 against 19,586.
$sideEarly = New-Record @{ type = 'user'; timestamp = $outOfWindow; isSidechain = $true; uuid = 's-out' }
$sideInside = New-Record @{ type = 'user'; timestamp = $inWindow; isSidechain = $true; uuid = 's-in' }
$excluded = Get-SidechainCount -Records @($sideEarly, $sideInside, $human) -Start $start -End $end
Assert-True ($excluded -eq 1) "only the in-window sidechain record counts as excluded, got $excluded"

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
    [pscustomobject]@{ id = 1; name = 'CI'; head_sha = 'aaa'; created_at = $inWindow; run_duration_ms = 600000 }
    [pscustomobject]@{ id = 1; name = 'CI'; head_sha = 'aaa'; created_at = $inWindow; run_duration_ms = 600000 }  # repeated id
    [pscustomobject]@{ id = 2; name = 'CI'; head_sha = 'bbb'; created_at = $inWindow; run_duration_ms = 300000 }
    [pscustomobject]@{ id = 3; name = 'CI'; head_sha = 'ccc'; created_at = $outOfWindow; run_duration_ms = 999000 }
    [pscustomobject]@{ id = 4; name = 'CI'; head_sha = 'ddd'; created_at = $inWindow; run_duration_ms = 120000 }
    [pscustomobject]@{ id = 5; name = 'CI'; head_sha = 'eee'; created_at = $inWindow; run_duration_ms = 0 }       # timing missing
    # A pull request that lands no net change. It resolves, and it changed zero files, so it is a
    # non-.NET run. Counting it as unresolved conflated 'could not resolve' with 'resolved to
    # nothing': run 30912438833 is exactly this shape, and it used 153,000 ms.
    [pscustomobject]@{ id = 8; name = 'CI'; head_sha = 'fff'; created_at = $inWindow; run_duration_ms = 153000 }
    # Not the CI workflow. opencode, PR-Agent and the two deploy workflows accounted for 339 of
    # the 531 in-window runs, and none of them is the gate this metric is about.
    [pscustomobject]@{ id = 6; name = 'opencode'; head_sha = 'aaa'; created_at = $inWindow; run_duration_ms = 900000 }
    [pscustomobject]@{ id = 7; name = 'Deploy API'; head_sha = 'aaa'; created_at = $inWindow; run_duration_ms = 900000 }
    # Another workflow, outside the window. It must be counted as out of window, never as an
    # 'other workflow': the name filter ran first, so out-of-window runs of other workflows
    # inflated the published population from 531 to 549.
    [pscustomobject]@{ id = 9; name = 'opencode'; head_sha = 'aaa'; created_at = $outOfWindow; run_duration_ms = 900000 }
)
$resolver = {
    param([string] $Sha)
    switch ($Sha) {
        'aaa' { return @{ Files = @('docs/development/workflow.md', 'AGENTS.md'); Base = 'base-aaa'; Kind = 'pull-request' } }
        'bbb' { return @{ Files = @('src/Backend/AHKFlowApp.API/Program.cs'); Base = 'base-bbb'; Kind = 'pull-request' } }
        'eee' { return @{ Files = @('README.md'); Base = 'base-eee'; Kind = 'pull-request' } }
        'fff' { return @{ Files = @(); Base = 'base-fff'; Kind = 'pull-request' } }
        'ddd' { return @{ Unresolved = $true; Reason = 'no-base-on-main-first-parent' } }
        default { return $null }
    }
}
$ci = Get-CiClassification -Runs $runs -Start $start -End $end -Resolver $resolver -WorkflowName 'CI'
Assert-True ($ci.OtherWorkflows -eq 2) "only the two in-window non-CI runs count as other workflows, got $($ci.OtherWorkflows)"
Assert-True ($ci.NonDotnetRuns -eq 3) "runs 1, 5 and 8 are in-window and non-.NET, got $($ci.NonDotnetRuns)"
Assert-True ($ci.NonDotnetMinutes -eq 12.6) "10 minutes plus the 153,000 ms zero-file run, got $($ci.NonDotnetMinutes)"
Assert-True ($ci.NoFileChange -eq 1) "the zero-file run must be reported as such, got $($ci.NoFileChange)"
Assert-True ($ci.Unresolved -eq 1) "only run 4 cannot be resolved, got $($ci.Unresolved)"
Assert-True ($ci.OutOfWindow -eq 2) "runs 3 and 9 are outside the window, got $($ci.OutOfWindow)"
Assert-True ($ci.DuplicateIds -eq 1) "the repeated run id must be reported, got $($ci.DuplicateIds)"
Assert-True ($ci.MissingTiming -eq 1) "run 5 has no duration and must be reported, got $($ci.MissingTiming)"
Assert-True ($ci.Rows.Count -eq 5) "the ledger must hold every in-window CI run, not only the counted ones, got $($ci.Rows.Count)"

# The ledger has to be able to reproduce every published figure on its own. Storing only the
# selected non-.NET rows could not reproduce the population, the .NET count, or the unresolved
# count, and a rounded minute figure could not reproduce the total.
$row1 = @($ci.Rows | Where-Object { $_.Id -eq '1' })[0]
Assert-True ($row1.Classification -eq 'non-dotnet') "run 1 must be recorded as non-dotnet, got $($row1.Classification)"
Assert-True ($row1.DurationMs -eq 600000) "the ledger must keep the raw duration, got $($row1.DurationMs)"
Assert-True ($row1.Base -eq 'base-aaa') 'each ledger row must record the base it was classified against'
Assert-True ($row1.BaseKind -eq 'pull-request') 'each ledger row must record how the base was found'
Assert-True ($row1.ChangedPaths -match 'AGENTS.md') 'the ledger must keep the changed paths, not only their count'
Assert-True (@($ci.Rows | Where-Object { $_.Classification -eq 'dotnet' }).Count -eq 1) 'the .NET run must be in the ledger too'
Assert-True (@($ci.Rows | Where-Object { $_.Classification -eq 'unresolved' }).Count -eq 1) 'the unresolved run must be in the ledger too'
$row4 = @($ci.Rows | Where-Object { $_.Id -eq '4' })[0]
Assert-True ($row4.Reason -eq 'no-base-on-main-first-parent') `
    "the ledger must keep the resolver's own reason, not one explanation for every run, got $($row4.Reason)"
$row5 = @($ci.Rows | Where-Object { $_.Id -eq '5' })[0]
Assert-True ($row5.TimingStatus -eq 'missing') "a run with no duration must say so, got $($row5.TimingStatus)"
$row8 = @($ci.Rows | Where-Object { $_.Id -eq '8' })[0]
Assert-True ($row8.Reason -eq 'no-file-change') "the zero-file run must record why, got $($row8.Reason)"

# --- A .NET path is decided by file type, never by folder ---
# 'anything under src/ or tests/' called a PowerShell suite and an nginx config .NET work. 21
# in-window runs changed no .NET file at all and were classified .NET, which kept 163.2 minutes
# out of a metric that measures exactly that.
foreach ($path in @(
        'tests/TestFastPowerShellMode.Tests.ps1'
        'tests/AgentWorktreeGuard.Tests.ps1'
        'src/Frontend/AHKFlowApp.UI.Blazor/nginx/default.conf'
        'scripts/test-fast.ps1'
        'docs/development/workflow.md'
    )) {
    Assert-True (-not (Test-DotnetPath -Path $path)) "'$path' changes no .NET file and must not classify a run as .NET"
}
foreach ($path in @(
        'src/Backend/AHKFlowApp.API/Program.cs'
        'tests/AHKFlowApp.API.Tests/AHKFlowApp.API.Tests.csproj'
        'src/Frontend/AHKFlowApp.UI.Blazor/Pages/Index.razor'
        'Directory.Packages.props'
        'AHKFlowApp.sln'
    )) {
    Assert-True (Test-DotnetPath -Path $path) "'$path' is a .NET file"
}

# --- The published population is the window's, not the calendar range's ---
# The API is asked for 'created=2026-07-15..2026-08-12', which includes both boundary dates in
# full and so returns more than the window holds. Printing that answer described a different
# population: 549 runs, 201 of them CI, against the window's real 531 and 192.
$population = Get-RunPopulationSummary -Runs $runs -Start $start -End $end
Assert-True ($population.InWindow -eq 8) "8 of the 10 fixture runs are in the window, got $($population.InWindow)"
Assert-True ($population.Returned -eq 10) "the returned count must still be reported, got $($population.Returned)"
Assert-True ($population.ByName['CI'] -eq 6) "6 in-window CI runs, got $($population.ByName['CI'])"
Assert-True ($population.ByName['opencode'] -eq 1) "the out-of-window opencode run must not be counted, got $($population.ByName['opencode'])"

# --- Metric 5, live: a pull-request head resolves to the WHOLE pull request ---
# CI runs on pull_request, so head_sha is the branch head, not a merge commit. The first-parent
# diff of that commit is one commit's change, not the pull request's. Measured on 2026-08-16:
# for 15076435 the first-parent diff returns 0 files and the real pull request changed 10, so
# the run was classified against a change that is not the one CI ran on.
$prHead = '1507643550b4906d8d1c165ae7626a7490286066'
& git -C $repoRoot cat-file -e "$prHead^{commit}" 2>$null
if ($LASTEXITCODE -eq 0) {
    $resolved = Get-ChangedFileForRun -RepoRoot $repoRoot -Sha $prHead
    Assert-True ($null -ne $resolved) 'a pull-request head that is present locally must resolve'
    if ($resolved) {
        Assert-True ($resolved.Files.Count -ge 10) "the pull request changed 10 files; got $($resolved.Files.Count)"
        # Named, not counted by type: the classification rule reads file types, and asserting
        # on it here would test that rule instead of the base this case exists to check.
        Assert-True ($resolved.Files -contains 'scripts/cleanup-merged-worktrees.ps1') `
            'the resolved file list must be the whole pull request, which the first-parent diff never saw'
        Assert-True ($resolved.Base -and $resolved.Base -ne $prHead) 'the resolved base must be the branch point, not the head itself'
    }
}
else {
    Write-Host "SKIPPED: commit $prHead is not present locally, so the live resolver was not exercised."
}

# --- The base comes from origin/main's first-parent chain, never from a branch-local merge ---
# 'rev-list --ancestry-path --merges' also returns merges made ON the branch, such as
# 'Merge branch main into feature/x'. The oldest of those is picked before the landing merge,
# its merge base with the head is the head itself, and the code then falls through to the
# first-parent rule. Measured on 2026-08-16: all 8 runs that reached that fallback sat off
# main's first-parent chain, and 2 of them changed a .cs file the fallback never saw.
$branchLocalHead = '1644fa35edf28b85783cd360647c505b07004be1'
& git -C $repoRoot cat-file -e "$branchLocalHead^{commit}" 2>$null
if ($LASTEXITCODE -eq 0) {
    $resolved = Get-ChangedFileForRun -RepoRoot $repoRoot -Sha $branchLocalHead
    Assert-True ($null -ne $resolved) 'a head whose branch landed on main must resolve'
    if ($resolved) {
        Assert-True ($resolved.Kind -eq 'pull-request') "the base must come from the landing merge, got $($resolved.Kind)"
        Assert-True ($resolved.Files.Count -eq 7) "the whole pull request changed 7 files, got $($resolved.Files.Count)"
        Assert-True ($resolved.Files -contains 'scripts/agents/agent-worktree-guard.common.ps1') `
            'the landing merge must give the whole pull request, not the one commit the first-parent rule sees'
    }
}
else {
    Write-Host "SKIPPED: commit $branchLocalHead is not present locally."
}

# --- A commit that never reached main is unresolved, not silently first-parented ---
# Falling back to head^1 for any unmerged commit answers with one commit's change and calls it
# a pull request. An audit found 13 such runs whose full pull request did touch .NET files.
$unmergedHead = (& git -C $repoRoot rev-parse HEAD).Trim()
& git -C $repoRoot merge-base --is-ancestor $unmergedHead origin/main 2>$null
if ($LASTEXITCODE -ne 0) {
    $resolvedUnmerged = Get-ChangedFileForRun -RepoRoot $repoRoot -Sha $unmergedHead
    Assert-True ($resolvedUnmerged.Unresolved -eq $true) 'a commit that is not on main and has no landing merge must be unresolved'
    Assert-True ($resolvedUnmerged.Reason -eq 'no-base-on-main-first-parent') `
        "the resolver must say why it could not answer, got $($resolvedUnmerged.Reason)"
}
else {
    Write-Host 'SKIPPED: HEAD is already on origin/main, so the unmerged case was not exercised.'
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host ''; Write-Host $failure -ForegroundColor Red }
    Write-Host ''
    throw "Process friction tests failed with $($failures.Count) problem(s). See the detail above."
}

Write-Host 'Process friction tests passed.'
