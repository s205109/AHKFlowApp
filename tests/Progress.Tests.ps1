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

    { Get-Content -LiteralPath (Join-Path $folder 'demo.json') -Raw | ConvertFrom-Json } | ForEach-Object { $_ } | Out-Null
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force
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
