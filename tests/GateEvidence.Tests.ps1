#Requires -Version 7.0

# Backlog 188. scripts/gate-evidence.common.ps1 decides whether the Suite runner may reuse a
# Suite's last passing result. It lists every file a Suite reads, hashes them with the runner's own
# files and the tool versions into one key, and stores a small evidence file per key.
#
# Two failures matter most. A list that misses an input reuses a result the change has broken, so
# the resolver must say "unresolved" whenever it cannot follow a dot-source. And evidence that is
# cut off, or written by another format, must read as a miss, never as a pass.
#
# Every case builds its files in a new temporary folder and deletes it after. One case reads the
# real runner, because a resolver that cannot follow it switches reuse off for every Suite.
#
# Run it by hand with:  pwsh ./tests/GateEvidence.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$library = Join-Path $repoRoot 'scripts\gate-evidence.common.ps1'

# Load the library only when it exists, so a missing library fails every case by name instead of
# stopping the Suite before the first one.
if (Test-Path -LiteralPath $library -PathType Leaf) { . $library }

$script:Failures = New-Object System.Collections.Generic.List[string]

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-TestCase {
    param([string] $Name, [scriptblock] $Body)
    if ($env:AHKFLOW_SUITE_CASE_START -eq '1') { Write-Host "  START  $Name" }
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

function New-TempRoot {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ('gate-evidence-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return (Resolve-Path -LiteralPath $path).Path
}

function Remove-TempRoot {
    param([string] $Path)
    if ($Path -and (Test-Path -LiteralPath $Path)) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Write-TestFile {
    param([string] $Root, [string] $Relative, [string] $Text)
    $path = Join-Path $Root $Relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    Set-Content -LiteralPath $path -Value $Text -Encoding utf8
    return $path
}

function Get-TestKey {
    # A key from a Suite folder and a runner folder, with fixed tool versions unless a case
    # passes its own.
    param(
        [string] $Root,
        [string] $RunnerRoot,
        [string[]] $ExtraInput = @(),
        [System.Collections.IDictionary] $ToolVersion = ([ordered]@{ pwsh = '7.5.0'; dotnet = '10.0.100'; git = 'git version 2.50.0' })
    )
    $suite = Get-SuiteInputList -Path (Join-Path $Root 'tests\S.Tests.ps1') -Root $Root -ExtraInput $ExtraInput
    $runner = Get-SuiteInputList -Path (Join-Path $RunnerRoot 'runner.ps1') -Root $RunnerRoot
    $entry = [pscustomobject]@{ Name = 'S.Tests.ps1'; Execution = 'parallel' }
    return Get-SuiteReuseKey -Entry $entry -InputList $suite -RunnerInputList $runner -ToolVersion $ToolVersion `
        -Job 'suites' -Platform 'windows' -LaneRole 'Worker' -Root $Root -RunnerRoot $RunnerRoot
}

function New-KeyFixture {
    # A Suite that dot-sources one library, and a runner that dot-sources one library.
    $root = New-TempRoot
    $runnerRoot = New-TempRoot
    Write-TestFile $root 'tests\S.Tests.ps1' ". (Join-Path `$PSScriptRoot 'lib.ps1')`nTest-Lib" | Out-Null
    Write-TestFile $root 'tests\lib.ps1' 'function Test-Lib { 1 }' | Out-Null
    Write-TestFile $root 'tests\x.json' '{ "a": 1 }' | Out-Null
    Write-TestFile $runnerRoot 'runner.ps1' ". `"`$PSScriptRoot\runner.common.ps1`"" | Out-Null
    Write-TestFile $runnerRoot 'runner.common.ps1' 'function Invoke-Runner { 1 }' | Out-Null
    return [pscustomobject]@{ Root = $root; RunnerRoot = $runnerRoot }
}

# --- The input list -----------------------------------------------------------

Invoke-TestCase 'The input list follows a dot-source chain to the end' {
    $root = New-TempRoot
    try {
        $suite = Write-TestFile $root 'tests\S.Tests.ps1' ". (Join-Path `$PSScriptRoot '..\scripts\a.ps1')"
        Write-TestFile $root 'scripts\a.ps1' ". `"`$PSScriptRoot\b.ps1`"" | Out-Null
        Write-TestFile $root 'scripts\b.ps1' 'function B { 1 }' | Out-Null

        $list = Get-SuiteInputList -Path $suite -Root $root
        Assert-True $list.Resolved "The chain must resolve. Unresolved: $($list.Unresolved -join ' | ')"
        Assert-True (($list.Inputs -join ',') -eq 'scripts/a.ps1,scripts/b.ps1,tests/S.Tests.ps1') `
            "Expected the Suite and both scripts, sorted, with forward slashes. Got: $($list.Inputs -join ',')"
    }
    finally { Remove-TempRoot $root }
}

Invoke-TestCase 'The input list holds a path named inside a here-string' {
    $root = New-TempRoot
    try {
        $suite = Write-TestFile $root 'tests\S.Tests.ps1' "`$text = @'`nThe notes live in docs/notes.md.`n'@`n`$text"
        Write-TestFile $root 'docs\notes.md' '# Notes' | Out-Null

        $list = Get-SuiteInputList -Path $suite -Root $root
        Assert-True $list.Resolved "The list must resolve. Unresolved: $($list.Unresolved -join ' | ')"
        Assert-True ($list.Inputs -contains 'docs/notes.md') "A path inside a here-string must count. Got: $($list.Inputs -join ',')"
    }
    finally { Remove-TempRoot $root }
}

Invoke-TestCase 'A path named only in a comment is not an input' {
    # A comment never makes a script read a file. Following comment paths once pulled most of
    # tests/ into the runner's own list, and their dot-sources made it unresolved.
    $root = New-TempRoot
    try {
        $suite = Write-TestFile $root 'tests\S.Tests.ps1' "# See docs/notes.md and tests/Other.Tests.ps1.`n<# docs/block.md #>`nWrite-Output 1"
        Write-TestFile $root 'docs\notes.md' '# Notes' | Out-Null
        Write-TestFile $root 'docs\block.md' '# Block' | Out-Null
        Write-TestFile $root 'tests\Other.Tests.ps1' '. $env:ANYTHING' | Out-Null

        $list = Get-SuiteInputList -Path $suite -Root $root
        Assert-True $list.Resolved "A dot-source in a file named only by a comment must not count. Unresolved: $($list.Unresolved -join ' | ')"
        Assert-True (($list.Inputs -join ',') -eq 'tests/S.Tests.ps1') "Only the Suite itself is an input. Got: $($list.Inputs -join ',')"
    }
    finally { Remove-TempRoot $root }
}

Invoke-TestCase 'A path under TestResults is not an input' {
    # Final review, backlog 188. The runner names TestResults/progress/budget-streak.json and
    # rewrites it after every Gate run. As an input it changed every key, so nothing was reused.
    # TestResults/ is git-ignored output that a run writes, never a file a Suite depends on.
    $root = New-TempRoot
    try {
        $suite = Write-TestFile $root 'tests\S.Tests.ps1' "`$streak = Join-Path `$PSScriptRoot '..\TestResults\progress\budget-streak.json'"
        Write-TestFile $root 'TestResults\progress\budget-streak.json' '{}' | Out-Null

        $list = Get-SuiteInputList -Path $suite -Root $root
        Assert-True $list.Resolved "The list must resolve. Unresolved: $($list.Unresolved -join ' | ')"
        Assert-True (($list.Inputs -join ',') -eq 'tests/S.Tests.ps1') "Run output must not be an input. Got: $($list.Inputs -join ',')"
    }
    finally { Remove-TempRoot $root }
}

Invoke-TestCase 'A dot-source of a variable built at run time leaves the list unresolved' {
    $root = New-TempRoot
    try {
        $suite = Write-TestFile $root 'tests\S.Tests.ps1' "`$lib = Join-Path `$PSScriptRoot ('lib' + `$env:SUFFIX + '.ps1')`n. `$lib"
        Write-TestFile $root 'tests\lib.ps1' 'function L { 1 }' | Out-Null

        $list = Get-SuiteInputList -Path $suite -Root $root
        Assert-True (-not $list.Resolved) 'A dot-source the resolver cannot follow must leave the list unresolved.'
        Assert-True (@($list.Unresolved | Where-Object { $_ -match 'S\.Tests\.ps1:2 dot-sources' }).Count -eq 1) `
            "The reason must name the file and line. Got: $($list.Unresolved -join ' | ')"
    }
    finally { Remove-TempRoot $root }
}

Invoke-TestCase 'A dot-source of a variable assigned a literal path resolves' {
    $root = New-TempRoot
    try {
        $suite = Write-TestFile $root 'tests\S.Tests.ps1' "`$lib = Join-Path `$PSScriptRoot 'lib.ps1'`n. `$lib"
        Write-TestFile $root 'tests\lib.ps1' 'function L { 1 }' | Out-Null

        $list = Get-SuiteInputList -Path $suite -Root $root
        Assert-True $list.Resolved "The list must resolve. Unresolved: $($list.Unresolved -join ' | ')"
        Assert-True ($list.Inputs -contains 'tests/lib.ps1') "The library must be on the list. Got: $($list.Inputs -join ',')"
    }
    finally { Remove-TempRoot $root }
}

Invoke-TestCase 'A dot-source through $using: resolves like the variable it names' {
    $root = New-TempRoot
    try {
        $suite = Write-TestFile $root 'tests\S.Tests.ps1' "`$mod = Join-Path `$PSScriptRoot 'lib.ps1'`n1 | ForEach-Object -Parallel { . `$using:mod }"
        Write-TestFile $root 'tests\lib.ps1' 'function L { 1 }' | Out-Null

        $list = Get-SuiteInputList -Path $suite -Root $root
        Assert-True $list.Resolved "The list must resolve. Unresolved: $($list.Unresolved -join ' | ')"
        Assert-True ($list.Inputs -contains 'tests/lib.ps1') "The library must be on the list. Got: $($list.Inputs -join ',')"
    }
    finally { Remove-TempRoot $root }
}

Invoke-TestCase 'A missing extra input leaves the list unresolved' {
    $root = New-TempRoot
    try {
        $suite = Write-TestFile $root 'tests\S.Tests.ps1' 'Write-Output 1'

        $list = Get-SuiteInputList -Path $suite -Root $root -ExtraInput @('tests/missing.json')
        Assert-True (-not $list.Resolved) 'A missing extra input must leave the list unresolved.'
        Assert-True (@($list.Unresolved | Where-Object { $_ -match 'tests/missing\.json' }).Count -ge 1) `
            "The reason must name the missing input. Got: $($list.Unresolved -join ' | ')"
    }
    finally { Remove-TempRoot $root }
}

Invoke-TestCase 'A path outside the root leaves the list unresolved' {
    $outer = New-TempRoot
    try {
        $root = Join-Path $outer 'repo'
        Write-TestFile $outer 'outside.json' '{}' | Out-Null
        $suite = Write-TestFile $root 'tests\S.Tests.ps1' "Get-Content (Join-Path `$PSScriptRoot '..\..\outside.json')"

        $list = Get-SuiteInputList -Path $suite -Root $root
        Assert-True (-not $list.Resolved) 'A file outside the root must leave the list unresolved.'
        Assert-True (@($list.Unresolved | Where-Object { $_ -match 'outside\.json' }).Count -ge 1) `
            "The reason must name the outside file. Got: $($list.Unresolved -join ' | ')"
    }
    finally { Remove-TempRoot $outer }
}

Invoke-TestCase "The real runner's input list resolves and holds the four scripts it dot-sources" {
    $list = Get-SuiteInputList -Path (Join-Path $repoRoot 'scripts\run-powershell-suites.ps1') -Root $repoRoot
    Assert-True $list.Resolved "The real runner must resolve, or reuse is off for every Suite. Unresolved: $($list.Unresolved -join ' | ')"
    foreach ($expected in @('scripts/progress.common.ps1', 'scripts/powershell-suites.common.ps1',
            'scripts/test-lanes.common.ps1', 'scripts/progress.parallel.ps1', 'scripts/run-powershell-suites.ps1')) {
        Assert-True ($list.Inputs -contains $expected) "The runner's list must hold $expected. Got: $($list.Inputs -join ',')"
    }
}

# --- The key ------------------------------------------------------------------

Invoke-TestCase "The key changes when an input's content changes" {
    $fixture = New-KeyFixture
    try {
        $first = Get-TestKey -Root $fixture.Root -RunnerRoot $fixture.RunnerRoot
        $again = Get-TestKey -Root $fixture.Root -RunnerRoot $fixture.RunnerRoot
        Assert-True ($first -match '^[0-9a-f]{64}$') "The key must be a SHA-256 hex string. Got: $first"
        Assert-True ($first -eq $again) 'The same inputs must give the same key.'

        Write-TestFile $fixture.Root 'tests\lib.ps1' 'function Test-Lib { 2 }' | Out-Null
        $changed = Get-TestKey -Root $fixture.Root -RunnerRoot $fixture.RunnerRoot
        Assert-True ($changed -ne $first) 'A changed library must change the key.'
    }
    finally { Remove-TempRoot $fixture.Root; Remove-TempRoot $fixture.RunnerRoot }
}

Invoke-TestCase 'The key changes when an input is added, removed or renamed' {
    $fixture = New-KeyFixture
    try {
        Write-TestFile $fixture.Root 'tests\y.json' '{ "a": 1 }' | Out-Null
        $one = Get-TestKey -Root $fixture.Root -RunnerRoot $fixture.RunnerRoot -ExtraInput @('tests/x.json')
        $added = Get-TestKey -Root $fixture.Root -RunnerRoot $fixture.RunnerRoot -ExtraInput @('tests/x.json', 'tests/y.json')
        $renamed = Get-TestKey -Root $fixture.Root -RunnerRoot $fixture.RunnerRoot -ExtraInput @('tests/y.json')
        $removed = Get-TestKey -Root $fixture.Root -RunnerRoot $fixture.RunnerRoot

        Assert-True ($added -ne $one) 'An added input must change the key.'
        Assert-True ($removed -ne $one) 'A removed input must change the key.'
        Assert-True ($renamed -ne $one) 'The same bytes under another name must change the key.'
    }
    finally { Remove-TempRoot $fixture.Root; Remove-TempRoot $fixture.RunnerRoot }
}

Invoke-TestCase 'The key changes when a tool version changes' {
    $fixture = New-KeyFixture
    try {
        $first = Get-TestKey -Root $fixture.Root -RunnerRoot $fixture.RunnerRoot
        foreach ($tool in @('pwsh', 'dotnet', 'git')) {
            $versions = [ordered]@{ pwsh = '7.5.0'; dotnet = '10.0.100'; git = 'git version 2.50.0' }
            $versions[$tool] = 'another'
            $changed = Get-TestKey -Root $fixture.Root -RunnerRoot $fixture.RunnerRoot -ToolVersion $versions
            Assert-True ($changed -ne $first) "A changed $tool version must change the key."
        }
    }
    finally { Remove-TempRoot $fixture.Root; Remove-TempRoot $fixture.RunnerRoot }
}

Invoke-TestCase 'The key changes when a runner input changes' {
    $fixture = New-KeyFixture
    try {
        $first = Get-TestKey -Root $fixture.Root -RunnerRoot $fixture.RunnerRoot
        Write-TestFile $fixture.RunnerRoot 'runner.common.ps1' 'function Invoke-Runner { 2 }' | Out-Null
        $changed = Get-TestKey -Root $fixture.Root -RunnerRoot $fixture.RunnerRoot
        Assert-True ($changed -ne $first) "A change to a file the runner dot-sources must change every Suite's key."
    }
    finally { Remove-TempRoot $fixture.Root; Remove-TempRoot $fixture.RunnerRoot }
}

Invoke-TestCase 'The key is null when either list is unresolved' {
    $fixture = New-KeyFixture
    try {
        $missing = Get-TestKey -Root $fixture.Root -RunnerRoot $fixture.RunnerRoot -ExtraInput @('tests/missing.json')
        Assert-True ($null -eq $missing) 'An unresolved Suite list must give no key.'

        Write-TestFile $fixture.RunnerRoot 'runner.ps1' ". `$env:SOME_RUNNER_LIBRARY" | Out-Null
        $runnerUnresolved = Get-TestKey -Root $fixture.Root -RunnerRoot $fixture.RunnerRoot
        Assert-True ($null -eq $runnerUnresolved) 'An unresolved runner list must give no key.'
    }
    finally { Remove-TempRoot $fixture.Root; Remove-TempRoot $fixture.RunnerRoot }
}

# --- The evidence file --------------------------------------------------------

function New-EvidenceFixture {
    $fixture = New-KeyFixture
    $suite = Get-SuiteInputList -Path (Join-Path $fixture.Root 'tests\S.Tests.ps1') -Root $fixture.Root
    $runner = Get-SuiteInputList -Path (Join-Path $fixture.RunnerRoot 'runner.ps1') -Root $fixture.RunnerRoot
    $key = Get-TestKey -Root $fixture.Root -RunnerRoot $fixture.RunnerRoot
    $evidenceRoot = Join-Path $fixture.Root 'TestResults\gate-evidence'
    Write-GateEvidence -EvidenceRoot $evidenceRoot -SuiteName 'S.Tests.ps1' -Key $key -InputList $suite -RunnerInputList $runner -Seconds 12.5
    return [pscustomobject]@{
        Fixture      = $fixture
        Suite        = $suite
        Runner       = $runner
        Key          = $key
        EvidenceRoot = $evidenceRoot
        File         = Join-Path $evidenceRoot "S.Tests.ps1\$key.json"
    }
}

Invoke-TestCase 'Evidence cut off halfway is a miss' {
    $e = New-EvidenceFixture
    try {
        $bytes = [System.IO.File]::ReadAllBytes($e.File)
        [System.IO.File]::WriteAllBytes($e.File, $bytes[0..([int]($bytes.Length / 2))])
        $read = Read-GateEvidence -EvidenceRoot $e.EvidenceRoot -SuiteName 'S.Tests.ps1' -Key $e.Key
        Assert-True ($null -eq $read) 'Evidence cut off halfway must read as a miss, and must not throw.'
    }
    finally { Remove-TempRoot $e.Fixture.Root; Remove-TempRoot $e.Fixture.RunnerRoot }
}

Invoke-TestCase 'Evidence in another format version is a miss' {
    $e = New-EvidenceFixture
    try {
        $json = Get-Content -LiteralPath $e.File -Raw | ConvertFrom-Json
        $json.formatVersion = 2
        Set-Content -LiteralPath $e.File -Value ($json | ConvertTo-Json -Depth 5) -Encoding utf8
        $read = Read-GateEvidence -EvidenceRoot $e.EvidenceRoot -SuiteName 'S.Tests.ps1' -Key $e.Key
        Assert-True ($null -eq $read) 'Evidence in another format version must read as a miss.'
    }
    finally { Remove-TempRoot $e.Fixture.Root; Remove-TempRoot $e.Fixture.RunnerRoot }
}

Invoke-TestCase 'Evidence for another key is a miss' {
    $e = New-EvidenceFixture
    try {
        $otherKey = 'f' * 64
        $read = Read-GateEvidence -EvidenceRoot $e.EvidenceRoot -SuiteName 'S.Tests.ps1' -Key $otherKey
        Assert-True ($null -eq $read) 'No evidence for a key must read as a miss.'

        # A file under the right name that records another key, or another Suite, is a miss too.
        Copy-Item -LiteralPath $e.File -Destination (Join-Path (Split-Path -Parent $e.File) "$otherKey.json")
        $read = Read-GateEvidence -EvidenceRoot $e.EvidenceRoot -SuiteName 'S.Tests.ps1' -Key $otherKey
        Assert-True ($null -eq $read) 'Evidence that records another key must read as a miss.'

        $otherSuite = Join-Path $e.EvidenceRoot 'T.Tests.ps1'
        New-Item -ItemType Directory -Path $otherSuite -Force | Out-Null
        Copy-Item -LiteralPath $e.File -Destination (Join-Path $otherSuite "$($e.Key).json")
        $read = Read-GateEvidence -EvidenceRoot $e.EvidenceRoot -SuiteName 'T.Tests.ps1' -Key $e.Key
        Assert-True ($null -eq $read) 'Evidence that records another Suite must read as a miss.'
    }
    finally { Remove-TempRoot $e.Fixture.Root; Remove-TempRoot $e.Fixture.RunnerRoot }
}

Invoke-TestCase 'Evidence written and read back gives the same inputs' {
    $e = New-EvidenceFixture
    try {
        $read = Read-GateEvidence -EvidenceRoot $e.EvidenceRoot -SuiteName 'S.Tests.ps1' -Key $e.Key
        Assert-True ($null -ne $read) 'Evidence just written must read back.'
        Assert-True ($read.formatVersion -eq $script:GateEvidenceFormatVersion) "The format version must survive. Got: $($read.formatVersion)"
        Assert-True ($read.suite -eq 'S.Tests.ps1' -and $read.key -eq $e.Key) 'The Suite and the key must survive.'
        Assert-True ([double] $read.seconds -eq 12.5) "The seconds must survive. Got: $($read.seconds)"
        Assert-True ((@($read.inputs) -join ',') -eq ($e.Suite.Inputs -join ',')) `
            "The inputs must survive in order. Got: $(@($read.inputs) -join ',')"
        Assert-True ((@($read.runnerInputs) -join ',') -eq ($e.Runner.Inputs -join ',')) `
            "The runner inputs must survive in order. Got: $(@($read.runnerInputs) -join ',')"
        Assert-True (@(Get-ChildItem -LiteralPath (Split-Path -Parent $e.File) -Filter '*.tmp').Count -eq 0) `
            'The write must leave no temporary file behind.'
    }
    finally { Remove-TempRoot $e.Fixture.Root; Remove-TempRoot $e.Fixture.RunnerRoot }
}

Invoke-TestCase 'The evidence root is the override when set, else TestResults/gate-evidence' {
    $previous = $env:AHKFLOW_GATE_EVIDENCE_ROOT
    try {
        $env:AHKFLOW_GATE_EVIDENCE_ROOT = 'C:\elsewhere\evidence'
        Assert-True ((Get-GateEvidenceRoot -RepoRoot 'C:\repo') -eq 'C:\elsewhere\evidence') 'The override must win.'
        $env:AHKFLOW_GATE_EVIDENCE_ROOT = $null
        $default = Get-GateEvidenceRoot -RepoRoot $repoRoot
        Assert-True ($default -eq (Join-Path $repoRoot 'TestResults\gate-evidence')) "Expected the TestResults default. Got: $default"
    }
    finally { $env:AHKFLOW_GATE_EVIDENCE_ROOT = $previous }
}

# --- The time budget per Suite -------------------------------------------------

$budgetLibrary = Join-Path $repoRoot 'scripts\suite-budget.common.ps1'
if (Test-Path -LiteralPath $budgetLibrary -PathType Leaf) { . $budgetLibrary }

function New-BudgetEntry {
    param($Baseline)
    return [pscustomobject]@{ Name = 'S.Tests.ps1'; BaselineSeconds = $Baseline }
}

Invoke-TestCase 'A Suite 31 percent over its budget warns' {
    $warning = Get-SuiteBudgetWarning -Entry (New-BudgetEntry 30) -Seconds 39.3
    Assert-True ($warning -eq 'BUDGET S.Tests.ps1: 39.3 s against a budget of 30.0 s (+31 %)') "Got: $warning"
}

Invoke-TestCase 'A Suite 29 percent over its budget does not warn' {
    $warning = Get-SuiteBudgetWarning -Entry (New-BudgetEntry 30) -Seconds 38.7
    Assert-True ($null -eq $warning) "Got: $warning"
}

Invoke-TestCase 'A budget under 5 s or null never warns' {
    Assert-True ($null -eq (Get-SuiteBudgetWarning -Entry (New-BudgetEntry 4.9) -Seconds 100)) 'A budget under 5 s must not warn.'
    Assert-True ($null -eq (Get-SuiteBudgetWarning -Entry (New-BudgetEntry $null) -Seconds 100)) 'A null budget must not warn.'
}

Invoke-TestCase 'Two warnings in a row suggest the audit' {
    $root = New-TempRoot
    try {
        $streak = Join-Path $root 'progress\budget-streak.json'
        $first = @(Update-SuiteBudgetStreak -Path $streak -Executed @('A.Tests.ps1', 'B.Tests.ps1') -Warned @('A.Tests.ps1'))
        Assert-True ($first.Count -eq 0) "One warning must not suggest the audit. Got: $($first -join ',')"
        $second = @(Update-SuiteBudgetStreak -Path $streak -Executed @('A.Tests.ps1', 'B.Tests.ps1') -Warned @('A.Tests.ps1'))
        Assert-True (($second -join ',') -eq 'A.Tests.ps1') "Two in a row must suggest A only. Got: $($second -join ',')"
    }
    finally { Remove-TempRoot $root }
}

Invoke-TestCase 'A run without a warning resets the streak' {
    $root = New-TempRoot
    try {
        $streak = Join-Path $root 'budget-streak.json'
        Update-SuiteBudgetStreak -Path $streak -Executed @('A.Tests.ps1') -Warned @('A.Tests.ps1') | Out-Null
        Update-SuiteBudgetStreak -Path $streak -Executed @('A.Tests.ps1') -Warned @() | Out-Null
        $after = @(Update-SuiteBudgetStreak -Path $streak -Executed @('A.Tests.ps1') -Warned @('A.Tests.ps1'))
        Assert-True ($after.Count -eq 0) "A clean run in between must reset the streak. Got: $($after -join ',')"
    }
    finally { Remove-TempRoot $root }
}

Invoke-TestCase 'A reused Suite leaves the streak unchanged' {
    $root = New-TempRoot
    try {
        $streak = Join-Path $root 'budget-streak.json'
        Update-SuiteBudgetStreak -Path $streak -Executed @('A.Tests.ps1') -Warned @('A.Tests.ps1') | Out-Null
        # A was reused: it is not in Executed, so its streak must survive this run.
        Update-SuiteBudgetStreak -Path $streak -Executed @('B.Tests.ps1') -Warned @() | Out-Null
        $after = @(Update-SuiteBudgetStreak -Path $streak -Executed @('A.Tests.ps1') -Warned @('A.Tests.ps1'))
        Assert-True (($after -join ',') -eq 'A.Tests.ps1') "A reused run must not reset the streak. Got: $($after -join ',')"
    }
    finally { Remove-TempRoot $root }
}

# --- The runner reuses evidence -----------------------------------------------
#
# Each scenario runs scripts/run-powershell-suites.ps1 as a child over a folder of fake Suites.
# A fake Suite appends one line to its own counter file each time it runs. The counter files end in
# .count, an extension the resolver does not follow, so a Suite's own writes never change its key.

$script:HostExe = [System.Diagnostics.Process]::GetCurrentProcess().Path
$script:Runner = Join-Path $repoRoot 'scripts\run-powershell-suites.ps1'

function ConvertTo-ScriptLiteral {
    param([string] $Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function New-GateFixture {
    # Suites: name -> @{ Reuse = $null or a hashtable; Body = extra lines; Baseline = seconds or absent }.
    param([System.Collections.IDictionary] $Suite)
    $root = New-TempRoot
    $tests = Join-Path $root 'tests'
    New-Item -ItemType Directory -Path $tests, (Join-Path $root 'counters') -Force | Out-Null

    $entries = foreach ($name in $Suite.Keys) {
        $counter = Join-Path (Join-Path $root 'counters') ($name -replace '\.Tests\.ps1$', '.count')
        $lines = @("Add-Content -LiteralPath $(ConvertTo-ScriptLiteral $counter) -Value 'ran'") + @($Suite[$name]['Body'])
        Set-Content -LiteralPath (Join-Path $tests $name) -Value ($lines -join [Environment]::NewLine) -Encoding utf8

        $entry = [ordered]@{ name = $name; jobs = @('suites'); platform = @('windows', 'linux'); execution = 'parallel'; baselineSeconds = $Suite[$name]['Baseline'] }
        if ($null -ne $Suite[$name]['Reuse']) { $entry['reuse'] = $Suite[$name]['Reuse'] }
        $entry
    }
    Set-Content -LiteralPath (Join-Path $tests 'powershell-suites.json') -Value (([ordered]@{ suites = @($entries) }) | ConvertTo-Json -Depth 6) -Encoding utf8
    return $root
}

function Get-RunCount {
    param([string] $Root, [string] $Name)
    $counter = Join-Path (Join-Path $Root 'counters') ($Name -replace '\.Tests\.ps1$', '.count')
    if (-not (Test-Path -LiteralPath $counter)) { return 0 }
    return @(Get-Content -LiteralPath $counter).Count
}

function Get-GateLogLine {
    param([string] $Root)
    $log = Join-Path $Root 'gate-log.jsonl'
    if (-not (Test-Path -LiteralPath $log)) { return , @() }
    return , @(Get-Content -LiteralPath $log | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
}

function Invoke-GateRunner {
    <#
      Runs the real runner over the fixture's tests folder. The child must not reach the real Lane
      pool, the real job summary, the real evidence, or a GitHub Actions setting inherited from CI,
      which would switch reuse off in every scenario.
    #>
    param([string] $Root, [switch] $Gate, [hashtable] $Environment = @{})
    $names = @('AHKFLOW_TEST_LANES_HOLDER', 'GITHUB_STEP_SUMMARY', 'GITHUB_ACTIONS', 'AHKFLOW_GATE_REUSE', 'AHKFLOW_GATE_EVIDENCE_ROOT')
    $saved = @{}
    foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
    try {
        if ([string]::IsNullOrWhiteSpace($env:AHKFLOW_TEST_LANES_ROOT) -and [string]::IsNullOrWhiteSpace($saved['AHKFLOW_TEST_LANES_HOLDER'])) {
            $env:AHKFLOW_TEST_LANES_HOLDER = [string]$PID
        }
        $env:GITHUB_STEP_SUMMARY = Join-Path $Root 'summary.md'
        $env:GITHUB_ACTIONS = $null
        $env:AHKFLOW_GATE_REUSE = $null
        $env:AHKFLOW_GATE_EVIDENCE_ROOT = Join-Path $Root 'evidence'
        foreach ($key in $Environment.Keys) { [Environment]::SetEnvironmentVariable($key, $Environment[$key]) }

        $arguments = @('-NoProfile', '-File', $script:Runner, '-SuiteRoot', (Join-Path $Root 'tests'))
        if ($Gate) { $arguments += '-Gate' }
        $output = & $script:HostExe @arguments 2>&1 | Out-String
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }
    finally {
        foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    }
}

# Scenario A: one eligible Suite, one with no reuse field. Three Gate runs, with an edit before the
# third. Slow is eligible too, with a 5 s budget it overruns once (Task 13): its 7 s sleep is the
# only one these cases pay, because the later runs reuse it.
$a = New-GateFixture -Suite ([ordered]@{
        'Quick.Tests.ps1' = @{ Reuse = [ordered]@{ eligible = $true } }
        'Plain.Tests.ps1' = @{ Reuse = $null }
        'Slow.Tests.ps1'  = @{ Reuse = [ordered]@{ eligible = $true }; Baseline = 5; Body = @('Start-Sleep -Seconds 7') }
    })
$aRuns = @(); $aCounts = @(); $aError = $null
try {
    foreach ($step in 1..3) {
        if ($step -eq 3) { Add-Content -LiteralPath (Join-Path $a 'tests\Quick.Tests.ps1') -Value "Write-Host 'edited'" }
        $aRuns += Invoke-GateRunner -Root $a -Gate
        $aCounts += , @((Get-RunCount $a 'Quick.Tests.ps1'), (Get-RunCount $a 'Plain.Tests.ps1'))
    }
    $aLog = Get-GateLogLine $a
}
catch { $aError = $_.Exception.Message }

Invoke-TestCase 'A second Gate run reuses an unchanged eligible Suite and runs the rest' {
    Assert-True ($null -eq $aError) "The scenario failed to run: $aError"
    Assert-True ($aRuns[0].ExitCode -eq 0 -and $aRuns[1].ExitCode -eq 0) "Both runs must pass. Output: $($aRuns[1].Output)"
    Assert-True ($aRuns[1].Output -match 'Gate evidence: on') "Expected the evidence line. Output: $($aRuns[1].Output)"
    Assert-True (($aCounts[1] -join ',') -eq '1,2') "Quick must run once and Plain twice, got Quick,Plain = $($aCounts[1] -join ',')."
    Assert-True ($aRuns[1].Output -match 'REUSED Quick\.Tests\.ps1 \(evidence [0-9a-f]{12}\)') "Expected the REUSED line. Output: $($aRuns[1].Output)"
    Assert-True ($aRuns[1].Output -match '\| Quick\.Tests\.ps1 \| reused \| 0 \| - \|') "Expected a reused row in the table. Output: $($aRuns[1].Output)"
    Assert-True ($aRuns[1].Output -match 'All 3 suite\(s\) passed\.') "A reused Suite still counts as passed. Output: $($aRuns[1].Output)"
}

Invoke-TestCase 'An edited eligible Suite runs again' {
    Assert-True ($null -eq $aError) "The scenario failed to run: $aError"
    Assert-True ($aRuns[2].ExitCode -eq 0) "The third run must pass. Output: $($aRuns[2].Output)"
    Assert-True (($aCounts[2] -join ',') -eq '2,3') "Quick must run again after its edit, got Quick,Plain = $($aCounts[2] -join ',')."
    Assert-True ($aRuns[2].Output -notmatch 'REUSED Quick') "The edited Suite must not be reused. Output: $($aRuns[2].Output)"
}

Invoke-TestCase 'Each Gate run appends one log line that names what ran and what was reused' {
    Assert-True ($null -eq $aError) "The scenario failed to run: $aError"
    Assert-True ($aLog.Count -eq 3) "Expected three log lines, got $($aLog.Count)."
    Assert-True ((@($aLog[0].executed | Sort-Object) -join ',') -eq 'Plain.Tests.ps1,Quick.Tests.ps1,Slow.Tests.ps1') "Run 1 executed all three. Got: $(@($aLog[0].executed) -join ',')"
    Assert-True (@($aLog[0].reused).Count -eq 0) 'Run 1 reused nothing.'
    Assert-True ((@($aLog[1].executed) -join ',') -eq 'Plain.Tests.ps1') "Run 2 executed only Plain. Got: $(@($aLog[1].executed) -join ',')"
    Assert-True ((@($aLog[1].reused) -join ',') -eq 'Quick.Tests.ps1,Slow.Tests.ps1') "Run 2 reused Quick and Slow. Got: $(@($aLog[1].reused) -join ',')"
    foreach ($line in $aLog) {
        Assert-True ($line.reuse -eq $true) 'Every run here had reuse on.'
        Assert-True ($line.elapsedSeconds -is [double] -or $line.elapsedSeconds -is [long] -or $line.elapsedSeconds -is [int]) "elapsedSeconds must be a number. Got: $($line.elapsedSeconds)"
        Assert-True (-not [string]::IsNullOrWhiteSpace([string] $line.startedAtUtc)) 'Every line must say when it started.'
        Assert-True ($null -ne $line.PSObject.Properties['revision'] -and $null -ne $line.PSObject.Properties['budgetWarnings']) 'Every line must carry revision and budgetWarnings.'
    }
}
Invoke-TestCase 'A budget warning prints and the exit code stays 0' {
    Assert-True ($null -eq $aError) "The scenario failed to run: $aError"
    Assert-True ($aRuns[0].ExitCode -eq 0) "A budget warning must not fail the run. Output: $($aRuns[0].Output)"
    Assert-True ($aRuns[0].Output -match 'BUDGET Slow\.Tests\.ps1: [\d.]+ s against a budget of 5\.0 s \(\+\d+ %\)') "Expected the BUDGET line. Output: $($aRuns[0].Output)"
    Assert-True ((@($aLog[0].budgetWarnings) -join ',') -eq 'Slow.Tests.ps1') "The log line must name the warned Suite. Got: $(@($aLog[0].budgetWarnings) -join ',')"
}

Invoke-TestCase 'A reused Suite never warns' {
    Assert-True ($null -eq $aError) "The scenario failed to run: $aError"
    Assert-True ($aRuns[1].Output -match 'REUSED Slow\.Tests\.ps1') "Slow must be reused in run 2. Output: $($aRuns[1].Output)"
    Assert-True ($aRuns[1].Output -notmatch 'BUDGET') "A reused Suite took no time, so it must not warn. Output: $($aRuns[1].Output)"
    Assert-True (@($aLog[1].budgetWarnings).Count -eq 0) 'Run 2 must log no budget warning.'
}
Remove-TempRoot $a

# Scenario B: one eligible Suite, with evidence from a first Gate run.
$b = New-GateFixture -Suite ([ordered]@{ 'Quick.Tests.ps1' = @{ Reuse = [ordered]@{ eligible = $true } } })
$bError = $null
try { $bFirst = Invoke-GateRunner -Root $b -Gate } catch { $bError = $_.Exception.Message }

Invoke-TestCase 'A Gate run where every Suite is reused still passes' {
    Assert-True ($null -eq $bError) "The scenario failed to run: $bError"
    Assert-True ($bFirst.ExitCode -eq 0) "The first run must pass. Output: $($bFirst.Output)"
    $run = Invoke-GateRunner -Root $b -Gate
    Assert-True ($run.ExitCode -eq 0) "A run with nothing left to run must pass. Output: $($run.Output)"
    Assert-True ((Get-RunCount $b 'Quick.Tests.ps1') -eq 1) 'The Suite must not run again.'
    Assert-True ($run.Output -match 'All 1 suite\(s\) passed\.') "Expected the all-passed line. Output: $($run.Output)"
}

Invoke-TestCase 'Inside GitHub Actions the Gate never reuses' {
    Assert-True ($null -eq $bError) "The scenario failed to run: $bError"
    $before = Get-RunCount $b 'Quick.Tests.ps1'
    $run = Invoke-GateRunner -Root $b -Gate -Environment @{ GITHUB_ACTIONS = 'true' }
    Assert-True ($run.ExitCode -eq 0) "The run must pass. Output: $($run.Output)"
    Assert-True ($run.Output -match 'Gate evidence: off \(GitHub Actions\)') "Expected the off line with its reason. Output: $($run.Output)"
    Assert-True ((Get-RunCount $b 'Quick.Tests.ps1') -eq $before + 1) 'CI must run the Suite even with evidence present.'
}

Invoke-TestCase 'AHKFLOW_GATE_REUSE=off stops reuse and writes no evidence' {
    Assert-True ($null -eq $bError) "The scenario failed to run: $bError"
    Remove-Item -LiteralPath (Join-Path $b 'evidence') -Recurse -Force -ErrorAction SilentlyContinue
    $before = Get-RunCount $b 'Quick.Tests.ps1'
    $run = Invoke-GateRunner -Root $b -Gate -Environment @{ AHKFLOW_GATE_REUSE = 'off' }
    Assert-True ($run.ExitCode -eq 0) "The run must pass. Output: $($run.Output)"
    Assert-True ($run.Output -match 'Gate evidence: off \(AHKFLOW_GATE_REUSE=off\)') "Expected the off line with its reason. Output: $($run.Output)"
    Assert-True ((Get-RunCount $b 'Quick.Tests.ps1') -eq $before + 1) 'The Suite must run.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $b 'evidence'))) 'With reuse off, no evidence may be written.'
}

Invoke-TestCase 'Without -Gate the runner prints no evidence line and writes no log line' {
    Assert-True ($null -eq $bError) "The scenario failed to run: $bError"
    Invoke-GateRunner -Root $b -Gate | Out-Null   # evidence again, so a reuse would be possible
    $before = Get-RunCount $b 'Quick.Tests.ps1'
    $logBefore = (Get-GateLogLine $b).Count
    $run = Invoke-GateRunner -Root $b
    Assert-True ($run.ExitCode -eq 0) "The run must pass. Output: $($run.Output)"
    Assert-True ($run.Output -notmatch 'Gate evidence') "Without -Gate the output must not change. Output: $($run.Output)"
    Assert-True ((Get-RunCount $b 'Quick.Tests.ps1') -eq $before + 1) 'Without -Gate nothing is reused.'
    Assert-True ((Get-GateLogLine $b).Count -eq $logBefore) 'Without -Gate no log line is written.'
}
Remove-TempRoot $b

# Scenario C: two eligible Suites in one run. One fails. The other changes its own extra input
# while it runs.
$c = New-GateFixture -Suite ([ordered]@{
        'Fail.Tests.ps1' = @{ Reuse = [ordered]@{ eligible = $true }; Body = @('exit 1') }
        'Grow.Tests.ps1' = @{ Reuse = [ordered]@{ eligible = $true; extraInputs = @('tests/grow.json') }; Body = @() }
    })
$cError = $null
try {
    $grow = Join-Path $c 'tests\grow.json'
    Set-Content -LiteralPath $grow -Value '{ "n": 0 }' -Encoding utf8
    Add-Content -LiteralPath (Join-Path $c 'tests\Grow.Tests.ps1') -Value "Add-Content -LiteralPath $(ConvertTo-ScriptLiteral $grow) -Value ' '"
    $cRun = Invoke-GateRunner -Root $c -Gate
}
catch { $cError = $_.Exception.Message }

Invoke-TestCase 'A failed Suite leaves no evidence' {
    Assert-True ($null -eq $cError) "The scenario failed to run: $cError"
    Assert-True ($cRun.ExitCode -ne 0) "The run must fail. Output: $($cRun.Output)"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $c 'evidence\Fail.Tests.ps1'))) 'A failed Suite must leave no evidence.'
}

Invoke-TestCase 'A Suite whose input changed during its run leaves no evidence' {
    Assert-True ($null -eq $cError) "The scenario failed to run: $cError"
    Assert-True ((Get-RunCount $c 'Grow.Tests.ps1') -eq 1) 'The Suite must have run.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $c 'evidence\Grow.Tests.ps1'))) 'Evidence for inputs that changed during the run must not be written.'
}
Remove-TempRoot $c

if ($script:Failures.Count -gt 0) {
    Write-Host ''
    Write-Host "FAILED: $($script:Failures.Count) test(s)" -ForegroundColor Red
    foreach ($failure in $script:Failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host ''
Write-Host 'Gate evidence tests passed.' -ForegroundColor Green
