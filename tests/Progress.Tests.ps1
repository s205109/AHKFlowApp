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
# prove Move-Item specifically: once the save has finished, a replaced file and a rewritten
# file look the same on disk, and telling them apart needs the file identity, which this
# repository has no way to read.

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
    'NaN'          = 'NaN'
    'Infinity'     = 'Infinity'
    '-Infinity'    = '-Infinity'
    'a negative'   = '-5'
    'far too big'  = '1e400'
    'not a number' = 'banana'
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
