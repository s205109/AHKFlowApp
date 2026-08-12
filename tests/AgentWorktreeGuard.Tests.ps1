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
        [string] $WorkingDirectory = $suiteRoot,
        # Defaults to the checked-in entrypoint, which protects the real repository. Pass a copy
        # planted inside the disposable fixture to protect the fixture instead.
        [string] $ScriptPath = $entrypointScript
    )

    return Invoke-CapturedProcess -FilePath $script:PowerShellHost `
        -Arguments @('-NoProfile', '-NonInteractive', '-File', $ScriptPath, '-Adapter', $Adapter) `
        -StdIn $StdIn -EnvironmentOverrides $EnvironmentOverrides -WorkingDirectory $WorkingDirectory
}

# The entrypoint derives the repository it protects from its own location, and that cannot be
# overridden. Planting a copy inside the fixture is therefore the only way to point it at the
# fixture. Without this, entrypoint cases would need a managed worktree of the REAL repository,
# which does not exist in a plain checkout or in CI.
function New-FixtureEntrypoint {
    param([string] $RepoRoot)

    $agents = Join-Path $RepoRoot 'scripts\agents'
    New-Item -ItemType Directory -Path $agents -Force | Out-Null
    Copy-Item -LiteralPath $commonScript -Destination $agents
    Copy-Item -LiteralPath $entrypointScript -Destination $agents
    return (Resolve-Path -LiteralPath (Join-Path $agents 'invoke-agent-worktree-guard.ps1')).Path
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

# A shim's only job is to decide whether to forward. Proving that against the real entrypoint
# needs the suite to be running inside a managed worktree, which it is not when it runs from a
# plain checkout or in CI. So the shim is copied into a temporary tree whose entrypoint is a stub
# that announces itself. Forwarded and not-forwarded then differ in the output, always.
$script:ShimStubMarker = 'STUB-ENTRYPOINT-REACHED'

function New-ShimHarness {
    param([string] $ShimFileName)

    $root = Join-Path ([System.IO.Path]::GetTempPath()) (
        'ahkflow-shim-harness-' + [guid]::NewGuid().ToString('N'))
    $hooks = Join-Path $root '.claude\hooks'
    $agents = Join-Path $root 'scripts\agents'
    New-Item -ItemType Directory -Path $hooks -Force | Out-Null
    New-Item -ItemType Directory -Path $agents -Force | Out-Null

    Copy-Item -LiteralPath (Join-Path $suiteRoot ".claude\hooks\$ShimFileName") `
        -Destination (Join-Path $hooks $ShimFileName)

    # The stub replaces the real entrypoint at the same relative path the shim resolves.
    Set-Content -LiteralPath (Join-Path $agents 'invoke-agent-worktree-guard.ps1') -Encoding utf8 -Value @"
param([string] `$Adapter = 'Auto')
[Console]::Error.WriteLine("$($script:ShimStubMarker) adapter=`$Adapter")
exit 0
"@

    return [pscustomobject]@{
        Root = (Resolve-Path -LiteralPath $root).Path
        Shim = (Resolve-Path -LiteralPath (Join-Path $hooks $ShimFileName)).Path
    }
}

function Remove-ShimHarness {
    param([object] $Harness)

    if ($null -eq $Harness) { return }
    $tempRoot = (Resolve-Path -LiteralPath ([System.IO.Path]::GetTempPath())).Path.TrimEnd('\', '/')
    $target = $Harness.Root.TrimEnd('\', '/')
    if (-not $target.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to delete a shim harness outside the temp directory: $target"
    }
    Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
}

function Invoke-HarnessShim {
    param(
        [object] $Harness,
        [string] $StdIn,
        [string[]] $ShimArguments = @(),
        [hashtable] $EnvironmentOverrides = @{}
    )

    return Invoke-CapturedProcess -FilePath $script:BashExecutable `
        -Arguments (@((ConvertTo-BashPath $Harness.Shim)) + $ShimArguments) `
        -StdIn $StdIn -EnvironmentOverrides $EnvironmentOverrides
}

function New-ClaudePayload {
    param([string] $Command, [string] $Cwd, [string] $AgentId = '')
    $payload = @{
        hook_event_name = 'PreToolUse'
        tool_name       = 'Bash'
        tool_input      = @{ command = $Command }
        cwd             = $Cwd
    }
    # Present at the top level only when the call originates inside a subagent - see
    # ConvertFrom-AgentHookInput. Optional so every existing caller is unaffected.
    if (-not [string]::IsNullOrWhiteSpace($AgentId)) {
        $payload.agent_id = $AgentId
    }
    return $payload | ConvertTo-Json -Compress -Depth 4
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

function New-ClaudeEditPayload {
    param([string] $ToolName, [string] $Path, [string] $Cwd)

    # Edit and Write carry file_path; NotebookEdit carries notebook_path.
    $pathKey = if ($ToolName -ieq 'NotebookEdit') { 'notebook_path' } else { 'file_path' }
    return @{
        hook_event_name = 'PreToolUse'
        tool_name       = $ToolName
        tool_input      = @{ $pathKey = $Path }
        cwd             = $Cwd
    } | ConvertTo-Json -Compress -Depth 4
}

# ── Disposable git fixture ──────────────────────────────────────────────────────────────────

function New-GuardFixture {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
        'ahkflow-agent-guard-' + [guid]::NewGuid().ToString('N'))
    $main = Join-Path $testRoot 'repo'
    $managed = Join-Path $main '.claude\worktrees\valid'
    # A second managed worktree, so a write into a sibling agent's checkout can be tested.
    $managed2 = Join-Path $main '.claude\worktrees\second'
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
    Invoke-Git -C $main worktree add -b feature/wt-second $managed2
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

    $managed2Root = (Resolve-Path -LiteralPath $managed2).Path
    New-Item -ItemType Directory -Path (Join-Path $managed2Root 'scripts') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $managed2Root 'scripts\.env.worktree') -Encoding utf8 -Value (@(
            'AHKFLOW_API_PORT=5604',
            'AHKFLOW_UI_PORT=5605',
            'AHKFLOW_API_URL=http://localhost:5604',
            'AHKFLOW_UI_URL=http://localhost:5605',
            'AHKFLOW_DB_NAME=AHKFlowApp_second',
            'AHKFLOW_SQL_PORT=14333',
            'AHKFLOW_COMPOSE_PROJECT=ahkflow-second',
            "AHKFLOW_ROOT=$managed2Root"
        ) -join "`n")

    # The symlinked docs/superpowers path is one of the two probes backlog 054 records, so its
    # absence must fail the suite rather than quietly skip a required regression.
    $plansSource = Join-Path $main 'docs\superpowers'
    New-Item -ItemType Directory -Path $plansSource -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $plansSource 'seed-plan.md') -Value '# seed' -Encoding utf8

    $plansLinkParent = Join-Path $managedRoot 'docs'
    New-Item -ItemType Directory -Path $plansLinkParent -Force | Out-Null
    Push-Location $plansLinkParent
    try { cmd /c mklink /D 'superpowers' $plansSource > $null 2>&1 }
    finally { Pop-Location }

    $plansLink = Join-Path $plansLinkParent 'superpowers'
    if (-not (Test-Path -LiteralPath $plansLink)) {
        throw ('Could not create the docs\superpowers symlink the guard tests require. ' +
            'Enable Windows Developer Mode, then re-run. See docs/development/prerequisites.md.')
    }
    if ((Get-Item -LiteralPath $plansLink -Force).LinkType -ne 'SymbolicLink') {
        throw ('docs\superpowers was created as a real directory, not a symlink. ' +
            'Enable Windows Developer Mode, then re-run. See docs/development/prerequisites.md.')
    }

    # A FILE symlink with a RELATIVE target, inside the worktree, pointing at the main checkout.
    # Windows resolves such a target against the directory holding the link. This repository
    # already tracks one of these at .github\AGENTS.md, so it is not a theoretical shape.
    Push-Location $managedRoot
    try { cmd /c mklink 'relative-link.md' '..\..\..\seed.txt' > $null 2>&1 }
    finally { Pop-Location }

    $relativeLink = Join-Path $managedRoot 'relative-link.md'
    if (-not (Test-Path -LiteralPath $relativeLink)) {
        throw ('Could not create the relative file symlink the guard tests require. ' +
            'Enable Windows Developer Mode, then re-run. See docs/development/prerequisites.md.')
    }

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
        Managed2      = $managed2Root
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
            $Fixture.Managed, $Fixture.Managed2, $Fixture.BadManifest, $Fixture.Nested,
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

    Invoke-TestCase 'Edit payload normalizes to the file-edit contract' {
        $json = New-ClaudeEditPayload 'Edit' 'C:\repo\src\a.cs' $fixture.Main
        $normalized = ConvertFrom-AgentHookInput -Adapter 'Claude' -InputJson $json
        Assert-Equal 'file-edit' $normalized.ToolName 'ToolName'
        Assert-Equal 'C:\repo\src\a.cs' $normalized.TargetPath 'TargetPath'
        Assert-Equal '' $normalized.Command 'Command'
    }

    Invoke-TestCase 'Write payload normalizes to the file-edit contract' {
        $json = New-ClaudeEditPayload 'Write' 'C:\repo\src\b.cs' $fixture.Main
        $normalized = ConvertFrom-AgentHookInput -Adapter 'Claude' -InputJson $json
        Assert-Equal 'file-edit' $normalized.ToolName 'ToolName'
        Assert-Equal 'C:\repo\src\b.cs' $normalized.TargetPath 'TargetPath'
    }

    Invoke-TestCase 'NotebookEdit payload carries its path under notebook_path' {
        $json = New-ClaudeEditPayload 'NotebookEdit' 'C:\repo\note.ipynb' $fixture.Main
        $normalized = ConvertFrom-AgentHookInput -Adapter 'Claude' -InputJson $json
        Assert-Equal 'file-edit' $normalized.ToolName 'ToolName'
        Assert-Equal 'C:\repo\note.ipynb' $normalized.TargetPath 'TargetPath'
    }

    Invoke-TestCase 'A Bash payload still carries no target path' {
        $normalized = ConvertFrom-AgentHookInput -Adapter 'Claude' `
            -InputJson (New-ClaudePayload 'git status' $fixture.Main)
        Assert-Equal 'shell' $normalized.ToolName 'ToolName'
        Assert-Equal '' $normalized.TargetPath 'TargetPath'
    }

    Invoke-TestCase 'An unknown tool name stays unrecognized' {
        $json = New-ClaudeEditPayload 'Read' 'C:\repo\src\a.cs' $fixture.Main
        $normalized = ConvertFrom-AgentHookInput -Adapter 'Claude' -InputJson $json
        Assert-Equal 'Read' $normalized.ToolName 'ToolName'
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
        # Recursive and force need not share a token. Splitting them, or spelling them out, is
        # the same command and must reach the same verdict.
        @{ Command = 'rm -r -f src'; Action = 'Deny'; Rule = 'dangerous-rm' },
        @{ Command = 'rm -f -r src'; Action = 'Deny'; Rule = 'dangerous-rm' },
        @{ Command = 'rm --recursive --force src'; Action = 'Deny'; Rule = 'dangerous-rm' },
        @{ Command = 'rm -r --force src'; Action = 'Deny'; Rule = 'dangerous-rm' },
        @{ Command = 'rm -R -f src'; Action = 'Deny'; Rule = 'dangerous-rm' },
        # Either flag on its own is not the destructive pair.
        @{ Command = 'rm -r src'; Action = 'Allow'; Rule = 'none' },
        @{ Command = 'rm -f src'; Action = 'Allow'; Rule = 'none' },
        # The build-output allow-list still applies to the split spelling.
        @{ Command = 'rm -r -f node_modules'; Action = 'Allow'; Rule = 'none' },
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
        @{ Command = 'git status && git.exe push --force origin main'; Rule = 'force-push' },
        # Clustered short flags and a '+' refspec force a push without an exact -f/--force token.
        @{ Command = 'git push -fu origin main'; Rule = 'force-push' },
        @{ Command = 'git push -uf origin main'; Rule = 'force-push' },
        @{ Command = 'git push origin +main:main'; Rule = 'force-push' },
        @{ Command = 'git push origin +refs/heads/topic'; Rule = 'force-push' },
        # Quoted and path-qualified executables must reach the same rules.
        @{ Command = '"git" reset --hard'; Rule = 'git-reset-hard' },
        @{ Command = '"C:\Program Files\Git\cmd\git.exe" reset --hard'; Rule = 'git-reset-hard' }
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

    Write-Host 'Segment-scoped rm/dotnet safety (no quoted-argument false positives)' -ForegroundColor Cyan

    $rmDotnetCases = @(
        # Real invocations still fire.
        @{ Command = 'rm -rf dist'; Action = 'Deny'; Rule = 'dangerous-rm' },
        @{ Command = 'git commit -m x && rm -rf src'; Action = 'Deny'; Rule = 'dangerous-rm' },
        @{ Command = 'cd build; rm -fr out'; Action = 'Deny'; Rule = 'dangerous-rm' },
        @{ Command = '/usr/bin/rm -Rf leftovers'; Action = 'Deny'; Rule = 'dangerous-rm' },
        @{ Command = 'dotnet run'; Action = 'Warn'; Rule = 'dotnet-run' },
        @{ Command = 'dotnet run --project src/Backend/AHKFlowApp.API'; Action = 'Warn'; Rule = 'dotnet-run' },
        # Build-output targets stay allow-listed regardless of flag spelling.
        @{ Command = 'rm -rf node_modules'; Action = 'Allow'; Rule = 'none' },
        @{ Command = 'rm -rf /tmp'; Action = 'Allow'; Rule = 'none' },
        @{ Command = 'rm -fr obj'; Action = 'Allow'; Rule = 'none' },
        # Regression: the pattern only inside a quoted git argument must not read as an invocation -
        # this is what the old raw-string rule got wrong, blocking legitimate commits and read-only
        # `git log --grep`.
        @{ Command = 'git commit -m "chore: rm -rf dist before packaging"'; Action = 'Allow'; Rule = 'none' },
        @{ Command = 'git commit -m "wip: dotnet run smoke test"'; Action = 'Allow'; Rule = 'none' },
        @{ Command = 'git log --grep "rm -rf dist"'; Action = 'Allow'; Rule = 'none' },
        @{ Command = 'git commit -m "note: rm -fr build"'; Action = 'Allow'; Rule = 'none' }
    )

    foreach ($case in $rmDotnetCases) {
        Invoke-TestCase "Segment safety: $($case.Command)" {
            $decision = Get-AgentCommandSafetyDecision -Command $case.Command
            Assert-Equal $case.Action $decision.Action 'Action'
            Assert-Equal $case.Rule $decision.Rule 'Rule'
        }
    }

    Invoke-TestCase 'A commit message mentioning rm -rf is allowed end to end in a managed worktree' {
        $decision = Invoke-AgentGuardPolicy -Command 'git commit -m "docs: rm -rf dist cleanup"' `
            -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Allow' $decision.Action 'Action'
    }

    Invoke-TestCase 'A real chained rm -rf is still denied end to end' {
        $decision = Invoke-AgentGuardPolicy -Command 'git status && rm -rf src' `
            -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Equal 'dangerous-rm' $decision.Rule 'Rule'
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

    Write-Host 'Tier reclassification' -ForegroundColor Cyan

    $somewhere = Join-Path $fixture.TestRoot 'somewhere'
    $somewhereElse = Join-Path $fixture.TestRoot 'somewhere-else'

    # Tier 2: cannot disturb the owner's HEAD, index, or working tree - unconditional Allow, even
    # from the main checkout, with no AllowMain. Nothing here touches the filesystem: Tier 2
    # short-circuits before the location decision ever resolves a target directory.
    $tier2AllowCases = @(
        'git worktree prune',
        'git worktree prune -n',
        "git worktree remove $somewhere",
        "git worktree add $somewhere sometopic",
        "git worktree add -b topic $somewhere", # lowercase -b is the safe, non-destructive spelling
        'git worktree list', # already allowed today (read-only) - pin, not a new behavior
        'git branch -d topic',
        'git branch --delete topic',
        'git branch newtopic',
        'git remote prune origin',
        'git fetch --prune' # already unguarded (not a recognized mutating subcommand) - pin
    )
    foreach ($command in $tier2AllowCases) {
        Invoke-TestCase "Tier 2 unconditional allow from main: $command" {
            $decision = Invoke-AgentGuardPolicy -Command $command -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
            Assert-Equal 'Allow' $decision.Action 'Action'
        }
    }

    # The force/destructive sibling of each Tier 2 case above can disturb the working tree (or, for
    # branch -D et al, discard unmerged work), so it drops out of Tier 2 into ordinary Tier 1a Ask.
    $forceVariantAskCases = @(
        "git worktree remove --force $somewhere",
        "git worktree remove -f $somewhere",
        "git worktree add --force $somewhere sometopic",
        "git worktree move $somewhere $somewhereElse",
        'git worktree repair',
        "git worktree lock $somewhere",
        "git worktree unlock $somewhere",
        'git branch -D topic',
        'git branch -d -f topic',
        'git branch -df topic',
        'git branch -fd topic',
        'git branch --delete --force topic',
        'git branch -m a b',
        'git branch -M a b',
        # -B is git's own force spelling for worktree add (resets an existing branch's tip); the
        # lowercase -b clustered/exact-match test coverage above (via $tier2AllowCases) stays Allow.
        "git worktree add -B topic $somewhere"
    )
    foreach ($command in $forceVariantAskCases) {
        Invoke-TestCase "Force/destructive variant asks (not Tier 2) from main: $command" {
            $decision = Invoke-AgentGuardPolicy -Command $command -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
            Assert-Equal 'Ask' $decision.Action 'Action'
            Assert-Equal 'agent-main-git-mutation' $decision.Rule 'Rule'
        }
    }

    # Tier 1a: guarded, not Tier 2, not commit - a permission prompt instead of a silent Deny.
    $tier1aAskCases = @(
        'git checkout other', 'git switch other', 'git reset HEAD~1', 'git stash', 'git push',
        'git tag v1.0.0', 'git add .', 'git config user.name x'
    )
    foreach ($command in $tier1aAskCases) {
        Invoke-TestCase "Tier 1a asks from main: $command" {
            $decision = Invoke-AgentGuardPolicy -Command $command -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
            Assert-Equal 'Ask' $decision.Action 'Action'
        }
    }

    # Tier 1b: only commit stays a silent Deny. `git commit -m test` and the unbalanced-quote case
    # are already covered above; this adds the one commit variant that was not: --amend.
    Invoke-TestCase 'git commit --amend from main is still denied (Tier 1b, unchanged)' {
        $decision = Invoke-AgentGuardPolicy -Command 'git commit --amend' -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Equal 'agent-main-git-mutation' $decision.Rule 'Rule'
    }

    # Critical regression: the location scan used to break at the FIRST blocking segment and derive
    # the Tier1b-vs-Ask decision from that one segment alone. So a non-commit mutation blocking
    # earlier in a chain (e.g. `git add .`) hid a `commit` blocking later, misclassifying the whole
    # command as Ask. commit must never be reachable behind an Ask prompt: approving the prompt
    # would run the earlier mutation in the owner's checkout, then commit would die at the separate
    # pre-commit backstop, leaving the owner's index staged with the agent's files.
    $commitDominatesCases = @(
        'git add . && git commit -m x',
        'git add .; git commit -m x',
        'git commit -m x && git add .'
    )
    foreach ($command in $commitDominatesCases) {
        Invoke-TestCase "Commit dominates regardless of scan order: $command" {
            $decision = Invoke-AgentGuardPolicy -Command $command -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
            Assert-Equal 'Deny' $decision.Action 'Action'
            Assert-Equal 'agent-main-git-mutation' $decision.Rule 'Rule'
        }
    }

    # Safety rules (force-push, reset --hard, clean -f, checkout ., dangerous rm) short-circuit
    # Invoke-AgentGuardPolicy before the location decision ever runs (see common.ps1:1147), so Ask
    # is structurally unreachable for them. $safetyCases/$indirectSafetyCases above already pin
    # Get-AgentCommandSafetyDecision's Action/Rule; this confirms the same end to end through the
    # full policy, never downgraded to Ask.
    $safetyStillDenyEndToEndCases = @(
        'git push --force', 'git push -f', 'git reset --hard', 'git clean -fd', 'git checkout .', 'rm -rf src'
    )
    foreach ($command in $safetyStillDenyEndToEndCases) {
        Invoke-TestCase "Safety rule still denies end to end, never Ask: $command" {
            $decision = Invoke-AgentGuardPolicy -Command $command -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
            Assert-Equal 'Deny' $decision.Action 'Action'
        }
    }

    # No regression inside a managed worktree: every Tier 1a and Tier 2 command above must still be
    # a plain Allow when it is not targeting the main checkout at all.
    foreach ($command in (@($tier2AllowCases) + @($forceVariantAskCases) + @($tier1aAskCases))) {
        Invoke-TestCase "No regression in a managed worktree: $command" {
            $decision = Invoke-AgentGuardPolicy -Command $command -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main
            Assert-Equal 'Allow' $decision.Action 'Action'
        }
    }

    Invoke-TestCase 'AHKFLOW_ALLOW_MAIN=1 downgrades a Tier 1a Ask to Warn' {
        $decision = Invoke-AgentGuardPolicy -Command 'git checkout other' `
            -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main -AllowMain $true
        Assert-Equal 'Warn' $decision.Action 'Action'
    }

    # Resolved design decision: AHKFLOW_ALLOW_MAIN=1 keeps its exact current behavior for commit -
    # a warned Allow, not a Deny. This task only changes whether a prompt is offered when it's unset.
    Invoke-TestCase 'AHKFLOW_ALLOW_MAIN=1 still turns a commit Deny into a warned Allow' {
        $decision = Invoke-AgentGuardPolicy -Command 'git commit -m test' `
            -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main -AllowMain $true
        Assert-Equal 'Warn' $decision.Action 'Action'
    }

    Write-Host 'Wrapper prefix (rtk)' -ForegroundColor Cyan

    # Parity: a wrapped command must get exactly the same decision as its bare form, across every
    # tier the guard recognizes. Driven from pairs so the two forms can never drift apart.
    $wrapperParityPairs = @(
        @{ Bare = 'git worktree prune'; Wrapped = 'rtk git worktree prune' },
        @{ Bare = 'git branch newtopic'; Wrapped = 'rtk git branch newtopic' },
        @{ Bare = 'git worktree repair'; Wrapped = 'rtk git worktree repair' },
        @{ Bare = 'git branch -D topic'; Wrapped = 'rtk git branch -D topic' },
        @{ Bare = 'git commit -m x'; Wrapped = 'rtk git commit -m x' },
        @{ Bare = 'git commit --amend'; Wrapped = 'rtk git commit --amend' }
    )
    foreach ($pair in $wrapperParityPairs) {
        Invoke-TestCase "Wrapped command matches its bare form: $($pair.Wrapped)" {
            $bareDecision = Invoke-AgentGuardPolicy -Command $pair.Bare -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
            $wrappedDecision = Invoke-AgentGuardPolicy -Command $pair.Wrapped -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
            Assert-Equal $bareDecision.Action $wrappedDecision.Action 'Action'
            Assert-Equal $bareDecision.Rule $wrappedDecision.Rule 'Rule'
        }
    }

    # No wrapped-command case above ever runs from a managed worktree - every Cwd is $fixture.Main.
    # Pin that a wrapped commit is a plain Allow there too, the same as its bare form.
    Invoke-TestCase 'Wrapped commit is Allow from a managed worktree' {
        $decision = Invoke-AgentGuardPolicy -Command 'rtk git commit -m x' `
            -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Allow' $decision.Action 'Action'
    }

    # Every spelling below must still deny a commit exactly the way the bare command does. This
    # covers rtk 0.43.0's global options (-v/-vv/-vvv/--verbose/--ultra-compact/--skip-env), all
    # five pass-through subcommands (proxy/run/err/summary/test), a repeated wrapper, a leading
    # NAME=value assignment, and a full path to the rtk executable.
    $wrapperSpellings = @(
        'rtk', 'rtk.exe', 'C:\tools\rtk.exe', 'rtk -v', 'rtk -vvv', 'rtk --ultra-compact',
        'rtk --skip-env', 'rtk --ultra-compact --skip-env', 'rtk proxy', 'rtk --ultra-compact proxy',
        'rtk rtk', 'SKIP_COVERAGE_HOOK=1 rtk', 'rtk err', 'rtk summary', 'rtk test'
    )
    foreach ($prefix in $wrapperSpellings) {
        Invoke-TestCase "Wrapper spelling still denies a commit: $prefix git commit -m x" {
            $decision = Invoke-AgentGuardPolicy -Command "$prefix git commit -m x" `
                -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
            Assert-Equal 'Deny' $decision.Action 'Action'
            Assert-Equal 'agent-main-git-mutation' $decision.Rule 'Rule'
        }
    }

    Invoke-TestCase 'Commit still dominates through a chain of wrapped segments' {
        $decision = Invoke-AgentGuardPolicy -Command 'rtk git add . && rtk git commit -m x' `
            -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Equal 'agent-main-git-mutation' $decision.Rule 'Rule'
    }

    # Documented remaining bypasses, pinned as tests so a future change to any of them is
    # deliberate, not accidental. The tokenizer keeps a quoted string as one token, so a
    # subcommand that takes a raw command string hides the git word inside a single token. A
    # hypothetical rtk option that takes the next token as its value has the same effect: the git
    # word is no longer the segment's leading word. A NAME=value assignment placed after the
    # wrapper is never stripped, because the NAME=value strip in Get-AgentCommandSegment runs once,
    # before the wrapper strip, and is not repeated afterward. None of these three cases is
    # modelled today.
    Invoke-TestCase 'Documented bypass: rtk run with a quoted command stays Allow' {
        $decision = Invoke-AgentGuardPolicy -Command 'rtk run "git commit -m x"' `
            -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Allow' $decision.Action 'Action'
    }

    Invoke-TestCase 'Documented bypass: a value-taking rtk option stays Allow' {
        $decision = Invoke-AgentGuardPolicy -Command 'rtk --out foo git commit -m x' `
            -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Allow' $decision.Action 'Action'
    }

    Invoke-TestCase 'Documented bypass: a NAME=value assignment after the wrapper stays Allow' {
        $decision = Invoke-AgentGuardPolicy -Command 'rtk FOO=1 git commit -m x' `
            -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Allow' $decision.Action 'Action'
    }

    # The one escalation guard: rtk cannot move the calling shell's own working directory, so the
    # guard must not act as if it did. Without this, the commit below would look like it targeted
    # the unrelated directory rtk was told to cd into, when the real shell never left main.
    Invoke-TestCase 'rtk cd to an outside directory does not escalate a commit in main to Allow' {
        $command = "rtk cd `"$($fixture.Unrelated)`" && git commit -m x"
        $decision = Invoke-AgentGuardPolicy -Command $command -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Equal 'agent-main-git-mutation' $decision.Rule 'Rule'
    }

    # Same escalation guard, the pushd/push-location spelling. A bare `pushd <dir>` really can move
    # the shell (Get-AgentGitLocationDecision tracks it as PushDirectory), which is exactly why the
    # concrete gap in the finding matters: `pushd C:/Windows && git commit -m x` resolves as Allow
    # today, because Windows already has that directory and it sits outside the protected repo. A
    # wrapped `rtk pushd ...` must still deny, the same way `rtk cd ...` does above.
    Invoke-TestCase 'rtk pushd to an outside directory does not escalate a commit in main to Allow' {
        $command = "rtk pushd `"$($fixture.Unrelated)`" && git commit -m x"
        $decision = Invoke-AgentGuardPolicy -Command $command -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Equal 'agent-main-git-mutation' $decision.Rule 'Rule'
    }

    Invoke-TestCase 'rtk push-location to an outside directory does not escalate a commit in main to Allow' {
        $command = "rtk push-location `"$($fixture.Unrelated)`" && git commit -m x"
        $decision = Invoke-AgentGuardPolicy -Command $command -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Equal 'agent-main-git-mutation' $decision.Rule 'Rule'
    }

    # popd/pop-location take no directory argument, so there is nothing to escalate to - it pops
    # whatever the (guard-tracked) stack already holds. With an empty stack the commit still runs
    # against the unchanged Cwd, main, so the correct expectation is the same Deny a bare `popd`
    # already gets today (confirmed by direct probe): both the bare and the wrapped spelling stay
    # in main and deny the commit. This test pins that the wrapper does not change that outcome.
    Invoke-TestCase 'rtk popd does not escalate a commit in main to Allow' {
        $command = 'rtk popd && git commit -m x'
        $decision = Invoke-AgentGuardPolicy -Command $command -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Equal 'agent-main-git-mutation' $decision.Rule 'Rule'
    }

    Invoke-TestCase 'rtk pop-location does not escalate a commit in main to Allow' {
        $command = 'rtk pop-location && git commit -m x'
        $decision = Invoke-AgentGuardPolicy -Command $command -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Equal 'agent-main-git-mutation' $decision.Rule 'Rule'
    }

    # The rm/dotnet safety rules read the same parsed segments as git, so they see through the
    # wrapper as a side effect of the fix, with no rule change of their own.
    Invoke-TestCase 'Wrapped force-push still denies' {
        $decision = Invoke-AgentGuardPolicy -Command 'rtk git push --force' -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Equal 'force-push' $decision.Rule 'Rule'
    }

    Invoke-TestCase 'Wrapped git reset --hard still denies' {
        $decision = Invoke-AgentGuardPolicy -Command 'rtk git reset --hard' -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Equal 'git-reset-hard' $decision.Rule 'Rule'
    }

    Invoke-TestCase 'Wrapped rm -rf still denies' {
        $decision = Invoke-AgentGuardPolicy -Command 'rtk rm -rf C:/somewhere' -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Equal 'dangerous-rm' $decision.Rule 'Rule'
    }

    Invoke-TestCase 'Wrapped dotnet run still warns' {
        $decision = Invoke-AgentGuardPolicy -Command 'rtk dotnet run' -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Warn' $decision.Action 'Action'
        Assert-Equal 'dotnet-run' $decision.Rule 'Rule'
    }

    # Not over-broad: a non-wrapper leading word is left untouched. These stay documented accepted
    # limitations, not something this change fixes.
    Invoke-TestCase 'sh -c wrapping a commit stays an accepted limitation, not newly caught' {
        $decision = Invoke-AgentGuardPolicy -Command 'sh -c "git commit -m x"' -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Allow' $decision.Action 'Action'
    }

    Invoke-TestCase 'pwsh running a git word after its options is untouched by the wrapper rule' {
        $decision = Invoke-AgentGuardPolicy -Command 'pwsh -Command git commit -m x' -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Allow' $decision.Action 'Action'
    }

    Write-Host 'Tier reclassification: adapter matrix' -ForegroundColor Cyan

    Invoke-TestCase 'Claude: a Tier 1a decision emits permissionDecision ask' {
        $result = Invoke-Entrypoint -StdIn (New-ClaudePayload 'git checkout other' $script:RealMainCheckout) -Adapter 'Claude'
        Assert-Equal 0 $result.ExitCode 'ExitCode'
        $json = $result.StdOut | ConvertFrom-Json
        Assert-Equal 'ask' $json.hookSpecificOutput.permissionDecision 'permissionDecision'
    }

    Invoke-TestCase 'Codex: a Tier 1a decision is translated to deny, never ask' {
        $result = Invoke-Entrypoint -StdIn (New-CodexPayload 'git checkout other' $script:RealMainCheckout) -Adapter 'Codex'
        Assert-Equal 0 $result.ExitCode 'ExitCode'
        $json = $result.StdOut | ConvertFrom-Json
        Assert-Equal 'deny' $json.hookSpecificOutput.permissionDecision 'permissionDecision'
    }

    Invoke-TestCase 'Copilot: a Tier 1a decision emits permissionDecision ask' {
        $result = Invoke-Entrypoint -StdIn (New-CopilotPayload 'git checkout other' $script:RealMainCheckout) -Adapter 'Copilot'
        Assert-Equal 0 $result.ExitCode 'ExitCode'
        $json = $result.StdOut | ConvertFrom-Json
        Assert-Equal 'ask' $json.permissionDecision 'permissionDecision'
    }

    Write-Host 'Subagent Ask->Deny downgrade' -ForegroundColor Cyan

    # Binding security control (plan-mandated): a subagent cannot show an interactive prompt, so a
    # Tier 1a hit from a subagent call must resolve to Deny, never Ask, on every adapter.
    Invoke-TestCase 'Claude: a subagent Tier 1a hit is denied, never asked' {
        $result = Invoke-Entrypoint -StdIn (New-ClaudePayload 'git checkout other' $script:RealMainCheckout -AgentId 'subagent-test-1') -Adapter 'Claude'
        Assert-Equal 0 $result.ExitCode 'ExitCode'
        $json = $result.StdOut | ConvertFrom-Json
        Assert-Equal 'deny' $json.hookSpecificOutput.permissionDecision 'permissionDecision'
        Assert-Match 'subagent' $json.hookSpecificOutput.permissionDecisionReason 'reason'
    }

    # Control: the identical command with no agent_id must still Ask - otherwise the Deny assertion
    # above could pass vacuously (e.g. if the command were Deny for an unrelated reason).
    Invoke-TestCase 'Claude: the same Tier 1a command without agent_id still asks (control)' {
        $result = Invoke-Entrypoint -StdIn (New-ClaudePayload 'git checkout other' $script:RealMainCheckout) -Adapter 'Claude'
        Assert-Equal 0 $result.ExitCode 'ExitCode'
        $json = $result.StdOut | ConvertFrom-Json
        Assert-Equal 'ask' $json.hookSpecificOutput.permissionDecision 'permissionDecision'
    }

    Invoke-TestCase 'Unknown decision action fails closed, verified structurally on every adapter branch' {
        # New-AgentGuardDecision's ValidateSet (Allow/Warn/Deny/Ask) makes an "unrecognized" Action
        # structurally unreachable through any real policy input - it can only come from a defect in
        # the decision engine itself. Invoke-Entrypoint runs the entrypoint as a real subprocess
        # (Invoke-CapturedProcess), so a function shadow defined in this test process cannot reach
        # it; calling Invoke-AgentGuardPolicy directly cannot exercise the adapter's own JSON/exit
        # translation, which is exactly what is under test. There is no seam to inject a fault into
        # the subprocess without adding a test-only hook to the product code, which is not
        # proportionate for this one case (see task-1-brief.md, section C1). This instead asserts
        # the fail-closed *structure* by inspecting the entrypoint's source: every adapter branch
        # must explicitly deny on any action it does not recognize, rather than falling through to
        # an implicit allow.
        $source = Get-Content -LiteralPath $entrypointScript -Raw

        $codexStart = $source.IndexOf("'Codex' {")
        $copilotStart = $source.IndexOf("'Copilot' {")
        $claudeStart = $source.IndexOf('default {')
        Assert-True ($codexStart -ge 0 -and $copilotStart -gt $codexStart -and $claudeStart -gt $copilotStart) `
            'expected the switch to contain Codex, then Copilot, then the default (Claude) branch in that order'

        $branches = @(
            @{ Name = 'Codex'; Text = $source.Substring($codexStart, $copilotStart - $codexStart) },
            @{ Name = 'Copilot'; Text = $source.Substring($copilotStart, $claudeStart - $copilotStart) },
            @{ Name = 'Claude (default)'; Text = $source.Substring($claudeStart) }
        )

        foreach ($branch in $branches) {
            Assert-True ($branch.Text.Contains("if (`$decision.Action -eq 'Allow') { exit 0 }")) `
                "$($branch.Name): a recognized Allow must exit before the fail-closed fallback is reached"
            Assert-True ($branch.Text.Contains('unrecognized decision action')) `
                "$($branch.Name): must diagnose an unrecognized action rather than silently falling through"
            Assert-True ($branch.Text.ToLowerInvariant().Contains('deny')) `
                "$($branch.Name): must deny an unrecognized action (fail closed)"
        }
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
        # git commit is the go-to probe for "any location mutation" here: a plain `git branch
        # <name>` create is now Tier 2 Allow, so it no longer demonstrates a location denial.
        $command = "Set-Location -LiteralPath `"$($fixture.Main)`"; git commit -m test"
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

    # Regression: a *relative* git -C after an unexpandable cd was wrongly treated as a re-anchor
    # and joined onto the stale base, so `cd $HOME && git -C sub commit` classified against
    # managed/sub and allowed a commit whose real target the guard could not know.
    Invoke-TestCase 'A relative git -C after an unexpandable cd is denied (no false re-anchor)' {
        $decision = Invoke-AgentGuardPolicy -Command 'cd $HOME && git -C sub commit -m test' `
            -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Equal 'agent-unresolved-git-target' $decision.Rule 'Rule'
    }

    Invoke-TestCase 'An absolute git -C into a managed worktree still re-anchors past an unexpandable cd' {
        $command = "cd `$HOME && git -C `"$($fixture.Managed)`" commit -m test"
        $decision = Invoke-AgentGuardPolicy -Command $command -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Allow' $decision.Action 'Action'
    }

    Invoke-TestCase 'An absolute git -C into main past an unexpandable cd is denied' {
        $command = "cd `$HOME && git -C `"$($fixture.Main)`" commit -m test"
        $decision = Invoke-AgentGuardPolicy -Command $command -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Equal 'agent-main-git-mutation' $decision.Rule 'Rule'
    }

    # Regression: a cd to a nonexistent path FAILS and leaves the shell where it was, so the
    # mutation runs there. Treating the move as successful classified it against the harmless
    # outside path and allowed a commit that actually landed in main.
    Invoke-TestCase 'A cd to a nonexistent path leaves the mutation in main and is denied' {
        $missing = Join-Path $fixture.TestRoot 'no-such-directory'
        $decision = Invoke-AgentGuardPolicy -Command "cd `"$missing`"; git commit -m test" `
            -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Equal 'agent-main-git-mutation' $decision.Rule 'Rule'
    }

    Invoke-TestCase 'popd unwinds to main and denies the following mutation' {
        $command = "pushd `"$($fixture.Main)`"; pushd `"$($fixture.Managed)`"; popd; git commit -m test"
        $decision = Invoke-AgentGuardPolicy -Command $command -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Equal 'agent-main-git-mutation' $decision.Rule 'Rule'
    }

    Invoke-TestCase 'popd back into the managed worktree keeps the mutation allowed' {
        $command = "pushd `"$($fixture.Main)`"; popd; git commit -m test"
        $decision = Invoke-AgentGuardPolicy -Command $command -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Allow' $decision.Action 'Action'
    }

    Invoke-TestCase 'popd on an empty stack leaves the directory unchanged' {
        $decision = Invoke-AgentGuardPolicy -Command 'popd; git commit -m test' `
            -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Equal 'agent-main-git-mutation' $decision.Rule 'Rule'
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

    Invoke-TestCase 'git init inside the protected checkout is asked (Tier 1a, not commit)' {
        $decision = Invoke-AgentGuardPolicy -Command 'git init .' -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Ask' $decision.Action 'Action'
        Assert-Equal 'agent-main-git-mutation' $decision.Rule 'Rule'
    }

    Invoke-TestCase 'git init in an unrelated empty temp directory is allowed' {
        $empty = Join-Path $fixture.TestRoot 'fresh-init-target'
        New-Item -ItemType Directory -Path $empty -Force | Out-Null
        $decision = Invoke-AgentGuardPolicy -Command 'git init .' -Cwd $empty -ProtectedRepoRoot $fixture.Main
        Assert-Equal 'Allow' $decision.Action 'Action'
    }

    Write-Host 'Adapter output contracts' -ForegroundColor Cyan

    Invoke-TestCase 'Claude commit denial (a location rule) emits hookSpecificOutput deny and exits 0' {
        # Commit stays Tier 1b Deny, but the wire protocol for the three location rules is now the
        # JSON hookSpecificOutput contract on every action (Ask included), not the legacy
        # stderr + exit 2 pair - that pair is reserved for safety-rule and ambiguous-command denials.
        $result = Invoke-Entrypoint -StdIn (New-ClaudePayload 'git commit -m test' $script:RealMainCheckout) -Adapter 'Claude'
        Assert-Equal 0 $result.ExitCode 'ExitCode'
        $json = $result.StdOut | ConvertFrom-Json
        Assert-Equal 'PreToolUse' $json.hookSpecificOutput.hookEventName 'hookEventName'
        Assert-Equal 'deny' $json.hookSpecificOutput.permissionDecision 'permissionDecision'
        Assert-Match 'BLOCKED: agent Git mutations' $json.hookSpecificOutput.permissionDecisionReason 'reason'
    }

    Invoke-TestCase 'Claude safety-rule denial still uses the legacy stderr + exit 2 protocol' {
        $result = Invoke-Entrypoint -StdIn (New-ClaudePayload 'git reset --hard' $script:RealMainCheckout) -Adapter 'Claude'
        Assert-Equal 2 $result.ExitCode 'ExitCode'
        Assert-Match 'BLOCKED: git reset --hard' $result.StdErr 'StdErr'
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
        'dotnet run',
        # Regression: the leading-boundary class enumerated shell delimiters, so a quote or a path
        # separator before the executable let these exit in Bash without ever reaching policy.
        '"git" commit -m test',
        "'git' commit -m test",
        '"C:\Program Files\Git\cmd\git.exe" commit -m test',
        'C:\Program` Files\Git\cmd\git.exe commit -m test',
        '/usr/bin/git commit -m test',
        '/c/Program\ Files/Git/cmd/git.exe commit -m test',
        '"/c/Program Files/Git/cmd/git.exe" commit -m test'
    )

    foreach ($command in $candidateCommands) {
        Invoke-TestCase "Bash shim forwards candidate command: $command" {
            $result = Invoke-BashShim -StdIn (New-ClaudePayload $command $script:RealMainCheckout) -ShimArguments @('Claude')
            # Reaching PowerShell is what is under test: every candidate above either denies (legacy
            # stderr + exit 2, or the JSON hookSpecificOutput protocol for a location-rule commit
            # denial) or warns.
            $reachedPolicy = $result.ExitCode -eq 2 -or $result.StdErr -match 'BLOCKED|WARNING' -or
            $result.StdOut -match 'permissionDecision'
            Assert-True $reachedPolicy "expected the command to reach the policy core (exit $($result.ExitCode), stdout '$($result.StdOut)', stderr '$($result.StdErr)')"
        }
    }

    Invoke-TestCase 'Bash shim forwards a payload whose metacharacters are unicode-escaped' {
        # Windows PowerShell's ConvertTo-Json escapes & as &, so the raw payload never shows
        # a literal delimiter before the git token. The shim must still forward it.
        $escaped = '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":' +
        '{"command":"cd f&&git commit -m test"},"cwd":"' +
        ($script:RealMainCheckout -replace '\\', '\\') + '"}'
        $result = Invoke-BashShim -StdIn $escaped -ShimArguments @('Claude')
        Assert-Equal 0 $result.ExitCode 'ExitCode'
        $json = $result.StdOut | ConvertFrom-Json
        Assert-Equal 'deny' $json.hookSpecificOutput.permissionDecision 'permissionDecision'
        Assert-Match 'BLOCKED: agent Git mutations' $json.hookSpecificOutput.permissionDecisionReason 'reason'
    }

    Invoke-TestCase 'Bash shim forwards an rtk-wrapped commit and produces the deny JSON' {
        $result = Invoke-BashShim -StdIn (New-ClaudePayload 'rtk git commit -m x' $script:RealMainCheckout) -ShimArguments @('Claude')
        Assert-Equal 0 $result.ExitCode 'ExitCode'
        $json = $result.StdOut | ConvertFrom-Json
        Assert-Equal 'deny' $json.hookSpecificOutput.permissionDecision 'permissionDecision'
        Assert-Match 'BLOCKED: agent Git mutations' $json.hookSpecificOutput.permissionDecisionReason 'reason'
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
        Assert-Equal 0 $result.ExitCode 'ExitCode'
        $json = $result.StdOut | ConvertFrom-Json
        Assert-Equal 'deny' $json.hookSpecificOutput.permissionDecision 'permissionDecision'
        Assert-Match 'BLOCKED: agent Git mutations' $json.hookSpecificOutput.permissionDecisionReason 'reason'
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

    Invoke-TestCase 'Claude registers the file-edit guard on all three writing tools' {
        $settings = Get-Content -LiteralPath (Join-Path $suiteRoot '.claude\settings.json') -Raw | ConvertFrom-Json
        $guards = @($settings.hooks.PreToolUse | Where-Object {
                @($_.hooks) | Where-Object {
                    $_.PSObject.Properties['command'] -and $_.command -match 'pre-edit-guard'
                }
            })

        Assert-Equal 1 $guards.Count 'exactly one file-edit guard registration'
        foreach ($tool in @('Edit', 'Write', 'NotebookEdit')) {
            Assert-Match "\b$tool\b" $guards[0].matcher "matcher must cover $tool"
        }
    }

    Write-Host 'Token quote masks' -ForegroundColor Cyan

    $maskCases = @(
        @{ Command = 'printf x > out.txt'; Token = 2; ExpectedToken = '>'; ExpectedMask = 'u' },
        @{ Command = "printf 'a>b'"; Token = 1; ExpectedToken = 'a>b'; ExpectedMask = 'qqq' },
        @{ Command = 'printf "a>b"'; Token = 1; ExpectedToken = 'a>b'; ExpectedMask = 'qqq' },
        @{ Command = 'printf x>out.txt'; Token = 1; ExpectedToken = 'x>out.txt'; ExpectedMask = 'uuuuuuuuu' }
    )

    foreach ($case in $maskCases) {
        Invoke-TestCase "Mask: $($case.Command)" {
            $parsed = Get-AgentCommandSegment -Command $case.Command
            $segment = $parsed.Segments[0]
            Assert-Equal $case.ExpectedToken $segment.Tokens[$case.Token] 'Token'
            Assert-Equal $case.ExpectedMask $segment.Masks[$case.Token] 'Mask'
        }
    }

    Invoke-TestCase 'Mask: an escaped redirect character is quoted, not a redirect' {
        $parsed = Get-AgentCommandSegment -Command 'printf x\>y'
        $segment = $parsed.Segments[0]
        Assert-Equal 'x>y' $segment.Tokens[1] 'Token'
        Assert-Equal 'uqu' $segment.Masks[1] 'Mask'
    }

    Invoke-TestCase 'Mask: masks stay aligned after an rtk wrapper is stripped' {
        $parsed = Get-AgentCommandSegment -Command 'rtk proxy printf x>out.txt'
        $segment = $parsed.Segments[0]
        Assert-Equal 'printf' $segment.Tokens[0] 'Leading token'
        Assert-Equal 'x>out.txt' $segment.Tokens[1] 'Target token'
        Assert-Equal 'uuuuuuuuu' $segment.Masks[1] 'Mask'
    }

    Invoke-TestCase 'Mask: masks stay aligned after a NAME=value prefix is stripped' {
        $parsed = Get-AgentCommandSegment -Command 'FOO=1 printf x>out.txt'
        $segment = $parsed.Segments[0]
        Assert-Equal 'printf' $segment.Tokens[0] 'Leading token'
        Assert-Equal 'uuuuuuuuu' $segment.Masks[1] 'Mask'
    }

    Write-Host 'Link target candidates' -ForegroundColor Cyan

    # A relative link target is resolved against the directory holding the link, not the working
    # directory, so one target has to be offered in every form it could mean.
    $linkCandidateCases = @(
        @{ Name = 'an absolute target says the same thing from every directory'
            LinkPath = 'link.md'; Target = 'C:\repo\README.md'
            Expected = @('C:\repo\README.md')
        },
        @{ Name = 'a UNC target is absolute too'
            LinkPath = 'link.md'; Target = '\\server\share\x.md'
            Expected = @('\\server\share\x.md')
        },
        @{ Name = 'a relative target with a parentless link drops the parent form'
            LinkPath = 'link.md'; Target = '..\README.md'
            Expected = @('..\README.md', 'link.md\..\README.md')
        },
        @{ Name = 'a relative target with a nested link carries all three forms'
            LinkPath = 'deep\x.md'; Target = '..\..\README.md'
            Expected = @('..\..\README.md', 'deep\x.md\..\..\README.md', 'deep\..\..\README.md')
        },
        # Join-Path rewrites every separator in BOTH arguments to the OS one, so the joined forms
        # come back fully backslashed. The raw target is added as written and keeps its slashes.
        @{ Name = 'a forward-slash link path splits the same way'
            LinkPath = 'deep/x.md'; Target = '../README.md'
            Expected = @('../README.md', 'deep\x.md\..\README.md', 'deep\..\README.md')
        },
        @{ Name = 'an empty target adds nothing'
            LinkPath = 'link.md'; Target = ''
            Expected = @()
        }
    )

    foreach ($case in $linkCandidateCases) {
        Invoke-TestCase "Link candidate: $($case.Name)" {
            $sink = New-Object System.Collections.Generic.List[string]
            Add-AgentLinkTargetCandidate -LinkPath $case.LinkPath -Target $case.Target -Sink $sink
            Assert-Equal ($case.Expected -join '|') ($sink.ToArray() -join '|') 'Candidates'
        }
    }

    Write-Host 'Write-target extraction' -ForegroundColor Cyan

    $writeTargetCases = @(
        # Redirects
        @{ Command = 'printf x > out.txt'; Expected = @('out.txt') },
        @{ Command = 'printf x >> out.txt'; Expected = @('out.txt') },
        @{ Command = 'printf x>out.txt'; Expected = @('out.txt') },
        @{ Command = 'printf x >out.txt'; Expected = @('out.txt') },
        @{ Command = 'dotnet build 2> err.log'; Expected = @('err.log') },
        @{ Command = "printf 'a>b'"; Expected = @() },
        @{ Command = 'printf x\>y'; Expected = @() },
        # Destination arguments
        @{ Command = 'cp a.txt b.txt'; Expected = @('b.txt') },
        # A move removes its source, so both endpoints are write targets. Destination first,
        # then sources - the assertion below joins the list in order.
        @{ Command = 'mv a.txt b.txt'; Expected = @('b.txt', 'a.txt') },
        @{ Command = 'mv a.txt c.txt b.txt'; Expected = @('b.txt', 'a.txt', 'c.txt') },
        @{ Command = 'mv -f a.txt b.txt'; Expected = @('b.txt', 'a.txt') },
        @{ Command = 'mv -t out a.txt c.txt'; Expected = @('out', 'a.txt', 'c.txt') },
        @{ Command = 'mv --target-directory=out a.txt'; Expected = @('out', 'a.txt') },
        # A short option takes its value from the FIRST 't' onward, so '-tout' is -t with the
        # value 'out'. Reading the LAST 't' instead made '-tout' look like a bare '-t' cluster,
        # which swallowed the next token as the directory and lost the real destination.
        @{ Command = 'mv -tout a.txt'; Expected = @('out', 'a.txt') },
        @{ Command = 'mv -vtout a.txt'; Expected = @('out', 'a.txt') },
        @{ Command = 'mv -tout a.txt c.txt'; Expected = @('out', 'a.txt', 'c.txt') },
        # '--' ends the options. A file name after it may start with a dash.
        @{ Command = 'mv -- -tracked.md dest.md'; Expected = @('dest.md', '-tracked.md') },
        @{ Command = 'mv -t out -- -a.txt'; Expected = @('out', '-a.txt') },
        @{ Command = 'Move-Item a.txt b.txt'; Expected = @('b.txt', 'a.txt') },
        @{ Command = 'Move-Item -Path a.txt -Destination b.txt'; Expected = @('b.txt', 'a.txt') },
        @{ Command = 'Move-Item -LiteralPath a.txt -Destination b.txt'; Expected = @('b.txt', 'a.txt') },
        # PowerShell's attached-colon form (-Path:value) packs the source into a dash-prefixed
        # token, which the positional reader alone would drop.
        @{ Command = 'Move-Item -Path:a.txt -Destination:b.txt'; Expected = @('b.txt', 'a.txt') },
        @{ Command = 'Move-Item -LiteralPath:a.txt -Destination b.txt'; Expected = @('b.txt', 'a.txt') },
        # Only -Path and -LiteralPath name a source, so a switch parameter is never harvested,
        # whatever value it carries. Reading the parameter NAME is what makes that true: an
        # earlier version filtered on the VALUE, which both dropped real paths and denied
        # ordinary switch values it could not expand.
        @{ Command = 'Move-Item a.txt b.txt -Confirm:$false'; Expected = @('b.txt', 'a.txt') },
        @{ Command = 'Move-Item a.txt b.txt -Force:$myVar'; Expected = @('b.txt', 'a.txt') },
        @{ Command = 'Move-Item a.txt b.txt -Confirm:$null'; Expected = @('b.txt', 'a.txt') },
        # A source whose name begins with a dash is a real file. The positional reader drops
        # every '-*' token, so only reading -Path by name keeps it.
        @{ Command = 'Move-Item -Path -tracked.md -Destination b.txt'; Expected = @('b.txt', '-tracked.md') },
        @{ Command = 'Move-Item -LiteralPath:-tracked.md -Destination b.txt'; Expected = @('b.txt', '-tracked.md') },
        # PowerShell binds an unambiguous prefix, so -pa and -li are -Path and -LiteralPath.
        @{ Command = 'Move-Item -pa:a.txt -Destination b.txt'; Expected = @('b.txt', 'a.txt') },
        @{ Command = 'Move-Item -li a.txt -Destination b.txt'; Expected = @('b.txt', 'a.txt') },
        # A boolean bound to -Path is a real (if odd) source name, so it is reported, not skipped.
        @{ Command = 'Move-Item -Path:$false -Destination b.txt'; Expected = @('b.txt', '$false') },
        # -Path takes an array, and PowerShell splits it across tokens at each comma.
        @{ Command = 'Move-Item -Path a.md,b.md -Destination x.md'; Expected = @('x.md', 'a.md', 'b.md') },
        @{ Command = 'Move-Item -Path a.md, b.md -Destination x.md'; Expected = @('x.md', 'a.md', 'b.md') },
        @{ Command = 'Rename-Item a.txt b.txt'; Expected = @('b.txt', 'a.txt') },
        # cp, install and ln leave the source in place, so they stay destination-only.
        @{ Command = 'cp -t out a.txt'; Expected = @('out') },
        @{ Command = 'cp -tout a.txt'; Expected = @('out') },
        @{ Command = 'Copy-Item a.txt -Destination b.txt'; Expected = @('b.txt') },
        @{ Command = 'rm a.txt b.txt'; Expected = @('a.txt', 'b.txt') },
        @{ Command = 'tee out.txt'; Expected = @('out.txt') },
        @{ Command = 'touch a.txt'; Expected = @('a.txt') },
        @{ Command = 'sed -i s/a/b/ file.txt'; Expected = @('file.txt') },
        @{ Command = 'sed s/a/b/ file.txt'; Expected = @() },
        @{ Command = 'dd if=a.bin of=b.bin'; Expected = @('b.bin') },
        @{ Command = 'Set-Content -Path out.txt -Value x'; Expected = @('out.txt') },
        @{ Command = 'Set-Content out.txt x'; Expected = @('out.txt') },
        @{ Command = 'Out-File -FilePath out.txt'; Expected = @('out.txt') },
        @{ Command = 'Copy-Item a.txt -Destination b.txt'; Expected = @('b.txt') },
        @{ Command = 'Copy-Item a.txt b.txt'; Expected = @('b.txt') },
        @{ Command = 'Remove-Item -LiteralPath out.txt'; Expected = @('out.txt') },
        # Reads produce nothing
        @{ Command = 'cat out.txt'; Expected = @() },
        @{ Command = 'Get-Content out.txt'; Expected = @() }
    )

    foreach ($case in $writeTargetCases) {
        Invoke-TestCase "Write target: $($case.Command)" {
            $parsed = Get-AgentCommandSegment -Command $case.Command
            $actual = @()
            foreach ($segment in $parsed.Segments) {
                $actual += @(Get-AgentSegmentWriteTarget -Tokens $segment.Tokens -Masks $segment.Masks)
            }
            Assert-Equal ($case.Expected -join '|') ($actual -join '|') 'Targets'
        }
    }

    Write-Host 'Nested interpreter write targets' -ForegroundColor Cyan

    $nestedCases = @(
        @{ Command = 'pwsh -Command "Set-Content -Path out.txt -Value x"'; Expected = @('out.txt') },
        @{ Command = "sh -c 'printf x > out.txt'"; Expected = @('out.txt') },
        @{ Command = "bash -c 'rm out.txt'"; Expected = @('out.txt') },
        @{ Command = 'cmd /c "del out.txt"'; Expected = @() },
        @{ Command = 'powershell -Command "Remove-Item out.txt"'; Expected = @('out.txt') },
        # Depth 2 is reached and still scanned.
        @{ Command = 'sh -c "pwsh -Command ''Set-Content out.txt x''"'; Expected = @('out.txt') },
        # A plain read inside the nested command yields nothing.
        @{ Command = "sh -c 'cat out.txt'"; Expected = @() }
    )

    foreach ($case in $nestedCases) {
        Invoke-TestCase "Nested: $($case.Command)" {
            $result = Get-AgentCommandWriteTarget -Command $case.Command
            Assert-Equal ($case.Expected -join '|') (@($result.Targets) -join '|') 'Targets'
            Assert-True (-not $result.Unresolved) 'Must resolve'
        }
    }

    Invoke-TestCase 'Nested: pwsh -File is deliberately not followed' {
        $result = Get-AgentCommandWriteTarget -Command 'pwsh -File build.ps1'
        Assert-Equal '' (@($result.Targets) -join '|') 'Targets'
        Assert-True (-not $result.Unresolved) 'Must resolve'
    }

    Invoke-TestCase 'Nested: nesting past the cap reports unresolved, not an empty target list' {
        $result = Get-AgentCommandWriteTarget -Command 'sh -c "sh -c \"sh -c ''rm out.txt''\""'
        Assert-True $result.Unresolved 'Must be unresolved'
    }

    Invoke-TestCase 'Nested: an untokenizable inner command reports unresolved' {
        $result = Get-AgentCommandWriteTarget -Command 'sh -c "rm ''out.txt"'
        Assert-True $result.Unresolved 'Must be unresolved'
    }

    Write-Host 'Write-target path resolution' -ForegroundColor Cyan

    Invoke-TestCase 'Resolution: a relative target joins the base directory' {
        $resolution = Get-AgentWriteTargetResolution -Target 'out.txt' -BaseDirectory $fixture.Managed
        Assert-True (-not $resolution.Unresolved) 'Must resolve'
        Assert-Equal (Join-Path $fixture.Managed 'out.txt') $resolution.Path 'Path'
    }

    Invoke-TestCase 'Resolution: an absolute target ignores the base directory' {
        $target = Join-Path $fixture.Main 'x.tmp'
        $resolution = Get-AgentWriteTargetResolution -Target $target -BaseDirectory $fixture.Managed
        Assert-True (-not $resolution.Unresolved) 'Must resolve'
        Assert-Equal $target $resolution.Path 'Path'
    }

    Invoke-TestCase 'Resolution: a symlinked directory resolves to its target' {
        $target = 'docs/superpowers/probe.tmp'
        $resolution = Get-AgentWriteTargetResolution -Target $target -BaseDirectory $fixture.Managed
        Assert-True (-not $resolution.Unresolved) 'Must resolve'
        Assert-Equal (Join-Path $fixture.Main 'docs\superpowers\probe.tmp') $resolution.Path 'Path'
    }

    Invoke-TestCase 'Resolution: a parent escape resolves out of the worktree' {
        $resolution = Get-AgentWriteTargetResolution -Target '../../../x.tmp' -BaseDirectory $fixture.Managed
        Assert-True (-not $resolution.Unresolved) 'Must resolve'
        Assert-Equal (Join-Path $fixture.Main 'x.tmp') $resolution.Path 'Path'
    }

    # A symlink target may be relative, and Windows resolves it against the directory holding the
    # link. Resolving it against the hook process's working directory instead classified the wrong
    # file, and a link that is the LAST path component indexed past the end of the split array.
    Invoke-TestCase 'Resolution: a relative file symlink resolves against the link parent' {
        $link = Join-Path $fixture.Managed 'relative-link.md'
        Assert-Equal (Join-Path $fixture.Main 'seed.txt') (Resolve-AgentSymlinkPath -Path $link) 'Resolved path'
    }

    Invoke-TestCase 'Resolution: a relative file symlink is classified in the main checkout' {
        $link = Join-Path $fixture.Managed 'relative-link.md'
        $resolution = Get-AgentWriteTargetResolution -Target $link -BaseDirectory $fixture.Managed -Literal
        Assert-True (-not $resolution.Unresolved) 'Must resolve'
        Assert-Equal (Join-Path $fixture.Main 'seed.txt') $resolution.Path 'Path'
    }

    # -Literal must classify the exact path the tool will open. A quote and a leading or trailing
    # space are legal Windows file name characters, so stripping them names a different file.
    Invoke-TestCase 'Resolution: -Literal keeps a leading quote in the path' {
        $resolution = Get-AgentWriteTargetResolution -Target "'\..\..\..\q.tmp" `
            -BaseDirectory $fixture.Managed -Literal
        Assert-True (-not $resolution.Unresolved) 'Must resolve'
        Assert-Equal (Join-Path $fixture.Main '.claude\q.tmp') $resolution.Path 'Path'
    }

    Invoke-TestCase 'Resolution: -Literal keeps a single quote in a file name' {
        $resolution = Get-AgentWriteTargetResolution -Target "'quoted'.cs" `
            -BaseDirectory $fixture.Managed -Literal
        Assert-Equal (Join-Path $fixture.Managed "'quoted'.cs") $resolution.Path 'Path'
    }

    # Windows PowerShell 5.1 runs on .NET Framework, whose path APIs reject '"' outright; pwsh 7
    # accepts it. Assert the invariant both hosts must hold: never throw, and never quietly drop
    # the character. Throwing would reach the entrypoint's catch and allow the write.
    Invoke-TestCase 'Resolution: -Literal never throws on a double quote in a file name' {
        $resolution = Get-AgentWriteTargetResolution -Target '"quoted".cs' `
            -BaseDirectory $fixture.Managed -Literal
        if ($resolution.Unresolved) {
            Assert-Equal '' $resolution.Path 'An unresolved target carries no path'
        }
        else {
            Assert-Equal (Join-Path $fixture.Managed '"quoted".cs') $resolution.Path 'Path'
        }
    }

    Invoke-TestCase 'Resolution: a command-line target still has its quoting stripped' {
        $resolution = Get-AgentWriteTargetResolution -Target '"quoted.cs"' -BaseDirectory $fixture.Managed
        Assert-Equal (Join-Path $fixture.Managed 'quoted.cs') $resolution.Path 'Path'
    }

    $unresolvedCases = @('$MAIN_ROOT/x.tmp', '%USERPROFILE%\x.tmp', '~/x.tmp')
    foreach ($case in $unresolvedCases) {
        Invoke-TestCase "Resolution: unexpandable leading component is unresolved: $case" {
            $resolution = Get-AgentWriteTargetResolution -Target $case -BaseDirectory $fixture.Managed
            Assert-True $resolution.Unresolved 'Must be unresolved'
        }
    }

    # A glob cannot match '..', so a literal prefix pins the directory. A variable or a command
    # substitution can expand to anything, including an absolute path or a parent escape.
    $unexpandableTailCases = @('./scripts/$DEST', 'scripts/%DEST%/x.tmp', 'scripts/$(cat p)/x.tmp', 'a/`b`/x.tmp')
    foreach ($case in $unexpandableTailCases) {
        Invoke-TestCase "Resolution: an unexpandable component after a literal prefix is unresolved: $case" {
            $resolution = Get-AgentWriteTargetResolution -Target $case -BaseDirectory $fixture.Managed
            Assert-True $resolution.Unresolved 'Must be unresolved'
        }
    }

    Invoke-TestCase 'Resolution: a glob after a literal prefix stays resolved' {
        $resolution = Get-AgentWriteTargetResolution -Target './obj/*' -BaseDirectory $fixture.Managed
        Assert-True (-not $resolution.Unresolved) 'Must resolve on the literal prefix'
        Assert-Equal (Join-Path $fixture.Managed 'obj') $resolution.Path 'Path'
    }

    Write-Host 'Worktree write isolation' -ForegroundColor Cyan

    $writeDecisionCases = @(
        # The two probes recorded in backlog 054.
        # Backlog 054 recorded this as a denial. Backlog 076 turned it into an allow on purpose:
        # docs/superpowers is a separate private repository the public repo git-ignores.
        @{ Name    = 'probe 1, symlinked plans path is now allowed'
            Command = 'printf probe > docs/superpowers/.guard-probe.tmp'; Cwd = 'Managed'; Action = 'Allow'
        },
        @{ Name    = 'a nested path inside the plans repo is allowed'
            Command = 'printf x > <MAIN>/docs/superpowers/plans/x.md'; Cwd = 'Managed'; Action = 'Allow'
        },
        @{ Name    = 'deleting a file inside the plans repo is allowed'
            Command = 'rm <MAIN>/docs/superpowers/seed-plan.md'; Cwd = 'Managed'; Action = 'Allow'
        },
        @{ Name    = 'moving a file within the plans repo is allowed'
            Command = 'mv <MAIN>/docs/superpowers/a.md <MAIN>/docs/superpowers/b.md'; Cwd = 'Managed'; Action = 'Allow'
        },
        # The move source is outside the plans repo, so the exception must not rescue it.
        @{ Name    = 'moving a main file into the plans repo is refused'
            Command = 'mv <MAIN>/seed.txt <MAIN>/docs/superpowers/seed.txt'; Cwd = 'Managed'; Action = 'Deny'
        },
        # PowerShell's attached-colon parameter form (-Path:value, -Destination:value) must not
        # slip the source past detection: the destination is inside the plans repo, but the
        # source is a plain main-checkout file the exception must not rescue.
        @{ Name    = 'moving a main file into the plans repo with colon-form parameters is refused'
            Command = 'Move-Item -Path:<MAIN>/seed.txt -Destination:<MAIN>/docs/superpowers/seed.txt'
            Cwd = 'Managed'; Action = 'Deny'
        },
        # A colon-form switch parameter riding along must not reopen the gap the case above
        # closes: the move source is still a plain main-checkout file, so this still denies.
        @{ Name    = 'moving a main file into the plans repo with colon-form parameters and a switch is refused'
            Command = 'Move-Item -Path:<MAIN>/seed.txt -Destination:<MAIN>/docs/superpowers/seed.txt -Confirm:$false'
            Cwd = 'Managed'; Action = 'Deny'
        },
        # The reverse direction: a file that already lives in the plans repo, moved back out to
        # an ordinary main-checkout location. The destination is outside the plans subtree, so
        # this must deny even though the source itself was allowed to live inside it.
        @{ Name    = 'moving a file out of the plans repo into main is refused'
            Command = 'mv <MAIN>/docs/superpowers/a.md <MAIN>/x.md'; Cwd = 'Managed'; Action = 'Deny'
        },
        # The plans repo's own .git is not an ordinary file inside it. Destroying it destroys the
        # private repository, including history that was never pushed, so the exception stops at
        # the repository boundary. Remove-Item is not the 'rm' the destructive tier matches, so
        # nothing else refuses this.
        @{ Name    = 'deleting the plans repo .git directory is refused'
            Command = 'Remove-Item <MAIN>/docs/superpowers/.git -Recurse -Force'
            Cwd = 'Managed'; Action = 'Deny'
        },
        @{ Name    = 'writing inside the plans repo .git directory is refused'
            Command = 'printf x > <MAIN>/docs/superpowers/.git/config'; Cwd = 'Managed'; Action = 'Deny'
        },
        # A git ref may be named 'bin', and 'bin' is a build-output component the allow-list
        # normally clears. The .git boundary has to win over that list, or a ref path reopens it.
        @{ Name    = 'a build-output name under the plans .git is still refused'
            Command = 'printf x > <MAIN>/docs/superpowers/.git/refs/heads/bin'
            Cwd = 'Managed'; Action = 'Deny'
        },
        @{ Name    = 'an obj name under the plans .git is still refused'
            Command = 'printf x > <MAIN>/docs/superpowers/.git/objects/obj'
            Cwd = 'Managed'; Action = 'Deny'
        },
        # The protected checkout's own .git carries the same risk one level up. A branch named
        # 'bin' or 'obj' puts a build-output component in the ref path, and the allow-list would
        # clear it, so a worktree session could delete a branch in the human's checkout.
        @{ Name    = 'a build-output name under the main .git is refused'
            Command = 'printf x > <MAIN>/.git/refs/heads/bin'; Cwd = 'Managed'; Action = 'Deny'
        },
        @{ Name    = 'deleting inside the main .git is refused'
            Command = 'Remove-Item <MAIN>/.git/worktrees/obj -Recurse -Force'
            Cwd = 'Managed'; Action = 'Deny'
        },
        # A real build-output path elsewhere in main stays allowed, so the fix above must not
        # disable the allow-list itself.
        @{ Name    = 'build output elsewhere in main stays allowed'
            Command = 'printf x > <MAIN>/src/bin/x.dll'; Cwd = 'Managed'; Action = 'Allow'
        },
        # PowerShell binds an unambiguous prefix for -Destination and -NewName too. The colon
        # form carries its own value, so no positional fallback can rescue a missed target.
        @{ Name    = 'an abbreviated colon-form destination into main is refused'
            Command = 'Move-Item a.txt -Dest:<MAIN>/x.txt'; Cwd = 'Managed'; Action = 'Deny'
        },
        @{ Name    = 'an abbreviated colon-form NewName into main is refused'
            Command = 'Rename-Item a.txt -NewN:<MAIN>/x.txt'; Cwd = 'Managed'; Action = 'Deny'
        },
        @{ Name    = 'an abbreviated colon-form Set-Content path into main is refused'
            Command = 'Set-Content -Pa:<MAIN>/x.txt -Value y'; Cwd = 'Managed'; Action = 'Deny'
        },
        # An option value is not a file the move touches, so it must not be read as a source.
        @{ Name    = 'a -Filter value is not treated as a move source'
            Command = 'Move-Item -Path a.txt -Destination b.txt -Filter <MAIN>/seed.txt'
            Cwd = 'Managed'; Action = 'Allow'
        },
        @{ Name    = 'an -Exclude value is not treated as a move source'
            Command = 'Move-Item -Path a.txt -Destination b.txt -Exclude <MAIN>/seed.txt'
            Cwd = 'Managed'; Action = 'Allow'
        },
        # A provider-qualified path names a real location, but it is not a rooted path, so it
        # would otherwise be anchored under the session worktree and wrongly allowed.
        @{ Name    = 'a provider-qualified move source out of main is refused'
            Command = "Move-Item -Path 'FileSystem::<MAIN>/seed.txt' -Destination <MANAGED>/x.md"
            Cwd = 'Managed'; Action = 'Deny'
        },
        # A switch parameter the guard cannot expand must not make an in-worktree move fail.
        @{ Name    = 'an unexpandable switch value does not block an in-worktree move'
            Command = 'Move-Item a.txt b.txt -Force:$myVar'; Cwd = 'Managed'; Action = 'Allow'
        },
        # The root is the link every worktree depends on.
        @{ Name    = 'the plans root itself is refused'
            Command = 'rm <MAIN>/docs/superpowers'; Cwd = 'Managed'; Action = 'Deny'
        },
        @{ Name    = 'renaming the plans root is refused'
            Command = 'mv <MAIN>/docs/superpowers <MAIN>/docs/superpowers-old'; Cwd = 'Managed'; Action = 'Deny'
        },
        # A name that merely starts the same way is a different directory.
        @{ Name    = 'a decoy sibling of the plans root is refused'
            Command = 'printf x > <MAIN>/docs/superpowers-decoy/x.md'; Cwd = 'Managed'; Action = 'Deny'
        },
        @{ Name    = 'another docs subtree is still refused'
            Command = 'printf x > <MAIN>/docs/anything-else/x.md'; Cwd = 'Managed'; Action = 'Deny'
        },
        @{ Name    = 'probe 2, plain main checkout root'
            Command = 'printf probe > <MAIN>/.guard-probe2.tmp'; Cwd = 'Managed'; Action = 'Deny'
        },
        # Reads stay allowed.
        @{ Name    = 'read through the symlink'
            Command = 'cat docs/superpowers/seed-plan.md'; Cwd = 'Managed'; Action = 'Allow'
        },
        @{ Name    = 'read a main checkout file'
            Command = 'cat <MAIN>/seed.txt'; Cwd = 'Managed'; Action = 'Allow'
        },
        # Writes inside the session's own worktree stay allowed.
        @{ Name    = 'write inside the worktree'
            Command = 'printf x > src.tmp'; Cwd = 'Managed'; Action = 'Allow'
        },
        # Build output in main stays allowed.
        @{ Name    = 'build output in main'
            Command = 'printf x > <MAIN>/obj/build.tmp'; Cwd = 'Managed'; Action = 'Allow'
        },
        @{ Name    = 'nested build output in main'
            Command = 'printf x > <MAIN>/src/Api/bin/Debug/app.dll'; Cwd = 'Managed'; Action = 'Allow'
        },
        # A sibling worktree is another agent's checkout.
        @{ Name    = 'sibling worktree is refused'
            Command = 'printf x > <MANAGED2>/src.tmp'; Cwd = 'Managed'; Action = 'Deny'
        },
        # The removal log is the one allowed path under the worktree parent.
        @{ Name    = 'removal log is allowed'
            Command = 'printf x >> <MAIN>/.claude/worktrees/worktree-removal.log'; Cwd = 'Managed'; Action = 'Allow'
        },
        # A main-checkout session is unaffected.
        @{ Name    = 'main session writes main'
            Command = 'printf x > <MAIN>/x.tmp'; Cwd = 'Main'; Action = 'Allow'
        },
        # Grammar shapes, end to end.
        @{ Name    = 'attached redirect'
            Command = 'printf x><MAIN>/x.tmp'; Cwd = 'Managed'; Action = 'Deny'
        },
        @{ Name    = 'nested interpreter'
            Command = 'pwsh -Command "Set-Content <MAIN>/x.tmp y"'; Cwd = 'Managed'; Action = 'Deny'
        },
        @{ Name    = 'destination argument'
            Command = 'cp a.txt <MAIN>/a.txt'; Cwd = 'Managed'; Action = 'Deny'
        },
        @{ Name    = 'quoted literal redirect is not a redirect'
            Command = "printf 'a><MAIN>/x.tmp'"; Cwd = 'Managed'; Action = 'Allow'
        },
        @{ Name    = 'unresolved target fails closed'
            Command = 'printf x > "$MAIN_ROOT/x.tmp"'; Cwd = 'Managed'; Action = 'Deny'
        },
        # `rm -rf` is not used here: the older dangerous-rm safety rule denies it on its own, so
        # the case would pass for the wrong reason. The write rule is exercised in isolation
        # below with the exact `rm -rf ./obj/*` command instead.
        @{ Name    = 'glob inside the worktree stays allowed'
            Command = 'rm -f ./obj/*'; Cwd = 'Managed'; Action = 'Allow'
        },
        # A cd earlier in the chain moves where the write lands.
        @{ Name    = 'cd into main then write'
            Command = 'cd <MAIN>; printf x > x.tmp'; Cwd = 'Managed'; Action = 'Deny'
        },
        # An unexpandable cd target leaves the guard blind to where a later relative write lands.
        @{ Name    = 'unresolved cd then a relative write'
            Command = 'cd "$MAIN_ROOT"; printf x > x.tmp'; Cwd = 'Managed'; Action = 'Deny'
        },
        @{ Name    = 'unresolved cd then an absolute write inside the worktree'
            Command = 'cd "$MAIN_ROOT"; printf x > <MANAGED>/x.tmp'; Cwd = 'Managed'; Action = 'Allow'
        },
        @{ Name    = 'a later resolved cd restores tracking'
            Command = 'cd "$MAIN_ROOT"; cd <MANAGED>; printf x > x.tmp'; Cwd = 'Managed'; Action = 'Allow'
        },
        # An unresolved pushd never lands on the guard's stack, because the guard cannot tell
        # whether the real pushd succeeded. So the following popd cannot prove where the shell
        # ended up either, and the chain stays untargetable.
        @{ Name    = 'popd after an unresolved pushd stays untargetable'
            Command = 'pushd "$MAIN_ROOT"; popd; printf x > x.tmp'; Cwd = 'Managed'; Action = 'Deny'
        },
        @{ Name    = 'popd after a resolved pushd restores tracking'
            Command = 'pushd <MAIN>; popd; printf x > x.tmp'; Cwd = 'Managed'; Action = 'Allow'
        },
        # A variable anywhere in the path can expand through '..' into main.
        @{ Name    = 'a variable after a literal prefix fails closed'
            Command = 'printf x > ./scripts/$DEST'; Cwd = 'Managed'; Action = 'Deny'
        },
        # -t / --target-directory move the destination off the last positional.
        @{ Name    = 'cp -t into main'
            Command = 'cp -t <MAIN> source.txt'; Cwd = 'Managed'; Action = 'Deny'
        },
        @{ Name    = 'cp --target-directory= into main'
            Command = 'cp --target-directory=<MAIN> source.txt'; Cwd = 'Managed'; Action = 'Deny'
        },
        @{ Name    = 'cp with a clustered -t into main'
            Command = 'cp -rt <MAIN> source.txt'; Cwd = 'Managed'; Action = 'Deny'
        },
        @{ Name    = 'mv -t into main'
            Command = 'mv -t <MAIN> source.txt'; Cwd = 'Managed'; Action = 'Deny'
        },
        @{ Name    = 'ln -t into main'
            Command = 'ln -s -t <MAIN> source.txt'; Cwd = 'Managed'; Action = 'Deny'
        },
        @{ Name    = 'install -t into main'
            Command = 'install -m 644 -t <MAIN> source.txt'; Cwd = 'Managed'; Action = 'Deny'
        },
        # A move out of main deletes a path in main, whatever its destination is.
        @{ Name    = 'mv out of main into the worktree is refused'
            Command = 'mv <MAIN>/seed.txt <MANAGED>/seed.txt'; Cwd = 'Managed'; Action = 'Deny'
        },
        @{ Name    = 'mv -t out of main into the worktree is refused'
            Command = 'mv -t <MANAGED> <MAIN>/seed.txt'; Cwd = 'Managed'; Action = 'Deny'
        },
        @{ Name    = 'Move-Item out of main is refused'
            Command = 'Move-Item <MAIN>/seed.txt <MANAGED>/seed.txt'; Cwd = 'Managed'; Action = 'Deny'
        },
        @{ Name    = 'Rename-Item inside main is refused'
            Command = 'Rename-Item <MAIN>/seed.txt old.txt'; Cwd = 'Managed'; Action = 'Deny'
        },
        # A copy leaves the source alone, so it stays allowed.
        @{ Name    = 'cp out of main into the worktree stays allowed'
            Command = 'cp <MAIN>/seed.txt <MANAGED>/seed.txt'; Cwd = 'Managed'; Action = 'Allow'
        },
        @{ Name    = 'mv inside the worktree stays allowed'
            Command = 'mv a.txt b.txt'; Cwd = 'Managed'; Action = 'Allow'
        },
        # A colon-form switch parameter is a normal non-interactive idiom and must not make the
        # harvest treat $false as an unresolvable source, which would deny an otherwise benign
        # in-worktree move.
        @{ Name    = 'Move-Item inside the worktree with a colon-form switch stays allowed'
            Command = 'Move-Item a.txt b.txt -Confirm:$false'; Cwd = 'Managed'; Action = 'Allow'
        },
        # A dash-prefixed source after '--' is a real file, not an option.
        @{ Name    = 'mv of a dash-prefixed source out of main is refused'
            Command = 'mv -- <MAIN>/-tracked.md <MANAGED>/tracked.md'; Cwd = 'Managed'; Action = 'Deny'
        },
        # -Path takes an array. The second element is the one that reaches main.
        @{ Name    = 'Move-Item with an array source is refused on the second element'
            Command = 'Move-Item -Path a.md, <MAIN>/seed.txt -Destination <MANAGED>/x.md'
            Cwd = 'Managed'; Action = 'Deny'
        },
        @{ Name    = 'cp -t inside the worktree stays allowed'
            Command = 'cp -t ./obj a.txt'; Cwd = 'Managed'; Action = 'Allow'
        },
        # Nesting deeper than the interpreter cap is never scanned, so it must fail closed.
        @{ Name    = 'nesting past the interpreter cap'
            Command = 'sh -c "sh -c \"sh -c ''printf x > <MAIN>/x.tmp''\""'; Cwd = 'Managed'; Action = 'Deny'
        },
        @{ Name    = 'nesting past the cap fails closed even when the inner command only reads'
            Command = 'sh -c "sh -c \"sh -c ''cat <MAIN>/seed.txt''\""'; Cwd = 'Managed'; Action = 'Deny'
        },
        # The session's worktree root is the git top level, not whatever directory it started in.
        @{ Name    = 'a subdirectory session writes its own worktree root'
            Command = 'printf x > ../README.md'; Cwd = 'ManagedSub'; Action = 'Allow'
        },
        @{ Name    = 'a subdirectory session still cannot write main'
            Command = 'printf x > <MAIN>/x.tmp'; Cwd = 'ManagedSub'; Action = 'Deny'
        }
    )

    foreach ($case in $writeDecisionCases) {
        Invoke-TestCase "Write isolation: $($case.Name)" {
            $command = $case.Command.
            Replace('<MAIN>', $fixture.Main.Replace('\', '/')).
            Replace('<MANAGED2>', $fixture.Managed2.Replace('\', '/')).
            Replace('<MANAGED>', $fixture.Managed.Replace('\', '/'))
            $cwd = switch ($case.Cwd) {
                'Main' { $fixture.Main }
                'ManagedSub' { Join-Path $fixture.Managed 'scripts' }
                default { $fixture.Managed }
            }
            $decision = Invoke-AgentGuardPolicy -Command $command `
                -Cwd $cwd -ProtectedRepoRoot $fixture.Main -AllowMain $false
            Assert-Equal $case.Action $decision.Action 'Action'
        }
    }

    Invoke-TestCase 'Write isolation: a move out of main names the source, not the destination' {
        $source = $fixture.Main.Replace('\', '/') + '/seed.txt'
        $destination = $fixture.Managed.Replace('\', '/') + '/seed.txt'
        $decision = Invoke-AgentGuardPolicy -Command "mv $source $destination" `
            -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main -AllowMain $false
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Match ([regex]::Escape((Join-Path $fixture.Main 'seed.txt'))) $decision.Message 'Message'
    }

    Invoke-TestCase 'Write isolation: rm -rf on a worktree glob is not a write-rule denial' {
        $decision = Get-AgentWorktreeWriteDecision -Command 'rm -rf ./obj/*' `
            -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main -AllowMain $false
        Assert-Equal 'Allow' $decision.Action 'Action'
    }

    Invoke-TestCase 'Write isolation: rm -rf inside the plans repo is still denied' {
        $command = 'rm -rf ' + $fixture.Main.Replace('\', '/') + '/docs/superpowers/plans'
        $decision = Invoke-AgentGuardPolicy -Command $command `
            -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main -AllowMain $false
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Equal 'dangerous-rm' $decision.Rule 'Rule'
    }

    Invoke-TestCase 'Write isolation: the plans-root refusal explains what is still refused' {
        $command = 'rm ' + $fixture.Main.Replace('\', '/') + '/docs/superpowers'
        $decision = Invoke-AgentGuardPolicy -Command $command `
            -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main -AllowMain $false
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Equal 'agent-worktree-main-write' $decision.Rule 'Rule'
        Assert-Match 'Files inside it are writable' $decision.Message 'Message'
        Assert-True ($decision.Message -notmatch 'worktree copy') 'Must not send the agent looking for a copy'
    }

    Invoke-TestCase 'Write isolation: AHKFLOW_ALLOW_MAIN=1 downgrades to a warning' {
        $command = 'printf probe > ' + $fixture.Main.Replace('\', '/') + '/x.tmp'
        $decision = Invoke-AgentGuardPolicy -Command $command `
            -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main -AllowMain $true
        Assert-Equal 'Warn' $decision.Action 'Action'
    }

    Invoke-TestCase 'Write isolation: a git mutation decision still wins over a write decision' {
        $command = 'git commit -m x'
        $decision = Invoke-AgentGuardPolicy -Command $command `
            -Cwd $fixture.Main -ProtectedRepoRoot $fixture.Main -AllowMain $false
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Equal 'agent-main-git-mutation' $decision.Rule 'Rule'
    }

    Write-Host 'File-edit write isolation' -ForegroundColor Cyan

    # One literal path per case. Placeholders are replaced against the disposable fixture below,
    # so no case names a real repository path.
    $fileEditCases = @(
        @{ Name = 'a file inside the session worktree'
            Path = '<MANAGED>\src\a.cs'; Cwd = 'Managed'; Action = 'Allow'
        },
        @{ Name = 'a file in the main checkout'
            Path = '<MAIN>\README.md'; Cwd = 'Managed'; Action = 'Deny'
        },
        @{ Name = 'a file in a sibling worktree'
            Path = '<MANAGED2>\src\a.cs'; Cwd = 'Managed'; Action = 'Deny'
        },
        @{ Name = 'build output under the main checkout'
            Path = '<MAIN>\obj\x.dll'; Cwd = 'Managed'; Action = 'Allow'
        },
        @{ Name = 'a path outside the protected checkout'
            Path = '<UNRELATED>\x.txt'; Cwd = 'Managed'; Action = 'Allow'
        },
        @{ Name = 'the worktree removal log'
            Path = '<MAIN>\.claude\worktrees\worktree-removal.log'; Cwd = 'Managed'; Action = 'Allow'
        },
        @{ Name = 'a main-checkout session may still edit main'
            Path = '<MAIN>\README.md'; Cwd = 'Main'; Action = 'Allow'
        },
        @{ Name = 'an unmanaged worktree session is not covered by this rule'
            Path = '<MAIN>\README.md'; Cwd = 'Unmanaged'; Action = 'Allow'
        },
        # docs\superpowers is a directory symlink back to the main checkout. The resolved path lands
        # in main, and backlog 076 allows it: the target is a separate private repository.
        @{ Name = 'the plans symlink resolves into the plans repo and is allowed'
            Path = '<MANAGED>\docs\superpowers\x.md'; Cwd = 'Managed'; Action = 'Allow'
        },
        @{ Name = 'the direct main path into the plans repo is allowed'
            Path = '<MAIN>\docs\superpowers\specs\x.md'; Cwd = 'Managed'; Action = 'Allow'
        },
        @{ Name = 'the plans root itself is refused'
            Path = '<MAIN>\docs\superpowers'; Cwd = 'Managed'; Action = 'Deny'
        },
        @{ Name = 'a decoy sibling of the plans root is refused'
            Path = '<MAIN>\docs\superpowers-decoy\x.md'; Cwd = 'Managed'; Action = 'Deny'
        },
        # A sibling worktree's own files are not the plans repo and stay refused.
        @{ Name = 'a sibling worktree file is still refused'
            Path = '<MANAGED2>\docs\notes.md'; Cwd = 'Managed'; Action = 'Deny'
        },
        @{ Name = 'a relative path resolves against the session working directory'
            Path = 'README.md'; Cwd = 'Managed'; Action = 'Allow'
        },
        @{ Name = 'a relative path can climb out into the main checkout'
            Path = '..\..\..\README.md'; Cwd = 'Managed'; Action = 'Deny'
        },
        @{ Name = 'an empty path has nothing to classify'
            Path = ''; Cwd = 'Managed'; Action = 'Allow'
        },
        # A tool call cannot expand '~'. Fail closed rather than guess which home directory.
        @{ Name = 'a home-relative path fails closed'
            Path = '~\x.txt'; Cwd = 'Managed'; Action = 'Deny'
        },
        # '$', '%' and backtick are legal in a Windows file name, and a tool call carries a literal
        # path with no shell expansion. Treating one as unexpandable would refuse a real edit
        # inside the session's own worktree.
        @{ Name = 'a dollar sign in a file name is not a shell expansion'
            Path = '<MANAGED>\src\a$b.cs'; Cwd = 'Managed'; Action = 'Allow'
        },
        @{ Name = 'a percent sign in a file name is not a shell expansion'
            Path = '<MANAGED>\src\a%b.cs'; Cwd = 'Managed'; Action = 'Allow'
        },
        @{ Name = 'a subdirectory session writes its own worktree root'
            Path = '<MANAGED>\README.md'; Cwd = 'ManagedSub'; Action = 'Allow'
        },
        @{ Name = 'a subdirectory session still cannot write the main checkout'
            Path = '<MAIN>\x.tmp'; Cwd = 'ManagedSub'; Action = 'Deny'
        },
        # A file symlink inside the worktree whose relative target climbs into the main checkout.
        # Edit and Write follow the link, so the classification has to follow it too.
        @{ Name = 'a relative file symlink into the main checkout'
            Path = '<MANAGED>\relative-link.md'; Cwd = 'Managed'; Action = 'Deny'
        },
        # A leading quote is a legal Windows file name character. Stripping it turned this path
        # into a drive-rooted one outside the checkout, and the write was allowed.
        @{ Name = 'a leading quote does not turn a parent escape into a rooted path'
            Path = "'\..\..\..\q.tmp"; Cwd = 'Managed'; Action = 'Deny'
        }
    )

    foreach ($case in $fileEditCases) {
        Invoke-TestCase "File-edit isolation: $($case.Name)" {
            $path = $case.Path.
            Replace('<MANAGED2>', $fixture.Managed2).
            Replace('<MANAGED>', $fixture.Managed).
            Replace('<UNRELATED>', $fixture.Unrelated).
            Replace('<MAIN>', $fixture.Main)
            $cwd = switch ($case.Cwd) {
                'Main' { $fixture.Main }
                'Unmanaged' { $fixture.Unmanaged }
                'ManagedSub' { Join-Path $fixture.Managed 'scripts' }
                default { $fixture.Managed }
            }
            $decision = Get-AgentFileEditWriteDecision -TargetPath $path `
                -Cwd $cwd -ProtectedRepoRoot $fixture.Main -AllowMain $false
            Assert-Equal $case.Action $decision.Action 'Action'
        }
    }

    Invoke-TestCase 'File-edit isolation: a denial carries the shared write rule name' {
        $decision = Get-AgentFileEditWriteDecision -TargetPath (Join-Path $fixture.Main 'README.md') `
            -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main -AllowMain $false
        Assert-Equal 'agent-worktree-main-write' $decision.Rule 'Rule'
        Assert-Match 'cannot write into the main checkout' $decision.Message 'Message'
    }

    Invoke-TestCase 'File-edit isolation: a file inside the plans repo is allowed' {
        $path = Join-Path $fixture.Managed 'docs\superpowers\x.md'
        $decision = Get-AgentFileEditWriteDecision -TargetPath $path `
            -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main -AllowMain $false
        Assert-Equal 'Allow' $decision.Action 'Action'
    }

    Invoke-TestCase 'File-edit isolation: the plans root itself explains what is still refused' {
        $path = Join-Path $fixture.Main 'docs\superpowers'
        $decision = Get-AgentFileEditWriteDecision -TargetPath $path `
            -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main -AllowMain $false
        Assert-Equal 'Deny' $decision.Action 'Action'
        Assert-Match 'Files inside it are writable' $decision.Message 'Message'
        Assert-True ($decision.Message -notmatch 'worktree copy') 'Must not send the agent looking for a copy'
    }

    Invoke-TestCase 'File-edit isolation: AHKFLOW_ALLOW_MAIN=1 downgrades to a warning' {
        $decision = Get-AgentFileEditWriteDecision -TargetPath (Join-Path $fixture.Main 'README.md') `
            -Cwd $fixture.Managed -ProtectedRepoRoot $fixture.Main -AllowMain $true
        Assert-Equal 'Warn' $decision.Action 'Action'
        Assert-Match 'AHKFLOW_ALLOW_MAIN=1' $decision.Message 'Message'
    }

    # A copy of the entrypoint planted inside the fixture, so it protects the fixture's main
    # checkout and treats $fixture.Managed as a real managed worktree. The checked-in entrypoint
    # would protect the real repository instead, and a fixture path would classify as
    # OutsideProtectedRepository.
    $script:FixtureEntrypoint = New-FixtureEntrypoint -RepoRoot $fixture.Main

    foreach ($toolName in @('Edit', 'Write', 'NotebookEdit')) {
        Invoke-TestCase "Entrypoint: $toolName into the main checkout is denied" {
            $target = Join-Path $fixture.Main 'README.md'
            $result = Invoke-Entrypoint -Adapter 'Claude' -ScriptPath $script:FixtureEntrypoint `
                -StdIn (New-ClaudeEditPayload $toolName $target $fixture.Managed)
            Assert-Equal 2 $result.ExitCode 'ExitCode'
            Assert-Match 'cannot write into the main checkout' $result.StdErr 'StdErr'
        }
    }

    Invoke-TestCase 'Entrypoint: a Write inside the plans repo is allowed' {
        $target = Join-Path $fixture.Managed 'docs\superpowers\x.md'
        $result = Invoke-Entrypoint -Adapter 'Claude' -ScriptPath $script:FixtureEntrypoint `
            -StdIn (New-ClaudeEditPayload 'Write' $target $fixture.Managed)
        Assert-Equal 0 $result.ExitCode 'ExitCode'
        Assert-Equal '' $result.StdOut.Trim() 'Must produce no decision payload'
    }

    Invoke-TestCase 'Entrypoint: the plans-root refusal reaches the agent verbatim' {
        $target = Join-Path $fixture.Main 'docs\superpowers'
        $result = Invoke-Entrypoint -Adapter 'Claude' -ScriptPath $script:FixtureEntrypoint `
            -StdIn (New-ClaudeEditPayload 'Write' $target $fixture.Managed)
        Assert-Equal 2 $result.ExitCode 'ExitCode'
        Assert-Match 'Files inside it are writable' $result.StdErr 'StdErr'
        Assert-True ($result.StdErr -notmatch 'worktree copy') 'Must not send the agent looking for a copy'
    }

    Invoke-TestCase 'Entrypoint: an edit inside the session worktree is allowed' {
        $target = Join-Path $fixture.Managed 'README.md'
        $result = Invoke-Entrypoint -Adapter 'Claude' -ScriptPath $script:FixtureEntrypoint `
            -StdIn (New-ClaudeEditPayload 'Edit' $target $fixture.Managed)
        Assert-Equal 0 $result.ExitCode 'ExitCode'
        Assert-Equal '' $result.StdOut.Trim() 'Must produce no decision payload'
    }

    Invoke-TestCase 'Entrypoint: a main-checkout session may still edit the main checkout' {
        $target = Join-Path $fixture.Main 'README.md'
        $result = Invoke-Entrypoint -Adapter 'Claude' -ScriptPath $script:FixtureEntrypoint `
            -StdIn (New-ClaudeEditPayload 'Edit' $target $fixture.Main)
        Assert-Equal 0 $result.ExitCode 'ExitCode'
    }

    Invoke-TestCase 'Entrypoint: AHKFLOW_ALLOW_MAIN=1 warns instead of denying an edit' {
        $target = Join-Path $fixture.Main 'README.md'
        $result = Invoke-Entrypoint -Adapter 'Claude' -ScriptPath $script:FixtureEntrypoint `
            -StdIn (New-ClaudeEditPayload 'Edit' $target $fixture.Managed) `
            -EnvironmentOverrides @{ AHKFLOW_ALLOW_MAIN = '1' }
        Assert-Equal 0 $result.ExitCode 'ExitCode'
        Assert-Match 'AHKFLOW_ALLOW_MAIN=1 overrode' $result.StdErr 'StdErr'
    }

    Invoke-TestCase 'Entrypoint: AHKFLOW_GUARD_DISABLE=1 skips the file-edit rule too' {
        $target = Join-Path $fixture.Main 'README.md'
        $result = Invoke-Entrypoint -Adapter 'Claude' -ScriptPath $script:FixtureEntrypoint `
            -StdIn (New-ClaudeEditPayload 'Edit' $target $fixture.Managed) `
            -EnvironmentOverrides @{ AHKFLOW_GUARD_DISABLE = '1' }
        Assert-Equal 0 $result.ExitCode 'ExitCode'
        Assert-True ($result.StdErr -notmatch 'cannot write into the main checkout') 'Must not deny'
    }

    Invoke-TestCase 'Entrypoint: Codex file-edit calls stay out of scope' {
        $target = Join-Path $fixture.Main 'README.md'
        $result = Invoke-Entrypoint -Adapter 'Codex' -ScriptPath $script:FixtureEntrypoint `
            -StdIn (New-ClaudeEditPayload 'Edit' $target $fixture.Managed)
        Assert-Equal 0 $result.ExitCode 'ExitCode'
        Assert-True ($result.StdErr -notmatch 'cannot write into the main checkout') 'Must not deny'
    }

    Write-Host 'Bash shim prefilter for worktree writes' -ForegroundColor Cyan

    # These three run against the REAL repository identity, like every other shim test above: the
    # entrypoint derives the protected repository from its own checked-in location, so a fixture
    # path would classify as OutsideProtectedRepository and prove nothing. Nothing is executed -
    # the shim only classifies the command text.
    $script:RealWriteCommand = 'printf probe > ' + $script:RealMainCheckout.Replace('\', '/') + '/.guard-probe.tmp'

    # Proved against the stub entrypoint, not the real one. The old version of this case passed a
    # payload whose cwd was $suiteRoot and expected a denial, which only happens when the suite
    # itself runs inside a managed worktree. From a plain checkout, and in CI, it failed.
    Invoke-TestCase 'Shim: a worktree-session write is forwarded to the policy core' {
        $harness = New-ShimHarness -ShimFileName 'pre-bash-guard.sh'
        try {
            $worktreeCwd = Join-Path $script:RealMainCheckout '.claude\worktrees\probe'
            $result = Invoke-HarnessShim -Harness $harness `
                -StdIn (New-ClaudePayload 'printf probe > ../../../README.md' $worktreeCwd)
            Assert-Match $script:ShimStubMarker $result.StdErr 'Must forward to the entrypoint'
        }
        finally { Remove-ShimHarness -Harness $harness }
    }

    Invoke-TestCase 'Shim: a main-session redirect still exits in Bash' {
        $result = Invoke-BashShim -StdIn (New-ClaudePayload $script:RealWriteCommand $script:RealMainCheckout)
        Assert-Equal 0 $result.ExitCode 'Exit code'
        Assert-Equal '' $result.StdOut.Trim() 'Must produce no decision payload'
    }

    Invoke-TestCase 'Shim: a worktree-session read still exits in Bash' {
        $result = Invoke-BashShim -StdIn (New-ClaudePayload 'cat README.md' $suiteRoot)
        Assert-Equal 0 $result.ExitCode 'Exit code'
        Assert-Equal '' $result.StdOut.Trim() 'Must produce no decision payload'
    }

    Write-Host 'Bash shim prefilter for file-edit tool calls' -ForegroundColor Cyan

    Invoke-TestCase 'Edit shim: a worktree-session edit is forwarded to the policy core' {
        $harness = New-ShimHarness -ShimFileName 'pre-edit-guard.sh'
        try {
            $worktreeCwd = Join-Path $script:RealMainCheckout '.claude\worktrees\probe'
            $target = Join-Path $script:RealMainCheckout 'README.md'
            $result = Invoke-HarnessShim -Harness $harness `
                -StdIn (New-ClaudeEditPayload 'Edit' $target $worktreeCwd)
            Assert-Match $script:ShimStubMarker $result.StdErr 'Must forward to the entrypoint'
            Assert-Match 'adapter=Claude' $result.StdErr 'Must select the Claude adapter'
        }
        finally { Remove-ShimHarness -Harness $harness }
    }

    Invoke-TestCase 'Edit shim: a main-session edit exits in Bash' {
        $harness = New-ShimHarness -ShimFileName 'pre-edit-guard.sh'
        try {
            $target = Join-Path $script:RealMainCheckout 'README.md'
            $result = Invoke-HarnessShim -Harness $harness `
                -StdIn (New-ClaudeEditPayload 'Edit' $target $script:RealMainCheckout)
            Assert-Equal 0 $result.ExitCode 'ExitCode'
            Assert-True ($result.StdErr -notmatch $script:ShimStubMarker) 'Must not start PowerShell'
        }
        finally { Remove-ShimHarness -Harness $harness }
    }

    Invoke-TestCase 'Edit shim: a Write payload is forwarded too' {
        $harness = New-ShimHarness -ShimFileName 'pre-edit-guard.sh'
        try {
            $worktreeCwd = Join-Path $script:RealMainCheckout '.claude\worktrees\probe'
            $target = Join-Path $script:RealMainCheckout 'notes.md'
            $result = Invoke-HarnessShim -Harness $harness `
                -StdIn (New-ClaudeEditPayload 'Write' $target $worktreeCwd)
            Assert-Match $script:ShimStubMarker $result.StdErr 'Must forward to the entrypoint'
        }
        finally { Remove-ShimHarness -Harness $harness }
    }

    Invoke-TestCase 'Edit shim: honors AHKFLOW_GUARD_DISABLE before doing any work' {
        $harness = New-ShimHarness -ShimFileName 'pre-edit-guard.sh'
        try {
            $worktreeCwd = Join-Path $script:RealMainCheckout '.claude\worktrees\probe'
            $target = Join-Path $script:RealMainCheckout 'README.md'
            $result = Invoke-HarnessShim -Harness $harness `
                -StdIn (New-ClaudeEditPayload 'Edit' $target $worktreeCwd) `
                -EnvironmentOverrides @{ AHKFLOW_GUARD_DISABLE = '1' }
            Assert-Equal 0 $result.ExitCode 'ExitCode'
            Assert-Match 'AHKFLOW_GUARD_DISABLE=1' $result.StdErr 'StdErr'
            Assert-True ($result.StdErr -notmatch $script:ShimStubMarker) 'Must not start PowerShell'
        }
        finally { Remove-ShimHarness -Harness $harness }
    }

    Invoke-TestCase 'Edit shim: warns and allows when no PowerShell host exists' {
        $harness = New-ShimHarness -ShimFileName 'pre-edit-guard.sh'
        try {
            $pathWithoutAnyHost = (
                $env:PATH -split ';' |
                Where-Object {
                    $_ -and -not (Test-Path -LiteralPath (Join-Path $_ 'pwsh.exe')) -and
                    -not (Test-Path -LiteralPath (Join-Path $_ 'powershell.exe'))
                }
            ) -join ';'
            $worktreeCwd = Join-Path $script:RealMainCheckout '.claude\worktrees\probe'
            $target = Join-Path $script:RealMainCheckout 'README.md'
            $result = Invoke-HarnessShim -Harness $harness `
                -StdIn (New-ClaudeEditPayload 'Edit' $target $worktreeCwd) `
                -EnvironmentOverrides @{ PATH = $pathWithoutAnyHost }
            Assert-Equal 0 $result.ExitCode 'ExitCode'
            Assert-Match 'could not find PowerShell' $result.StdErr 'StdErr'
        }
        finally { Remove-ShimHarness -Harness $harness }
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
