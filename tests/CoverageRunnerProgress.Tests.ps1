#Requires -Version 7.0

# Backlog 124. scripts/run-coverage.ps1 wraps its work in the progress module: it reads the
# coverage projects first, builds a tracker over a mixed unit list, starts and stops a unit around
# each step, and saves the timings after the report step.
#
# The unit list is the point. It is not one kind of thing, the way the other two runners' lists
# are. Three fixed phases, then one unit per coverage project read at run time, then one more
# fixed phase. tests/Progress.Tests.ps1 builds trackers by hand, which proves the module and says
# nothing about this wiring. Backlog 123 measured that gap: removing every progress call from
# test-fast.ps1 left the module suite green.
#
# So this suite drives scripts/run-coverage.ps1 itself. The runner resolves its repository root
# from $PSScriptRoot, so it gets a repository of its own under the temp folder. Everything it
# dot-sources is copied in, and four stub commands go earlier on PATH: dotnet, docker,
# reportgenerator and python. Nothing real is built, started, or measured.
#
# Run it by hand with:  pwsh ./tests/CoverageRunnerProgress.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# A non-zero exit code from the child runner is data here, not a terminating error.
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$hostExe = [System.Diagnostics.Process]::GetCurrentProcess().Path

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

# The three fixed phases that come before the projects, and the one that comes after. Written out
# here rather than derived, so a change to the runner's list fails this suite instead of quietly
# agreeing with itself.
$script:LeadingUnit = @('restore', 'build', 'sql container')
$script:TrailingUnit = @('report')

function Get-ExpectedUnit {
    param([string[]] $ProjectName)
    return @($script:LeadingUnit + $ProjectName + $script:TrailingUnit)
}

# --- The fixture ---

function New-CoverageFixture {
    param([string[]] $ProjectName = @('Alpha.Tests', 'Beta.Tests'))

    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('coverage-progress-' + [guid]::NewGuid().ToString('N'))
    $scriptFolder = Join-Path $root 'scripts'
    $stubFolder = Join-Path $root 'stub'
    New-Item -ItemType Directory -Path $scriptFolder -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $scriptFolder 'ci') -Force | Out-Null
    New-Item -ItemType Directory -Path $stubFolder -Force | Out-Null

    # The container script asks git whether this is a linked worktree or a main checkout, and stops
    # when git cannot answer. A bare 'git init' answers: no linked worktree, so this is a main
    # checkout. Its Compose project is the base name followed by a token standing for this clone,
    # and its repository label is this fixture's own path, so neither can be written out here. The
    # fixture asks the real helpers for both once the scripts are copied, below.
    & git -C $root init --quiet 2>&1 | Out-Null

    foreach ($name in @(
            'run-coverage.ps1'
            'test-fast.ps1'
            'Common.ps1'
            'test-sql-container.common.ps1'
            'worktree-docker.common.ps1'
            'worktree-git.common.ps1'
            'test-run-lock.common.ps1'
            'test-lanes.common.ps1'
            'suite-worker-count.common.ps1'
            'coverage-inputs.common.ps1'
            'code-change-filter.common.ps1'
            'progress.common.ps1'
            'progress.parallel.ps1'
            'slice-runner.common.ps1'
            'test-results.common.ps1'
        )) {
        Copy-Item -LiteralPath (Join-Path (Join-Path $repoRoot 'scripts') $name) `
            -Destination (Join-Path $scriptFolder $name)
    }

    # The runner builds this path and hands it to python. The python stub ignores its arguments,
    # so the content never matters, but a path that names nothing would be a lie in the fixture.
    Set-Content -LiteralPath (Join-Path (Join-Path $scriptFolder 'ci') 'check-coverage-thresholds.py') `
        -Value '# stub threshold gate' -Encoding utf8

    Set-CoverageFixtureProject -Root $root -ProjectName $ProjectName

    Set-Content -LiteralPath (Join-Path $stubFolder 'dotnet.ps1') -Encoding utf8 -Value @'
$stubFolder = Split-Path -Parent $PSCommandPath
# Side-by-side Slices append to the same call log at the same moment, and an append can meet a
# file another stub holds open. So every stub appends through this retry loop.
function Add-CallLine([string] $Path, [string] $Line) {
    for ($try = 1; $try -le 50; $try++) {
        try { [System.IO.File]::AppendAllText($Path, $Line + [Environment]::NewLine); return }
        catch { if ($try -eq 50) { throw }; Start-Sleep -Milliseconds 20 }
    }
}
Add-CallLine (Join-Path $stubFolder 'calls.txt') ($args -join ' ')

# The project list is a file, not a literal, so a test case can make the solution drop a project
# between two runs in the same fixture.
if ($args[0] -eq 'sln') {
    Write-Output 'Project(s)'
    Write-Output '----------'
    foreach ($line in (Get-Content -LiteralPath (Join-Path $stubFolder 'projects.txt'))) {
        Write-Output $line
    }
    exit 0
}

if ($args[0] -eq 'restore' -or $args[0] -eq 'build') {
    Write-Output "stub dotnet $($args[0])"
    exit 0
}

if ($args[0] -eq 'test') {
    # The project name, and two tick markers, so a case can tell which Slices ran at the same time.
    $project = [System.IO.Path]::GetFileNameWithoutExtension([string]$args[1])
    Set-Content -LiteralPath (Join-Path $stubFolder "start-$project.txt") -Value ([DateTime]::UtcNow.Ticks)

    # A test case drops this marker to make one project fail. Nothing else creates it.
    if (Test-Path -LiteralPath (Join-Path $stubFolder 'test-fail.txt')) {
        Write-Output 'stub dotnet test: forced failure'
        exit 1
    }

    # Each marker names one project. zero-tests.txt makes its TRX file count no test.
    # fail-after-coverage.txt makes it write its coverage file and its TRX file, then exit 1.
    function Test-NamedBy([string] $Marker) {
        $path = Join-Path $stubFolder $Marker
        if (-not (Test-Path -LiteralPath $path)) { return $false }
        return ((Get-Content -LiteralPath $path -Raw).Trim() -eq $project)
    }

    $resultsDirectory = $null
    $logFileName = $null
    for ($i = 0; $i -lt $args.Count; $i++) {
        if ($args[$i] -eq '--results-directory' -and $i + 1 -lt $args.Count) {
            $resultsDirectory = $args[$i + 1]
        }
        if ($args[$i] -eq '--logger' -and $i + 1 -lt $args.Count -and $args[$i + 1] -match 'LogFileName=(.+)$') {
            $logFileName = $Matches[1]
        }
    }

    # coverlet writes the file under a run-specific folder, and the completeness check searches
    # recursively, so the stub writes it the same way.
    if ($resultsDirectory) {
        $runFolder = Join-Path $resultsDirectory ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $runFolder -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $runFolder 'coverage.cobertura.xml') `
            -Value '<coverage />' -Encoding utf8
        if ($logFileName) {
            $total = 1
            if (Test-NamedBy 'zero-tests.txt') { $total = 0 }
            Set-Content -LiteralPath (Join-Path $resultsDirectory $logFileName) -Encoding utf8 `
                -Value "<TestRun><ResultSummary outcome=`"Completed`"><Counters total=`"$total`" executed=`"$total`" passed=`"$total`" failed=`"0`" /></ResultSummary></TestRun>"
        }
    }

    Write-Output 'stub dotnet test'
    Set-Content -LiteralPath (Join-Path $stubFolder "end-$project.txt") -Value ([DateTime]::UtcNow.Ticks)
    if (Test-NamedBy 'fail-after-coverage.txt') { exit 1 }

    # fail-projects.txt lists, one per line, the projects whose test call exits 1.
    $failList = Join-Path $stubFolder 'fail-projects.txt'
    if ((Test-Path -LiteralPath $failList) -and @(Get-Content -LiteralPath $failList | ForEach-Object { $_.Trim() }) -contains $project) { exit 1 }
    exit 0
}

Write-Output "stub dotnet: $($args -join ' ')"
exit 0
'@

    Set-Content -LiteralPath (Join-Path $stubFolder 'docker.ps1') -Encoding utf8 -Value @'
$stubFolder = Split-Path -Parent $PSCommandPath
# Side-by-side Slices append to the same call log at the same moment, and an append can meet a
# file another stub holds open. So every stub appends through this retry loop.
function Add-CallLine([string] $Path, [string] $Line) {
    for ($try = 1; $try -le 50; $try++) {
        try { [System.IO.File]::AppendAllText($Path, $Line + [Environment]::NewLine); return }
        catch { if ($try -eq 50) { throw }; Start-Sleep -Milliseconds 20 }
    }
}
Add-CallLine (Join-Path $stubFolder 'docker-calls.txt') ($args -join ' ')

# The shapes Start-AhkFlowTestSqlContainer needs. 'inspect' answers one blob carrying every field
# the verification reads: the id, the running state, the image, the three ownership labels, and the
# published port. A non-zero exit from 'inspect' means the container does not exist, which is how
# the script decides to build one.
#
# Both ownership labels are read from files the fixture writes, and the fixture asks the real
# helpers for them rather than spelling them out. They have to match what the script derives from
# this fixture's own git repository, or the ownership check refuses the container, and the
# repository one is a path that is different every run.
$project = (Get-Content -LiteralPath (Join-Path $stubFolder 'compose-project.txt') -Raw).Trim()
$repository = (Get-Content -LiteralPath (Join-Path $stubFolder 'repository-id.txt') -Raw).Trim()

switch ($args[0]) {
    'run' { Write-Output 'stubcontainerid'; exit 0 }
    'inspect' {
        # The repository label is a Windows path, so every separator in it has to be escaped before
        # it goes into JSON.
        $repositoryJson = $repository.Replace('\', '\\').Replace('"', '\"')
        Write-Output ('[{"Id":"stubcontainerid0000000000000000000000000000000000000000000000000000",' +
            '"State":{"Running":true},' +
            '"Config":{"Image":"mcr.microsoft.com/mssql/server:2022-CU14-ubuntu-22.04",' +
            '"Labels":{"com.ahkflowapp.role":"test-sql","com.ahkflowapp.compose-project":"' + $project + '"' +
            ',"com.ahkflowapp.repository":"' + $repositoryJson + '"}},' +
            '"NetworkSettings":{"Ports":{"1433/tcp":[{"HostIp":"127.0.0.1","HostPort":"14399"}]}}}]')
        exit 0
    }
    'ps' { exit 0 }
    'start' { exit 0 }
    'exec' { exit 0 }
    'logs' { Write-Output 'stub docker logs'; exit 0 }
    'rm' { exit 0 }
    default { exit 0 }
}
'@

    # Asked of the real helpers, against this fixture's own git repository, rather than written out
    # here. The Compose project carries a hash of the fixture's path and the repository label is
    # that path, so both are different on every run and neither can be a literal. Asking also keeps
    # the stub honest: if the naming rule changes, the stub follows it instead of disagreeing.
    $ownership = & pwsh -NoProfile -Command (
        ". '$(Join-Path $scriptFolder 'worktree-docker.common.ps1')'; " +
        ". '$(Join-Path $scriptFolder 'worktree-git.common.ps1')'; " +
        ". '$(Join-Path $scriptFolder 'test-sql-container.common.ps1')'; " +
        "Write-Output (Get-AhkFlowTestSqlComposeProject -RepoRoot '$root'); " +
        "Write-Output (Get-WorktreeRepositoryId -RepoRoot '$root')")

    if (@($ownership).Count -lt 2) {
        throw "Could not resolve the fixture's container ownership from the real helpers. Got: $($ownership -join '; ')"
    }

    Set-Content -LiteralPath (Join-Path $stubFolder 'compose-project.txt') -Encoding utf8 -Value ([string] $ownership[0]).Trim()
    Set-Content -LiteralPath (Join-Path $stubFolder 'repository-id.txt') -Encoding utf8 -Value ([string] $ownership[1]).Trim()

    Set-Content -LiteralPath (Join-Path $stubFolder 'reportgenerator.ps1') -Encoding utf8 -Value @'
$stubFolder = Split-Path -Parent $PSCommandPath
# Side-by-side Slices append to the same call log at the same moment, and an append can meet a
# file another stub holds open. So every stub appends through this retry loop.
function Add-CallLine([string] $Path, [string] $Line) {
    for ($try = 1; $try -le 50; $try++) {
        try { [System.IO.File]::AppendAllText($Path, $Line + [Environment]::NewLine); return }
        catch { if ($try -eq 50) { throw }; Start-Sleep -Milliseconds 20 }
    }
}
Add-CallLine (Join-Path $stubFolder 'reportgenerator-calls.txt') ($args -join ' ')

# A test case drops this marker to fail the report step. Nothing else creates it.
if (Test-Path -LiteralPath (Join-Path $stubFolder 'report-fail.txt')) {
    Write-Output 'stub reportgenerator: forced failure'
    exit 1
}

# -targetdir is relative, and the runner pushes its repository root, so this is the same folder
# the runner reads back afterwards.
$reportFolder = Join-Path (Get-Location).Path 'CoverageReport'
New-Item -ItemType Directory -Path $reportFolder -Force | Out-Null
Set-Content -LiteralPath (Join-Path $reportFolder 'index.html') -Value '<html></html>' -Encoding utf8
Set-Content -LiteralPath (Join-Path $reportFolder 'Cobertura.xml') -Value '<coverage />' -Encoding utf8
Set-Content -LiteralPath (Join-Path $reportFolder 'SummaryGithub.md') -Value '# stub summary' -Encoding utf8
Set-Content -LiteralPath (Join-Path $reportFolder 'Summary.json') -Encoding utf8 `
    -Value '{ "summary": { "linecoverage": 90.1, "branchcoverage": 80.2 } }'

Write-Output 'stub reportgenerator'
exit 0
'@

    Set-Content -LiteralPath (Join-Path $stubFolder 'python.ps1') -Encoding utf8 -Value @'
$stubFolder = Split-Path -Parent $PSCommandPath
# Side-by-side Slices append to the same call log at the same moment, and an append can meet a
# file another stub holds open. So every stub appends through this retry loop.
function Add-CallLine([string] $Path, [string] $Line) {
    for ($try = 1; $try -le 50; $try++) {
        try { [System.IO.File]::AppendAllText($Path, $Line + [Environment]::NewLine); return }
        catch { if ($try -eq 50) { throw }; Start-Sleep -Milliseconds 20 }
    }
}
Add-CallLine (Join-Path $stubFolder 'python-calls.txt') ($args -join ' ')
Write-Output 'stub coverage footer'
exit 0
'@

    return $root
}

function Set-CoverageFixtureProject {
    <#
      Write the fixture's project set: one .csproj per name, and the projects.txt the dotnet stub
      answers 'sln list' from. Called again on an existing fixture to change the set between runs.

      Forward slashes on purpose. Join-Path in Get-AhkFlowCoverageProject resolves them on Windows
      and on Linux; backslashes would only work on Windows.
    #>
    param(
        [Parameter(Mandatory)][string] $Root,
        [Parameter(Mandatory)][string[]] $ProjectName
    )

    $relative = @()
    foreach ($name in $ProjectName) {
        $folder = Join-Path (Join-Path $Root 'tests') $name
        New-Item -ItemType Directory -Path $folder -Force | Out-Null

        # The coverlet.collector reference is what makes Get-AhkFlowCoverageProject keep a project.
        Set-Content -LiteralPath (Join-Path $folder "$name.csproj") -Encoding utf8 -Value @"
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <PackageReference Include="coverlet.collector" />
  </ItemGroup>
</Project>
"@

        $relative += "tests/$name/$name.csproj"
    }

    Set-Content -LiteralPath (Join-Path (Join-Path $Root 'stub') 'projects.txt') `
        -Value $relative -Encoding utf8
}

function Remove-CoverageFixture {
    param([string] $Root)
    if ($Root -and (Test-Path -LiteralPath $Root)) {
        Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-InFixture {
    param(
        [Parameter(Mandatory)][string] $Root,
        [Parameter(Mandatory)][string] $ScriptName,
        [string[]] $Argument = @()
    )

    $previousHolder = $env:AHKFLOW_TEST_LANES_HOLDER
    if ([string]::IsNullOrWhiteSpace($env:AHKFLOW_TEST_LANES_ROOT) -and [string]::IsNullOrWhiteSpace($env:AHKFLOW_TEST_LANES_HOLDER)) {
        $env:AHKFLOW_TEST_LANES_HOLDER = [string]$PID
    }
    $previousPath = $env:PATH
    $env:PATH = (Join-Path $Root 'stub') + [System.IO.Path]::PathSeparator + $previousPath
    try {
        $scriptPath = Join-Path (Join-Path $Root 'scripts') $ScriptName
        $output = & $hostExe -NoProfile -File $scriptPath @Argument 2>&1 | Out-String
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }
    finally {
        $env:PATH = $previousPath
        $env:AHKFLOW_TEST_LANES_HOLDER = $previousHolder
    }
}

function Invoke-CoverageRun {
    param([Parameter(Mandatory)][string] $Root)
    # The cases that use this helper check the progress lines of a run in sequence. Since
    # backlog 204 the default is Budget, and side by side the Slices end in any order, so the
    # helper asks for 1. The side-by-side cases pass their own -SlicesAtOnce.
    return Invoke-InFixture -Root $Root -ScriptName 'run-coverage.ps1' -Argument @('-SlicesAtOnce', '1')
}

function Get-ProgressHistoryFolder {
    param([Parameter(Mandatory)][string] $Root)
    # The same expression the module uses, so the folder matches on Windows and on Linux.
    return (Join-Path $Root 'TestResults\progress')
}

function Get-SavedTiming {
    param([Parameter(Mandatory)][string] $Root, [string] $RunnerKey = 'run-coverage')

    $path = Join-Path (Get-ProgressHistoryFolder -Root $Root) "$RunnerKey.json"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
}

function Get-ProgressLine {
    <# Every progress line in a run's output, in the order it printed them. #>
    param([Parameter(Mandatory)][string] $Output)
    return @(($Output -split "`r?`n") | Where-Object { $_ -match '^\[\s*\d+/\d+(?: done)?\]\s' })
}

Write-Host "Testing $(Join-Path $repoRoot 'scripts/run-coverage.ps1')"

# --- The cases ---

Invoke-TestCase 'A coverage run prints one progress line per unit, in order' {
    $root = New-CoverageFixture
    try {
        $result = Invoke-CoverageRun -Root $root
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        $expected = Get-ExpectedUnit -ProjectName @('Alpha.Tests', 'Beta.Tests')
        $lines = @(Get-ProgressLine -Output $result.Output)

        Assert-True ($lines.Count -eq $expected.Count) `
            "Expected $($expected.Count) progress lines, got $($lines.Count): $($lines -join ' | ')"

        for ($i = 0; $i -lt $expected.Count; $i++) {
            $position = $i + 1
            $pattern = '^\[' + $position + '/' + $expected.Count + '(?: done)?\] ' + [regex]::Escape($expected[$i])
            Assert-True ($lines[$i] -match $pattern) `
                "Line $position must read '[$position/$($expected.Count)] $($expected[$i])', got: $($lines[$i])"
        }
    }
    finally { Remove-CoverageFixture -Root $root }
}

Invoke-TestCase 'The project part of the unit list is read at run time' {
    # The mixed list is what backlog 123 kept out of scope, so this is the case that covers it.
    # Three projects instead of two must make the list one longer, with no change to the runner.
    $root = New-CoverageFixture -ProjectName @('Alpha.Tests', 'Beta.Tests', 'Gamma.Tests')
    try {
        $result = Invoke-CoverageRun -Root $root
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        $expected = Get-ExpectedUnit -ProjectName @('Alpha.Tests', 'Beta.Tests', 'Gamma.Tests')
        Assert-True ($expected.Count -eq 7) "The fixture must produce 7 units, got $($expected.Count)."

        $lines = @(Get-ProgressLine -Output $result.Output)
        Assert-True ($lines.Count -eq 7) `
            "Expected 7 progress lines, got $($lines.Count): $($lines -join ' | ')"

        foreach ($line in $lines) {
            Assert-True ($line -match '^\[\d/7(?: done)?\]') "Every line must count out of 7, got: $line"
        }

        Assert-True ($result.Output -match '\[6/7(?: done)?\] Gamma\.Tests') `
            "The third project must have its own unit. Output: $($result.Output)"
    }
    finally { Remove-CoverageFixture -Root $root }
}

Invoke-TestCase 'The run saves a timing for every unit under its own key' {
    $root = New-CoverageFixture
    try {
        $result = Invoke-CoverageRun -Root $root
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        $saved = Get-SavedTiming -Root $root
        Assert-True ($null -ne $saved) `
            "Expected saved timings at run-coverage.json. Output: $($result.Output)"

        foreach ($unit in (Get-ExpectedUnit -ProjectName @('Alpha.Tests', 'Beta.Tests'))) {
            Assert-True ($null -ne $saved.PSObject.Properties[$unit]) `
                "Expected a saved timing for '$unit', got: $(($saved.PSObject.Properties.Name) -join ', ')"
        }
    }
    finally { Remove-CoverageFixture -Root $root }
}

Invoke-TestCase 'The coverage store never mixes with a test-fast store' {
    $root = New-CoverageFixture
    try {
        # A real test-fast store, seeded before the run. The coverage run must not read it, write
        # it, or add a key of its own beside it.
        $folder = Get-ProgressHistoryFolder -Root $root
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        $fastPath = Join-Path $folder 'test-fast.Fast.json'
        Set-Content -LiteralPath $fastPath -Value '{ "Fast[Category!=Integration]": 42.5 }' -Encoding utf8

        # The file's bytes, not the text a reader would compare. Set-Content appends a line ending
        # that Get-Content -Raw then reads back, so a text comparison against the value written
        # fails on a file nothing touched.
        $fastBefore = (Get-FileHash -LiteralPath $fastPath -Algorithm SHA256).Hash

        $result = Invoke-CoverageRun -Root $root
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        $fastAfter = (Get-FileHash -LiteralPath $fastPath -Algorithm SHA256).Hash
        Assert-True ($fastAfter -ceq $fastBefore) `
            "The test-fast store must be untouched. Before: $fastBefore After: $fastAfter"

        $written = @(Get-ChildItem -LiteralPath $folder -Filter '*.json' -File | ForEach-Object { $_.Name } | Sort-Object)
        Assert-True (($written -join ', ') -ceq 'run-coverage.json, test-fast.Fast.json') `
            "Only run-coverage.json may be added, got: $($written -join ', ')"
    }
    finally { Remove-CoverageFixture -Root $root }
}

Invoke-TestCase 'A second run reads the first run timings back as an estimate' {
    $root = New-CoverageFixture
    try {
        $first = Invoke-CoverageRun -Root $root
        Assert-True ($first.ExitCode -eq 0) "First run: expected exit code 0, got $($first.ExitCode). Output: $($first.Output)"

        $second = Invoke-CoverageRun -Root $root
        Assert-True ($second.ExitCode -eq 0) "Second run: expected exit code 0, got $($second.ExitCode). Output: $($second.Output)"

        Assert-True ($second.Output -match 'remaining ~') `
            "The second run must estimate the time left. Output: $($second.Output)"
        Assert-True (-not ($second.Output -match 'no history')) `
            "The second run must not report missing history. Output: $($second.Output)"
    }
    finally { Remove-CoverageFixture -Root $root }
}

Invoke-TestCase 'A project the solution dropped leaves the store' {
    # This is what -KnownUnit buys. Without it a renamed or deleted test project keeps a place in
    # the store forever, and its seconds keep inflating every later estimate.
    $root = New-CoverageFixture -ProjectName @('Alpha.Tests', 'Beta.Tests', 'Gamma.Tests')
    try {
        $first = Invoke-CoverageRun -Root $root
        Assert-True ($first.ExitCode -eq 0) "First run: expected exit code 0, got $($first.ExitCode). Output: $($first.Output)"

        $afterFirst = Get-SavedTiming -Root $root
        Assert-True ($null -ne $afterFirst.PSObject.Properties['Gamma.Tests']) `
            'The first run must save the third project.'

        Set-CoverageFixtureProject -Root $root -ProjectName @('Alpha.Tests', 'Beta.Tests')

        $second = Invoke-CoverageRun -Root $root
        Assert-True ($second.ExitCode -eq 0) "Second run: expected exit code 0, got $($second.ExitCode). Output: $($second.Output)"

        $afterSecond = Get-SavedTiming -Root $root
        Assert-True ($null -eq $afterSecond.PSObject.Properties['Gamma.Tests']) `
            "A project the solution no longer has must be dropped, got: $(($afterSecond.PSObject.Properties.Name) -join ', ')"
        foreach ($unit in (Get-ExpectedUnit -ProjectName @('Alpha.Tests', 'Beta.Tests'))) {
            Assert-True ($null -ne $afterSecond.PSObject.Properties[$unit]) `
                "'$unit' still exists and must survive, got: $(($afterSecond.PSObject.Properties.Name) -join ', ')"
        }
    }
    finally { Remove-CoverageFixture -Root $root }
}

Invoke-TestCase 'Coverage through test-fast prints one sequence, not two' {
    # Acceptance criterion 4. test-fast.ps1 delegates Coverage mode to run-coverage.ps1 and must
    # add no tracker of its own. A nested one would show up twice: extra lines, and a second file.
    #
    # -Force skips the changed-file question, which the fixture cannot answer because it is not a
    # git repository. Without it the run would still go ahead, but it would print warnings that
    # say nothing about this item.
    $root = New-CoverageFixture
    try {
        $result = Invoke-InFixture -Root $root -ScriptName 'test-fast.ps1' -Argument @('-Mode', 'Coverage', '-Force')
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        $expected = Get-ExpectedUnit -ProjectName @('Alpha.Tests', 'Beta.Tests')
        $lines = @(Get-ProgressLine -Output $result.Output)
        Assert-True ($lines.Count -eq $expected.Count) `
            "Expected exactly $($expected.Count) progress lines, got $($lines.Count): $($lines -join ' | ')"

        foreach ($line in $lines) {
            Assert-True ($line -match ('^\[\d/' + $expected.Count + '(?: done)?\]')) `
                "Every line must belong to the one sequence, got: $line"
        }

        $written = @(Get-ChildItem -LiteralPath (Get-ProgressHistoryFolder -Root $root) -Filter '*.json' -File |
            ForEach-Object { $_.Name })
        Assert-True (($written -join ', ') -ceq 'run-coverage.json') `
            "Coverage through test-fast must write only run-coverage.json, got: $($written -join ', ')"
    }
    finally { Remove-CoverageFixture -Root $root }
}

Invoke-TestCase 'A failing report step saves no timings' {
    # The save sits behind the report step, not in a finally. An interrupted run must teach the
    # store nothing, which is the rule the module already keeps for a single unit.
    $root = New-CoverageFixture
    try {
        Set-Content -LiteralPath (Join-Path (Join-Path $root 'stub') 'report-fail.txt') `
            -Value 'fail' -Encoding utf8

        $result = Invoke-CoverageRun -Root $root
        Assert-True ($result.ExitCode -ne 0) `
            "A failing report step must fail the run. Output: $($result.Output)"
        Assert-True ($result.Output -match 'reportgenerator failed') `
            "The failure must name the step. Output: $($result.Output)"

        Assert-True ($null -eq (Get-SavedTiming -Root $root)) `
            'A run that never reached the save must write no timings file.'
    }
    finally { Remove-CoverageFixture -Root $root }
}

Invoke-TestCase 'A failing project still records its own seconds' {
    # The loop keeps going after a failing project, and the time that project took is real. The
    # run fails afterwards, so the only thing this proves is that the unit was stopped, not
    # abandoned. The store stays empty because the run never reaches the save.
    $root = New-CoverageFixture
    try {
        Set-Content -LiteralPath (Join-Path (Join-Path $root 'stub') 'test-fail.txt') `
            -Value 'fail' -Encoding utf8

        $result = Invoke-CoverageRun -Root $root
        Assert-True ($result.ExitCode -ne 0) `
            "A failing project must fail the run. Output: $($result.Output)"
        Assert-True ($result.Output -match 'dotnet test failed') `
            "The failure must name the step. Output: $($result.Output)"

        # Both projects still got a line. A run that stopped at the first failure would print one.
        $lines = @(Get-ProgressLine -Output $result.Output)
        Assert-True ($lines.Count -eq 5) `
            "Expected 5 progress lines before the failure, got $($lines.Count): $($lines -join ' | ')"
    }
    finally { Remove-CoverageFixture -Root $root }
}

Invoke-TestCase 'A solution with no coverage project fails before it restores' {
    # Reading the project list first is what makes the mixed unit list possible. It also moves
    # this check ahead of the restore, the build, and the container, so the run fails in seconds
    # rather than minutes.
    $root = New-CoverageFixture
    try {
        Set-Content -LiteralPath (Join-Path (Join-Path $root 'stub') 'projects.txt') `
            -Value '' -Encoding utf8

        $result = Invoke-CoverageRun -Root $root
        Assert-True ($result.ExitCode -ne 0) `
            "A solution with nothing to measure must fail. Output: $($result.Output)"
        Assert-True ($result.Output -match 'references coverlet\.collector') `
            "The failure must say what is missing. Output: $($result.Output)"

        $calls = @()
        $callsPath = Join-Path (Join-Path $root 'stub') 'calls.txt'
        if (Test-Path -LiteralPath $callsPath) { $calls = @(Get-Content -LiteralPath $callsPath) }

        Assert-True (@($calls | Where-Object { $_ -match '^restore' }).Count -eq 0) `
            "The run must fail before it restores. Calls: $($calls -join ' | ')"
        Assert-True (@($calls | Where-Object { $_ -match '^build ' }).Count -eq 0) `
            "The run must fail before it builds. Calls: $($calls -join ' | ')"
    }
    finally { Remove-CoverageFixture -Root $root }
}


# --- Backlog 204: the coverage Slices run through the Slice runner ---

function Get-StubCall {
    param([string] $Root, [string] $Name = 'calls.txt')
    $path = Join-Path (Join-Path $Root 'stub') $Name
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    return @(Get-Content -LiteralPath $path)
}

function Get-StubTick {
    param([string] $Root, [string] $File)
    return [long](Get-Content -LiteralPath (Join-Path (Join-Path $Root 'stub') $File) -Raw).Trim()
}

function Set-StubMarker {
    param([string] $Root, [string] $Name, [string] $Value)
    Set-Content -LiteralPath (Join-Path (Join-Path $Root 'stub') $Name) -Value $Value -Encoding utf8
}

function Get-StartOrder {
    param([string] $Output)
    return @(($Output -split "`r?`n") | Where-Object { $_ -match '^start (\S+)  log ' } | ForEach-Object { ($_ -split ' ')[1] })
}

function Use-RunAttempt {
    param([AllowNull()][string] $Value, [scriptblock] $Body)
    $previous = $env:AHKFLOW_RUN_ATTEMPT
    try {
        if ($null -eq $Value) { Remove-Item Env:\AHKFLOW_RUN_ATTEMPT -ErrorAction SilentlyContinue }
        else { $env:AHKFLOW_RUN_ATTEMPT = $Value }
        & $Body
    }
    finally {
        if ($null -eq $previous) { Remove-Item Env:\AHKFLOW_RUN_ATTEMPT -ErrorAction SilentlyContinue }
        else { $env:AHKFLOW_RUN_ATTEMPT = $previous }
    }
}

Invoke-TestCase 'Every coverage Slice writes a TRX file and its own log' {
    $root = New-CoverageFixture
    try {
        $result = Invoke-CoverageRun -Root $root
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"
        foreach ($name in @('Alpha.Tests', 'Beta.Tests')) {
            $folder = Join-Path $root "TestResults/coverage/$name"
            Assert-True (Test-Path -LiteralPath (Join-Path $folder "$name.trx")) "No $name.trx in $folder."
            Assert-True (Test-Path -LiteralPath (Join-Path $folder "$name.log")) "No $name.log in $folder."
        }
        Assert-True (Test-Path -LiteralPath (Join-Path $root 'TestResults/coverage/slices.json')) 'No slices.json.'
        $tests = @(Get-StubCall $root | Where-Object { $_ -match '^test ' })
        Assert-True ($tests.Count -eq 2) "Expected 2 test calls, got $($tests.Count)."
        foreach ($line in $tests) {
            $name = [regex]::Match($line, '([A-Za-z0-9.]+)\.csproj').Groups[1].Value
            Assert-True ($line.Contains("--logger trx;LogFileName=$name.trx")) "The call for $name has no TRX logger: $line"
        }
    }
    finally { Remove-CoverageFixture -Root $root }
}

Invoke-TestCase 'A coverage Slice that ran zero tests fails the run and names itself' {
    $root = New-CoverageFixture
    try {
        Set-StubMarker $root 'zero-tests.txt' 'Beta.Tests'
        $result = Invoke-CoverageRun -Root $root
        Assert-True ($result.ExitCode -ne 0) "An empty Slice must fail the run. Output: $($result.Output)"
        Assert-True ($result.Output.Contains('Beta.Tests discovered zero tests')) "The failure must name the Slice. Output: $($result.Output)"
    }
    finally { Remove-CoverageFixture -Root $root }
}

Invoke-TestCase 'A failing test still builds the report when every project has coverage' {
    $root = New-CoverageFixture
    try {
        Set-StubMarker $root 'fail-after-coverage.txt' 'Alpha.Tests'
        $result = Invoke-CoverageRun -Root $root
        Assert-True ($result.ExitCode -ne 0) "A failing test must fail the run. Output: $($result.Output)"
        Assert-True ($result.Output.Contains('dotnet test failed for: Alpha.Tests')) "The failure must name the Slice. Output: $($result.Output)"
        Assert-True (@(Get-StubCall $root 'reportgenerator-calls.txt').Count -eq 1) 'The report must still be built once.'
        Assert-True (@(Get-StubCall $root 'python-calls.txt').Count -eq 0) 'The threshold gate must not run.'
        Assert-True ($result.Output.Contains('=== Alpha.Tests:')) "The failing log must be printed. Output: $($result.Output)"
    }
    finally { Remove-CoverageFixture -Root $root }
}

Invoke-TestCase "At the value 1 the coverage step keeps today's order" {
    $root = New-CoverageFixture
    try {
        $folder = Get-ProgressHistoryFolder -Root $root
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $folder 'run-coverage.json') -Value '{ "Beta.Tests": 90, "Alpha.Tests": 10 }' -Encoding utf8
        $result = Invoke-InFixture -Root $root -ScriptName 'run-coverage.ps1' -Argument @('-SlicesAtOnce', '1')
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"
        $order = (Get-StartOrder $result.Output) -join ','
        Assert-True ($order -eq 'Alpha.Tests,Beta.Tests') "Start order: $order"
    }
    finally { Remove-CoverageFixture -Root $root }
}

Invoke-TestCase 'test-fast refuses -SlicesAtOnce outside Integration and Coverage' {
    $root = New-CoverageFixture
    try {
        $result = Invoke-InFixture -Root $root -ScriptName 'test-fast.ps1' -Argument @('-Mode', 'Fast', '-SlicesAtOnce', '2')
        Assert-True ($result.ExitCode -ne 0) "Expected a failure. Output: $($result.Output)"
        Assert-True ($result.Output.Contains('-SlicesAtOnce works only with -Mode Integration or -Mode Coverage.')) "Output: $($result.Output)"
        Assert-True (@(Get-StubCall $root).Count -eq 0) 'test-fast called dotnet before it refused.'
    }
    finally { Remove-CoverageFixture -Root $root }
}


# --- test-fast.ps1 Integration Mode ---

$script:IntegrationProject = @(
    'AHKFlowApp.Application.Tests'
    'AHKFlowApp.CLI.Tests'
    'AHKFlowApp.API.Tests'
    'AHKFlowApp.Infrastructure.Tests'
)

# Each Slice checks that its project file exists, so the fixture writes the four that the
# Integration Mode names.
function Add-IntegrationProject {
    param([string] $Root)
    foreach ($name in $script:IntegrationProject) {
        $folder = Join-Path (Join-Path $Root 'tests') $name
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $folder "$name.csproj") -Value '<Project />' -Encoding utf8
    }
}

function Invoke-IntegrationRun {
    param([string] $Root, [string[]] $Argument = @())
    return Invoke-InFixture -Root $Root -ScriptName 'test-fast.ps1' -Argument (@('-Mode', 'Integration') + $Argument)
}

Invoke-TestCase 'Integration without -NoBuild builds once, before any Slice' {
    $root = New-CoverageFixture
    try {
        Add-IntegrationProject $root
        $result = Invoke-IntegrationRun $root
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"
        $calls = @(Get-StubCall $root)
        Assert-True ($calls.Count -gt 0 -and $calls[0].StartsWith('build ')) "The first call is not the build: $($calls -join ' | ')"
        Assert-True (@($calls | Where-Object { $_.StartsWith('build ') }).Count -eq 1) "Expected one build: $($calls -join ' | ')"
    }
    finally { Remove-CoverageFixture -Root $root }
}

Invoke-TestCase 'Every Integration Slice runs with --no-build' {
    foreach ($noBuild in @($false, $true)) {
        $root = New-CoverageFixture
        try {
            Add-IntegrationProject $root
            $argument = @()
            if ($noBuild) { $argument = @('-NoBuild') }
            $result = Invoke-IntegrationRun $root $argument
            Assert-True ($result.ExitCode -eq 0) "NoBuild=${noBuild}: expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"
            $calls = @(Get-StubCall $root)
            $tests = @($calls | Where-Object { $_.StartsWith('test ') })
            Assert-True ($tests.Count -eq 4) "NoBuild=${noBuild}: expected 4 test calls, got $($tests.Count)."
            foreach ($line in $tests) { Assert-True ($line.Contains('--no-build')) "NoBuild=${noBuild}: a test call has no --no-build: $line" }
            if ($noBuild) {
                Assert-True (@($calls | Where-Object { $_.StartsWith('build ') }).Count -eq 0) 'A -NoBuild run built the solution.'
            }
        }
        finally { Remove-CoverageFixture -Root $root }
    }
}

Invoke-TestCase 'A failing Integration Slice does not stop the others, and the run names every failure' {
    $root = New-CoverageFixture
    try {
        Add-IntegrationProject $root
        Set-StubMarker $root 'fail-projects.txt' "AHKFlowApp.API.Tests`nAHKFlowApp.Infrastructure.Tests"
        $result = Invoke-IntegrationRun $root
        Assert-True ($result.ExitCode -ne 0) "Expected a failure. Output: $($result.Output)"
        Assert-True (@(Get-StubCall $root | Where-Object { $_.StartsWith('test ') }).Count -eq 4) 'Not every Slice ran.'
        Assert-True ($result.Output.Contains('dotnet test failed for: AHKFlowApp.API.Tests, AHKFlowApp.Infrastructure.Tests.')) "Output: $($result.Output)"
    }
    finally { Remove-CoverageFixture -Root $root }
}

Invoke-TestCase 'Each Integration Slice keeps its own results folder and log' {
    $root = New-CoverageFixture
    try {
        Add-IntegrationProject $root
        $result = Invoke-IntegrationRun $root
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"
        foreach ($name in $script:IntegrationProject) {
            $folder = Join-Path $root "TestResults/test-fast/Integration/$name"
            Assert-True (Test-Path -LiteralPath (Join-Path $folder "$name.trx")) "No $name.trx in $folder."
            Assert-True (Test-Path -LiteralPath (Join-Path $folder "$name.log")) "No $name.log in $folder."
        }
    }
    finally { Remove-CoverageFixture -Root $root }
}

Invoke-TestCase 'The Integration Mode marks its results with the attempt it belongs to' {
    $root = New-CoverageFixture
    try {
        Add-IntegrationProject $root
        $attemptPath = Join-Path $root 'TestResults/test-fast/Integration/attempt.txt'
        $with = Use-RunAttempt 'attempt-204' { Invoke-IntegrationRun $root }
        Assert-True ($with.ExitCode -eq 0) "Expected exit code 0, got $($with.ExitCode). Output: $($with.Output)"
        Assert-True ((Get-Content -LiteralPath $attemptPath -Raw).Trim() -eq 'attempt-204') 'attempt.txt does not hold attempt-204.'
        $without = Use-RunAttempt $null { Invoke-IntegrationRun $root }
        Assert-True ($without.ExitCode -eq 0) "Expected exit code 0, got $($without.ExitCode). Output: $($without.Output)"
        Assert-True (-not (Test-Path -LiteralPath $attemptPath)) 'A run with no attempt left an attempt.txt.'
    }
    finally { Remove-CoverageFixture -Root $root }
}


. (Join-Path $PSScriptRoot 'DotnetLane.Common.ps1')
foreach ($route in @('direct', 'delegated')) {
    foreach ($nested in @($false, $true)) {
        Invoke-TestCase "Coverage Lane route: $route nested=$nested" {
            $root = New-CoverageFixture
            try {
                $name = if ($route -eq 'direct') { 'run-coverage.ps1' } else { 'test-fast.ps1' }
                # The route steps through each dotnet test call in turn, so it runs the Slices in
                # sequence. Since backlog 204 the default is Budget, which starts them together.
                $arguments = if ($route -eq 'direct') { @{ SlicesAtOnce = '1' } } else { @{ Mode = 'Coverage'; Force = $true; SlicesAtOnce = '1' } }
                Test-DotnetLaneRoute -Root $root -ScriptName $name -Arguments $arguments -Calls 2 -Nested:$nested
            } finally { Remove-CoverageFixture $root }
        }
    }
}

Invoke-TestCase 'Coverage Lane route: direct failure' {
    $root = New-CoverageFixture
    try { Test-DotnetLaneRoute -Root $root -ScriptName 'run-coverage.ps1' -Arguments @{ SlicesAtOnce = '1' } -Calls 2 -Fail }
    finally { Remove-CoverageFixture $root }
}


Invoke-TestCase 'The coverage step marks its results with the attempt it belongs to' {
    $root = New-CoverageFixture
    try {
        $attemptPath = Join-Path $root 'TestResults/coverage/attempt.txt'
        $with = Use-RunAttempt 'attempt-204' { Invoke-CoverageRun -Root $root }
        Assert-True ($with.ExitCode -eq 0) "Expected exit code 0, got $($with.ExitCode). Output: $($with.Output)"
        Assert-True ((Get-Content -LiteralPath $attemptPath -Raw).Trim() -eq 'attempt-204') 'attempt.txt does not hold attempt-204.'

        $without = Use-RunAttempt $null { Invoke-CoverageRun -Root $root }
        Assert-True ($without.ExitCode -eq 0) "Expected exit code 0, got $($without.ExitCode). Output: $($without.Output)"
        Assert-True (-not (Test-Path -LiteralPath $attemptPath)) 'A run with no attempt left an attempt.txt.'

        Set-Content -LiteralPath $attemptPath -Value 'attempt-old' -Encoding utf8
        $checkout = Enter-AhkFlowTestRunLock $root Fresh
        try { $locked = Use-RunAttempt 'attempt-204' { Invoke-CoverageRun -Root $root } }
        finally { Exit-AhkFlowTestRunLock $checkout }
        Assert-True ($locked.ExitCode -ne 0) "A run that cannot take the lock must fail. Output: $($locked.Output)"
        Assert-True ((Get-Content -LiteralPath $attemptPath -Raw).Trim() -eq 'attempt-old') 'A run that failed before it cleared changed attempt.txt.'
    }
    finally { Remove-CoverageFixture -Root $root }
}

Invoke-TestCase 'Side by side the coverage step starts the longest Slice first' {
    $root = New-CoverageFixture -ProjectName @('Alpha.Tests', 'Beta.Tests', 'Gamma.Tests')
    $pool = New-PinnedLanePool 4
    try {
        $folder = Get-ProgressHistoryFolder -Root $root
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $folder 'run-coverage.json') -Value '{ "Beta.Tests": 90, "Alpha.Tests": 10 }' -Encoding utf8
        $result = Use-LaneEnvironment -Value @{ AHKFLOW_TEST_LANES_ROOT = $pool.Root; AHKFLOW_TEST_LANES_HOLDER = '  ' } -Body {
            Invoke-InFixture -Root $root -ScriptName 'run-coverage.ps1' -Argument @('-SlicesAtOnce', 'Budget')
        }
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output.Contains('Slices at once: 2 (asked for Budget, budget 2)')) "Output: $($result.Output)"
        $order = (Get-StartOrder $result.Output) -join ','
        Assert-True ($order -eq 'Gamma.Tests,Beta.Tests,Alpha.Tests') "Start order: $order"
    }
    finally { Remove-PinnedLanePool $pool; Remove-CoverageFixture -Root $root }
}

Invoke-TestCase 'Cancellation releases Lane and checkout ownership in a surviving host' {
    $root = New-CoverageFixture
    try { Test-DotnetLaneCancellation -Root $root -ScriptName 'run-coverage.ps1' }
    finally { Remove-CoverageFixture $root }
}

if ($script:Failures.Count -gt 0) {
    Write-Host ''
    Write-Host "FAILED: $($script:Failures.Count) test(s)" -ForegroundColor Red
    foreach ($failure in $script:Failures) {
        Write-Host "  - $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host ''
Write-Host 'Coverage runner progress wiring tests passed.' -ForegroundColor Green
