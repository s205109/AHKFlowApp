#Requires -Version 7.0
<#
.SYNOPSIS
    Blocks the upstream mattpocock-skills slash commands inside AHKFlowApp.

.DESCRIPTION
    AHKFlowApp keeps its own adapted forks of eight upstream skills, named mp-*.
    Each fork points at files in that repository, so the upstream version is the
    wrong one to run there. Permissions cannot stop a slash command the human
    types, because they gate the agent's Skill tool instead. This UserPromptExpansion
    hook does stop it.

    The settings matcher decides which commands reach this script. The script only
    writes the message and exits 2, which blocks the expansion.

    Two upstream skills stay reachable on purpose: handoff and wait-what. The
    repository deleted its copies of both in backlog item 125.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$raw = [Console]::In.ReadToEnd()

# Read the command name from the hook payload. Fall back to a text search when the
# payload shape is not what this script expects, so a rename upstream cannot turn
# the block into a silent pass.
$name = ''
try {
    $payload = $raw | ConvertFrom-Json
    if ($payload.PSObject.Properties.Name -contains 'command_name') {
        $name = [string] $payload.command_name
    }
} catch {
    $name = ''
}

if ([string]::IsNullOrWhiteSpace($name)) {
    if ($raw -match 'mattpocock-skills:([a-z0-9-]+)') {
        $name = $Matches[1]
    }
}

$short = $name -replace '^mattpocock-skills:', ''

if ([string]::IsNullOrWhiteSpace($short)) {
    [Console]::Error.WriteLine('Blocked in AHKFlowApp. This repository has its own adapted fork of this upstream skill. Use the mp- version instead.')
    exit 2
}

$message = @"
Blocked in AHKFlowApp. Use /mp-$short instead of /mattpocock-skills:$short.

This repository keeps an adapted fork of that skill. The fork points at files in
this repository, so the upstream version would give you the wrong instructions.
See .agents/ATTRIBUTION.md for what each fork changed.
"@

[Console]::Error.WriteLine($message)
exit 2
