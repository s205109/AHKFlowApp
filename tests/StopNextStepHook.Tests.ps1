#Requires -Version 7.0
<#
.SYNOPSIS
Tests the Claude Code Stop hook that asks for a Next-step line.

.DESCRIPTION
Each case writes a small transcript and a hook input under the temp folder, then runs
.claude/hooks/stop-next-step.ps1 as its own process, the way Claude Code runs it. The exit code
is the answer: 2 refuses the stop, 0 allows it.

The last case loads the hook's functions directly. It proves the hook's human-prompt test agrees
with Test-HumanTurn in scripts/measure-process-friction.ps1.

Run it by hand with:  pwsh ./tests/StopNextStepHook.Tests.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$script:HookPath = Join-Path $repoRoot '.claude/hooks/stop-next-step.ps1'
$script:HostExe = [System.Diagnostics.Process]::GetCurrentProcess().Path
$script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-stophook-' + [guid]::NewGuid().ToString('N'))
$script:Failures = New-Object System.Collections.Generic.List[string]
New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-TestCase {
    param([string] $Name, [scriptblock] $Body)
    try {
        & $Body
        Write-Host "  PASS  $Name" -ForegroundColor Green
    }
    catch {
        $script:Failures.Add("$Name :: $($_.Exception.Message)")
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        Write-Host "        $($_.Exception.Message)" -ForegroundColor DarkRed
    }
}

# --- Transcript records, in the shapes Claude Code writes ---

function New-HumanRecord {
    param([string] $Text = 'do the thing')
    return [ordered]@{ type = 'user'; origin = [ordered]@{ kind = 'human' }; promptSource = 'typed'
        message = [ordered]@{ role = 'user'; content = $Text } }
}

function New-ToolCallRecord {
    return [ordered]@{ type = 'assistant'; message = [ordered]@{ role = 'assistant'
            content = @([ordered]@{ type = 'tool_use'; id = 'toolu_1'; name = 'Bash'; input = [ordered]@{ command = 'git status' } }) } }
}

# A tool result is stored as a user record. It must never read as the human prompt.
function New-ToolResultRecord {
    return [ordered]@{ type = 'user'; toolUseResult = 'clean'; message = [ordered]@{ role = 'user'
            content = @([ordered]@{ type = 'tool_result'; tool_use_id = 'toolu_1'; content = 'clean' }) } }
}

function New-TextRecord {
    param([string] $Text = 'Here is the answer.')
    return [ordered]@{ type = 'assistant'; message = [ordered]@{ role = 'assistant'
            content = @([ordered]@{ type = 'text'; text = $Text }) } }
}

function New-Transcript {
    param([object[]] $Records, [string[]] $ExtraLine = @())
    $path = Join-Path $script:TempRoot ('transcript-' + [guid]::NewGuid().ToString('N') + '.jsonl')
    $lines = @($Records | ForEach-Object { $_ | ConvertTo-Json -Depth 20 -Compress }) + $ExtraLine
    [System.IO.File]::WriteAllLines($path, [string[]]$lines, [System.Text.UTF8Encoding]::new($false))
    return $path
}

# A turn that used a tool. The turn before it used none, so a reader that walks past the human
# prompt would give the wrong answer for the next case's transcript.
function New-ToolTurnTranscript {
    return New-Transcript -Records @(
        (New-HumanRecord 'first question'), (New-TextRecord 'An answer with no tool.'),
        (New-HumanRecord 'second question'), (New-ToolCallRecord), (New-ToolResultRecord), (New-TextRecord 'Done.'))
}

# A turn that used no tool. The turn before it did, so a reader that walks past the human
# prompt finds that old tool call and refuses wrongly.
function New-TalkTurnTranscript {
    return New-Transcript -Records @(
        (New-HumanRecord 'first question'), (New-ToolCallRecord), (New-ToolResultRecord), (New-TextRecord 'Done.'),
        (New-HumanRecord 'what does that mean?'), (New-TextRecord 'It means this.'))
}

function New-HookInput {
    param([string] $TranscriptPath, [AllowNull()] $Message, [bool] $Active = $false, [switch] $NoMessage)
    $payload = [ordered]@{ session_id = 'test-session'; transcript_path = $TranscriptPath; cwd = $repoRoot
        hook_event_name = 'Stop'; stop_hook_active = $Active }
    if (-not $NoMessage) { $payload['last_assistant_message'] = $Message }
    return ($payload | ConvertTo-Json -Compress)
}

# Runs the hook exactly as Claude Code does: its own process, the input on stdin.
function Invoke-Hook {
    param([string] $Stdin)
    $id = [guid]::NewGuid().ToString('N')
    $stdinFile = Join-Path $script:TempRoot "stdin-$id.json"
    $stdoutFile = Join-Path $script:TempRoot "stdout-$id.txt"
    $stderrFile = Join-Path $script:TempRoot "stderr-$id.txt"
    [System.IO.File]::WriteAllText($stdinFile, $Stdin, [System.Text.UTF8Encoding]::new($false))
    $proc = Start-Process -FilePath $script:HostExe `
        -ArgumentList @('-NoProfile', '-NonInteractive', '-File', "`"$script:HookPath`"") `
        -RedirectStandardInput $stdinFile -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile `
        -NoNewWindow -PassThru -Wait
    return [pscustomobject]@{
        ExitCode = $proc.ExitCode
        Stderr   = [System.IO.File]::ReadAllText($stderrFile)
    }
}

try {
    # --- The hook as Claude Code runs it ---

    Invoke-TestCase 'A tool turn that ends with no Next-step line is refused' {
        $result = Invoke-Hook (New-HookInput -TranscriptPath (New-ToolTurnTranscript) -Message 'I changed the file.')
        Assert-True ($result.ExitCode -eq 2) "Expected exit 2, got $($result.ExitCode). Stderr: $($result.Stderr)"
        Assert-True ($result.Stderr -match 'Next:' -and $result.Stderr -match 'Nothing pending\.' -and $result.Stderr -match 'next-step-line') `
            "The refusal must name both accepted forms and the rule. Stderr: $($result.Stderr)"
    }

    Invoke-TestCase 'Next: with a step on the same line is allowed' {
        $result = Invoke-Hook (New-HookInput -TranscriptPath (New-ToolTurnTranscript) -Message "I changed the file.`n`nNext: run the suite.")
        Assert-True ($result.ExitCode -eq 0) "Expected exit 0, got $($result.ExitCode). Stderr: $($result.Stderr)"
    }

    Invoke-TestCase 'Bold **Next:** is allowed' {
        $result = Invoke-Hook (New-HookInput -TranscriptPath (New-ToolTurnTranscript) -Message "Done.`n`n**Next:** push the branch.")
        Assert-True ($result.ExitCode -eq 0) "Expected exit 0, got $($result.ExitCode). Stderr: $($result.Stderr)"
    }

    Invoke-TestCase 'Next: followed by two list items is allowed' {
        $message = "Done.`n`nNext:`n- run the suite`n- open the pull request"
        $result = Invoke-Hook (New-HookInput -TranscriptPath (New-ToolTurnTranscript) -Message $message)
        Assert-True ($result.ExitCode -eq 0) "Expected exit 0, got $($result.ExitCode). Stderr: $($result.Stderr)"
    }

    Invoke-TestCase 'Nothing pending. is allowed, with or without words after it' {
        foreach ($ending in @('Nothing pending.', 'Nothing pending. The branch is merged.')) {
            $result = Invoke-Hook (New-HookInput -TranscriptPath (New-ToolTurnTranscript) -Message "Checked it.`n`n$ending")
            Assert-True ($result.ExitCode -eq 0) "Expected exit 0 for '$ending', got $($result.ExitCode)."
        }
    }

    Invoke-TestCase 'A bare Next: with no step is refused' {
        $result = Invoke-Hook (New-HookInput -TranscriptPath (New-ToolTurnTranscript) -Message "Done.`n`nNext:")
        Assert-True ($result.ExitCode -eq 2) "Expected exit 2, got $($result.ExitCode)."
    }

    Invoke-TestCase 'A Next: line followed by a closing sentence is refused' {
        $result = Invoke-Hook (New-HookInput -TranscriptPath (New-ToolTurnTranscript) -Message "Next: push.`n`nLet me know.")
        Assert-True ($result.ExitCode -eq 2) "Expected exit 2, got $($result.ExitCode)."
    }

    Invoke-TestCase 'A turn with no tool call is allowed, even after a tool turn' {
        $result = Invoke-Hook (New-HookInput -TranscriptPath (New-TalkTurnTranscript) -Message 'It means this.')
        Assert-True ($result.ExitCode -eq 0) "Expected exit 0, got $($result.ExitCode). Stderr: $($result.Stderr)"
    }

    Invoke-TestCase 'stop_hook_active true is allowed, so the hook never refuses twice' {
        $result = Invoke-Hook (New-HookInput -TranscriptPath (New-ToolTurnTranscript) -Message 'I changed the file.' -Active $true)
        Assert-True ($result.ExitCode -eq 0) "Expected exit 0, got $($result.ExitCode)."
    }

    Invoke-TestCase 'Input that is not JSON is allowed' {
        $result = Invoke-Hook 'this is not json'
        Assert-True ($result.ExitCode -eq 0) "Expected exit 0, got $($result.ExitCode)."
    }

    Invoke-TestCase 'A missing transcript is allowed' {
        $missing = Join-Path $script:TempRoot 'no-such-transcript.jsonl'
        $result = Invoke-Hook (New-HookInput -TranscriptPath $missing -Message 'I changed the file.')
        Assert-True ($result.ExitCode -eq 0) "Expected exit 0, got $($result.ExitCode)."
    }

    Invoke-TestCase 'A missing last_assistant_message is allowed' {
        $result = Invoke-Hook (New-HookInput -TranscriptPath (New-ToolTurnTranscript) -NoMessage)
        Assert-True ($result.ExitCode -eq 0) "Expected exit 0, got $($result.ExitCode)."
    }

    Invoke-TestCase 'A half-written last transcript line is skipped, not fatal' {
        $path = New-Transcript -Records @((New-HumanRecord), (New-ToolCallRecord), (New-ToolResultRecord)) -ExtraLine @('{"type":"assistant","mess')
        $result = Invoke-Hook (New-HookInput -TranscriptPath $path -Message 'I changed the file.')
        Assert-True ($result.ExitCode -eq 2) "Expected exit 2, got $($result.ExitCode)."
    }

    # --- The functions, loaded directly ---

    # A missing hook must fail the cases below, not end the run before the summary.
    if (Test-Path -LiteralPath $script:HookPath) { . $script:HookPath -AsModule }

    Invoke-TestCase 'Test-HumanPrompt agrees with Test-HumanTurn in measure-process-friction.ps1' {
        . (Join-Path $repoRoot 'scripts/measure-process-friction.ps1') -AsModule
        $records = @(
            (New-HumanRecord)
            [pscustomobject]@{ type = 'user'; promptSource = 'suggestion_accepted'; origin = [pscustomobject]@{ kind = 'human' } }
            [pscustomobject]@{ type = 'user'; promptSource = 'queued' }
            [pscustomobject]@{ type = 'user'; promptSource = 'system'; origin = [pscustomobject]@{ kind = 'task-notification' } }
            (New-ToolResultRecord)
            (New-ToolCallRecord)
            [pscustomobject]@{ type = 'user'; isMeta = $true; message = [pscustomobject]@{ content = 'injected skill text' } }
        )
        foreach ($record in $records) {
            $parsed = ($record | ConvertTo-Json -Depth 20 -Compress) | ConvertFrom-Json -Depth 20
            $json = $record | ConvertTo-Json -Depth 20 -Compress
            Assert-True ((Test-HumanPrompt -Record $parsed) -eq (Test-HumanTurn -Record $parsed)) "The two tests disagree on $json"
        }
    }
}
finally {
    Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:Failures.Count -gt 0) {
    Write-Host "FAILED: $($script:Failures.Count) test(s)" -ForegroundColor Red
    foreach ($failure in $script:Failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'All Stop hook tests passed.' -ForegroundColor Green
exit 0
