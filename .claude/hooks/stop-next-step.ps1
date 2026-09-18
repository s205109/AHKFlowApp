#Requires -Version 7.0
<#
.SYNOPSIS
    Stop hook: a turn that used a tool must end with a Next-step line.

.DESCRIPTION
    The rule lives in docs/development/workflow.md, section 7, under "The Recap and the
    Next-step line". A Next-step line is a line that starts `Next:` and names one or two
    concrete steps, or a line that starts `Nothing pending.` A turn with no tool call needs
    neither.

    The hook refuses a stop at most once per turn. Exit code 2 keeps Claude working and hands
    it the stderr text. On the next stop, Claude Code sets stop_hook_active, and this hook
    allows every stop while that is true. Claude Code 2.1.276 gives hooks the same advice when
    one blocks too often: "check stop_hook_active in the input and return success while it's
    true".

    Every error allows the stop. A broken hook must never keep a session from ending.

    The final message comes from last_assistant_message, never from the transcript. The
    hooks reference says the transcript "is written asynchronously and may lag the in-memory
    conversation". The transcript is read only for records written earlier in the turn: the
    human prompt and the tool calls.

.PARAMETER AsModule
    Load the functions and return, so a test can call them. Claude Code never passes it.
#>
[CmdletBinding()]
param([switch] $AsModule)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# A field of a parsed JSON object, or $null when the object or the field is missing. Strict
# mode throws on a missing property, so every read goes through here.
function Get-Field {
    param([AllowNull()] $Object, [Parameter(Mandatory)][string] $Name)
    if ($null -eq $Object -or $Object -isnot [psobject]) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

# The same test as Test-HumanTurn in scripts/measure-process-friction.ps1. A tool result and
# injected skill text are stored as user records too, so type alone is not enough.
# tests/StopNextStepHook.Tests.ps1 runs both functions on the same records.
function Test-HumanPrompt {
    param([AllowNull()] $Record)
    if ((Get-Field $Record 'type') -ne 'user') { return $false }
    if ((Get-Field (Get-Field $Record 'origin') 'kind') -eq 'human') { return $true }
    return ((Get-Field $Record 'promptSource') -in @('typed', 'suggestion_accepted', 'queued'))
}

function Test-ToolCall {
    param([AllowNull()] $Record)
    if ((Get-Field $Record 'type') -ne 'assistant') { return $false }
    $content = Get-Field (Get-Field $Record 'message') 'content'
    foreach ($block in @($content)) {
        if ((Get-Field $block 'type') -eq 'tool_use') { return $true }
    }
    return $false
}

# $true when the line is a tool call, $false when it is the human prompt, $null otherwise.
# A line that is not valid JSON is skipped: the last line may still be half written.
function Get-LineVerdict {
    param([byte[]] $Bytes, [int] $Start, [int] $Length)
    if ($Length -le 0) { return $null }
    $text = [System.Text.Encoding]::UTF8.GetString($Bytes, $Start, $Length).Trim()
    if (-not $text) { return $null }
    try { $record = $text | ConvertFrom-Json -Depth 100 }
    catch { return $null }
    if (Test-ToolCall -Record $record) { return $true }
    if (Test-HumanPrompt -Record $record) { return $false }
    return $null
}

# Reads the transcript from the end, one line at a time, and stops at the first answer: a tool
# call means the turn used a tool, and the human prompt means it did not. The whole file is
# read into memory, but only the lines of the last turn are parsed.
function Test-TurnUsedTool {
    param([Parameter(Mandatory)][string] $TranscriptPath)

    $bytes = [System.IO.File]::ReadAllBytes($TranscriptPath)
    # 10 is the newline byte. UTF-8 never uses it inside a multi-byte character.
    $end = $bytes.Length
    while ($end -gt 0) {
        $newline = [Array]::LastIndexOf($bytes, [byte]10, $end - 1)
        $start = $newline + 1
        $verdict = Get-LineVerdict -Bytes $bytes -Start $start -Length ($end - $start)
        if ($null -ne $verdict) { return $verdict }
        if ($newline -lt 0) { return $false }
        $end = $newline
    }
    return $false
}

# Markup around the marker does not count, so **Next:**, _Next:_ and > Next: all read as Next:.
function ConvertTo-PlainLine {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Line)
    return (($Line -replace '^[>#\s]+', '') -replace '[*_`]', '').Trim()
}

# True when the message ends with a Next-step line. The steps may follow `Next:` on the same
# line or sit in list items below it, so the check reads the last line that is not a list item.
function Test-NextStepLine {
    param([AllowNull()][AllowEmptyString()][string] $Message)
    if ([string]::IsNullOrWhiteSpace($Message)) { return $false }

    $lines = @($Message -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $index = $lines.Count - 1
    $listItems = 0
    while ($index -ge 0 -and $lines[$index] -match '^([-*+]|\d+[.)])\s+\S') {
        $index--
        $listItems++
    }
    if ($index -lt 0) { return $false }

    $line = ConvertTo-PlainLine -Line $lines[$index]
    if ($line -match '^Nothing pending\.') { return $true }
    if ($line -notmatch '^Next:(.*)$') { return $false }
    return ($Matches[1].Trim().Length -gt 0 -or $listItems -gt 0)
}

if ($AsModule) { return }

$refusal = 'This turn used a tool, so it must end with a Next-step line. ' +
    'End the final message with a line that starts "Next:" and names one or two concrete steps, ' +
    'or with a line that starts "Nothing pending." ' +
    'The rule: docs/development/workflow.md#next-step-line.'

try {
    $reader = [System.IO.StreamReader]::new([Console]::OpenStandardInput(), [System.Text.UTF8Encoding]::new($false))
    $hookInput = $reader.ReadToEnd() | ConvertFrom-Json -Depth 100

    if ((Get-Field $hookInput 'stop_hook_active') -eq $true) { exit 0 }

    $message = Get-Field $hookInput 'last_assistant_message'
    if ($null -eq $message) { exit 0 }
    if (Test-NextStepLine -Message ([string]$message)) { exit 0 }

    $transcript = [string](Get-Field $hookInput 'transcript_path')
    if (-not $transcript -or -not (Test-Path -LiteralPath $transcript -PathType Leaf)) { exit 0 }
    if (-not (Test-TurnUsedTool -TranscriptPath $transcript)) { exit 0 }

    [Console]::Error.WriteLine($refusal)
    exit 2
}
catch {
    exit 0
}
