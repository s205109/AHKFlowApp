#Requires -Version 5.1
<#
.SYNOPSIS
Thin Claude/Codex/Copilot PreToolUse adapter for the cross-agent Git guardrails.

.DESCRIPTION
Reads a native PreToolUse payload from stdin, normalizes it, evaluates the shared policy in
scripts/agents/agent-worktree-guard.common.ps1, and writes the resolved agent's native
allow/warn/deny response. Adapters normalize payloads and responses only - no policy regex or
path decision belongs in this file.

Two kinds of tool call are evaluated. A shell call is classified from its command line by
Invoke-AgentGuardPolicy. A Claude Edit, Write, or NotebookEdit call is classified from its single
literal path by Get-AgentFileEditWriteDecision. Every other tool call exits without a decision.

Adapter 'Auto' infers Copilot from a top-level 'toolArgs' key and Claude otherwise.
#>
[CmdletBinding()]
param(
    [ValidateSet('Auto', 'Claude', 'Codex', 'Copilot')]
    [string] $Adapter = 'Auto'
)

# Emergency kill switch. This must be the first executable statement: strict mode, module
# loading, stdin parsing, and git probes are all downstream of it, so a defect in any of them
# stays recoverable. $Adapter has a safe default so parameter binding cannot block recovery.
if ($env:AHKFLOW_GUARD_DISABLE -eq '1') {
    [Console]::Error.WriteLine(
        'WARNING: AHKFLOW_GUARD_DISABLE=1; all agent command guardrails are disabled.')
    exit 0
}

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'agent-worktree-guard.common.ps1')

function Write-GuardDiagnostic {
    param([string] $Message)

    # Never echo the whole payload or a stack trace - hook stderr is user-visible.
    [Console]::Error.WriteLine("[agent-guard:$Adapter] $Message")
}

$inputJson = [Console]::In.ReadToEnd()

# Claude only: older configurations delivered the command through an environment variable.
if ([string]::IsNullOrWhiteSpace($inputJson) -and
    $Adapter -in @('Auto', 'Claude') -and
    -not [string]::IsNullOrWhiteSpace($env:CLAUDE_TOOL_INPUT)) {
    $inputJson = @{
        hook_event_name = 'PreToolUse'
        tool_name       = 'Bash'
        tool_input      = @{ command = $env:CLAUDE_TOOL_INPUT }
        cwd             = (Get-Location).Path
    } | ConvertTo-Json -Compress -Depth 4
}

try {
    $normalized = ConvertFrom-AgentHookInput -Adapter $Adapter -InputJson $inputJson
    $Adapter = $normalized.Adapter
}
catch {
    # Fail open: an unparseable payload must not take the agent's shell away.
    Write-GuardDiagnostic "could not parse the hook payload; allowing. $($_.Exception.Message)"
    exit 0
}

if ($normalized.ToolName -notin @('shell', 'file-edit')) {
    exit 0
}

# Derive the protected repository from this checked-in script's own location, never from the
# command's target - otherwise `git -C <elsewhere>` would redefine what is being protected.
$protectedRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path

# A file-writing tool call carries one literal path and no command, so none of the command
# evaluators apply to it. It is answered here and never reaches the adapter switch below: the
# only outcomes are a stderr denial, a stderr warning, or silence.
if ($normalized.ToolName -eq 'file-edit') {
    # Codex and Copilot are out of scope. Their file-edit tool names and payload shapes are not
    # verified here. See docs/agents/cross-agent-git-guardrails.md.
    if ($Adapter -ne 'Claude') { exit 0 }

    try {
        $editDecision = Get-AgentFileEditWriteDecision `
            -TargetPath $normalized.TargetPath `
            -Cwd $normalized.Cwd `
            -ProtectedRepoRoot $protectedRepoRoot `
            -AllowMain ($env:AHKFLOW_ALLOW_MAIN -eq '1')
    }
    catch {
        # Fail open, same as the shell write rule: keep the agent's editor usable, but say so.
        Write-GuardDiagnostic "the file-edit write guard could not evaluate this path; allowing. $($_.Exception.Message)"
        exit 0
    }

    if ($editDecision.Action -eq 'Allow') { exit 0 }

    Write-GuardDiagnostic "$($editDecision.Action.ToLowerInvariant()) [$($editDecision.Rule)]"
    [Console]::Error.WriteLine($editDecision.Message)
    if ($editDecision.Action -eq 'Deny') { exit 2 }
    exit 0
}

if ([string]::IsNullOrWhiteSpace($normalized.Command)) {
    Write-GuardDiagnostic 'hook payload carried no command; allowing.'
    exit 0
}

$decision = Invoke-AgentGuardPolicy `
    -Command $normalized.Command `
    -Cwd $normalized.Cwd `
    -ProtectedRepoRoot $protectedRepoRoot `
    -AllowMain ($env:AHKFLOW_ALLOW_MAIN -eq '1')

if ($decision.Action -eq 'Ask' -and -not [string]::IsNullOrWhiteSpace($normalized.AgentId)) {
    $decision = New-AgentGuardDecision -Action Deny -Rule $decision.Rule -Message `
        ($decision.Message + ' This call originated from a subagent and cannot show an interactive prompt. Report this back so the main-thread agent can retry it, which will prompt correctly.')
}

if ($decision.Action -ne 'Allow') {
    # Names the resolved adapter so a real-session probe can prove which contract was selected.
    Write-GuardDiagnostic "$($decision.Action.ToLowerInvariant()) [$($decision.Rule)]"
}

$locationDecisionRules = @('agent-main-git-mutation', 'agent-git-dir-mutation', 'agent-unresolved-git-target')

switch ($Adapter) {
    'Codex' {
        # Codex: 'ask' is parsed but not supported yet - emitting it marks the hook run failed and
        # the tool call proceeds (fails OPEN). Treat Ask exactly like Deny here, never emit 'ask'.
        if ($decision.Action -in @('Deny', 'Ask')) {
            @{
                hookSpecificOutput = @{
                    hookEventName            = 'PreToolUse'
                    permissionDecision       = 'deny'
                    permissionDecisionReason = $decision.Message
                }
            } | ConvertTo-Json -Compress -Depth 4 | Write-Output
            exit 0
        }

        if ($decision.Action -eq 'Warn') {
            @{ systemMessage = $decision.Message } | ConvertTo-Json -Compress -Depth 4 | Write-Output
            exit 0
        }

        if ($decision.Action -eq 'Allow') { exit 0 }

        Write-GuardDiagnostic "unrecognized decision action '$($decision.Action)'; denying to fail closed."
        @{
            hookSpecificOutput = @{
                hookEventName            = 'PreToolUse'
                permissionDecision       = 'deny'
                permissionDecisionReason = 'BLOCKED: the guard produced an unrecognized decision; denying to fail closed.'
            }
        } | ConvertTo-Json -Compress -Depth 4 | Write-Output
        exit 0
    }

    'Copilot' {
        if ($decision.Action -eq 'Deny') {
            @{
                permissionDecision       = 'deny'
                permissionDecisionReason = $decision.Message
            } | ConvertTo-Json -Compress -Depth 4 | Write-Output
            exit 0
        }

        if ($decision.Action -eq 'Ask') {
            @{
                permissionDecision       = 'ask'
                permissionDecisionReason = $decision.Message
            } | ConvertTo-Json -Compress -Depth 4 | Write-Output
            exit 0
        }

        if ($decision.Action -eq 'Warn') {
            @{
                permissionDecision       = 'allow'
                permissionDecisionReason = $decision.Message
            } | ConvertTo-Json -Compress -Depth 4 | Write-Output
            exit 0
        }

        if ($decision.Action -eq 'Allow') { exit 0 }

        Write-GuardDiagnostic "unrecognized decision action '$($decision.Action)'; denying to fail closed."
        @{
            permissionDecision       = 'deny'
            permissionDecisionReason = 'BLOCKED: the guard produced an unrecognized decision; denying to fail closed.'
        } | ConvertTo-Json -Compress -Depth 4 | Write-Output
        exit 0
    }

    default {
        # Claude. Ask and Deny outcomes from the three location rules use the JSON
        # hookSpecificOutput protocol (this is what makes Ask possible at all); everything else
        # (safety-rule Deny, ambiguous-git-command Deny) keeps the legacy stderr + exit 2 protocol.
        if ($decision.Rule -in $locationDecisionRules -and $decision.Action -in @('Ask', 'Deny')) {
            $permissionDecision = if ($decision.Action -eq 'Ask') { 'ask' } else { 'deny' }
            @{
                hookSpecificOutput = @{
                    hookEventName            = 'PreToolUse'
                    permissionDecision       = $permissionDecision
                    permissionDecisionReason = $decision.Message
                }
            } | ConvertTo-Json -Compress -Depth 4 | Write-Output
            exit 0
        }

        if ($decision.Action -eq 'Deny') {
            [Console]::Error.WriteLine($decision.Message)
            exit 2
        }

        if ($decision.Action -eq 'Warn') {
            [Console]::Error.WriteLine($decision.Message)
            exit 0
        }

        if ($decision.Action -eq 'Allow') { exit 0 }

        Write-GuardDiagnostic "unrecognized decision action '$($decision.Action)'; denying to fail closed."
        [Console]::Error.WriteLine('BLOCKED: the guard produced an unrecognized decision; denying to fail closed.')
        exit 2
    }
}
