#Requires -Version 7.0

# The two backlog 103 scripts, driven with controlled inputs.
#
# tests/CleanupEventLabels.Tests.ps1 checks the committed artifacts. It cannot check what the
# scripts do with an input the committed data never contains: an offset with no dataset behind
# it, a 'msg:' identity, or two transcript records that claim the same uuid. This suite builds
# those inputs in a temporary folder and runs each script against them.
#
# No machine-local data is read. Every path is passed in, so this suite runs in CI.
#
# Run it by hand with:  pwsh ./tests/CleanupEventScripts.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$measureScript = Join-Path $repoRoot 'scripts/measure-cleanup-log-events.ps1'
$labelScript = Join-Path $repoRoot 'scripts/label-cleanup-events.ps1'
$hostExe = [System.Diagnostics.Process]::GetCurrentProcess().Path

$failures = @()

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { $script:failures += $Message }
}

function Invoke-Suite {
    <#
    .SYNOPSIS
        Runs one script in its own process and returns its exit code with all of its output.
    .DESCRIPTION
        Both scripts dot-source measure-process-friction.ps1, which sets script-scoped state.
        Running two of them in this process would let one run's state reach the next.
    #>
    param(
        [Parameter(Mandatory)][string] $Script,
        [Parameter(Mandatory)][string[]] $ScriptArguments
    )

    $output = & $hostExe -NoProfile -File $Script @ScriptArguments 2>&1
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output   = (@($output) | ForEach-Object { [string]$_ }) -join "`n"
    }
}

$temp = Join-Path ([System.IO.Path]::GetTempPath()) "cleanup-event-scripts-$([guid]::NewGuid().ToString('n'))"
New-Item -ItemType Directory -Path $temp -Force | Out-Null

try {
    # --- Fixture: a removal log with two in-window outcome lines ---

    # The window runs 2026-07-15T14:14:32Z to 2026-08-12T14:14:32Z. The log stamps are local
    # time with no offset, so these two sit inside it at every offset the script accepts.
    $fixtureLog = Join-Path $temp 'worktree-removal.log'
    Set-Content -LiteralPath $fixtureLog -Encoding utf8 -Value @(
        '2026-08-01 10:00:00  wt-alpha  Watcher started. PID=4242'
        '2026-08-01 10:00:07  wt-alpha  Watcher done (removed).'
        '2026-08-01 10:00:07  wt-alpha  Removal requested by the merged-cleanup sweep.'
        '2026-06-01 09:00:00  wt-before  Watcher started. PID=1'
    )

    # --- 1. An offset with no dataset behind it fails, and writes nothing ---

    # Only offsets 1, 2 and 3 are computed. Before this check, -AssumedOffsetHours 4 selected a
    # missing hashtable key, which is $null, and exported an empty ledger over the committed one.
    $ledgerFour = Join-Path $temp 'offset-four.csv'
    $badOffset = Invoke-Suite -Script $measureScript -ScriptArguments @(
        '-LogPath', $fixtureLog, '-LedgerPath', $ledgerFour, '-AssumedOffsetHours', '4')

    Assert-True ($badOffset.ExitCode -ne 0) `
        "An offset of 4 must fail. It exited $($badOffset.ExitCode) instead.`n$($badOffset.Output)"
    Assert-True (-not (Test-Path -LiteralPath $ledgerFour)) `
        'An offset of 4 must not write a ledger. Writing an empty one would overwrite the committed rows.'

    # --- 2. A valid offset writes the in-window rows, stamped in ISO UTC ---

    $ledgerTwo = Join-Path $temp 'offset-two.csv'
    $goodOffset = Invoke-Suite -Script $measureScript -ScriptArguments @(
        '-LogPath', $fixtureLog, '-LedgerPath', $ledgerTwo, '-AssumedOffsetHours', '2')

    Assert-True ($goodOffset.ExitCode -eq 0) `
        "An offset of 2 must succeed. It exited $($goodOffset.ExitCode).`n$($goodOffset.Output)"

    if (Test-Path -LiteralPath $ledgerTwo) {
        $written = @(Import-Csv -LiteralPath $ledgerTwo)

        Assert-True ($written.Count -eq 2) `
            "The fixture log holds two in-window outcome lines. The ledger has $($written.Count)."

        # 'Removal requested by...' has the log line shape but is not an outcome, and the
        # 2026-06-01 line is outside the window. Neither may reach the ledger.
        Assert-True (@($written | Where-Object { [string]$_.Line -like '*Removal requested*' }).Count -eq 0) `
            'A log line that is not a cleanup outcome reached the ledger.'
        Assert-True (@($written | Where-Object { [string]$_.Line -like '2026-06-01*' }).Count -eq 0) `
            'An out-of-window line reached the ledger.'
    }

    if ((Test-Path -LiteralPath $ledgerTwo) -and (@(Import-Csv -LiteralPath $ledgerTwo)).Count -gt 0) {
        $written = @(Import-Csv -LiteralPath $ledgerTwo)

        $expectedSchema = @('EventStampLocal', 'EventStampUtc', 'Worktree', 'Matched', 'Line')
        $actualSchema = @($written[0].PSObject.Properties.Name)
        Assert-True (($actualSchema -join ',') -eq ($expectedSchema -join ',')) `
            "The log ledger schema changed. Expected '$($expectedSchema -join ',')', got '$($actualSchema -join ',')'."

        # The stamp must be unambiguous. 'yyyy-MM-dd HH:mm:ss' carries no zone marker, so a
        # reader cannot tell it apart from the local stamp in the column beside it.
        foreach ($row in $written) {
            Assert-True ([string]$row.EventStampUtc -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$') `
                "EventStampUtc must be ISO 8601 UTC, such as 2026-08-01T08:00:00Z. Got '$($row.EventStampUtc)'."
        }

        $first = @($written | Where-Object { [string]$_.EventStampLocal -eq '2026-08-01 10:00:00' })
        Assert-True ($first.Count -eq 1) 'The 10:00:00 line is missing from the ledger.'
        if ($first.Count -eq 1) {
            Assert-True ([string]$first[0].EventStampUtc -eq '2026-08-01T08:00:00Z') `
                "At UTC+2, 10:00:00 local is 2026-08-01T08:00:00Z. Got '$($first[0].EventStampUtc)'."
            Assert-True ([string]$first[0].Worktree -eq 'wt-alpha') `
                "The worktree column read '$($first[0].Worktree)', not 'wt-alpha'."
        }
    }

    # --- Fixture: a transcript root with four records ---

    $sessionRoot = Join-Path $temp 'projects/fixture'
    New-Item -ItemType Directory -Path $sessionRoot -Force | Out-Null

    $toolLine = '2026-08-01 10:00:00  wt-alpha  Watcher started. PID=4242'
    $pasteLine = '2026-08-01 10:00:07  wt-alpha  Watcher done (removed).'
    $dupeLine = '2026-08-01 10:00:09  wt-beta  Watcher done (removed).'

    # A record identified by message.id, not by uuid. Get-MessageKey prefers message.id, so the
    # metric writes a 'msg:' key whenever the record carries one.
    $byMessageId = [ordered]@{
        type          = 'assistant'
        uuid          = 'ffffffff-0000-0000-0000-000000000001'
        timestamp     = '2026-08-01T08:00:01.000Z'
        toolUseResult = [ordered]@{ stdout = $toolLine }
        message       = [ordered]@{ id = 'msg_fixture_001' }
    }

    # A typed human turn, identified by uuid.
    $byUuid = [ordered]@{
        type         = 'user'
        uuid         = '11111111-2222-3333-4444-555555555555'
        timestamp    = '2026-08-01T08:00:08.000Z'
        promptSource = 'typed'
        message      = [ordered]@{ role = 'user'; content = $pasteLine }
    }

    # Two records claiming one uuid, in one file. The first read must win, and the script must
    # say the choice was made rather than resolving it in silence.
    $dupeFirst = [ordered]@{
        type         = 'user'
        uuid         = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        timestamp    = '2026-08-01T08:00:10.000Z'
        promptSource = 'typed'
        message      = [ordered]@{ role = 'user'; content = $dupeLine }
    }
    $dupeSecond = [ordered]@{
        type          = 'assistant'
        uuid          = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        timestamp     = '2026-08-01T08:00:11.000Z'
        toolUseResult = [ordered]@{ stdout = $dupeLine }
        message       = [ordered]@{ id = 'msg_fixture_dupe' }
    }

    # A second fragment of the message $byMessageId opened. Every fragment carries the same
    # message id, so a repeated 'msg:' key is the normal case, not a clash. It must be counted
    # and not warned about, or the count of real clashes drowns.
    $secondFragment = [ordered]@{
        type          = 'assistant'
        uuid          = 'ffffffff-0000-0000-0000-000000000002'
        timestamp     = '2026-08-01T08:00:02.000Z'
        toolUseResult = [ordered]@{ stdout = 'a later fragment of the same message' }
        message       = [ordered]@{ id = 'msg_fixture_001' }
    }

    $sessionFile = Join-Path $sessionRoot 'fixture-session.jsonl'
    Set-Content -LiteralPath $sessionFile -Encoding utf8 -Value @(
        ($byMessageId | ConvertTo-Json -Depth 8 -Compress)
        ($secondFragment | ConvertTo-Json -Depth 8 -Compress)
        ($byUuid | ConvertTo-Json -Depth 8 -Compress)
        ($dupeFirst | ConvertTo-Json -Depth 8 -Compress)
        ($dupeSecond | ConvertTo-Json -Depth 8 -Compress)
    )

    $fixtureLedger = Join-Path $temp 'fixture-ledger.csv'
    @(
        [pscustomobject]@{
            Key = 'msg:msg_fixture_001'; Session = 'fixture-session.jsonl'
            Matched = '^Watcher started\.'; Line = $toolLine
        }
        [pscustomobject]@{
            Key = 'uuid:11111111-2222-3333-4444-555555555555'; Session = 'fixture-session.jsonl'
            Matched = '^Watcher done \('; Line = $pasteLine
        }
        [pscustomobject]@{
            Key = 'uuid:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; Session = 'fixture-session.jsonl'
            Matched = '^Watcher done \('; Line = $dupeLine
        }
    ) | Export-Csv -LiteralPath $fixtureLedger -NoTypeInformation -Encoding utf8

    # --- 3. The labeller resolves a 'msg:' identity as well as a 'uuid:' one ---

    $labelledOut = Join-Path $temp 'fixture-labelled.csv'
    $labelRun = Invoke-Suite -Script $labelScript -ScriptArguments @(
        '-ProjectRoot', $sessionRoot, '-LedgerPath', $fixtureLedger,
        '-OutputPath', $labelledOut, '-LogPath', $fixtureLog)

    Assert-True ($labelRun.ExitCode -eq 0) `
        "The labeller must succeed on the fixture. It exited $($labelRun.ExitCode).`n$($labelRun.Output)"
    Assert-True (Test-Path -LiteralPath $labelledOut) 'The labeller wrote no output file.'

    if (Test-Path -LiteralPath $labelledOut) {
        $out = @(Import-Csv -LiteralPath $labelledOut)
        $byKey = @{}
        foreach ($row in $out) { $byKey[[string]$row.Key] = $row }

        Assert-True ($out.Count -eq 3) "The labeller wrote $($out.Count) rows for a 3-row ledger."

        # Get-MessageKey writes 'msg:' whenever the record carries a message id. A labeller that
        # reads only 'uuid:' keys silently marks every such row 'unresolved'.
        Assert-True ($byKey.ContainsKey('msg:msg_fixture_001')) 'The msg: row is missing from the output.'
        if ($byKey.ContainsKey('msg:msg_fixture_001')) {
            Assert-True ([string]$byKey['msg:msg_fixture_001'].Route -eq 'tool-result') `
                "A 'msg:' key with a toolUseResult must label as tool-result, not '$($byKey['msg:msg_fixture_001'].Route)'."
            Assert-True ([string]$byKey['msg:msg_fixture_001'].InCurrentLog -eq 'yes') `
                'A line the log holds must read InCurrentLog=yes.'
        }

        $uuidKey = 'uuid:11111111-2222-3333-4444-555555555555'
        Assert-True ($byKey.ContainsKey($uuidKey)) 'The uuid: row is missing from the output.'
        if ($byKey.ContainsKey($uuidKey)) {
            Assert-True ([string]$byKey[$uuidKey].Route -eq 'human-paste') `
                "A typed user turn must label as human-paste, not '$($byKey[$uuidKey].Route)'."
        }

        # --- 4. Two records claiming one uuid: the first read wins, and it says so ---

        $dupeKey = 'uuid:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        Assert-True ($byKey.ContainsKey($dupeKey)) 'The duplicate-uuid row is missing from the output.'
        if ($byKey.ContainsKey($dupeKey)) {
            Assert-True ([string]$byKey[$dupeKey].Route -eq 'human-paste') `
                "The first record read carries the uuid, so the route is human-paste, not '$($byKey[$dupeKey].Route)'."
            # The fixture log does not hold wt-beta's line.
            Assert-True ([string]$byKey[$dupeKey].InCurrentLog -eq 'no') `
                'A line the log does not hold must read InCurrentLog=no.'
        }
        Assert-True ($labelRun.Output -match 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee') `
            "A duplicate identity must be reported, never resolved in silence.`n$($labelRun.Output)"

        # --- 5. A repeated message id is a fragment, not a clash ---

        Assert-True ($labelRun.Output -notmatch 'WARNING.*msg_fixture_001') `
            "A repeated message id is a message fragment. Warning on it buries the real clashes.`n$($labelRun.Output)"
        Assert-True ($labelRun.Output -match 'message fragments\s*:\s*1\b') `
            "The one repeated message id must be counted and reported.`n$($labelRun.Output)"
    }
}
finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

# --- Report ---

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Host ''
        Write-Host $failure -ForegroundColor Red
    }
    Write-Host ''
    throw "Cleanup event script tests failed with $($failures.Count) problem(s). See the detail above."
}

Write-Host 'Cleanup event script tests passed.'
