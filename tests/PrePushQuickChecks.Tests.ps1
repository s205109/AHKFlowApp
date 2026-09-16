#Requires -Version 7.0
<#
.SYNOPSIS
Tests that the pre-push hook skips the .NET checks on a branch with no Code change.

.DESCRIPTION
The hook script runs in a throwaway repository under the temp folder. Two stubs stand in for the
expensive work: a fake dotnet on PATH, and a stub test-fast.ps1. Each writes a marker file, and the
markers are what a case asserts. No real build ever runs here.

The fixture has no docs/superpowers, so the record checks report themselves skipped and this suite
stays about one question: does the push run the .NET checks?
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$script:Failures = New-Object System.Collections.Generic.List[string]
$script:HostExe = [System.Diagnostics.Process]::GetCurrentProcess().Path

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

function New-HookFixture {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-prepush-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path (Join-Path $root 'scripts') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root '.github') -Force | Out-Null

    Copy-Item -LiteralPath (Join-Path $repoRoot '.github/code-paths-filter.yml') `
        -Destination (Join-Path $root '.github/code-paths-filter.yml')

    foreach ($name in @(
            'pre-push-quick-checks.ps1'
            'Common.ps1'
            'plans-citation-scan.common.ps1'
            'code-change-filter.common.ps1'
        )) {
        Copy-Item -LiteralPath (Join-Path $repoRoot "scripts/$name") -Destination (Join-Path $root "scripts/$name")
    }

    # The stub writes a marker instead of running a test slice.
    Set-Content -LiteralPath (Join-Path $root 'scripts/test-fast.ps1') -Encoding utf8 -Value @'
[CmdletBinding()]
param([string]$Mode, [string]$Configuration, [switch]$NoBuild)
Set-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'fast-ran.marker') -Value $Mode
exit 0
'@

    & git -C $root init --quiet --initial-branch=main *> $null
    & git -C $root config user.email 'test@example.com' *> $null
    & git -C $root config user.name 'Test' *> $null
    & git -C $root config commit.gpgsign false *> $null
    # fakebin/ arrives later, from Invoke-QuickChecks, after the case has committed. The decision
    # reads untracked files, so an untracked folder would count as a changed path, force the build,
    # and break the skip case. The fixture ignores it.
    Set-Content -LiteralPath (Join-Path $root '.gitignore') -Value 'fakebin/' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $root 'README.md') -Value 'base' -Encoding utf8
    & git -C $root add -A *> $null
    & git -C $root commit --quiet -m 'base' *> $null

    # The hook resolves the base against origin/main, so the fixture needs that ref to exist.
    & git -C $root update-ref refs/remotes/origin/main main *> $null
    & git -C $root checkout --quiet -b work *> $null

    return (Resolve-Path -LiteralPath $root).Path
}

function Add-FixtureFile {
    param([string] $Root, [string] $RelativePath, [string] $Content = 'x')
    $target = Join-Path $Root $RelativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Set-Content -LiteralPath $target -Value $Content -Encoding utf8
}

function Save-Fixture {
    param([string] $Root, [string] $Message)
    & git -C $Root add -A *> $null
    & git -C $Root commit --quiet -m $Message *> $null
}

# A fake dotnet, first on PATH, so 'dotnet build' writes a marker and returns 0.
function New-FakeDotnet {
    param([string] $Root)
    $bin = Join-Path $Root 'fakebin'
    New-Item -ItemType Directory -Path $bin -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $bin 'dotnet.cmd') -Encoding ascii -Value @"
@echo off
echo build > "$Root\build-ran.marker"
exit /b 0
"@
    return $bin
}

function Invoke-QuickChecks {
    param([string] $Root)

    $bin = New-FakeDotnet -Root $Root
    $previousPath = $env:PATH
    $env:PATH = "$bin;$previousPath"
    try {
        $output = & $script:HostExe -NoProfile -File (Join-Path $Root 'scripts/pre-push-quick-checks.ps1') 2>&1 | Out-String
        $code = $LASTEXITCODE
    }
    finally { $env:PATH = $previousPath }

    return [pscustomobject]@{
        ExitCode = $code
        Output   = $output
        BuildRan = (Test-Path -LiteralPath (Join-Path $Root 'build-ran.marker'))
        FastRan  = (Test-Path -LiteralPath (Join-Path $Root 'fast-ran.marker'))
    }
}

function Remove-Fixture {
    param([string] $Root)
    if (Test-Path -LiteralPath $Root) {
        Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-TestCase 'A branch with no Code change skips the build and the fast tests' {
    $root = New-HookFixture
    try {
        Add-FixtureFile -Root $root -RelativePath 'backlog/074-thing.md'
        Add-FixtureFile -Root $root -RelativePath 'tests/powershell-suites.json'
        Save-Fixture -Root $root -Message 'records only'

        $result = Invoke-QuickChecks -Root $root
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True (-not $result.BuildRan) "The build must not run. Output: $($result.Output)"
        Assert-True (-not $result.FastRan) "The fast slice must not run. Output: $($result.Output)"
        Assert-True ($result.Output -match 'Build and fast tests skipped') `
            "The skip must be reported. Output: $($result.Output)"
        Assert-True ($result.Output -match 'tests/powershell-suites\.json\s+excluded by tests/\*\.json') `
            "The report must name each file and the pattern that excluded it. Output: $($result.Output)"
        # CI skips its .NET steps on this branch too, so a hint that points at the Gate would send
        # the reader to a check that also skips. The hint must say what makes the checks run again.
        Assert-True ($result.Output -match 'run again as soon as this branch changes a path the filter does not exclude') `
            "The hint must say what makes the checks run again, not point at a gate that also skips. Output: $($result.Output)"
        Assert-True ($result.Output -notmatch 'before a pull request goes ready') `
            "The hint must not promise the Gate runs the build on this branch. Output: $($result.Output)"
    }
    finally { Remove-Fixture -Root $root }
}

Invoke-TestCase 'One .cs file still builds and runs the fast tests' {
    $root = New-HookFixture
    try {
        Add-FixtureFile -Root $root -RelativePath 'src/Backend/AHKFlowApp.Domain/Hotstring.cs'
        Save-Fixture -Root $root -Message 'one cs file'

        $result = Invoke-QuickChecks -Root $root
        Assert-True $result.BuildRan "The build must run for a .cs change. Output: $($result.Output)"
        Assert-True $result.FastRan "The fast slice must run for a .cs change. Output: $($result.Output)"
        Assert-True ($result.Output -notmatch 'Build and fast tests skipped') `
            "It must not report a skip. Output: $($result.Output)"
    }
    finally { Remove-Fixture -Root $root }
}

Invoke-TestCase 'A decision that cannot be made builds and runs the fast tests' {
    $root = New-HookFixture
    try {
        Add-FixtureFile -Root $root -RelativePath 'docs/thing.md'
        Save-Fixture -Root $root -Message 'docs only'
        Remove-Item -LiteralPath (Join-Path $root '.github/code-paths-filter.yml') -Force

        $result = Invoke-QuickChecks -Root $root
        Assert-True $result.BuildRan "A broken decision must fall back to building. Output: $($result.Output)"
        Assert-True $result.FastRan "A broken decision must fall back to the fast slice too. Output: $($result.Output)"
        Assert-True ($result.Output -match 'code-paths-filter') `
            "It must name what it could not read. Output: $($result.Output)"
    }
    finally { Remove-Fixture -Root $root }
}

Invoke-TestCase 'A coverage-tooling change still builds and runs the fast tests' {
    # scripts/run-coverage.ps1 is a .ps1 under scripts/, so the 'code' patterns exclude it, and
    # CI skips its .NET steps for such a branch. The shared decision still sets CoverageRequired,
    # because the coverage slice is the only local check that runs that script. The hook reads
    # that one decision, so it is stricter than CI on these eleven paths, and never looser. This
    # case pins that exception, which a check against the raw 'code' exclusions would break.
    $root = New-HookFixture
    try {
        Add-FixtureFile -Root $root -RelativePath 'scripts/run-coverage.ps1' -Content '# changed'
        Save-Fixture -Root $root -Message 'coverage tooling only'

        $result = Invoke-QuickChecks -Root $root
        Assert-True $result.BuildRan "The build must run for a coverage-tooling change. Output: $($result.Output)"
        Assert-True $result.FastRan "The fast slice must run for a coverage-tooling change. Output: $($result.Output)"
        Assert-True ($result.Output -notmatch 'Build and fast tests skipped') `
            "It must not report a skip. Output: $($result.Output)"
    }
    finally { Remove-Fixture -Root $root }
}

Invoke-TestCase 'The hook script reads the shared filter module and holds no second list' {
    $text = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts/pre-push-quick-checks.ps1') -Raw

    Assert-True ($text -match 'code-change-filter\.common\.ps1') `
        'pre-push-quick-checks.ps1 must dot-source the shared filter module.'
    Assert-True ($text -match 'Get-AhkFlowCoverageDecision') `
        'It must ask the shared decision, not judge the diff itself.'

    # The whole pattern set, read from the filter file itself, not one hand-written spelling. A
    # second list written with double quotes, or holding only the newly added patterns, would pass
    # a single literal check and still let the push and CI disagree.
    . (Join-Path $repoRoot 'scripts/code-change-filter.common.ps1')
    $filterPath = Get-AhkFlowCodePathFilterPath -RepoRoot $repoRoot
    $patterns = Read-AhkFlowCodePathExclusion -FilterPath $filterPath
    Assert-True ($patterns.Count -gt 0) 'The filter file must list at least one code exclusion.'

    foreach ($pattern in $patterns) {
        Assert-True (-not $text.Contains($pattern)) `
            "It must not keep a second copy of the patterns. One source of truth, or the push and CI can disagree. Found '$pattern' in pre-push-quick-checks.ps1."
    }
}

Invoke-TestCase 'The push reuses the merge base it already computed and never calls gh for a base ref' {
    $root = New-HookFixture
    try {
        & git -C $root remote add origin 'https://example.invalid/fake.git' *> $null

        Add-FixtureFile -Root $root -RelativePath 'src/Backend/AHKFlowApp.Domain/Hotstring.cs'
        Save-Fixture -Root $root -Message 'one cs file'

        $bin = New-FakeDotnet -Root $root
        $ghMarker = Join-Path $root 'gh-called.marker'
        Set-Content -LiteralPath (Join-Path $bin 'gh.cmd') -Encoding ascii -Value @"
@echo off
echo called > "$ghMarker"
exit /b 1
"@

        $previousPath = $env:PATH
        $env:PATH = "$bin;$previousPath"
        try {
            $output = & $script:HostExe -NoProfile -File (Join-Path $root 'scripts/pre-push-quick-checks.ps1') 2>&1 | Out-String
            $code = $LASTEXITCODE
        }
        finally { $env:PATH = $previousPath }

        Assert-True ($code -eq 0) "Expected exit code 0, got $code. Output: $output"
        Assert-True (-not (Test-Path -LiteralPath $ghMarker)) `
            "The push must not call gh when it already knows the merge base. Output: $output"
    }
    finally { Remove-Fixture -Root $root }
}

Write-Host ''
if ($script:Failures.Count -gt 0) {
    Write-Host "FAILED: $($script:Failures.Count) test(s)" -ForegroundColor Red
    foreach ($failure in $script:Failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'All pre-push quick-check cases passed.' -ForegroundColor Green
exit 0
