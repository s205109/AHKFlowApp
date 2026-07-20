#Requires -Version 5.1
<#
.SYNOPSIS
Focused tests for the cross-agent Git guardrails policy core, adapters, and Bash shim.

.DESCRIPTION
Every git mutation exercised here happens inside a disposable repository under the system temp
directory - never in the real AHKFlowApp checkout.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$suiteRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$commonScript = Join-Path $suiteRoot 'scripts\agents\agent-worktree-guard.common.ps1'
$entrypointScript = Join-Path $suiteRoot 'scripts\agents\invoke-agent-worktree-guard.ps1'
$bashShim = Join-Path $suiteRoot '.claude\hooks\pre-bash-guard.sh'

. $commonScript

# The adapter/entrypoint tests exercise the real protected repository identity, because the
# entrypoint derives it from its own checked-in location and must not be overridable. Only
# read-only classification happens against these paths - every git mutation in this suite runs
# in the disposable fixture below.
$script:RealMainCheckout = Split-Path -Parent (
    (& git -C $suiteRoot rev-parse --path-format=absolute --git-common-dir).Trim())
$script:RealMainCheckout = (Resolve-Path -LiteralPath $script:RealMainCheckout).Path

$script:Failures = New-Object System.Collections.Generic.List[string]

# Windows PowerShell 5.1 promotes native stderr to a terminating error under -ErrorAction Stop,
# and git narrates ordinary progress on stderr. Run every fixture git call through here.
function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]] $GitArguments)

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & git @GitArguments 2>&1 | Out-Null
        # Emit nothing: these calls sit inside functions whose return value is the fixture.
        $script:LastGitExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }
}

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [string] $Message)
    if (-not [string]::Equals([string] $Expected, [string] $Actual, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Message (expected '$Expected', got '$Actual')"
    }
}

function Assert-Match {
    param([string] $Pattern, [string] $Actual, [string] $Message)
    if ($Actual -notmatch $Pattern) {
        throw "$Message (expected match '$Pattern', got '$Actual')"
    }
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

# ── Process helpers ─────────────────────────────────────────────────────────────────────────

function Invoke-CapturedProcess {
    param(
        [string] $FilePath,
        [string[]] $Arguments,
        [string] $StdIn = '',
        [hashtable] $EnvironmentOverrides = @{},
        [string] $WorkingDirectory = $suiteRoot
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    if ($startInfo.PSObject.Properties['ArgumentList']) {
        foreach ($argument in $Arguments) { [void] $startInfo.ArgumentList.Add($argument) }
    }
    else {
        # ProcessStartInfo.ArgumentList is .NET Core only; Windows PowerShell 5.1 needs a
        # pre-quoted command line.
        $startInfo.Arguments = ($Arguments | ForEach-Object {
                if ($_ -match '[\s"]') { '"' + ($_ -replace '(\\*)"', '$1$1\"') + '"' } else { $_ }
            }) -join ' '
    }
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.UseShellExecute = $false
    $startInfo.WorkingDirectory = $WorkingDirectory

    # Explicitly clear the bypass switches so an operator's ambient environment cannot make a
    # denial test pass vacuously.
    $startInfo.EnvironmentVariables['AHKFLOW_GUARD_DISABLE'] = ''
    $startInfo.EnvironmentVariables['AHKFLOW_ALLOW_MAIN'] = ''
    $startInfo.EnvironmentVariables['CLAUDE_TOOL_INPUT'] = ''
    foreach ($key in $EnvironmentOverrides.Keys) {
        $startInfo.EnvironmentVariables[$key] = [string] $EnvironmentOverrides[$key]
    }

    $process = [System.Diagnostics.Process]::Start($startInfo)
    $process.StandardInput.Write($StdIn)
    $process.StandardInput.Close()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        StdOut   = $stdout
        StdErr   = $stderr
    }
}

# Run the entrypoint under the same PowerShell host that is running this suite, so a single
# invocation of the file under pwsh and under powershell.exe covers both supported hosts.
$script:PowerShellHost = (Get-Process -Id $PID).Path

function Invoke-Entrypoint {
    param(
        [string] $StdIn,
        [string] $Adapter = 'Auto',
        [hashtable] $EnvironmentOverrides = @{},
        [string] $WorkingDirectory = $suiteRoot
    )

    return Invoke-CapturedProcess -FilePath $script:PowerShellHost `
        -Arguments @('-NoProfile', '-NonInteractive', '-File', $entrypointScript, '-Adapter', $Adapter) `
        -StdIn $StdIn -EnvironmentOverrides $EnvironmentOverrides -WorkingDirectory $WorkingDirectory
}

function ConvertTo-BashPath {
    param([string] $Path)

    # Git Bash cannot open a Windows path passed as a bash argument: the backslashes are eaten
    # as escapes. Hand it the /c/... form instead.
    $normalized = $Path -replace '\\', '/'
    if ($normalized -match '^([A-Za-z]):/(.*)$') {
        return "/$($Matches[1].ToLowerInvariant())/$($Matches[2])"
    }

    return $normalized
}

function Resolve-BashExecutable {
    # A bare 'bash' on Windows can resolve to WSL, whose filesystem layout has no /c/... paths.
    # Prefer the bash that ships beside git, which is the one the agent hooks actually run under.
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        $gitBash = Join-Path (Split-Path -Parent (Split-Path -Parent $git.Source)) 'bin\bash.exe'
        if (Test-Path -LiteralPath $gitBash) { return (Resolve-Path -LiteralPath $gitBash).Path }
    }

    $bash = Get-Command bash -ErrorAction SilentlyContinue
    if ($bash) { return $bash.Source }

    throw 'No bash executable was found; the Bash shim tests cannot run.'
}

$script:BashExecutable = Resolve-BashExecutable

function Invoke-BashShim {
    param(
        [string] $StdIn,
        [string[]] $ShimArguments = @(),
        [hashtable] $EnvironmentOverrides = @{}
    )

    return Invoke-CapturedProcess -FilePath $script:BashExecutable `
        -Arguments (@((ConvertTo-BashPath $bashShim)) + $ShimArguments) `
        -StdIn $StdIn -EnvironmentOverrides $EnvironmentOverrides
}

function New-ClaudePayload {
    param([string] $Command, [string] $Cwd)
    return @{
        hook_event_name = 'PreToolUse'
        tool_name       = 'Bash'
        tool_input      = @{ command = $Command }
        cwd             = $Cwd
    } | ConvertTo-Json -Compress -Depth 4
}

function New-CodexPayload {
    param([string] $Command, [string] $Cwd)
    return @{
        hook_event_name = 'PreToolUse'
        tool_name       = 'shell_command'
        tool_input      = @{ command = $Command }
        cwd             = $Cwd
    } | ConvertTo-Json -Compress -Depth 4
}

function New-CopilotPayload {
    param([string] $Command, [string] $Cwd, [string] $ToolName = 'bash')
    return @{
        toolName = $ToolName
        toolArgs = (@{ command = $Command } | ConvertTo-Json -Compress)
        cwd      = $Cwd
    } | ConvertTo-Json -Compress -Depth 4
}

# ── Disposable git fixture ──────────────────────────────────────────────────────────────────

function New-GuardFixture {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
        'ahkflow-agent-guard-' + [guid]::NewGuid().ToString('N'))
    $main = Join-Path $testRoot 'repo'
    $managed = Join-Path $main '.claude\worktrees\valid'
    $badManifest = Join-Path $main '.claude\worktrees\badmanifest'
    # One level deeper than the approved parent: an approved grandparent must not qualify.
    $nested = Join-Path $main '.claude\worktrees\group\nested'
    # 'worktrees-evil' shares a prefix with the approved 'worktrees' parent but is not it.
    $siblingPrefix = Join-Path $main '.claude\worktrees-evil\lookalike'
    $unmanaged = Join-Path $testRoot 'unmanaged'
    $unrelated = Join-Path $testRoot 'unrelated'

    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

    Invoke-Git init --initial-branch=main $main
    Invoke-Git init --initial-branch=main $unrelated
    Invoke-Git -C $main config user.name 'Agent Guard Test'
    Invoke-Git -C $main config user.email 'agent-guard@example.invalid'
    Set-Content -LiteralPath (Join-Path $main 'seed.txt') -Value 'seed' -Encoding utf8
    Invoke-Git -C $main add seed.txt
    Invoke-Git -C $main commit -m 'test: seed temporary repository'
    Invoke-Git -C $main worktree add -b feature/wt-valid $managed
    Invoke-Git -C $main worktree add -b feature/wt-badmanifest $badManifest
    Invoke-Git -C $main worktree add -b feature/wt-nested $nested
    Invoke-Git -C $main worktree add -b feature/wt-sibling $siblingPrefix
    Invoke-Git -C $main worktree add -b feature/wt-unmanaged $unmanaged

    $managedRoot = (Resolve-Path -LiteralPath $managed).Path
    New-Item -ItemType Directory -Path (Join-Path $managedRoot 'scripts') -Force | Out-Null
    $manifest = @(
        'AHKFLOW_API_PORT=5602',
        'AHKFLOW_UI_PORT=5603',
        'AHKFLOW_API_URL=http://localhost:5602',
        'AHKFLOW_UI_URL=http://localhost:5603',
        'AHKFLOW_DB_NAME=AHKFlowApp_valid',
        'AHKFLOW_SQL_PORT=14330',
        'AHKFLOW_COMPOSE_PROJECT=ahkflow-valid',
        "AHKFLOW_ROOT=$managedRoot"
    ) -join "`n"
    Set-Content -LiteralPath (Join-Path $managedRoot 'scripts\.env.worktree') -Value $manifest -Encoding utf8

    # badManifest sits in an approved parent but its manifest port disagrees with its URL.
    $badRoot = (Resolve-Path -LiteralPath $badManifest).Path
    New-Item -ItemType Directory -Path (Join-Path $badRoot 'scripts') -Force | Out-Null
    $broken = @(
        'AHKFLOW_API_PORT=5602',
        'AHKFLOW_UI_PORT=5603',
        'AHKFLOW_API_URL=http://localhost:9999',
        'AHKFLOW_UI_URL=http://localhost:5603',
        'AHKFLOW_DB_NAME=AHKFlowApp_bad',
        'AHKFLOW_SQL_PORT=14331',
        'AHKFLOW_COMPOSE_PROJECT=ahkflow-bad',
        "AHKFLOW_ROOT=$badRoot"
    ) -join "`n"
    Set-Content -LiteralPath (Join-Path $badRoot 'scripts\.env.worktree') -Value $broken -Encoding utf8

    # Both of these get a *valid* manifest on purpose: their rejection must come from the
    # approved-direct-child location rule, not from a manifest that happens to be missing.
    $nestedRoot = (Resolve-Path -LiteralPath $nested).Path
    $siblingRoot = (Resolve-Path -LiteralPath $siblingPrefix).Path
    foreach ($root in @($nestedRoot, $siblingRoot)) {
        New-Item -ItemType Directory -Path (Join-Path $root 'scripts') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'scripts\.env.worktree') -Encoding utf8 -Value (@(
                'AHKFLOW_API_PORT=5602',
                'AHKFLOW_UI_PORT=5603',
                'AHKFLOW_API_URL=http://localhost:5602',
                'AHKFLOW_UI_URL=http://localhost:5603',
                'AHKFLOW_DB_NAME=AHKFlowApp_x',
                'AHKFLOW_SQL_PORT=14332',
                'AHKFLOW_COMPOSE_PROJECT=ahkflow-x',
                "AHKFLOW_ROOT=$root"
            ) -join "`n")
    }

    return [pscustomobject]@{
        TestRoot      = (Resolve-Path -LiteralPath $testRoot).Path
        Main          = (Resolve-Path -LiteralPath $main).Path
        Managed       = $managedRoot
        BadManifest   = $badRoot
        Nested        = $nestedRoot
        SiblingPrefix = $siblingRoot
        Unmanaged     = (Resolve-Path -LiteralPath $unmanaged).Path
        Unrelated     = (Resolve-Path -LiteralPath $unrelated).Path
    }
}

function Remove-GuardFixture {
    param([object] $Fixture)

    if ($null -eq $Fixture) { return }

    $tempRoot = (Resolve-Path -LiteralPath ([System.IO.Path]::GetTempPath())).Path.TrimEnd('\', '/')
    $target = $Fixture.TestRoot.TrimEnd('\', '/')
    if (-not $target.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to delete a fixture outside the temp directory: $target"
    }

    foreach ($worktree in @(
            $Fixture.Managed, $Fixture.BadManifest, $Fixture.Nested,
            $Fixture.SiblingPrefix, $Fixture.Unmanaged)) {
        Invoke-Git -C $Fixture.Main worktree remove --force $worktree
    }
    Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
}

# ── Tests ───────────────────────────────────────────────────────────────────────────────────

$fixture = $null
try {
    $fixture = New-GuardFixture

    Write-Host 'Payload normalization' -ForegroundColor Cyan

    $payloadCases = @(
        @{ Name = 'Claude snake-case payload'; Adapter = 'Claude'; Json = (New-ClaudePayload 'git reset --hard' $fixture.Main) },
        @{ Name = 'Codex snake-case payload'; Adapter = 'Codex'; Json = (New-CodexPayload 'git reset --hard' $fixture.Main) },
        @{ Name = 'Copilot camel-case payload with JSON toolArgs'; Adapter = 'Copilot'; Json = (New-CopilotPayload 'git reset --hard' $fixture.Main) }
    )

    foreach ($case in $payloadCases) {
        Invoke-TestCase "$($case.Name) normalizes to the shared contract" {
            $normalized = ConvertFrom-AgentHookInput -Adapter $case.Adapter -InputJson $case.Json
            Assert-Equal $case.Adapter $normalized.Adapter 'Adapter'
            Assert-Equal 'shell' $normalized.ToolName 'ToolName'
            Assert-Equal 'git reset --hard' $normalized.Command 'Command'
            Assert-Equal $fixture.Main $normalized.Cwd 'Cwd'
        }
    }

    Invoke-TestCase 'Auto adapter infers Copilot from a top-level toolArgs key' {
        $normalized = ConvertFrom-AgentHookInput -Adapter 'Auto' -InputJson (New-CopilotPayload 'git status' $fixture.Main)
        Assert-Equal 'Copilot' $normalized.Adapter 'Adapter'
    }

    Invoke-TestCase 'Auto adapter falls back to Claude without toolArgs' {
        $normalized = ConvertFrom-AgentHookInput -Adapter 'Auto' -InputJson (New-ClaudePayload 'git status' $fixture.Main)
        Assert-Equal 'Claude' $normalized.Adapter 'Adapter'
    }

    Write-Host 'Entrypoint input handling' -ForegroundColor Cyan

    Invoke-TestCase 'AHKFLOW_GUARD_DISABLE=1 short-circuits before parsing and warns' {
        $result = Invoke-Entrypoint -StdIn 'this is not json at all' -Adapter 'Claude' `
            -EnvironmentOverrides @{ AHKFLOW_GUARD_DISABLE = '1' }
        Assert-Equal 0 $result.ExitCode 'ExitCode'
        Assert-Match 'AHKFLOW_GUARD_DISABLE=1' $result.StdErr 'StdErr'
    }

    Invoke-TestCase 'AHKFLOW_GUARD_DISABLE=1 allows an otherwise denied command' {
        $result = Invoke-Entrypoint -StdIn (New-ClaudePayload 'git reset --hard' $fixture.Main) -Adapter 'Claude' `
            -EnvironmentOverrides @{ AHKFLOW_GUARD_DISABLE = '1' }
        Assert-Equal 0 $result.ExitCode 'ExitCode'
    }

    Invoke-TestCase 'Malformed JSON warns and allows' {
        $result = Invoke-Entrypoint -StdIn '{ this is not json' -Adapter 'Claude'
        Assert-Equal 0 $result.ExitCode 'ExitCode'
        Assert-Match 'could not parse' $result.StdErr 'StdErr'
    }

    Invoke-TestCase 'Parseable payload with an empty command warns and allows' {
        $result = Invoke-Entrypoint -StdIn (New-ClaudePayload '' $fixture.Main) -Adapter 'Claude'
        Assert-Equal 0 $result.ExitCode 'ExitCode'
        Assert-Match 'no command' $result.StdErr 'StdErr'
    }

    Invoke-TestCase 'Copilot non-shell tool payload is allowed without policy evaluation' {
        $json = @{
            toolName = 'str_replace_editor'
            toolArgs = (@{ path = 'README.md' } | ConvertTo-Json -Compress)
            cwd      = $fixture.Main
        } | ConvertTo-Json -Compress -Depth 4
        $result = Invoke-Entrypoint -StdIn $json -Adapter 'Copilot'
        Assert-Equal 0 $result.ExitCode 'ExitCode'
        Assert-Equal '' $result.StdOut.Trim() 'StdOut'
    }

    Invoke-TestCase 'CLAUDE_TOOL_INPUT fallback applies only when stdin is empty' {
        $result = Invoke-Entrypoint -StdIn '' -Adapter 'Claude' -WorkingDirectory $fixture.Main `
            -EnvironmentOverrides @{ CLAUDE_TOOL_INPUT = 'git reset --hard' }
        Assert-Equal 2 $result.ExitCode 'ExitCode'
        Assert-Match 'BLOCKED' $result.StdErr 'StdErr'
    }

    Invoke-TestCase 'CLAUDE_TOOL_INPUT is ignored when stdin carries a payload' {
        $result = Invoke-Entrypoint -StdIn (New-ClaudePayload 'git status' $fixture.Main) -Adapter 'Claude' `
            -EnvironmentOverrides @{ CLAUDE_TOOL_INPUT = 'git reset --hard' }
        Assert-Equal 0 $result.ExitCode 'ExitCode'
    }

    Write-Host 'Ported safety rules' -ForegroundColor Cyan

    $safetyCases = @(
        @{ Command = 'git push --force'; Action = 'Deny'; Rule = 'force-push' },
        @{ Command = 'git push -f'; Action = 'Deny'; Rule = 'force-push' },
        @{ Command = 'git reset --hard'; Action = 'Deny'; Rule = 'git-reset-hard' },
        @{ Command = 'git clean -f'; Action = 'Deny'; Rule = 'git-clean-force' },
        @{ Command = 'git clean -xdf'; Action = 'Deny'; Rule = 'git-clean-force' },
        @{ Command = 'git checkout .'; Action = 'Deny'; Rule = 'git-checkout-dot' },
        @{ Command = 'rm -rf src'; Action = 'Deny'; Rule = 'dangerous-rm' },
        @{ Command = 'rm -fr src'; Action = 'Deny'; Rule = 'dangerous-rm' },
        @{ Command = 'rm -rf node_modules'; Action = 'Allow'; Rule = 'none' },
        @{ Command = 'rm -rf bin'; Action = 'Allow'; Rule = 'none' },
        @{ Command = 'rm -rf obj'; Action = 'Allow'; Rule = 'none' },
        @{ Command = 'rm -rf TestResults'; Action = 'Allow'; Rule = 'none' },
        @{ Command = 'rm -rf .vs'; Action = 'Allow'; Rule = 'none' },
        @{ Command = 'rm -rf /tmp'; Action = 'Allow'; Rule = 'none' },
        @{ Command = 'dotnet run'; Action = 'Warn'; Rule = 'dotnet-run' },
        @{ Command = 'rg -n "Goal" README.md'; Action = 'Allow'; Rule = 'none' }
    )

    foreach ($case in $safetyCases) {
        Invoke-TestCase "Safety rule: $($case.Command)" {
            $decision = Get-AgentCommandSafetyDecision -Command $case.Command
            Assert-Equal $case.Action $decision.Action 'Action'
            Assert-Equal $case.Rule $decision.Rule 'Rule'
        }
    }

    # Regression: these were all classified with regexes over the raw command, so anything between
    # `git` and the subcommand (-C, .exe, a global option) silently skipped the destructive rule -
    # and AHKFLOW_ALLOW_MAIN=1 then downgraded the location denial to a warning.
    $indirectSafetyCases = @(
        @{ Command = 'git -C . reset --hard'; Rule = 'git-reset-hard' },
        @{ Command = 'git.exe reset --hard'; Rule = 'git-reset-hard' },
        @{ Command = 'git --no-pager checkout .'; Rule = 'git-checkout-dot' },
        @{ Command = 'git -C . clean -fd'; Rule = 'git-clean-force' },
        @{ Command = 'git -C . push origin -f'; Rule = 'force-push' },
        @{ Command = 'git -c core.pager=cat reset --hard HEAD~1'; Rule = 'git-reset-hard' },
        @{ Command = 'git status && git.exe push --force origin main'; Rule = 'force-push' }
    )

    foreach ($case in $indirectSafetyCases) {
        Invoke-TestCase "Safety rule survives indirection: $($case.Command)" {
            $decision = Get-AgentCommandSafetyDecision -Command $case.Command
            Assert-Equal 'Deny' $decision.Action 'Action'
            Assert-Equal $case.Rule $decision.Rule 'Rule'
        }

        Invoke-TestCase "AHKFLOW_ALLOW_MAIN=1 cannot downgrade: $($case.Command)" {
            $decision = Invoke-AgentGuardPolicy -Command $case.Command `
                -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main -AllowMain $true
            Assert-Equal 'Deny' $decision.Action 'Action'
            Assert-Equal $case.Rule $decision.Rule 'Rule'
        }
    }

    Write-Host 'Precedence and fault handling' -ForegroundColor Cyan

    Invoke-TestCase 'AHKFLOW_ALLOW_MAIN=1 downgrades a location denial to Warn' {
        $decision = Invoke-AgentGuardPolicy -Command 'git commit --allow-empty -m test' `
            -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main -AllowMain $true
        Assert-Equal 'Warn' $decision.Action 'Action'
        Assert-Match 'AHKFLOW_ALLOW_MAIN' $decision.Message 'Message'
    }

    Invoke-TestCase 'AHKFLOW_ALLOW_MAIN=1 never relaxes a safety denial' {
        $decision = Invoke-AgentGuardPolicy -Command 'git reset --hard' `
            -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main -AllowMain $true
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Equal 'git-reset-hard' $decision.Rule 'Rule'
    }

    Invoke-TestCase 'A location classifier fault fails open with a warning' {
        function Get-AgentWorktreeGuardDecision { param($Command, $Cwd, $ProtectedRepoRoot, $AllowMain) throw 'injected location fault' }
        $decision = Invoke-AgentGuardPolicy -Command 'git commit -m test' `
            -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Warn' $decision.Action 'Action'
        Assert-Equal 'location-guard-error' $decision.Rule 'Rule'
    }

    Invoke-TestCase 'A safety evaluator fault fails closed' {
        function Get-AgentCommandSafetyDecision { param($Command) throw 'injected safety fault' }
        $decision = Invoke-AgentGuardPolicy -Command 'git status' `
            -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Equal 'safety-guard-error' $decision.Rule 'Rule'
    }

    Write-Host 'Location policy' -ForegroundColor Cyan

    Invoke-TestCase 'Mutating git in the protected main checkout is denied' {
        $decision = Invoke-AgentGuardPolicy -Command 'git commit -m test' `
            -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Match 'BLOCKED: agent Git mutations' $decision.Message 'Message'
    }

    # The old wording just said "Override with AHKFLOW_ALLOW_MAIN=1", which reads as actionable to
    # the agent seeing it - but an inline prefix never reaches this evaluator's own process.
    Invoke-TestCase 'The denial message says where the override must be set' {
        $decision = Invoke-AgentGuardPolicy -Command 'git commit -m test' `
            -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
        # Fragments must not span the here-string's line wraps.
        Assert-Match 'in the shell environment before starting the' $decision.Message 'Message'
        Assert-Match 'prefix does not work' $decision.Message 'Message'
    }

    Invoke-TestCase 'Mutating git in a managed linked worktree is allowed' {
        $decision = Invoke-AgentGuardPolicy -Command 'git commit -m test' `
            -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Allow' $decision.Action 'Action'
    }

    Invoke-TestCase 'Mutating git in an unmanaged linked worktree is denied' {
        $decision = Invoke-AgentGuardPolicy -Command 'git commit -m test' `
            -Cwd $fixture.Unmanaged -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Deny' $decision.Action 'Action'
    }

    Invoke-TestCase 'Read-only git in the protected main checkout is allowed' {
        $decision = Invoke-AgentGuardPolicy -Command 'git status --short' `
            -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Allow' $decision.Action 'Action'
    }

    Invoke-TestCase 'Mutating git in an unrelated repository is allowed' {
        $decision = Invoke-AgentGuardPolicy -Command 'git commit -m test' `
            -Cwd $fixture.Unrelated -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Allow' $decision.Action 'Action'
    }

    Invoke-TestCase 'An unbalanced quote is an explicit ambiguous-git-command denial' {
        $decision = Invoke-AgentGuardPolicy -Command 'git -C "C:\unbalanced;path commit -m test' `
            -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Equal 'ambiguous-git-command' $decision.Rule 'Rule'
    }

    Write-Host 'Mutation detection' -ForegroundColor Cyan

    $mutatingCommands = @(
        'git add .', 'git commit -m test', '  git commit -m indented', 'git switch -c fix/wt-test',
        'git checkout -b fix/wt-test', 'git branch fix/wt-test', 'git merge topic', 'git rebase main',
        'git push', 'git reset HEAD^', 'git restore file.txt', 'git clean -fd', 'git stash',
        'git tag v1.0.0', 'git worktree add somewhere', 'git config core.hooksPath disabled',
        'git update-ref refs/heads/test HEAD', 'git status; git commit -m test',
        'git status && git branch fix/wt-test', 'git stash push', 'git notes add -m note HEAD',
        'git bisect start', 'git apply patch.diff', 'git init .', 'git submodule update',
        'git remote add origin url', 'git reflog delete', 'git config user.name bob',
        'git config set user.name bob', 'git config unset user.name', 'git.exe commit -m test',
        'git -C somewhere commit -m test', 'FOO=1 git commit -m test', 'git branch -f main HEAD'
    )
    foreach ($command in $mutatingCommands) {
        Invoke-TestCase "Mutation detected: $command" {
            $parsed = Get-AgentGitInvocation -Command $command
            $anyMutation = @($parsed.Invocations | Where-Object { Test-AgentGitMutation -Tokens $_ }).Count -gt 0
            Assert-True $anyMutation 'expected a mutation'
        }
    }

    $readOnlyCommands = @(
        'git status', 'git log -1', 'git diff', 'git show HEAD', 'git branch --show-current',
        'git branch --list', 'git tag --list', 'git worktree list', 'git config --get core.hooksPath',
        'git remote -v', 'git fetch', 'git stash list', 'git stash show', 'git notes list',
        'git notes show HEAD', 'git bisect log', 'git apply --check patch.diff',
        "git log --author='O'\''Brien'", 'rg -n "Backend" README.md', 'Get-Content README.md',
        'dotnet build', 'dotnet test', 'dotnet format', 'git status > status.txt',
        'git config --get-regexp branch', 'git remote show origin', 'git submodule status',
        'git tag --contains HEAD',
        # Ordinary inspection that a positional-argument-means-mutation rule wrongly denied.
        "git branch --list 'feature/*'", 'git branch --contains HEAD', 'git branch --merged main',
        'git branch --points-at HEAD', 'git tag -v v1.0.0', 'git tag --verify v1.0.0',
        'git tag --points-at HEAD', 'git config get core.hooksPath', 'git config list',
        'git -C somewhere status', 'git.exe status'
    )
    foreach ($command in $readOnlyCommands) {
        Invoke-TestCase "No mutation: $command" {
            $parsed = Get-AgentGitInvocation -Command $command
            if ($parsed.Ambiguous) { throw 'unexpected ambiguous parse' }
            $anyMutation = @($parsed.Invocations | Where-Object { Test-AgentGitMutation -Tokens $_ }).Count -gt 0
            Assert-True (-not $anyMutation) 'expected no mutation'
        }
    }

    Write-Host 'Managed-worktree classification' -ForegroundColor Cyan

    $stateCases = @(
        @{ Name = 'main checkout'; Cwd = { $fixture.Main }; State = 'MainCheckout' },
        @{ Name = 'managed worktree'; Cwd = { $fixture.Managed }; State = 'ManagedWorktree' },
        @{ Name = 'unmanaged linked worktree'; Cwd = { $fixture.Unmanaged }; State = 'UnmanagedWorktree' },
        @{ Name = 'nested below an approved parent'; Cwd = { $fixture.Nested }; State = 'UnmanagedWorktree' },
        @{ Name = 'sibling-prefix parent (.claude/worktrees-evil)'; Cwd = { $fixture.SiblingPrefix }; State = 'UnmanagedWorktree' },
        @{ Name = 'approved location, invalid manifest'; Cwd = { $fixture.BadManifest }; State = 'InvalidManifest' },
        @{ Name = 'unrelated repository'; Cwd = { $fixture.Unrelated }; State = 'OutsideProtectedRepository' },
        @{ Name = 'non-repository temp dir'; Cwd = { $fixture.TestRoot }; State = 'NotRepository' }
    )
    foreach ($case in $stateCases) {
        Invoke-TestCase "State: $($case.Name)" {
            $state = Get-ManagedWorktreeState -Cwd (& $case.Cwd) -ProtectedRepoRoot $fixture.Main
            Assert-Equal $case.State $state 'State'
        }
    }

    Invoke-TestCase 'Manifest with a missing key is invalid' {
        $missing = Join-Path $fixture.Managed 'scripts\.env.worktree'
        $original = Get-Content -LiteralPath $missing -Raw
        try {
            Set-Content -LiteralPath $missing -Value ($original -replace 'AHKFLOW_DB_NAME=.*\r?\n', '') -Encoding utf8
            Assert-Equal 'InvalidManifest' (Get-ManagedWorktreeState -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main) 'State'
        }
        finally {
            Set-Content -LiteralPath $missing -Value $original -Encoding utf8 -NoNewline
        }
    }

    Invoke-TestCase 'Manifest whose AHKFLOW_ROOT points at another directory is invalid' {
        $path = Join-Path $fixture.Managed 'scripts\.env.worktree'
        $original = Get-Content -LiteralPath $path -Raw
        try {
            Set-Content -LiteralPath $path -Encoding utf8 -Value (
                $original -replace 'AHKFLOW_ROOT=.*', "AHKFLOW_ROOT=$($fixture.Main)")
            Assert-Equal 'InvalidManifest' (Get-ManagedWorktreeState -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main) 'State'
        }
        finally {
            Set-Content -LiteralPath $path -Value $original -Encoding utf8 -NoNewline
        }
    }

    Invoke-TestCase 'Manifest with a nonnumeric port is invalid' {
        $path = Join-Path $fixture.Managed 'scripts\.env.worktree'
        $original = Get-Content -LiteralPath $path -Raw
        try {
            Set-Content -LiteralPath $path -Encoding utf8 -Value (
                $original -replace 'AHKFLOW_SQL_PORT=.*', 'AHKFLOW_SQL_PORT=not-a-port')
            Assert-Equal 'InvalidManifest' (Get-ManagedWorktreeState -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main) 'State'
        }
        finally {
            Set-Content -LiteralPath $path -Value $original -Encoding utf8 -NoNewline
        }
    }

    Invoke-TestCase 'Missing manifest is invalid' {
        $path = Join-Path $fixture.Managed 'scripts\.env.worktree'
        $original = Get-Content -LiteralPath $path -Raw
        try {
            Remove-Item -LiteralPath $path -Force
            Assert-Equal 'InvalidManifest' (Get-ManagedWorktreeState -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main) 'State'
        }
        finally {
            Set-Content -LiteralPath $path -Value $original -Encoding utf8 -NoNewline
        }
    }

    Invoke-TestCase 'Manifest with a duplicate key is invalid' {
        $path = Join-Path $fixture.Managed 'scripts\.env.worktree'
        $original = Get-Content -LiteralPath $path -Raw
        try {
            Set-Content -LiteralPath $path -Value ($original + "`nAHKFLOW_DB_NAME=second") -Encoding utf8
            Assert-Equal 'InvalidManifest' (Get-ManagedWorktreeState -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main) 'State'
        }
        finally {
            Set-Content -LiteralPath $path -Value $original -Encoding utf8 -NoNewline
        }
    }

    Write-Host 'Effective git -C target resolution' -ForegroundColor Cyan

    Invoke-TestCase 'Managed worktree targeting main through git -C is denied' {
        $command = "git -C `"$($fixture.Main)`" commit -m test"
        $decision = Invoke-AgentGuardPolicy -Command $command -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Deny' $decision.Action 'Action'
    }

    Invoke-TestCase 'Main targeting a managed worktree through git -C is allowed' {
        $command = "git -C `"$($fixture.Managed)`" commit -m test"
        $decision = Invoke-AgentGuardPolicy -Command $command -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Allow' $decision.Action 'Action'
    }

    Invoke-TestCase 'Main targeting an unrelated repository through git -C is allowed' {
        $command = "git -C `"$($fixture.Unrelated)`" commit -m test"
        $decision = Invoke-AgentGuardPolicy -Command $command -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Allow' $decision.Action 'Action'
    }

    # Regression: the guard classified the payload's own cwd, so a chained directory change moved
    # the real target into main while the decision was still being made about the worktree.
    Invoke-TestCase 'cd into main before a git mutation is denied' {
        $command = "cd `"$($fixture.Main)`" && git commit -m test"
        $decision = Invoke-AgentGuardPolicy -Command $command -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Equal 'agent-main-git-mutation' $decision.Rule 'Rule'
    }

    Invoke-TestCase 'Set-Location into main before a git mutation is denied' {
        $command = "Set-Location -LiteralPath `"$($fixture.Main)`"; git branch review-bypass"
        $decision = Invoke-AgentGuardPolicy -Command $command -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Equal 'agent-main-git-mutation' $decision.Rule 'Rule'
    }

    Invoke-TestCase 'A relative cd into main before a git mutation is denied' {
        $decision = Invoke-AgentGuardPolicy -Command 'cd ..\..\.. && git commit -m test' `
            -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Equal 'agent-main-git-mutation' $decision.Rule 'Rule'
    }

    Invoke-TestCase 'cd within the managed worktree keeps a git mutation allowed' {
        $decision = Invoke-AgentGuardPolicy -Command 'cd scripts && git commit -m test' `
            -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Allow' $decision.Action 'Action'
    }

    Invoke-TestCase 'A cd target the guard cannot expand denies a following mutation' {
        $decision = Invoke-AgentGuardPolicy -Command 'cd $HOME && git commit -m test' `
            -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Equal 'agent-unresolved-git-target' $decision.Rule 'Rule'
    }

    Invoke-TestCase 'An unexpandable cd does not block read-only git' {
        $decision = Invoke-AgentGuardPolicy -Command 'cd $HOME && git status' `
            -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Allow' $decision.Action 'Action'
    }

    # Regression: an environment-assignment prefix hid the git token from the invocation scan.
    Invoke-TestCase 'An environment-prefixed git mutation in main is denied' {
        $decision = Invoke-AgentGuardPolicy -Command 'FOO=1 git commit -m test' `
            -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Equal 'agent-main-git-mutation' $decision.Rule 'Rule'
    }

    Invoke-TestCase 'A mutating invocation with --git-dir is denied' {
        $decision = Invoke-AgentGuardPolicy -Command 'git --git-dir=/somewhere/.git commit -m test' `
            -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Equal 'agent-git-dir-mutation' $decision.Rule 'Rule'
    }

    Invoke-TestCase 'A chained command denies when any mutation targets main' {
        $command = "git -C `"$($fixture.Managed)`" status && git -C `"$($fixture.Main)`" commit -m test"
        $decision = Invoke-AgentGuardPolicy -Command $command -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Deny' $decision.Action 'Action'
    }

    Invoke-TestCase 'git init inside the protected checkout is denied' {
        $decision = Invoke-AgentGuardPolicy -Command 'git init .' -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Deny' $decision.Action 'Action'
    }

    Invoke-TestCase 'git init in an unrelated empty temp directory is allowed' {
        $empty = Join-Path $fixture.TestRoot 'fresh-init-target'
        New-Item -ItemType Directory -Path $empty -Force | Out-Null
        $decision = Invoke-AgentGuardPolicy -Command 'git init .' -Cwd $empty -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Allow' $decision.Action 'Action'
    }

    Write-Host 'Adapter output contracts' -ForegroundColor Cyan

    Invoke-TestCase 'Claude denial writes stderr and exits 2' {
        $result = Invoke-Entrypoint -StdIn (New-ClaudePayload 'git commit -m test' $script:RealMainCheckout) -Adapter 'Claude'
        Assert-Equal 2 $result.ExitCode 'ExitCode'
        Assert-Match 'BLOCKED: agent Git mutations' $result.StdErr 'StdErr'
    }

    Invoke-TestCase 'Codex denial emits hookSpecificOutput and exits 0' {
        $result = Invoke-Entrypoint -StdIn (New-CodexPayload 'git commit -m test' $script:RealMainCheckout) -Adapter 'Codex'
        Assert-Equal 0 $result.ExitCode 'ExitCode'
        $json = $result.StdOut | ConvertFrom-Json
        Assert-Equal 'PreToolUse' $json.hookSpecificOutput.hookEventName 'hookEventName'
        Assert-Equal 'deny' $json.hookSpecificOutput.permissionDecision 'permissionDecision'
        Assert-Match 'BLOCKED: agent Git mutations' $json.hookSpecificOutput.permissionDecisionReason 'reason'
    }

    Invoke-TestCase 'Copilot denial emits permissionDecision deny and exits 0' {
        $result = Invoke-Entrypoint -StdIn (New-CopilotPayload 'git commit -m test' $script:RealMainCheckout) -Adapter 'Copilot'
        Assert-Equal 0 $result.ExitCode 'ExitCode'
        $json = $result.StdOut | ConvertFrom-Json
        Assert-Equal 'deny' $json.permissionDecision 'permissionDecision'
        Assert-Match 'BLOCKED: agent Git mutations' $json.permissionDecisionReason 'reason'
    }

    Invoke-TestCase 'Allow paths emit no JSON on any adapter' {
        foreach ($adapter in @('Claude', 'Codex', 'Copilot')) {
            $json = switch ($adapter) {
                'Copilot' { New-CopilotPayload 'git status' $fixture.Main }
                'Codex' { New-CodexPayload 'git status' $fixture.Main }
                default { New-ClaudePayload 'git status' $fixture.Main }
            }
            $result = Invoke-Entrypoint -StdIn $json -Adapter $adapter
            Assert-Equal 0 $result.ExitCode "ExitCode ($adapter)"
            Assert-Equal '' $result.StdOut.Trim() "StdOut ($adapter)"
        }
    }

    Invoke-TestCase 'Adapter=Auto selects the Copilot contract for a native toolArgs payload' {
        $result = Invoke-Entrypoint -StdIn (New-CopilotPayload 'git commit -m test' $script:RealMainCheckout) -Adapter 'Auto'
        Assert-Equal 0 $result.ExitCode 'ExitCode'
        $json = $result.StdOut | ConvertFrom-Json
        Assert-Equal 'deny' $json.permissionDecision 'permissionDecision'
        Assert-Match '\[agent-guard:Copilot\]' $result.StdErr 'diagnostic names Copilot'
    }

    Write-Host 'Bash shim' -ForegroundColor Cyan

    $candidateCommands = @(
        'git commit -m test',
        '  git commit -m indented',
        'cd f&&git commit -m test',
        'GIT commit -m test',
        '`git commit -m test`',
        'rm -rf src',
        'dotnet run'
    )

    foreach ($command in $candidateCommands) {
        Invoke-TestCase "Bash shim forwards candidate command: $command" {
            $result = Invoke-BashShim -StdIn (New-ClaudePayload $command $script:RealMainCheckout) -ShimArguments @('Claude')
            # Reaching PowerShell is what is under test: every candidate above either denies or warns.
            $reachedPolicy = $result.ExitCode -eq 2 -or $result.StdErr -match 'BLOCKED|WARNING'
            Assert-True $reachedPolicy "expected the command to reach the policy core (exit $($result.ExitCode), stderr '$($result.StdErr)')"
        }
    }

    Invoke-TestCase 'Bash shim forwards a payload whose metacharacters are unicode-escaped' {
        # Windows PowerShell's ConvertTo-Json escapes & as &, so the raw payload never shows
        # a literal delimiter before the git token. The shim must still forward it.
        $escaped = '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":' +
        '{"command":"cd f&&git commit -m test"},"cwd":"' +
        ($script:RealMainCheckout -replace '\\', '\\') + '"}'
        $result = Invoke-BashShim -StdIn $escaped -ShimArguments @('Claude')
        Assert-Equal 2 $result.ExitCode 'ExitCode'
        Assert-Match 'BLOCKED: agent Git mutations' $result.StdErr 'StdErr'
    }

    Invoke-TestCase 'Bash shim exits fast for a noncandidate command despite a matching cwd' {
        $result = Invoke-BashShim -StdIn (New-ClaudePayload 'rg -n "Goal" README.md' $fixture.Main) -ShimArguments @('Claude')
        Assert-Equal 0 $result.ExitCode 'ExitCode'
        Assert-Equal '' $result.StdErr.Trim() 'StdErr'
    }

    Invoke-TestCase 'Bash shim honors AHKFLOW_GUARD_DISABLE before doing any work' {
        $result = Invoke-BashShim -StdIn 'not json' -EnvironmentOverrides @{ AHKFLOW_GUARD_DISABLE = '1' }
        Assert-Equal 0 $result.ExitCode 'ExitCode'
        Assert-Match 'AHKFLOW_GUARD_DISABLE=1' $result.StdErr 'StdErr'
    }

    Invoke-TestCase 'Bash shim selects Copilot from a native toolArgs payload with no argument' {
        $result = Invoke-BashShim -StdIn (New-CopilotPayload 'git commit -m test' $script:RealMainCheckout)
        Assert-Equal 0 $result.ExitCode 'ExitCode'
        $json = $result.StdOut | ConvertFrom-Json
        Assert-Equal 'deny' $json.permissionDecision 'permissionDecision'
        Assert-Match '\[agent-guard:Copilot\]' $result.StdErr 'diagnostic names Copilot'
    }

    Invoke-TestCase 'Bash shim stays correct when jq is unavailable' {
        # Drop only the jq directories from PATH - PowerShell must stay reachable, otherwise the
        # shim's missing-host branch would allow the command and the test would pass vacuously.
        $pathWithoutJq = (
            $env:PATH -split ';' |
                Where-Object {
                    $_ -and -not (Test-Path -LiteralPath (Join-Path $_ 'jq.exe')) -and
                    -not (Test-Path -LiteralPath (Join-Path $_ 'jq'))
                }
        ) -join ';'

        $result = Invoke-BashShim -StdIn (New-CopilotPayload 'git commit -m test' $script:RealMainCheckout) `
            -EnvironmentOverrides @{ PATH = $pathWithoutJq }
        $json = $result.StdOut | ConvertFrom-Json
        Assert-Equal 'deny' $json.permissionDecision 'permissionDecision'
        Assert-Match '\[agent-guard:Copilot\]' $result.StdErr 'diagnostic names Copilot'
    }

    Invoke-TestCase 'Bash shim falls back to powershell.exe when pwsh is unavailable' {
        # Drop only the pwsh directories: powershell.exe lives in System32 and must stay reachable,
        # otherwise this would silently exercise the missing-host branch instead.
        $pathWithoutPwsh = (
            $env:PATH -split ';' |
                Where-Object { $_ -and -not (Test-Path -LiteralPath (Join-Path $_ 'pwsh.exe')) }
        ) -join ';'

        $result = Invoke-BashShim -StdIn (New-ClaudePayload 'git commit -m test' $script:RealMainCheckout) `
            -ShimArguments @('Claude') -EnvironmentOverrides @{ PATH = $pathWithoutPwsh }
        Assert-Equal 2 $result.ExitCode 'ExitCode'
        Assert-Match 'BLOCKED: agent Git mutations' $result.StdErr 'StdErr'
    }

    Invoke-TestCase 'Bash shim warns and allows when no PowerShell host exists' {
        $pathWithoutAnyHost = (
            $env:PATH -split ';' |
                Where-Object {
                    $_ -and -not (Test-Path -LiteralPath (Join-Path $_ 'pwsh.exe')) -and
                    -not (Test-Path -LiteralPath (Join-Path $_ 'powershell.exe'))
                }
        ) -join ';'

        $result = Invoke-BashShim -StdIn (New-ClaudePayload 'git commit -m test' $script:RealMainCheckout) `
            -ShimArguments @('Claude') -EnvironmentOverrides @{ PATH = $pathWithoutAnyHost }
        Assert-Equal 0 $result.ExitCode 'ExitCode'
        Assert-Match 'could not find PowerShell' $result.StdErr 'StdErr'
    }

    Invoke-TestCase 'Copilot hook registration covers both platforms' {
        $hooks = Get-Content -LiteralPath (Join-Path $suiteRoot '.github\hooks\hooks.json') -Raw | ConvertFrom-Json
        $guards = @($hooks.hooks.preToolUse | Where-Object {
                ($_.PSObject.Properties['bash'] -and $_.bash -match 'pre-bash-guard') -or
                ($_.PSObject.Properties['powershell'] -and $_.powershell -match 'invoke-agent-worktree-guard')
            })

        Assert-Equal 1 $guards.Count 'exactly one Copilot guard registration'
        # Copilot picks 'bash' on Unix and 'powershell' on Windows; a bash-only entry is skipped
        # entirely on Windows, which is where this repository is developed.
        Assert-Match 'pre-bash-guard\.sh' $guards[0].bash 'bash command'
        Assert-Match 'invoke-agent-worktree-guard\.ps1' $guards[0].powershell 'powershell command'
        Assert-Match '-Adapter Copilot' $guards[0].powershell 'powershell adapter'
    }
}
finally {
    Remove-GuardFixture -Fixture $fixture
}

Write-Host ''
if ($script:Failures.Count -gt 0) {
    Write-Host "FAILED: $($script:Failures.Count) test(s)" -ForegroundColor Red
    foreach ($failure in $script:Failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'All agent worktree guard tests passed.' -ForegroundColor Green
exit 0
