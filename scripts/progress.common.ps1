#Requires -Version 5.1
# Shared progress lines for the long test runners. Backlog 123.
#
# A long runner walks a list of units, one after another. Before each unit this module prints
# one line that carries the unit's position, its name, the time spent so far, and an estimate of
# the time left. The estimate comes from the previous run's per-unit seconds, kept in
# TestResults/progress/<runner key>.json. That folder is git-ignored, so the file never reaches
# a diff.
#
# Dot-source it from a runner:  . "$PSScriptRoot\progress.common.ps1"
#
# Four functions:
#   New-ProgressTracker   create a tracker over a named list of units
#   Start-ProgressUnit    start a unit and print its line
#   Stop-ProgressUnit     stop the current unit and record its seconds
#   Save-ProgressTimings  write the run's timings, once, through a temporary file
#
# This file targets 5.1 because run-powershell-suites.ps1 and test-fast.ps1 both dot-source it
# and both declare '#Requires -Version 5.1'. A '#Requires' inside a dot-sourced file is enforced.
#
# It does not call Set-StrictMode. That call leaks from a dot-sourced file into the caller's
# scope, and test-fast.ps1 does not run under strict mode. The two test suites for this module
# set strict mode themselves, so the functions are still checked under it.

# A number this module is willing to treat as one unit's seconds. One year is far past any real
# test suite, so a value above it is a broken file rather than a slow run.
$script:MaxProgressSeconds = 31536000.0

# The largest total the line will print. A run adds up the seconds of every unit still to come,
# and enough units can legitimately total more than one year, so the unit limit above is the
# wrong ceiling for a total. This one exists only to keep the Int32 conversion below in range.
$script:MaxProgressTotalSeconds = 2147483647.0

function Test-ProgressSeconds {
    param([double] $Seconds)

    if ([double]::IsNaN($Seconds) -or [double]::IsInfinity($Seconds)) { return $false }
    if ($Seconds -lt 0.0) { return $false }
    if ($Seconds -gt $script:MaxProgressSeconds) { return $false }
    return $true
}

function Format-ProgressDuration {
    param([double] $Seconds)

    # Held inside the range the Int32 conversion below can take, and no tighter. The one-year
    # limit belongs to a single unit, where the file is read; using it here would quietly print
    # one year for any run whose units add up to more than that.
    if ([double]::IsNaN($Seconds)) { $Seconds = 0.0 }
    $Seconds = [Math]::Max(0.0, [Math]::Min($script:MaxProgressTotalSeconds, $Seconds))

    $whole = [int][Math]::Round([Math]::Max(0.0, $Seconds))
    if ($whole -lt 60) {
        return "${whole}s"
    }

    $minutes = [Math]::Floor($whole / 60)
    $rest = $whole % 60
    return ('{0}m{1:d2}s' -f $minutes, $rest)
}

function Test-ProgressTimingsWanted {
    <#
      Whether a run should keep its timings.

      Only a run over the repository's own suites should, because the seconds a fake suite takes
      would poison the estimate the next real run reads. The question is which folder the run
      covers, not whether the caller passed an argument: naming the real folder is still a real
      run, and testing for the argument alone treated it as a fixture and stored nothing.

      Both paths are resolved first, so a trailing slash, a relative path, or different case all
      still count as the same folder.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string] $SuiteRoot,
        [Parameter(Mandatory)][AllowEmptyString()][string] $DefaultSuiteRoot
    )

    if ([string]::IsNullOrWhiteSpace($SuiteRoot) -or [string]::IsNullOrWhiteSpace($DefaultSuiteRoot)) {
        return $false
    }

    if (-not (Test-Path -LiteralPath $SuiteRoot) -or -not (Test-Path -LiteralPath $DefaultSuiteRoot)) {
        return $false
    }

    $left = (Resolve-Path -LiteralPath $SuiteRoot).ProviderPath.TrimEnd('\', '/')
    $right = (Resolve-Path -LiteralPath $DefaultSuiteRoot).ProviderPath.TrimEnd('\', '/')

    return $left.Equals($right, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-ProgressHistoryPath {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][string] $RunnerKey
    )

    return (Join-Path (Join-Path $RepoRoot 'TestResults\progress') "$RunnerKey.json")
}

function Read-ProgressHistory {
    param([Parameter(Mandatory)][string] $Path)

    $history = @{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $history
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $history
        }

        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($parsed -isnot [System.Management.Automation.PSCustomObject]) {
            return $history
        }

        $invariant = [System.Globalization.CultureInfo]::InvariantCulture
        $numberStyles = [System.Globalization.NumberStyles]::Float
        foreach ($property in $parsed.PSObject.Properties) {
            $number = 0.0
            if (-not [double]::TryParse([string]$property.Value, $numberStyles, $invariant, [ref] $number)) {
                continue
            }

            # Double.TryParse accepts 'NaN', 'Infinity', and a number too large for a Double,
            # and it accepts a negative. Each of those either stops the estimate outright, when
            # it is converted to an Int32, or quietly makes it wrong. A timings file is an
            # optional convenience, so an unusable value is dropped and counts as no history.
            if (-not (Test-ProgressSeconds -Seconds $number)) {
                continue
            }

            $history[$property.Name] = $number
        }
    }
    catch {
        # A history file we cannot read is the same as no history. The next finished run
        # rewrites it.
        return @{}
    }

    return $history
}

function New-ProgressTracker {
    param(
        [Parameter(Mandatory)][string] $RunnerKey,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $Unit,
        [string] $RepoRoot,

        # Print the lines, but read no history and save none. A run over a folder of fake units
        # uses this: the lines are still worth checking, while the timings of fake units must
        # never reach the store that a real run reads.
        [switch] $NoStore
    )

    if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
        $RepoRoot = Split-Path -Parent $PSScriptRoot
    }

    $historyPath = if ($NoStore) { $null } else { Get-ProgressHistoryPath -RepoRoot $RepoRoot -RunnerKey $RunnerKey }
    $history = if ($NoStore) { @{} } else { Read-ProgressHistory -Path $historyPath }

    return [pscustomobject]@{
        RunnerKey    = $RunnerKey
        Unit         = [string[]] $Unit
        RepoRoot     = $RepoRoot
        HistoryPath  = $historyPath
        History      = $history
        Completed    = [ordered]@{}
        Index        = 0
        CurrentName  = $null
        CurrentWatch = $null
        RunWatch     = [System.Diagnostics.Stopwatch]::StartNew()
    }
}

function Get-ProgressLine {
    param(
        [Parameter(Mandatory)][object] $Tracker,
        [Parameter(Mandatory)][string] $Name
    )

    $total = $Tracker.Unit.Count
    $position = $Tracker.Index
    $width = ([Math]::Max($total, 1)).ToString().Length

    $nameWidth = 0
    foreach ($unitName in $Tracker.Unit) {
        if ($unitName.Length -gt $nameWidth) { $nameWidth = $unitName.Length }
    }
    if ($Name.Length -gt $nameWidth) { $nameWidth = $Name.Length }

    $elapsed = Format-ProgressDuration -Seconds $Tracker.RunWatch.Elapsed.TotalSeconds

    # The units from the current one to the end are the ones still to run.
    $remainingUnits = @()
    if ($position -ge 1 -and ($position - 1) -lt $total) {
        $remainingUnits = @($Tracker.Unit[($position - 1)..($total - 1)])
    }
    elseif ($position -lt 1 -or $total -eq 0) {
        $remainingUnits = @($Name)
    }

    $known = @($remainingUnits | Where-Object { $Tracker.History.Contains($_) })
    $unknownCount = $remainingUnits.Count - $known.Count

    $noHistoryNote = ''
    if ($unknownCount -eq 1) {
        $noHistoryNote = ' (1 unit has no history)'
    }
    elseif ($unknownCount -gt 1) {
        $noHistoryNote = " ($unknownCount units have no history)"
    }

    if ($known.Count -eq 0) {
        $remainingText = "unknown$noHistoryNote"
    }
    else {
        $estimate = 0.0
        foreach ($unitName in $remainingUnits) {
            if (-not $Tracker.History.Contains($unitName)) { continue }

            if ($unitName -eq $Tracker.CurrentName -and $Tracker.CurrentWatch) {
                $left = $Tracker.History[$unitName] - $Tracker.CurrentWatch.Elapsed.TotalSeconds
                $estimate += [Math]::Max(0.0, $left)
            }
            else {
                $estimate += $Tracker.History[$unitName]
            }
        }

        $remainingText = "~$(Format-ProgressDuration -Seconds $estimate)$noHistoryNote"
    }

    # Right-align the position inside the width of the total, so the names line up.
    $positionText = '[' + ($position.ToString().PadLeft($width)) + '/' + $total + ']'
    $nameText = $Name.PadRight($nameWidth)

    return "$positionText $nameText  elapsed $elapsed  remaining $remainingText"
}

function Start-ProgressUnit {
    param(
        [Parameter(Mandatory)][object] $Tracker,
        [Parameter(Mandatory)][string] $Name
    )

    $Tracker.Index++
    $Tracker.CurrentName = $Name
    $Tracker.CurrentWatch = [System.Diagnostics.Stopwatch]::StartNew()

    Write-Host (Get-ProgressLine -Tracker $Tracker -Name $Name)
}

function Stop-ProgressUnit {
    param([Parameter(Mandatory)][object] $Tracker)

    if (-not $Tracker.CurrentWatch -or -not $Tracker.CurrentName) {
        return
    }

    $Tracker.CurrentWatch.Stop()
    # A unit records its seconds only when it finishes, so an interrupted run adds nothing.
    $Tracker.Completed[$Tracker.CurrentName] = [Math]::Round($Tracker.CurrentWatch.Elapsed.TotalSeconds, 1)
    $Tracker.CurrentName = $null
    $Tracker.CurrentWatch = $null
}

function Save-ProgressTimings {
    param([Parameter(Mandatory)][object] $Tracker)

    # A tracker made with -NoStore has no file to write.
    if (-not $Tracker.HistoryPath) {
        return
    }

    if ($Tracker.Completed.Count -eq 0) {
        return
    }

    $folder = Split-Path -Parent $Tracker.HistoryPath
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }

    $payload = [ordered]@{}
    foreach ($entry in $Tracker.Completed.GetEnumerator()) {
        $payload[$entry.Key] = $entry.Value
    }

    $json = ([pscustomobject] $payload) | ConvertTo-Json -Depth 4

    # Write once, through a temporary file that is then moved into place, so two runs at once
    # cannot leave a half-written file. Last writer wins, which is acceptable for an estimate.
    $temp = "$($Tracker.HistoryPath).$PID.tmp"
    Set-Content -LiteralPath $temp -Value $json -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $Tracker.HistoryPath -Force
}
