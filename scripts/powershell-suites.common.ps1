#Requires -Version 7.0
# The suite inventory. Backlog 126.
#
# tests/powershell-suites.json is the one record of which PowerShell suites exist, which CI jobs
# run each of them, whether a suite may share the machine with another, and how long it took when
# somebody last measured it. The runner reads that file before it starts anything.
#
# Dot-source it from a runner:  . "$PSScriptRoot\powershell-suites.common.ps1"
#
# Three functions:
#   Read-SuiteManifest   read and validate the manifest against the files on disk
#   Select-SuiteEntry    turn the inventory plus an optional pattern into the run's selection
#   Get-SuiteSchedule    order the selection longest-first, using local history over the baseline
#
# This file targets 7.0 because run-powershell-suites.ps1 does. It does not call Set-StrictMode:
# that call leaks from a dot-sourced file into the caller's scope, and the runner sets it itself.

$script:KnownJob = @('invariants', 'suites', 'codex-parity')
$script:KnownExecution = @('parallel', 'exclusive')

function Read-SuiteManifest {
    <#
      Returns one object per manifest entry, or throws. Every check runs before the caller starts
      a child process, because a manifest we cannot trust means we cannot trust the coverage.
    #>
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $DiscoveredName
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Suite manifest not found: $Path. Every suite folder needs a powershell-suites.json beside its suites."
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    try {
        $parsed = $raw | ConvertFrom-Json
    } catch {
        throw "Suite manifest is not valid JSON: $Path. $($_.Exception.Message)"
    }

    if ($parsed -isnot [System.Management.Automation.PSCustomObject] -or
        $null -eq $parsed.PSObject.Properties['suites']) {
        throw "Suite manifest has no 'suites' array: $Path"
    }

    $entries = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($item in @($parsed.suites)) {
        foreach ($field in @('name', 'jobs', 'execution')) {
            if ($null -eq $item.PSObject.Properties[$field]) {
                throw "Suite manifest entry has no '$field': $Path"
            }
        }

        $name = [string] $item.name
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw "Suite manifest holds an entry with an empty name: $Path"
        }
        if (-not $seen.Add($name)) {
            throw "Suite manifest names '$name' more than once: $Path"
        }

        $jobs = @($item.jobs | ForEach-Object { [string] $_ })
        if ($jobs.Count -eq 0) {
            throw "Suite '$name' has an empty jobs array: $Path"
        }
        foreach ($job in $jobs) {
            if ($script:KnownJob -notcontains $job) {
                throw "Suite '$name' names an unknown job '$job'. Known jobs: $($script:KnownJob -join ', '). File: $Path"
            }
        }

        $execution = [string] $item.execution
        if ($script:KnownExecution -notcontains $execution) {
            throw "Suite '$name' names an unknown execution '$execution'. Known values: $($script:KnownExecution -join ', '). File: $Path"
        }

        $reason = if ($null -ne $item.PSObject.Properties['reason']) { [string] $item.reason } else { $null }
        if ($execution -eq 'exclusive' -and [string]::IsNullOrWhiteSpace($reason)) {
            throw "Suite '$name' is exclusive, so it needs a non-empty reason saying what it cannot share: $Path"
        }

        $baseline = $null
        if ($null -ne $item.PSObject.Properties['baselineSeconds'] -and $null -ne $item.baselineSeconds) {
            $number = 0.0
            $parsedOk = [double]::TryParse(
                [string] $item.baselineSeconds,
                [System.Globalization.NumberStyles]::Float,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [ref] $number)

            # TryParse accepts 'NaN' and 'Infinity', and either one breaks the schedule quietly.
            # A duration must be a real, positive number of seconds or absent.
            if (-not $parsedOk -or [double]::IsNaN($number) -or [double]::IsInfinity($number) -or $number -le 0.0) {
                throw "Suite '$name' has an unusable baselineSeconds '$($item.baselineSeconds)'. Use a number above zero, or null. File: $Path"
            }
            $baseline = $number
        }

        $entries.Add([pscustomobject]@{
                Name            = $name
                Jobs            = $jobs
                Execution       = $execution
                Reason          = $reason
                BaselineSeconds = $baseline
            })
    }

    # One-to-one against the folder, in both directions. A suite missing from the manifest would
    # silently stop running; an entry with no file is a rename nobody finished.
    $discovered = [System.Collections.Generic.HashSet[string]]::new(
        [string[]] $DiscoveredName, [System.StringComparer]::OrdinalIgnoreCase)

    $missing = @($DiscoveredName | Where-Object { -not $seen.Contains($_) } | Sort-Object)
    if ($missing.Count -gt 0) {
        throw "These suite files are missing from $Path`: $($missing -join ', ')"
    }

    $stale = @($entries | Where-Object { -not $discovered.Contains($_.Name) } | ForEach-Object { $_.Name } | Sort-Object)
    if ($stale.Count -gt 0) {
        throw "These manifest entries name no suite file: $($stale -join ', '). File: $Path"
    }

    return $entries.ToArray()
}

function Select-SuiteEntry {
    <#
      The suites this run covers. With no pattern that is every suite in the 'suites' job, which is
      what the runner has always done when given no arguments.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Entry,
        [string[]] $Pattern
    )

    $inJob = @($Entry | Where-Object { $_.Jobs -contains 'suites' })

    if (-not $Pattern -or $Pattern.Count -eq 0) {
        if ($inJob.Count -eq 0) {
            throw 'No suite belongs to the suites job. A run with nothing to run must not look green.'
        }
        return ($inJob | Sort-Object Name)
    }

    $selected = [System.Collections.Generic.List[object]]::new()
    $chosen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($wildcard in $Pattern) {
        $matched = @($inJob | Where-Object { $_.Name -like $wildcard })
        if ($matched.Count -eq 0) {
            # Say which kind of miss it was. A name that exists but sits outside the job is a
            # different mistake from a name nothing matches, and the two need different fixes.
            $elsewhere = @($Entry | Where-Object { $_.Name -like $wildcard })
            if ($elsewhere.Count -gt 0) {
                throw "-Suite '$wildcard' matches only suites outside the suites job: $($elsewhere.Name -join ', ')"
            }
            throw "-Suite '$wildcard' matched no suite."
        }

        foreach ($item in $matched) {
            if ($chosen.Add($item.Name)) { $selected.Add($item) }
        }
    }

    if ($selected.Count -eq 0) {
        throw 'The selection ran no suites. A run with nothing to run must not look green.'
    }

    return ($selected | Sort-Object Name)
}

function Get-SuiteSchedule {
    <#
      The selection, ordered longest first, each entry carrying an EffectiveSeconds member.

      A suite with no duration at all sorts first. Starting it last would risk it being the only
      thing still running at the end, which is the one shape a parallel run must avoid.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Entry,
        [hashtable] $History
    )

    if ($null -eq $History) { $History = @{} }

    $withDuration = foreach ($item in $Entry) {
        $seconds = $null

        # Local history wins. It measured this machine; the committed baseline measured another.
        if ($History.ContainsKey($item.Name)) {
            $candidate = [double] $History[$item.Name]
            if (-not [double]::IsNaN($candidate) -and -not [double]::IsInfinity($candidate) -and $candidate -gt 0.0) {
                $seconds = $candidate
            }
        }

        if ($null -eq $seconds) { $seconds = $item.BaselineSeconds }
        $effective = if ($null -eq $seconds) { [double]::PositiveInfinity } else { [double] $seconds }

        $copy = $item.PSObject.Copy()
        Add-Member -InputObject $copy -NotePropertyName 'EffectiveSeconds' -NotePropertyValue $effective -Force
        $copy
    }

    # Name is the tie-breaker, so two runs on one machine schedule the same way.
    return @($withDuration | Sort-Object -Property @{ Expression = 'EffectiveSeconds'; Descending = $true }, @{ Expression = 'Name'; Descending = $false })
}
