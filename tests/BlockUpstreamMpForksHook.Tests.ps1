#Requires -Version 7.0
<#
.SYNOPSIS
Tests the Claude Code UserPromptExpansion hook that blocks the upstream mattpocock-skills forks.

.DESCRIPTION
The repository keeps adapted forks of some upstream mattpocock-skills skills, named mp-*. The
hook .claude/hooks/block-upstream-mp-forks.ps1 blocks the typed upstream slash command. Each
script case writes a hook input under the temp folder, then runs the hook as its own process,
the way Claude Code runs it. Exit code 2 blocks the expansion.

Run it by hand with:  pwsh ./tests/BlockUpstreamMpForksHook.Tests.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$script:HookPath = Join-Path $repoRoot '.claude/hooks/block-upstream-mp-forks.ps1'
$script:HostExe = [System.Diagnostics.Process]::GetCurrentProcess().Path
$script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-mpblock-' + [guid]::NewGuid().ToString('N'))
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

    Invoke-TestCase 'A payload with command_name is blocked and names the mp- fork' {
        $result = Invoke-Hook '{"hook_event_name":"UserPromptExpansion","command_name":"mattpocock-skills:grilling"}'
        Assert-True ($result.ExitCode -eq 2) "Expected exit 2, got $($result.ExitCode). Stderr: $($result.Stderr)"
        Assert-True ($result.Stderr.Contains('/mp-grilling')) "The message must name /mp-grilling. Stderr: $($result.Stderr)"
    }

    Invoke-TestCase 'A payload with no command_name is blocked by the text search' {
        $result = Invoke-Hook '{"hook_event_name":"UserPromptExpansion","prompt":"/mattpocock-skills:research"}'
        Assert-True ($result.ExitCode -eq 2) "Expected exit 2, got $($result.ExitCode). Stderr: $($result.Stderr)"
        Assert-True ($result.Stderr.Contains('/mp-research')) "The message must name /mp-research. Stderr: $($result.Stderr)"
    }

    Invoke-TestCase 'An empty payload is still blocked' {
        $result = Invoke-Hook ''
        Assert-True ($result.ExitCode -eq 2) "Expected exit 2, got $($result.ExitCode). Stderr: $($result.Stderr)"
        Assert-True ($result.Stderr.Contains('Use the mp- version instead.')) "The message must point at the mp- version. Stderr: $($result.Stderr)"
    }

    # --- The registration in .claude/settings.json ---

    # The fork names come from the .agents/mp-* folders, so a new or retired fork fails these
    # cases until the deny list and the matcher change with it.
    $forkNames = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot '.agents') -Directory -Filter 'mp-*' |
        ForEach-Object { $_.Name.Substring(3) } | Sort-Object)
    $settings = Get-Content -LiteralPath (Join-Path $repoRoot '.claude/settings.json') -Raw | ConvertFrom-Json

    function Get-BlockerRegistration {
        if ($null -eq $settings.hooks.PSObject.Properties['UserPromptExpansion']) { return @() }
        return @($settings.hooks.UserPromptExpansion | ForEach-Object {
                $group = $_
                @($group.hooks) | Where-Object {
                    $_.PSObject.Properties['command'] -and $_.command -eq 'pwsh' -and
                    $_.PSObject.Properties['args'] -and
                    @($_.args) -contains '${CLAUDE_PROJECT_DIR}/.claude/hooks/block-upstream-mp-forks.ps1'
                } | ForEach-Object { [pscustomobject]@{ Matcher = [string]$group.matcher; Hook = $_ } }
            })
    }

    function Get-BlockerMatcher {
        $registrations = @(Get-BlockerRegistration)
        Assert-True ($registrations.Count -ge 1) '.claude/settings.json registers no UserPromptExpansion hook for block-upstream-mp-forks.ps1.'
        return $registrations[0].Matcher
    }

    # The script exits 2 on every path, so the matcher alone decides what is blocked.
    # -cmatch keeps case, the way the JavaScript regular expression in Claude Code does.
    Invoke-TestCase 'The matcher accepts every mp- fork' {
        Assert-True ($forkNames.Count -gt 0) 'Found no .agents/mp-* folders.'
        $matcher = Get-BlockerMatcher
        foreach ($name in $forkNames) {
            Assert-True ("mattpocock-skills:$name" -cmatch $matcher) "The matcher does not match mattpocock-skills:$name. Matcher: $matcher"
        }
    }

    Invoke-TestCase 'The matcher rejects every other command' {
        $matcher = Get-BlockerMatcher
        $others = @(
            'mattpocock-skills:handoff'       # kept reachable, backlog 125
            'mattpocock-skills:wait-what'     # kept reachable, backlog 125
            'mp-grilling'                     # the local fork
            'mattpocock-skills:grilling-extra' # proves the $ anchor
            'x-mattpocock-skills:grilling'    # proves the ^ anchor
            'Mattpocock-skills:grilling'      # proves case
            'superpowers:brainstorming'
        )
        foreach ($other in $others) {
            Assert-True (-not ($other -cmatch $matcher)) "The matcher must not match $other. Matcher: $matcher"
        }
    }

    # The negatives above cannot catch a matcher that names one skill too many, such as a
    # retired fork. So the matcher's name list must equal the fork names exactly.
    Invoke-TestCase 'The matcher names every mp- fork and nothing else' {
        $matcher = Get-BlockerMatcher
        Assert-True ($matcher -cmatch '^\^mattpocock-skills:\(([a-z0-9|-]+)\)\$$') "The matcher must have the form ^mattpocock-skills:(a|b|...)$. Matcher: $matcher"
        $named = @($Matches[1].Split('|') | Sort-Object)
        $expected = $forkNames -join ', '
        $actual = $named -join ', '
        Assert-True ($actual -eq $expected) "Expected the matcher to name [$expected], found [$actual]."
    }

    Invoke-TestCase 'The deny list names every mp- fork and nothing else from mattpocock-skills' {
        $denied = @(@($settings.permissions.deny) | ForEach-Object {
                if ($_ -match '^Skill\(mattpocock-skills:(.+)\)$') { $Matches[1] }
            } | Sort-Object)
        $expected = $forkNames -join ', '
        $actual = $denied -join ', '
        Assert-True ($actual -eq $expected) "Expected Skill(mattpocock-skills:...) denies for [$expected], found [$actual]."
    }

    Invoke-TestCase '.claude/settings.json runs the blocker on UserPromptExpansion, once' {
        $registrations = @(Get-BlockerRegistration)
        Assert-True ($registrations.Count -eq 1) "Expected one UserPromptExpansion entry for block-upstream-mp-forks.ps1, found $($registrations.Count)."
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

Write-Host 'All upstream mp block hook tests passed.' -ForegroundColor Green
exit 0
