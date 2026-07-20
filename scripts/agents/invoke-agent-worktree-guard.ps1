#Requires -Version 5.1
<#
.SYNOPSIS
Thin Claude/Codex/Copilot PreToolUse adapter for the cross-agent Git guardrails.

.DESCRIPTION
Reads a native PreToolUse payload from stdin, normalizes it, evaluates the shared policy in
scripts/agents/agent-worktree-guard.common.ps1, and writes the resolved agent's native
allow/warn/deny response. Adapters normalize payloads and responses only - no policy regex or
path decision belongs in this file.

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

if ($normalized.ToolName -ne 'shell') {
    exit 0
}

if ([string]::IsNullOrWhiteSpace($normalized.Command)) {
    Write-GuardDiagnostic 'hook payload carried no command; allowing.'
    exit 0
}

# Derive the protected repository from this checked-in script's own location, never from the
# command's target - otherwise `git -C <elsewhere>` would redefine what is being protected.
$protectedRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path

$decision = Invoke-AgentGuardPolicy `
    -Command $normalized.Command `
    -Cwd $normalized.Cwd `
    -ProtectedRepoRoot $protectedRepoRoot `
    -AllowMain ($env:AHKFLOW_ALLOW_MAIN -eq '1')

if ($decision.Action -ne 'Allow') {
    # Names the resolved adapter so a real-session probe can prove which contract was selected.
    Write-GuardDiagnostic "$($decision.Action.ToLowerInvariant()) [$($decision.Rule)]"
}

switch ($Adapter) {
    'Codex' {
        if ($decision.Action -eq 'Deny') {
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
        }

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

        if ($decision.Action -eq 'Warn') {
            @{
                permissionDecision       = 'allow'
                permissionDecisionReason = $decision.Message
            } | ConvertTo-Json -Compress -Depth 4 | Write-Output
        }

        exit 0
    }

    default {
        # Claude: stderr plus exit 2 blocks; exit 0 allows.
        if ($decision.Action -eq 'Deny') {
            [Console]::Error.WriteLine($decision.Message)
            exit 2
        }

        if ($decision.Action -eq 'Warn') {
            [Console]::Error.WriteLine($decision.Message)
        }

        exit 0
    }
}
