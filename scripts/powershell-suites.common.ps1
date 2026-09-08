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

# Backlog 127. Every entry records the platforms a real run has passed it on, and the runner drops
# a suite whose platform does not include the one it is running on. The field is a rule, not a note:
# CodexSkillsHashParity is Linux-only because the bash script it compares against refuses under
# Windows Git Bash, and a field the runner ignored would let a future edit run it there anyway.
$script:KnownPlatform = @('windows', 'linux')

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
        foreach ($field in @('name', 'jobs', 'execution', 'platform')) {
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

        # Read the raw property before coercing it. The jobs check above coerces instead, so
        # "jobs": "suites" passes there as a one-element array. Backlog 127 requires platform to be
        # a JSON array, so the type of the parsed value is itself part of the contract:
        # ConvertFrom-Json returns [object[]] for an array and [string] for a scalar.
        $rawPlatform = $item.platform
        if ($rawPlatform -is [string]) {
            throw "Suite '$name' has a platform that is not an array. Write it as [`"$($rawPlatform)`"], with the brackets. File: $Path"
        }

        $platform = @($rawPlatform | ForEach-Object { [string] $_ })
        if ($platform.Count -eq 0) {
            throw "Suite '$name' has an empty platform array: $Path"
        }
        foreach ($value in $platform) {
            # -cnotcontains, not -notcontains. The plain operator ignores letter case, so 'LINUX'
            # would pass and be stored, and the manifest would hold a spelling the contract does not
            # name. The two values are exact.
            if ($script:KnownPlatform -cnotcontains $value) {
                throw "Suite '$name' names an unknown platform '$value'. Known platforms: $($script:KnownPlatform -join ', '). File: $Path"
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
                Platform        = $platform
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

# The platform this process is running on, as the manifest spells it. Backlog 127.
# $IsWindows and $IsLinux are automatic variables in PowerShell 7 on every platform, so no
# version check is needed. macOS throws rather than selecting nothing: a run with nothing to
# run must not look green, and a silent empty selection is exactly that.
function Get-CurrentSuitePlatform {
    if ($IsWindows) { return 'windows' }
    if ($IsLinux) { return 'linux' }
    throw "This platform is not one the suite manifest knows. Known platforms: $($script:KnownPlatform -join ', ')."
}

function Select-SuiteEntry {
    <#
      The suites this run covers: the ones this job runs, less the ones this platform does not.
      With no pattern that is every suite in the job, which is what the runner has always done
      when given no arguments.

      -Platform exists so a test can ask for the other platform without running there. Leave it
      out and the run uses the platform it is on.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Entry,
        [string[]] $Pattern,
        [string] $Job = 'suites',
        [string] $Platform
    )

    if ($script:KnownJob -notcontains $Job) {
        throw "-Job '$Job' is not a known job. Known jobs: $($script:KnownJob -join ', ')."
    }

    if ([string]::IsNullOrWhiteSpace($Platform)) {
        $Platform = Get-CurrentSuitePlatform
    } elseif ($script:KnownPlatform -cnotcontains $Platform) {
        throw "-Platform '$Platform' is not a known platform. Known platforms: $($script:KnownPlatform -join ', ')."
    }

    $inJob = @($Entry | Where-Object { $_.Jobs -contains $Job })
    $runnable = @($inJob | Where-Object { $_.Platform -contains $Platform })

    # Test for $null, never for truthiness. PowerShell reads a one-element array as its element,
    # so '-not @('''')' is true, and a blank wildcard would then select the whole job.
    if ($null -eq $Pattern -or $Pattern.Count -eq 0) {
        if ($inJob.Count -eq 0) {
            throw "No suite belongs to the $Job job. A run with nothing to run must not look green."
        }
        # Say which of the two emptied the selection. "No suite belongs to this job" and "every
        # suite in it is for the other platform" need different fixes.
        if ($runnable.Count -eq 0) {
            throw "Every suite in the $Job job is for another platform, so none runs on $Platform`: $(($inJob.Name | Sort-Object) -join ', '). A run with nothing to run must not look green."
        }
        return ($runnable | Sort-Object Name)
    }

    $selected = [System.Collections.Generic.List[object]]::new()
    $chosen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($wildcard in $Pattern) {
        # A caller who hands -Suite an unset variable lands here with a blank value. They asked for
        # a subset, so a value that names nothing is a mistake, not a request for every suite.
        if ([string]::IsNullOrWhiteSpace($wildcard)) {
            throw "-Suite was given a blank value. Leave -Suite out to run every suite in the $Job job."
        }

        $matched = @($runnable | Where-Object { $_.Name -like $wildcard })
        if ($matched.Count -eq 0) {
            # Say which kind of miss it was. Three misses need three different fixes: a name that
            # exists but this platform does not run, a name that exists outside the job, and a
            # name nothing matches at all. A suite silently skipped is the failure this
            # repository has already paid for once.
            $wrongPlatform = @($inJob | Where-Object { $_.Name -like $wildcard })
            if ($wrongPlatform.Count -gt 0) {
                throw "-Suite '$wildcard' matches only suites this platform does not run. Not on $Platform`: $($wrongPlatform.Name -join ', ')"
            }
            $elsewhere = @($Entry | Where-Object { $_.Name -like $wildcard })
            if ($elsewhere.Count -gt 0) {
                throw "-Suite '$wildcard' matches only suites outside the $Job job: $($elsewhere.Name -join ', ')"
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

# Runs one suite as its own child process and returns what happened. A child that cannot start is
# that suite's failure, not the run's, so every other suite still runs. This lives in the module
# rather than in the runner for one reason: `Every selected suite runs, including after another
# fails or cannot start` is an acceptance criterion, and the only way to make the host fail to
# start is to hand this function a host path that does not exist. A test can do that to a function
# in a dot-sourced module. It cannot do it to a function inside a script that runs on dot-source.
function Invoke-SuiteChild {
    param([string] $Path, [string] $Name, [string] $HostExe)

    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $output = & $HostExe -NoProfile -File $Path 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
    } catch {
        # The host itself could not start. PowerShell throws CommandNotFoundException before any
        # child process exists, so there is no exit code to read.
        $output = "Could not start the suite: $($_.Exception.Message)"
        $exitCode = 1
    }
    $watch.Stop()

    return [pscustomobject]@{
        Name     = $Name
        ExitCode = $exitCode
        Seconds  = $watch.Elapsed.TotalSeconds
        Output   = $output
    }
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

# How many suites may run at once when nobody says. Backlog 145.
#
# The measurement behind the number: on an eight-core laptop, six workers finished the same 56
# suites in the same wall clock as eight. The last two workers waited on the disk and on process
# starts and returned nothing, while the machine became hard to use. So on a developer's machine
# the default is 75% of the physical cores.
#
# Physical cores, never [Environment]::ProcessorCount. That property counts hardware threads. The
# measured machine reports 16 for its 8 cores, and 75% of 16 is 12 - more than the old default,
# and the opposite of what this change is for.
#
# The ceiling of eight is the number this repository has run with for months. Nobody has measured
# a machine larger than eight cores, so the rule stops there rather than guessing.
#
# -AllProcessors is the GitHub Actions rule. The 75% exists to keep a laptop usable while the
# suites run, and nobody is using a hosted runner while it works. A runner should finish and stop,
# so it takes every processor it has. That is also what CI did before backlog 145, which is why
# the job is no slower than it was.
function Get-DefaultSuiteWorkerCount {
    param(
        [int] $PhysicalCoreCount,
        [int] $LogicalProcessorCount = [Environment]::ProcessorCount,
        [switch] $AllProcessors
    )

    if ($AllProcessors) {
        return [Math]::Max(1, $LogicalProcessorCount)
    }

    # A machine whose core count we cannot read is a machine we know nothing about. The one number
    # known to be safe there is the number it has been running with all along, which is the rule
    # this function replaces. A smaller guess would slow a run for no measured reason.
    if ($PhysicalCoreCount -lt 1) {
        return [Math]::Max(1, [Math]::Min($LogicalProcessorCount, 8))
    }

    return [Math]::Max(1, [Math]::Min([int] [Math]::Floor($PhysicalCoreCount * 0.75), 8))
}

# Counts physical cores in the text of /proc/cpuinfo. Kept apart from the file read so a Windows
# host can test the Linux rule against a fixture string.
#
# Linux lists one block per hardware thread. Two threads on one core share a core id and a
# physical id, so the number of distinct pairs is the number of physical cores. The core id alone
# is not enough: core 0 exists on every socket.
#
# Text that names no pair returns zero, which the caller reads as unknown. An ARM board is the
# common case: it lists processors and no core id, and nothing in the file says how many physical
# cores sit behind them. Guessing there would be worse than falling back.
function ConvertFrom-ProcCpuInfoCoreCount {
    param([string] $Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return 0 }

    $pairs = [System.Collections.Generic.HashSet[string]]::new()
    $physicalId = $null
    $coreId = $null

    # A trailing empty line is appended so the last block is recorded even when the file ends
    # without one. Splitting on blank lines instead would drop a block whose file ends abruptly.
    foreach ($line in (($Text -split "`r?`n") + @(''))) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            if ($null -ne $physicalId -and $null -ne $coreId) {
                [void] $pairs.Add("$physicalId/$coreId")
            }

            $physicalId = $null
            $coreId = $null
            continue
        }

        if ($line -match '^\s*physical id\s*:\s*(\S+)\s*$') { $physicalId = $Matches[1] }
        elseif ($line -match '^\s*core id\s*:\s*(\S+)\s*$') { $coreId = $Matches[1] }
    }

    return $pairs.Count
}

# The host's physical core count, or zero when it cannot be read. Never throws: a run must not
# fail because a machine would not answer a question about itself.
#
# macOS returns zero. Get-CurrentSuitePlatform above throws on macOS before a run reaches here, so
# that path is only reachable from a test that calls this function directly.
function Get-PhysicalCoreCount {
    if ($IsWindows) {
        try {
            # NumberOfCores is per processor package, so a two-socket machine needs the sum.
            $sum = (Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop |
                    Measure-Object -Property NumberOfCores -Sum).Sum
            if ($null -ne $sum -and $sum -ge 1) { return [int] $sum }
        } catch {
            # A locked-down machine can refuse the CIM query. Unknown, not fatal.
        }

        return 0
    }

    if ($IsLinux) {
        try {
            $text = Get-Content -LiteralPath '/proc/cpuinfo' -Raw -ErrorAction Stop
        } catch {
            return 0
        }

        return (ConvertFrom-ProcCpuInfoCoreCount -Text $text)
    }

    return 0
}
