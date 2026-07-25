#Requires -Version 5.1
<#
.SYNOPSIS
Regression tests for the Claude Code pre-commit anti-pattern hook's sync-over-async scan.

.DESCRIPTION
Guards the `using X.Result;` exclusion (`.claude/hooks/pre-commit-antipattern.ps1`): a namespace
import whose last segment is literally `Result` must NOT be flagged as a blocking `.Result` access,
while a real sync-over-async access — including a `using` *declaration* that ends in `.Result` — must
still be caught. Each scenario builds a disposable git repo under the temp directory, copies the
in-development hook into its `.claude/hooks` layout (the hook anchors to `$PSScriptRoot/../..`), stages
a real .cs file, and drives the hook over stdin exactly as Claude Code does.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$suiteRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$script:Failures = New-Object System.Collections.Generic.List[string]

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]] $GitArguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & git @GitArguments 2>&1 | Out-Null }
    finally { $ErrorActionPreference = $previous }
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

function New-HookFixture {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-antipattern-' + [guid]::NewGuid().ToString('N'))
    $repo = Join-Path $testRoot 'repo'

    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    Invoke-Git init --initial-branch=main $repo
    Invoke-Git -C $repo config user.name 'AntiPattern Test'
    Invoke-Git -C $repo config user.email 'antipattern@example.invalid'
    Set-Content -LiteralPath (Join-Path $repo 'seed.txt') -Value 'seed' -Encoding utf8
    Invoke-Git -C $repo add seed.txt
    Invoke-Git -C $repo commit -m 'seed'

    New-Item -ItemType Directory -Path (Join-Path $repo '.claude\hooks') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $suiteRoot '.claude\hooks\pre-commit-antipattern.ps1') `
              -Destination (Join-Path $repo '.claude\hooks\pre-commit-antipattern.ps1') -Force

    return [pscustomobject]@{
        TestRoot = (Resolve-Path -LiteralPath $testRoot).Path
        Repo     = (Resolve-Path -LiteralPath $repo).Path
    }
}

function Remove-HookFixture {
    param([object] $Fixture)
    if ($null -eq $Fixture) { return }
    $tempRoot = (Resolve-Path -LiteralPath ([System.IO.Path]::GetTempPath())).Path.TrimEnd('\', '/')
    $target = $Fixture.TestRoot.TrimEnd('\', '/')
    if (-not $target.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to delete a fixture outside the temp directory: $target"
    }
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try { Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop; return }
        catch { if ($attempt -eq 3) { return }; Start-Sleep -Milliseconds 200 }
    }
}

# Stages a .cs file with the given body and runs the hook exactly as Claude Code does — a git-commit
# command delivered over stdin as tool_input JSON. Returns the hook's exit code (0 clean, 2 blocked).
function Invoke-HookOnCsFile {
    param([object] $Fixture, [string] $Body)

    $file = Join-Path $Fixture.Repo ('Sample-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.cs')
    Set-Content -LiteralPath $file -Value $Body -Encoding utf8
    Invoke-Git -C $Fixture.Repo add ($file)

    $hookPath = Join-Path $Fixture.Repo '.claude\hooks\pre-commit-antipattern.ps1'
    $psExe = [System.Diagnostics.Process]::GetCurrentProcess().Path
    $json = '{"tool_input":{"command":"git commit -m test"}}'

    $stdinFile = [System.IO.Path]::GetTempFileName()
    Set-Content -LiteralPath $stdinFile -Value $json -Encoding utf8 -NoNewline
    try {
        $proc = Start-Process -FilePath $psExe `
            -ArgumentList @('-NoProfile', '-NonInteractive', '-File', $hookPath) `
            -WorkingDirectory $Fixture.Repo -RedirectStandardInput $stdinFile `
            -RedirectStandardOutput ([System.IO.Path]::GetTempFileName()) `
            -RedirectStandardError ([System.IO.Path]::GetTempFileName()) `
            -NoNewWindow -PassThru -Wait
        return $proc.ExitCode
    }
    finally {
        Remove-Item -LiteralPath $stdinFile -Force -ErrorAction SilentlyContinue
        # Unstage so the next case starts from a clean index.
        Invoke-Git -C $Fixture.Repo reset --quiet
    }
}

# ── Scenarios ───────────────────────────────────────────────────────────────────────────────

$fixture = $null
try {
    $fixture = New-HookFixture

    Invoke-TestCase 'using X.Result; namespace import is not flagged as sync-over-async' {
        $body = @(
            'using Ardalis.Result;',
            'namespace Sample;',
            'public sealed class Ok { public int Value => 1; }'
        ) -join "`n"
        $exit = Invoke-HookOnCsFile -Fixture $fixture -Body $body
        Assert-True ($exit -eq 0) "expected exit 0 (clean); got $exit"
    }

    Invoke-TestCase 'A real blocking .Result access is still caught' {
        $body = @(
            'using System.Threading.Tasks;',
            'namespace Sample;',
            'public sealed class Bad { public int Value() => Task.FromResult(1).Result; }'
        ) -join "`n"
        $exit = Invoke-HookOnCsFile -Fixture $fixture -Body $body
        Assert-True ($exit -eq 2) "expected exit 2 (blocked); got $exit"
    }

    Invoke-TestCase 'A using DECLARATION ending in .Result is not swallowed by the import exclusion' {
        $body = @(
            'using System.Threading.Tasks;',
            'namespace Sample;',
            'public sealed class Decl { public void M() { using var d = (System.IDisposable)Task.FromResult(1).Result; } }'
        ) -join "`n"
        $exit = Invoke-HookOnCsFile -Fixture $fixture -Body $body
        Assert-True ($exit -eq 2) "expected exit 2 (blocked); got $exit"
    }
}
finally {
    Remove-HookFixture -Fixture $fixture
}

Write-Host ''
if ($script:Failures.Count -gt 0) {
    Write-Host "FAILED: $($script:Failures.Count) test(s)" -ForegroundColor Red
    foreach ($failure in $script:Failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'All pre-commit anti-pattern hook tests passed.' -ForegroundColor Green
exit 0
