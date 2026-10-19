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

if ($script:Failures.Count -gt 0) {
    Write-Host ''
    Write-Host "FAILED: $($script:Failures.Count) test(s)" -ForegroundColor Red
    foreach ($failure in $script:Failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host ''
Write-Host 'Gate evidence tests passed.' -ForegroundColor Green
