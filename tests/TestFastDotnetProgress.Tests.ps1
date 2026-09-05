#Requires -Version 7.0

# Backlog 123. scripts/test-fast.ps1 wraps its .NET test loop in the progress module: it builds a
# tracker keyed by mode, starts and stops a unit around each project, and saves the timings when
# the loop finishes.
#
# Building trackers by hand proves the module. It does not prove the wrapper calls it. Removing
# every progress call from the Fast and Integration loops left the module suite green, so this
# suite drives scripts/test-fast.ps1 itself.
#
# The wrapper resolves its repository root from $PSScriptRoot, so it gets a repository of its own.
# Everything it dot-sources is copied in, the five Fast projects exist as empty .csproj files with
# a stub .dll under bin, and 'dotnet' is a stub earlier on PATH that records the arguments it saw
# and writes the TRX file the wrapper reads. Fast mode now builds once and runs all five
# assemblies in one 'dotnet test' call, so a pass here is the wiring, not a real test run.
#
# Run it by hand with:  pwsh ./tests/TestFastDotnetProgress.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# A non-zero exit code from the child wrapper is data here, not a terminating error.
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

# The five projects Fast mode runs, in the order it runs them, each with the unit label the
# wrapper builds for it. Derived from scripts/test-fast.ps1, so a change there fails this suite
# rather than quietly passing with the wrong list.
$script:FastProject = @(
    @{ Name = 'AHKFlowApp.Domain.Tests';       Label = 'AHKFlowApp.Domain.Tests' }
    @{ Name = 'AHKFlowApp.TestUtilities.Tests'; Label = 'AHKFlowApp.TestUtilities.Tests' }
    @{ Name = 'AHKFlowApp.UI.Blazor.Tests';    Label = 'AHKFlowApp.UI.Blazor.Tests' }
    @{ Name = 'AHKFlowApp.Application.Tests';  Label = 'AHKFlowApp.Application.Tests[Category!=Integration]' }
    @{ Name = 'AHKFlowApp.CLI.Tests';          Label = 'AHKFlowApp.CLI.Tests[Category!=Integration]' }
)

function New-WrapperFixture {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('test-fast-progress-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path (Join-Path $root 'scripts') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root 'stub') -Force | Out-Null

    foreach ($name in @(
            'test-fast.ps1'
            'Common.ps1'
            'test-sql-container.common.ps1'
            'test-run-lock.common.ps1'
            'code-change-filter.common.ps1'
            'progress.common.ps1'
        )) {
        Copy-Item -LiteralPath (Join-Path $repoRoot "scripts\$name") -Destination (Join-Path $root "scripts\$name")
    }

    foreach ($project in $script:FastProject) {
        $folder = Join-Path (Join-Path $root 'tests') $project.Name
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $folder "$($project.Name).csproj") `
            -Value '<Project Sdk="Microsoft.NET.Sdk" />' -Encoding utf8

        # Fast mode runs built assemblies now, and the wrapper checks each one exists before it
        # calls dotnet. The content never matters, because dotnet is a stub.
        $binFolder = Join-Path $folder 'bin\Release\net10.0'
        New-Item -ItemType Directory -Path $binFolder -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $binFolder "$($project.Name).dll") `
            -Value 'stub assembly' -Encoding utf8
    }

    # PowerShell finds a .ps1 by its bare name on PATH, and passes arguments as an array, so the
    # ';' inside the --logger value survives. A .cmd shim would split it.
    Set-Content -LiteralPath (Join-Path $root 'stub\dotnet.ps1') -Encoding utf8 -Value @'
$stubFolder = Split-Path -Parent $PSCommandPath
Add-Content -LiteralPath (Join-Path $stubFolder 'calls.txt') -Value ($args -join ' ')

if ($args[0] -eq 'build') {
    Write-Output 'stub dotnet build'
    exit 0
}

# A test case drops this marker to make the run fail, so the suite can prove that a red test run
# fails the script. Nothing else creates it.
if (Test-Path -LiteralPath (Join-Path $stubFolder 'fail.txt')) {
    Write-Output 'stub dotnet test: forced failure'
    exit 1
}

$resultsDirectory = $null
$logFileName = 'stub.trx'
$assembly = @()
for ($i = 0; $i -lt $args.Count; $i++) {
    if ($args[$i] -eq '--results-directory' -and $i + 1 -lt $args.Count) {
        $resultsDirectory = $args[$i + 1]
    }
    if ($args[$i] -eq '--logger' -and $i + 1 -lt $args.Count -and $args[$i + 1] -match 'LogFileName=(.+)$') {
        $logFileName = $Matches[1]
    }
    if ($args[$i] -like '*.dll') {
        $assembly += $args[$i]
    }
}

if ($resultsDirectory) {
    New-Item -ItemType Directory -Path $resultsDirectory -Force | Out-Null

    # A test case drops this marker naming one assembly, and the TRX then carries no result for
    # it while the run still exits 0. That is exactly what a filter typo looks like from outside:
    # a green run with one assembly silently empty. Nothing else creates it.
    $silent = ''
    $silentMarker = Join-Path $stubFolder 'silent.txt'
    if (Test-Path -LiteralPath $silentMarker) {
        $silent = (Get-Content -LiteralPath $silentMarker -Raw).Trim()
    }

    # One definition and one result per assembly, joined by test id, which is the shape
    # Get-TestCountByAssembly reads.
    $definitions = ''
    $results = ''
    $index = 0
    foreach ($path in $assembly) {
        if ($silent -and ([System.IO.Path]::GetFileName($path) -eq $silent)) { continue }
        $index++
        $id = "00000000-0000-0000-0000-$($index.ToString('000000000000'))"
        $definitions += "<UnitTest name=""T$index"" storage=""$path"" id=""$id""><TestMethod codeBase=""$path"" className=""C"" name=""T$index"" /></UnitTest>"
        $results += "<UnitTestResult testId=""$id"" testName=""T$index"" outcome=""Passed"" />"
    }

    # $index, not $assembly.Count: a silenced assembly contributes no result, so the summary has
    # to agree with the results it wrote.
    $total = $index
    if ($total -lt 1) { $total = 1 }
    $trx = '<?xml version="1.0" encoding="UTF-8"?><TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010">' +
        "<TestDefinitions>$definitions</TestDefinitions><Results>$results</Results>" +
        "<ResultSummary><Counters total=""$total"" passed=""$total"" failed=""0"" /></ResultSummary></TestRun>"
    Set-Content -LiteralPath (Join-Path $resultsDirectory $logFileName) -Value $trx -Encoding utf8
}

Write-Output 'stub dotnet test'
exit 0
'@

    return $root
}

function Remove-WrapperFixture {
    param([string] $Root)
    if ($Root -and (Test-Path -LiteralPath $Root)) {
        Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-FastMode {
    param([Parameter(Mandatory)][string] $Root)

    $previousPath = $env:PATH
    $env:PATH = (Join-Path $Root 'stub') + [System.IO.Path]::PathSeparator + $previousPath
    try {
        $output = & $hostExe -NoProfile -File (Join-Path $Root 'scripts\test-fast.ps1') -Mode Fast -NoBuild 2>&1 | Out-String
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }
    finally {
        $env:PATH = $previousPath
    }
}

Write-Host "Testing $(Join-Path $repoRoot 'scripts\test-fast.ps1')"

$script:FastLabel = 'Fast[Category!=Integration]'

Invoke-TestCase 'Fast mode prints one progress line for the combined run' {
    $root = New-WrapperFixture
    try {
        $result = Invoke-FastMode -Root $root
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        $pattern = '\[1/1\] ' + [regex]::Escape($script:FastLabel)
        Assert-True ($result.Output -match $pattern) `
            "Expected a progress line '[1/1] $($script:FastLabel)'. Output: $($result.Output)"
    }
    finally { Remove-WrapperFixture -Root $root }
}

Invoke-TestCase 'Fast mode passes all five assemblies to one dotnet call' {
    $root = New-WrapperFixture
    try {
        $result = Invoke-FastMode -Root $root
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        $calls = @(Get-Content -LiteralPath (Join-Path $root 'stub\calls.txt'))
        $testCall = @($calls | Where-Object { $_ -notmatch '^build ' })
        Assert-True ($testCall.Count -eq 1) `
            "Expected exactly one dotnet test call, got $($testCall.Count): $($calls -join ' | ')"

        foreach ($project in $script:FastProject) {
            Assert-True ($testCall[0] -match [regex]::Escape("$($project.Name).dll")) `
                "The one dotnet test call must name $($project.Name).dll. Call: $($testCall[0])"
        }
    }
    finally { Remove-WrapperFixture -Root $root }
}

Invoke-TestCase 'Fast mode without -NoBuild builds the solution before it runs any test' {
    $root = New-WrapperFixture
    try {
        $previousPath = $env:PATH
        $env:PATH = (Join-Path $root 'stub') + [System.IO.Path]::PathSeparator + $previousPath
        $output = $null
        try {
            $output = & $hostExe -NoProfile -File (Join-Path $root 'scripts\test-fast.ps1') -Mode Fast 2>&1
            $exitCode = $LASTEXITCODE
        }
        finally { $env:PATH = $previousPath }

        # Discarding the exit code with Out-Null was the earlier shape of this case, and it made
        # the whole thing advisory: the script could fail outright and the call count would still
        # be right.
        Assert-True ($exitCode -eq 0) "Expected exit code 0, got $exitCode. Output: $output"

        $calls = @(Get-Content -LiteralPath (Join-Path $root 'stub\calls.txt'))
        Assert-True (@($calls | Where-Object { $_ -match '^build ' }).Count -eq 1) `
            "A Fast run without -NoBuild must build once. Calls: $($calls -join ' | ')"

        # Counting is not ordering. A build that ran after the test run would satisfy the count
        # above and still be the stale-binary defect this build exists to prevent, so assert the
        # position: the build is the first call, and no test call precedes it.
        Assert-True ($calls.Count -ge 2) `
            "Expected a build call and a test call. Calls: $($calls -join ' | ')"
        Assert-True ($calls[0] -match '^build ') `
            "The build must be the first dotnet call. Calls: $($calls -join ' | ')"
        Assert-True ($calls[1] -match '^test ') `
            "The test call must follow the build. Calls: $($calls -join ' | ')"
    }
    finally { Remove-WrapperFixture -Root $root }
}

Invoke-TestCase 'Fast mode with -NoBuild does not build' {
    $root = New-WrapperFixture
    try {
        Invoke-FastMode -Root $root | Out-Null

        $calls = @(Get-Content -LiteralPath (Join-Path $root 'stub\calls.txt'))
        Assert-True (@($calls | Where-Object { $_ -match '^build ' }).Count -eq 0) `
            "-NoBuild must skip the build. Calls: $($calls -join ' | ')"
    }
    finally { Remove-WrapperFixture -Root $root }
}

Invoke-TestCase 'Fast mode saves its timings under the key for its own mode' {
    $root = New-WrapperFixture
    try {
        $result = Invoke-FastMode -Root $root
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"

        $historyPath = Join-Path $root 'TestResults\progress\test-fast.Fast.json'
        Assert-True (Test-Path -LiteralPath $historyPath -PathType Leaf) `
            "Expected saved timings at $historyPath. Output: $($result.Output)"

        $saved = Get-Content -LiteralPath $historyPath -Raw | ConvertFrom-Json
        Assert-True ($null -ne $saved.PSObject.Properties[$script:FastLabel]) `
            "Expected saved seconds for '$($script:FastLabel)', got: $(($saved.PSObject.Properties.Name) -join ', ')"

        # The key carries the mode, so an Integration run cannot read a Fast estimate.
        $integrationPath = Join-Path $root 'TestResults\progress\test-fast.Integration.json'
        Assert-True (-not (Test-Path -LiteralPath $integrationPath)) `
            'A Fast run must not write the Integration timings file.'
    }
    finally { Remove-WrapperFixture -Root $root }
}

Invoke-TestCase 'Fast mode reads last run timings back as an estimate' {
    $root = New-WrapperFixture
    try {
        Invoke-FastMode -Root $root | Out-Null
        $result = Invoke-FastMode -Root $root

        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True ($result.Output -match 'remaining ~') `
            "The second run must estimate the time left from the first run's timings. Output: $($result.Output)"
        Assert-True (-not ($result.Output -match 'no history')) `
            "The second run must not report missing history. Output: $($result.Output)"
    }
    finally { Remove-WrapperFixture -Root $root }
}

# The two failure paths. Both belong to code this change introduces, so neither is covered by
# anything that ran before it.

Invoke-TestCase 'Fast mode stops when a built assembly is missing' {
    $root = New-WrapperFixture
    try {
        # This is the stale-binary trap the build step exists to close. If the guard is wrong,
        # the run reaches dotnet with a path that does not exist and the failure is confusing.
        $missing = Join-Path $root 'tests\AHKFlowApp.CLI.Tests\bin\Release\net10.0\AHKFlowApp.CLI.Tests.dll'
        Remove-Item -LiteralPath $missing -Force

        $result = Invoke-FastMode -Root $root
        Assert-True ($result.ExitCode -ne 0) `
            "A missing assembly must fail the run. Output: $($result.Output)"
        Assert-True ($result.Output -match 'Test assembly not found') `
            "The failure must name the missing assembly. Output: $($result.Output)"
    }
    finally { Remove-WrapperFixture -Root $root }
}

Invoke-TestCase 'Fast mode stops when the test run fails' {
    $root = New-WrapperFixture
    try {
        # Invoke-CombinedTestRun is new code with its own throw on a non-zero exit code, so a
        # green suite here would otherwise say nothing about a red test run. The marker is how
        # the stub is told to fail: appending code to the stub would not work, because its test
        # path ends in 'exit 0'.
        Set-Content -LiteralPath (Join-Path $root 'stub\fail.txt') -Value 'fail' -Encoding utf8

        $result = Invoke-FastMode -Root $root
        Assert-True ($result.ExitCode -ne 0) `
            "A failing test run must fail the script. Output: $($result.Output)"
    }
    finally { Remove-WrapperFixture -Root $root }
}

Invoke-TestCase 'Fast mode stops when one assembly in the combined run discovers no tests' {
    $root = New-WrapperFixture
    try {
        # The defect this guard exists for. Five separate calls each got their own zero-test
        # check; one combined call gets one exit code, and four healthy assemblies hide the
        # fifth. The stub writes a TRX with no result for the named assembly and still exits 0,
        # which is what a filter typo looks like from outside.
        Set-Content -LiteralPath (Join-Path $root 'stub\silent.txt') `
            -Value 'AHKFlowApp.CLI.Tests.dll' -Encoding utf8

        $result = Invoke-FastMode -Root $root
        Assert-True ($result.ExitCode -ne 0) `
            "An assembly that discovered nothing must fail the run. Output: $($result.Output)"
        Assert-True ($result.Output -match 'AHKFlowApp\.CLI\.Tests discovered zero tests') `
            "The failure must name the empty assembly. Output: $($result.Output)"
    }
    finally { Remove-WrapperFixture -Root $root }
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
Write-Host 'test-fast .NET progress wiring tests passed.' -ForegroundColor Green
