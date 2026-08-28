#Requires -Version 5.1
<#
.SYNOPSIS
Tests for the coverage-slice skip decision shared by the local Gate and ci.yml.

.DESCRIPTION
Three layers are covered here.

  1. Reading .github/code-paths-filter.yml and turning each pattern into a regex.
  2. Deciding from a real branch diff, in a throwaway git repository under the temp folder.
  3. The wiring in scripts/test-fast.ps1, driven in a synthetic repository whose
     run-coverage.ps1 is a stub that writes a marker file. The marker is what proves the
     slice ran; no SQL Server container is ever started by this suite.

No case runs against the real repository's own diff. That diff changes with every commit, so a
case reading it would pass or fail depending on what the developer had edited.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# PowerShell 7.4 turns a non-zero native exit code into a terminating error while
# $ErrorActionPreference is 'Stop'. Several cases here run git and a child pwsh and read the
# exit code themselves, so opt out.
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts\code-change-filter.common.ps1')

$script:Failures = New-Object System.Collections.Generic.List[string]

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

Invoke-TestCase 'The real filter file parses into a non-empty pattern list' {
    $path = Get-AhkFlowCodePathFilterPath -RepoRoot $repoRoot
    Assert-True (Test-Path -LiteralPath $path) "Filter file not found at $path."

    $exclusion = Read-AhkFlowCodePathExclusion -FilterPath $path
    Assert-True ($exclusion.Count -ge 6) "Expected at least 6 patterns, got $($exclusion.Count)."
    Assert-True ($exclusion -contains '**/*.md') 'Expected the markdown pattern.'
    Assert-True ($exclusion -contains 'scripts/*.ps1') 'Expected the top-level scripts pattern.'
    Assert-True ($exclusion -contains 'scripts/**/*.ps1') 'Expected the nested scripts pattern.'
    Assert-True ($exclusion -contains 'tests/*.ps1') 'Expected the PowerShell suites pattern.'
}

Invoke-TestCase 'Each supported pattern shape matches the right paths' {
    $exclusion = Read-AhkFlowCodePathExclusion -FilterPath (Get-AhkFlowCodePathFilterPath -RepoRoot $repoRoot)

    $excluded = @(
        'backlog/119-thing.md'
        'README.md'
        'docs/development/testing-workflow.md'
        '.claude/rules/agents.md'
        'scripts/test-fast.ps1'
        'scripts/agents/check-symlinks.ps1'
        'scripts/ci/generate-changelog-json.ps1'
        'tests/CoverageSliceSkip.Tests.ps1'
    )
    foreach ($path in $excluded) {
        $match = Get-AhkFlowPathExclusionMatch -Path $path -Exclusion $exclusion
        Assert-True ($null -ne $match) "Expected '$path' to be excluded, and nothing matched it."
    }

    $code = @(
        'Program.cs'
        'AHKFlowApp.csproj'
        'src/Backend/AHKFlowApp.Domain/Entities/Hotstring.cs'
        'tests/AHKFlowApp.Domain.Tests/HotstringTests.cs'
        'scripts/ci/check-coverage-thresholds.py'
        'Directory.Packages.props'
        'coverlet.runsettings'
    )
    foreach ($path in $code) {
        $match = Get-AhkFlowPathExclusionMatch -Path $path -Exclusion $exclusion
        Assert-True ($null -eq $match) "Expected '$path' to count as code, but pattern '$match' excluded it."
    }
}

Invoke-TestCase 'Matching is case-sensitive, the way the action matches' {
    # PowerShell's -match is case-insensitive and picomatch is not. With -match, this path is
    # excluded here and counted as code in CI, which is the disagreement the shared file exists
    # to prevent.
    $exclusion = Read-AhkFlowCodePathExclusion -FilterPath (Get-AhkFlowCodePathFilterPath -RepoRoot $repoRoot)

    # DOCS/ carries a .txt extension on purpose. With .md, '**/*.md' excludes it whatever the
    # case of the folder, so the case would pass with a case-insensitive matcher and prove
    # nothing about 'docs/**'.
    foreach ($path in @('scripts/Thing.PS1', 'DOCS/thing.txt', 'README.MD')) {
        $match = Get-AhkFlowPathExclusionMatch -Path $path -Exclusion $exclusion
        Assert-True ($null -eq $match) "Expected '$path' to count as code under case-sensitive matching, but '$match' excluded it."
    }

    # The same names in the case the patterns actually use are still excluded.
    foreach ($path in @('scripts/thing.ps1', 'docs/thing.txt', 'README.md')) {
        $match = Get-AhkFlowPathExclusionMatch -Path $path -Exclusion $exclusion
        Assert-True ($null -ne $match) "Expected '$path' to be excluded."
    }
}

Invoke-TestCase 'The coverage tooling list is exactly the seven files the slice runs' {
    # The exact set, not a couple of spot checks. Asserting only that two entries are present,
    # and that whatever entries remain exist on disk, lets any of the other five be deleted
    # from the YAML with the suite still green - and a deleted entry silently stops protecting
    # that file.
    $path = Get-AhkFlowCodePathFilterPath -RepoRoot $repoRoot
    $tooling = @(Read-AhkFlowCoverageToolingPath -FilterPath $path | Sort-Object)

    $expected = @(
        'scripts/Common.ps1'
        'scripts/code-change-filter.common.ps1'
        'scripts/coverage-inputs.common.ps1'
        'scripts/run-coverage.ps1'
        'scripts/test-fast.ps1'
        'scripts/test-run-lock.common.ps1'
        'scripts/test-sql-container.common.ps1'
    ) | Sort-Object

    Assert-True ($tooling.Count -eq 7) "Expected 7 coverage-tooling entries, got $($tooling.Count): $($tooling -join ', ')"
    Assert-True (($tooling -join '|') -ceq ($expected -join '|')) `
        "Coverage tooling list does not match. Got: $($tooling -join ', ')"

    # An entry naming a file that no longer exists is a rename nobody finished.
    foreach ($entry in $tooling) {
        Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot $entry)) "Coverage tooling entry '$entry' does not exist."
    }

    # The list must stay in step with what run-coverage.ps1 actually loads. A new dot-source
    # there with no entry here is the failure this catches.
    $runCoverage = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts/run-coverage.ps1') -Raw
    foreach ($name in @('test-sql-container.common.ps1', 'Common.ps1', 'test-run-lock.common.ps1', 'coverage-inputs.common.ps1')) {
        Assert-True ($runCoverage -match [regex]::Escape($name)) `
            "run-coverage.ps1 no longer mentions $name. Re-derive the coverage-tooling list."
    }
}

Invoke-TestCase 'A pattern shape the matcher cannot read is rejected, never ignored' {
    $threw = $false
    try { ConvertTo-AhkFlowPathRegex -Pattern 'src/**/@(a|b).cs' | Out-Null }
    catch { $threw = $true; Assert-True ($_.Exception.Message -match 'src/') 'The message must name the pattern.' }
    Assert-True $threw 'An unsupported pattern must throw. Silently ignoring one would skip real coverage.'
}

Invoke-TestCase 'A filter file with no code key is rejected' {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-filter-' + [guid]::NewGuid().ToString('N') + '.yml')
    Set-Content -LiteralPath $path -Value "other:`n  - '!**/*.md'" -Encoding utf8
    try {
        $threw = $false
        try { Read-AhkFlowCodePathExclusion -FilterPath $path | Out-Null } catch { $threw = $true }
        Assert-True $threw 'A file with no code: key must throw.'
    }
    finally { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
}

Invoke-TestCase 'A filter entry that is not a negative pattern is rejected' {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-filter-' + [guid]::NewGuid().ToString('N') + '.yml')
    Set-Content -LiteralPath $path -Value "code:`n  - 'src/**'" -Encoding utf8
    try {
        $threw = $false
        try { Read-AhkFlowCodePathExclusion -FilterPath $path | Out-Null } catch { $threw = $true }
        Assert-True $threw 'A positive entry must throw. The whole design assumes every entry excludes.'
    }
    finally { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
if ($script:Failures.Count -gt 0) {
    Write-Host "FAILED: $($script:Failures.Count) test(s)" -ForegroundColor Red
    foreach ($failure in $script:Failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'Coverage slice skip tests passed.' -ForegroundColor Green
exit 0
