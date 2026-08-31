#Requires -Version 7.0

# Backlog 123. scripts/progress.common.ps1 prints a progress line before each unit of a long
# runner and remembers each unit's seconds for the next run's estimate. This suite pins the
# estimate with full, partial, and absent history, proves an interrupted unit records nothing,
# and proves the timings file is written through a temporary file.
#
# Run it by hand with:  pwsh ./tests/Progress.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts/progress.common.ps1')

$failures = @()

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) {
        $script:failures += $Message
    }
}

function New-ProgressTestRoot {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) "progress-tests-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    return $root
}

function Set-History {
    param(
        [Parameter(Mandatory)][string] $Root,
        [Parameter(Mandatory)][string] $RunnerKey,
        [Parameter(Mandatory)][hashtable] $Timings
    )

    $folder = Join-Path $Root 'TestResults\progress'
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $payload = [ordered]@{}
    foreach ($key in $Timings.Keys) { $payload[$key] = $Timings[$key] }
    ([pscustomobject] $payload) | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $folder "$RunnerKey.json") -Encoding UTF8
}

function Get-StartLine {
    param(
        [Parameter(Mandatory)][object] $Tracker,
        [Parameter(Mandatory)][string] $Name
    )

    $captured = Start-ProgressUnit -Tracker $Tracker -Name $Name 6>&1
    return (($captured | Out-String).Trim())
}

# --- The estimate with full history ---

$root = New-ProgressTestRoot
try {
    Set-History -Root $root -RunnerKey 'demo' -Timings @{ 'a.Tests.ps1' = 10; 'b.Tests.ps1' = 20; 'c.Tests.ps1' = 30 }
    $tracker = New-ProgressTracker -RunnerKey 'demo' -RepoRoot $root -Unit @('a.Tests.ps1', 'b.Tests.ps1', 'c.Tests.ps1')

    $line = Get-StartLine -Tracker $tracker -Name 'a.Tests.ps1'
    Assert-True ($line -like '`[1/3`]*') "Full history: line must start with the position, got: $line"
    Assert-True ($line -match 'a\.Tests\.ps1') "Full history: line must name the unit, got: $line"
    Assert-True ($line -match 'remaining ~1m00s') "Full history: 10+20+30 must read as ~1m00s, got: $line"
    Assert-True (-not ($line -match 'no history')) "Full history: no missing-history note is expected, got: $line"
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}

# --- The estimate with partial history ---

$root = New-ProgressTestRoot
try {
    Set-History -Root $root -RunnerKey 'demo' -Timings @{ 'a.Tests.ps1' = 10; 'c.Tests.ps1' = 30 }
    $tracker = New-ProgressTracker -RunnerKey 'demo' -RepoRoot $root -Unit @('a.Tests.ps1', 'b.Tests.ps1', 'c.Tests.ps1')

    $line = Get-StartLine -Tracker $tracker -Name 'a.Tests.ps1'
    Assert-True ($line -match 'remaining ~40s') "Partial history: 10+30 must read as ~40s, got: $line"
    Assert-True ($line -match '\(1 unit has no history\)') "Partial history: one unit is missing, got: $line"
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}

# --- The estimate with no history ---

$root = New-ProgressTestRoot
try {
    $tracker = New-ProgressTracker -RunnerKey 'demo' -RepoRoot $root -Unit @('a.Tests.ps1', 'b.Tests.ps1', 'c.Tests.ps1')

    $line = Get-StartLine -Tracker $tracker -Name 'a.Tests.ps1'
    Assert-True ($line -match 'remaining unknown') "No history: the line must say the time left is unknown, got: $line"
    Assert-True ($line -match '\(3 units have no history\)') "No history: all three units are missing, got: $line"
    Assert-True (-not ($line -match '~')) "No history: no number is printed, got: $line"
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}

# --- A unit that does not finish records nothing ---

$root = New-ProgressTestRoot
try {
    $tracker = New-ProgressTracker -RunnerKey 'demo' -RepoRoot $root -Unit @('a.Tests.ps1', 'b.Tests.ps1')

    Get-StartLine -Tracker $tracker -Name 'a.Tests.ps1' | Out-Null
    Stop-ProgressUnit -Tracker $tracker
    Get-StartLine -Tracker $tracker -Name 'b.Tests.ps1' | Out-Null
    # b never stops, as if the run was interrupted here.
    Save-ProgressTimings -Tracker $tracker

    $saved = Get-Content -LiteralPath (Join-Path $root 'TestResults\progress\demo.json') -Raw | ConvertFrom-Json
    Assert-True ($null -ne $saved.'a.Tests.ps1') "Interrupted run: the finished unit must be saved, got: $saved"
    $names = @($saved.PSObject.Properties.Name)
    Assert-True ($names -notcontains 'b.Tests.ps1') "Interrupted run: the unfinished unit must not be saved, got: $($names -join ', ')"
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}

# --- The save writes through a temporary file and leaves none behind ---

$root = New-ProgressTestRoot
try {
    $tracker = New-ProgressTracker -RunnerKey 'demo' -RepoRoot $root -Unit @('a.Tests.ps1')
    Get-StartLine -Tracker $tracker -Name 'a.Tests.ps1' | Out-Null
    Stop-ProgressUnit -Tracker $tracker
    Save-ProgressTimings -Tracker $tracker

    $folder = Join-Path $root 'TestResults\progress'
    Assert-True (Test-Path -LiteralPath (Join-Path $folder 'demo.json')) 'Atomic save: the timings file must exist.'
    $leftovers = @(Get-ChildItem -LiteralPath $folder -Filter '*.tmp' -ErrorAction SilentlyContinue)
    $leftoverNames = ($leftovers | ForEach-Object { $_.Name }) -join ', '
    Assert-True ($leftovers.Count -eq 0) "Atomic save: no temporary file may be left behind, found: $leftoverNames"

    # Run the parse, do not pipe a script block. A script block piped as a value is passed
    # along unexecuted, so the assertion it carried never ran.
    $parsed = $null
    $parseError = $null
    try {
        $parsed = Get-Content -LiteralPath (Join-Path $folder 'demo.json') -Raw | ConvertFrom-Json
    }
    catch {
        $parseError = $_.Exception.Message
    }

    Assert-True ($null -eq $parseError) "Atomic save: the saved file must parse as JSON, got: $parseError"
    Assert-True ($null -ne $parsed -and $null -ne $parsed.'a.Tests.ps1') 'Atomic save: the saved file must hold the unit it recorded.'
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}

# --- The save replaces an existing file completely, leaving nothing of the old content ---
#
# This proves the destination is never left holding a mix of old and new text. It does not
# prove which replacement call was used: once the save has finished, a replaced file and a
# rewritten file look the same on disk, and telling them apart needs the file identity, which
# this repository has no way to read.

$root = New-ProgressTestRoot
try {
    # An old file that is much longer than the new one. A write that did not replace the whole
    # file would leave the tail of this text behind.
    Set-History -Root $root -RunnerKey 'demo' -Timings @{
        'old-one.Tests.ps1'   = 11
        'old-two.Tests.ps1'   = 22
        'old-three.Tests.ps1' = 33
        'old-four.Tests.ps1'  = 44
        'old-five.Tests.ps1'  = 55
    }

    $tracker = New-ProgressTracker -RunnerKey 'demo' -RepoRoot $root -Unit @('new.Tests.ps1')
    Get-StartLine -Tracker $tracker -Name 'new.Tests.ps1' | Out-Null
    Stop-ProgressUnit -Tracker $tracker
    Save-ProgressTimings -Tracker $tracker

    $text = Get-Content -LiteralPath (Join-Path $root 'TestResults\progress\demo.json') -Raw
    Assert-True ($text -notmatch 'old-') "Replace: no part of the old file may survive, got: $text"
    $saved = $text | ConvertFrom-Json
    Assert-True ($null -ne $saved.'new.Tests.ps1') 'Replace: the new unit must be in the saved file.'
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}

# --- A history value that is not a usable number is treated as no history ---
#
# Double.TryParse accepts 'NaN' and 'Infinity', and the estimate then converts the total to an
# Int32, which throws. A timings file is an optional convenience, so a value it cannot use must
# never stop the runner that reads it.

$badValues = @{
    'NaN'                    = 'NaN'
    'Infinity'               = 'Infinity'
    '-Infinity'              = '-Infinity'
    'a negative'             = '-5'
    'larger than a Double'   = '1e400'
    'not a number'           = 'banana'

    # 1e400 above parses as Infinity, so it never reaches the one-year limit. This value is a
    # real number, one second past that limit, which is the only way to check the limit itself.
    'one second past a year' = '31536001'
}

foreach ($case in $badValues.GetEnumerator()) {
    $root = New-ProgressTestRoot
    try {
        # Written as raw JSON so the value reaches the reader exactly as a real file would carry it.
        $folder = Join-Path $root 'TestResults\progress'
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $folder 'demo.json') -Encoding UTF8 `
            -Value ('{ "a.Tests.ps1": "' + $case.Value + '", "b.Tests.ps1": 12 }')

        $tracker = New-ProgressTracker -RunnerKey 'demo' -RepoRoot $root -Unit @('a.Tests.ps1', 'b.Tests.ps1')

        $line = $null
        $thrown = $null
        try {
            $line = Get-StartLine -Tracker $tracker -Name 'a.Tests.ps1'
        }
        catch {
            $thrown = $_.Exception.Message
        }

        Assert-True ($null -eq $thrown) "Bad history ($($case.Key)): the progress line must not throw, got: $thrown"
        Assert-True ($line -match '\(1 unit has no history\)') "Bad history ($($case.Key)): the bad value must count as no history, got: $line"
        Assert-True ($line -match 'remaining ~12s') "Bad history ($($case.Key)): the good value must still be used, got: $line"
    }
    finally {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}

# --- Valid JSON with the wrong top-level shape is treated as no history ---

$shapeCases = @(
    @{ Name = 'an array';          Json = '[10, 20]'; Unit = 'Count' }
    @{ Name = 'a string';          Json = '"text"';   Unit = 'Length' }
    @{ Name = 'a number';          Json = '42';       Unit = 'unit' }
    @{ Name = 'null';              Json = 'null';     Unit = 'unit' }
    @{ Name = 'truncated JSON';    Json = '{"unit":'; Unit = 'unit' }
)

foreach ($case in $shapeCases) {
    $root = New-ProgressTestRoot
    try {
        $folder = Join-Path $root 'TestResults\progress'
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $folder 'demo.json') -Encoding UTF8 -Value $case.Json

        $tracker = New-ProgressTracker -RunnerKey 'demo' -RepoRoot $root -Unit @($case.Unit)
        $line = Get-StartLine -Tracker $tracker -Name $case.Unit

        Assert-True ($line -match 'remaining unknown') "History shape ($($case.Name)): a non-object must be ignored, got: $line"
        Assert-True ($line -match '1 unit has no history') "History shape ($($case.Name)): the unit must count as unknown, got: $line"
    }
    finally {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}

# --- The value exactly on the one-year limit is still used ---
#
# The case above rejects one second past the limit. Without this one, moving the limit to zero
# would keep every test green.

$root = New-ProgressTestRoot
try {
    $folder = Join-Path $root 'TestResults\progress'
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $folder 'demo.json') -Encoding UTF8 -Value '{ "a.Tests.ps1": 31536000 }'

    $tracker = New-ProgressTracker -RunnerKey 'demo' -RepoRoot $root -Unit @('a.Tests.ps1')
    $line = Get-StartLine -Tracker $tracker -Name 'a.Tests.ps1'

    Assert-True ($line -notmatch 'no history') "On the limit: the value must be used, got: $line"
    # 31536000 seconds is 525600 minutes exactly. Checking the number, not just that some number
    # appeared, is what catches a clamp that quietly replaces the real total.
    Assert-True ($line -match 'remaining ~525600m00s') "On the limit: the estimate must be the value itself, got: $line"
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}

# --- A total larger than one year is printed, not clamped back to one year ---
#
# The one-year limit belongs to a single unit. Several units, each inside that limit, can add up
# to more, and the line used to print one year for any such run.

$root = New-ProgressTestRoot
try {
    $folder = Join-Path $root 'TestResults\progress'
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    # Two units of 20,000,000 seconds each. Both are inside the one-year unit limit; the total is
    # 40,000,000, which is not. That is 666666 minutes and 40 seconds.
    Set-Content -LiteralPath (Join-Path $folder 'demo.json') -Encoding UTF8 `
        -Value '{ "a.Tests.ps1": 20000000, "b.Tests.ps1": 20000000 }'

    $tracker = New-ProgressTracker -RunnerKey 'demo' -RepoRoot $root -Unit @('a.Tests.ps1', 'b.Tests.ps1')
    $line = Get-StartLine -Tracker $tracker -Name 'a.Tests.ps1'

    Assert-True ($line -match 'remaining ~666666m40s') "Over a year: the total must be printed in full, got: $line"
    Assert-True ($line -notmatch '525600m') "Over a year: the total must not be clamped back to one year, got: $line"
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}

# --- Timings are kept for the repository's own suites, whether or not the caller named them ---
#
# The decision used to test whether -SuiteRoot was passed, so naming the real folder ran the real
# suites and then stored nothing.

$root = New-ProgressTestRoot
try {
    $realSuites = Join-Path $root 'tests'
    $fakeSuites = Join-Path $root 'fake-suites'
    New-Item -ItemType Directory -Path $realSuites -Force | Out-Null
    New-Item -ItemType Directory -Path $fakeSuites -Force | Out-Null

    Assert-True (Test-ProgressTimingsWanted -SuiteRoot $realSuites -DefaultSuiteRoot $realSuites) `
        'Timings wanted: the repository''s own suites must keep their timings.'
    Assert-True (-not (Test-ProgressTimingsWanted -SuiteRoot $fakeSuites -DefaultSuiteRoot $realSuites)) `
        'Timings wanted: a folder of fake suites must not keep timings.'

    # The same folder named a different way is still the same folder.
    Assert-True (Test-ProgressTimingsWanted -SuiteRoot ($realSuites + '\') -DefaultSuiteRoot $realSuites) `
        'Timings wanted: a trailing separator must not change the answer.'
    Assert-True (Test-ProgressTimingsWanted -SuiteRoot $realSuites.ToUpperInvariant() -DefaultSuiteRoot $realSuites) `
        'Timings wanted: a different case must not change the answer.'
    Assert-True (Test-ProgressTimingsWanted -SuiteRoot (Join-Path (Join-Path $realSuites '..') 'tests') -DefaultSuiteRoot $realSuites) `
        'Timings wanted: a path that walks up and back must not change the answer.'

    # Nothing to compare against is not a reason to write into the store.
    Assert-True (-not (Test-ProgressTimingsWanted -SuiteRoot $realSuites -DefaultSuiteRoot (Join-Path $root 'missing'))) `
        'Timings wanted: a default folder that does not exist must not keep timings.'
    Assert-True (-not (Test-ProgressTimingsWanted -SuiteRoot '' -DefaultSuiteRoot $realSuites)) `
        'Timings wanted: an empty suite root must not keep timings.'
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}

# --- The progress module runs under Windows PowerShell 5.1 ---

$windowsPowerShell = Get-Command powershell.exe -ErrorAction SilentlyContinue
if ($windowsPowerShell) {
    $root = New-ProgressTestRoot
    try {
        Set-History -Root $root -RunnerKey 'windows-powershell' -Timings @{ 'unit' = 12; 'old' = 99 }
        $modulePath = Join-Path $repoRoot 'scripts\progress.common.ps1'
        $output = & $windowsPowerShell.Source -NoProfile -Command @"
`$ErrorActionPreference = 'Stop'
. '$modulePath'
`$tracker = New-ProgressTracker -RunnerKey 'windows-powershell' -RepoRoot '$root' -Unit @('unit')
`$line = (Start-ProgressUnit -Tracker `$tracker -Name 'unit' 6>&1 | Out-String)
if (`$line -notmatch 'remaining ~12s') { throw "History was not read: `$line" }
Stop-ProgressUnit -Tracker `$tracker
Save-ProgressTimings -Tracker `$tracker
`$saved = Get-Content -LiteralPath (Join-Path '$root' 'TestResults\progress\windows-powershell.json') -Raw | ConvertFrom-Json
if (`$null -eq `$saved.unit) { throw 'The completed unit was not saved.' }
if (`$null -ne `$saved.PSObject.Properties['old']) { throw 'The old file was not replaced.' }
"@ 2>&1 | Out-String
        $exitCode = $LASTEXITCODE

        Assert-True ($exitCode -eq 0) "Windows PowerShell 5.1: module behavior must pass. Exit: $exitCode. Output: $output"
    }
    finally {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}
else {
    Write-Host 'Windows PowerShell 5.1 check skipped: powershell.exe is not available.' -ForegroundColor Yellow
}

# --- Runner keys for Fast and Integration do not collide ---

$root = New-ProgressTestRoot
try {
    $fast = New-ProgressTracker -RunnerKey 'test-fast.Fast' -RepoRoot $root -Unit @('P[Category!=Integration]')
    Get-StartLine -Tracker $fast -Name 'P[Category!=Integration]' | Out-Null
    Stop-ProgressUnit -Tracker $fast
    Save-ProgressTimings -Tracker $fast

    $integration = New-ProgressTracker -RunnerKey 'test-fast.Integration' -RepoRoot $root -Unit @('P[Category=Integration]')
    Get-StartLine -Tracker $integration -Name 'P[Category=Integration]' | Out-Null
    Stop-ProgressUnit -Tracker $integration
    Save-ProgressTimings -Tracker $integration

    $folder = Join-Path $root 'TestResults\progress'
    Assert-True (Test-Path -LiteralPath (Join-Path $folder 'test-fast.Fast.json')) 'Runner keys: the Fast timings file must exist.'
    Assert-True (Test-Path -LiteralPath (Join-Path $folder 'test-fast.Integration.json')) 'Runner keys: the Integration timings file must exist.'

    $fastSaved = Get-Content -LiteralPath (Join-Path $folder 'test-fast.Fast.json') -Raw | ConvertFrom-Json
    $integrationSaved = Get-Content -LiteralPath (Join-Path $folder 'test-fast.Integration.json') -Raw | ConvertFrom-Json
    Assert-True ($null -ne $fastSaved.'P[Category!=Integration]') 'Runner keys: the Fast file keeps its own unit.'
    Assert-True ($null -ne $integrationSaved.'P[Category=Integration]') 'Runner keys: the Integration file keeps its own unit.'
    Assert-True ($null -eq $fastSaved.PSObject.Properties['P[Category=Integration]']) 'Runner keys: the Fast file must not hold the Integration unit.'
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}

# --- A timings file that cannot be written does not fail the run ---
#
# Save-ProgressTimings runs after the tests have already passed. Timings are an estimate for the
# next run, and Read-ProgressHistory already treats them as optional. Letting a write error escape
# turned a green test run into a failing runner, and stopped the summary that comes after the save.
#
# The destination file is held open with no sharing, so the move into place fails for a real
# reason rather than a stubbed one.

$root = New-ProgressTestRoot
$lockStream = $null
try {
    $folder = Join-Path $root 'TestResults\progress'
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $historyPath = Join-Path $folder 'locked.json'
    Set-Content -LiteralPath $historyPath -Value '{}' -Encoding UTF8

    $lockStream = [System.IO.File]::Open(
        $historyPath,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None)

    $tracker = New-ProgressTracker -RunnerKey 'locked' -RepoRoot $root -Unit @('a.Tests.ps1')
    Get-StartLine -Tracker $tracker -Name 'a.Tests.ps1' | Out-Null
    Stop-ProgressUnit -Tracker $tracker

    $threw = $false
    $warnings = $null
    try {
        Save-ProgressTimings -Tracker $tracker -WarningVariable warnings 3>$null
    }
    catch {
        $threw = $true
    }

    Assert-True (-not $threw) 'Locked timings: a file that cannot be written must not fail the run.'
    Assert-True ($warnings.Count -ge 1) 'Locked timings: the failure must be reported as a warning, not swallowed.'

    $leftovers = @(Get-ChildItem -LiteralPath $folder -Filter '*.tmp' -File | ForEach-Object { $_.Name })
    Assert-True ($leftovers.Count -eq 0) `
        "Locked timings: the temporary file must be cleaned up, found: $($leftovers -join ', ')"
}
finally {
    if ($lockStream) { $lockStream.Dispose() }
    Remove-Item -LiteralPath $root -Recurse -Force
}

# --- A history path the filesystem itself rejects counts as no history ---
#
# Test-Path does not always answer with $true or $false. A path holding a null character makes
# it throw, and every runner that reads history sets $ErrorActionPreference = 'Stop', so a check
# left outside the try would end a green run over a file that is only an optional convenience.

$threw = $false
$badPathHistory = $null
try {
    $badPathHistory = Read-ProgressHistory -Path "C:\progress`0broken.json"
}
catch {
    $threw = $true
}

Assert-True (-not $threw) 'Bad history path: a path Test-Path rejects must not throw out of Read-ProgressHistory.'
Assert-True ($null -ne $badPathHistory -and $badPathHistory.Count -eq 0) `
    'Bad history path: a path that cannot be checked must count as no history.'

# --- Report ---

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Host ''
        Write-Host $failure -ForegroundColor Red
    }
    Write-Host ''
    throw "Progress tests failed with $($failures.Count) problem(s). See the detail above."
}

Write-Host 'Progress tests passed.' -ForegroundColor Green
