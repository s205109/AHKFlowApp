#Requires -Version 7.0
<#
.SYNOPSIS
  Runs every PowerShell test suite in tests/ and fails when any of them fails.
.DESCRIPTION
  Run it locally before a push, and read the table it prints. CI runs the same script in the
  powershell-suites job in .github/workflows/ci.yml.

  This script needs PowerShell 7. Start it with pwsh, which is what every documented command
  already does. tests/powershell-suites.json is the one record of which suites exist and which
  CI jobs run each of them; this script reads and checks it before it starts any child process.

  Each suite runs as its own process. That is the whole point of this script. The suites end in
  two different ways: some call 'exit 1' on failure and 'exit 0' on success, others throw on
  failure and simply run off the end on success. A suite that runs off the end leaves
  $LASTEXITCODE at whatever the last native command inside it returned, so checking $LASTEXITCODE
  after dot-sourcing or calling the suite in this process would report passing suites as failed.
  A child process has none of that history: its exit code is 0 unless the suite failed.

  Every suite runs even after an earlier one fails, so one CI run reports every broken suite.
#>

[CmdletBinding()]
param(
    [string] $SuiteRoot,

    # Wildcards matched against suite file names, for the inner development loop. Leave the
    # argument out and the run covers every suite in the selected job, which is what CI and the
    # Gate both want. A value that matches nothing fails the run: a typo must never look like a
    # green run. So does a blank value, and so does the argument with no value at all.
    [string[]] $Suite = @(),

    # Which CI job's suite set to run. Backlog 127. The manifest is the one record of which job
    # runs which suite, so scripts/ci/check-repo-invariants.ps1 passes '-Job invariants' instead
    # of keeping its own copy of the five names. An unknown value fails the run.
    [string] $Job = 'suites',

    # How many suites may run at once. With no value a developer's machine uses about 75% of its
    # physical cores, never more than eight, and a run inside GitHub Actions uses every processor it
    # has. AHKFLOW_SUITE_MAX_PARALLEL overrides both, and an explicit value wins over the variable.
    # Backlog 145 measured 56 suites on an eight-core laptop and found six workers as fast as eight,
    # so the last two workers only added load to the machine.
    #
    # Whatever the value, the run never starts more workers than it has suites to share out.
    #
    # Bound as text on purpose. An [int] parameter would round '1.5' to 2 and '2.5' to 2 while
    # binding, so a typo would run a number nobody asked for and the "whole number" promise below
    # could never be checked. The environment-variable path parses its text the same way.
    [string] $MaxParallel = '',

    # Backlog 188. This run is the Gate's PowerShell step. Only a Gate run may reuse a Suite's last
    # passing result, prints its 'Gate evidence:' line, and appends a line to the Gate log. CI and
    # a direct run leave it off, so their output does not change.
    [switch] $Gate
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# PowerShell 7.4 turns a non-zero exit code from a native command into a terminating error when
# $ErrorActionPreference is 'Stop'. That would abort this script on the first failing suite, which
# is exactly the behaviour this job must not have. Opt out so a failing suite is data, not an error.
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = Split-Path -Parent $PSScriptRoot
$gateStartedAtUtc = [DateTime]::UtcNow
$gateWatch = [System.Diagnostics.Stopwatch]::StartNew()

. "$PSScriptRoot\progress.common.ps1"
. "$PSScriptRoot\powershell-suites.common.ps1"
. "$PSScriptRoot\test-lanes.common.ps1"
. "$PSScriptRoot\progress.parallel.ps1"
. "$PSScriptRoot\gate-evidence.common.ps1"
. "$PSScriptRoot\suite-budget.common.ps1"

if ([string]::IsNullOrWhiteSpace($SuiteRoot)) {
    $SuiteRoot = Join-Path $repoRoot 'tests'
}

function Write-Failure([string]$Message) {
    Write-Host $Message -ForegroundColor Red
}

if (-not (Test-Path -LiteralPath $SuiteRoot -PathType Container)) {
    Write-Failure "Suite folder not found: $SuiteRoot"
    exit 1
}

$SuiteRoot = (Resolve-Path -LiteralPath $SuiteRoot).ProviderPath

# Every run prints progress lines, so a test over a folder of fake suites checks the same code
# path a real run uses. Only a run over the repository's own suites keeps the timings.
$keepTimings = Test-ProgressTimingsWanted -SuiteRoot $SuiteRoot -DefaultSuiteRoot (Join-Path $repoRoot 'tests')

$discovered = @(Get-ChildItem -LiteralPath $SuiteRoot -Filter '*.Tests.ps1' -File | Sort-Object Name)

# A folder the glob finds nothing in cannot have a manifest worth reading, and the message a
# reader needs there names the folder, not the manifest.
if ($discovered.Count -eq 0) {
    Write-Failure "No test suites found in $SuiteRoot"
    Write-Host 'A run with nothing to run must not look green.'
    exit 1
}

$manifestPath = Join-Path $SuiteRoot 'powershell-suites.json'
try {
    $entries = @(Read-SuiteManifest -Path $manifestPath -DiscoveredName @($discovered.Name))

    # Leaving -Suite out is the only way to ask for the whole job. A caller who passes the argument
    # asked for a subset, so an argument that names nothing is a mistake. '-Suite $env:FILTER' with
    # the variable unset binds $null, and that used to run every suite.
    if ($PSBoundParameters.ContainsKey('Suite') -and ($null -eq $Suite -or $Suite.Count -eq 0)) {
        throw '-Suite was given no value to match. Leave -Suite out to run every suite in the suites job.'
    }

    # The platform comes from the host, and this script takes no override. An argument here would
    # let a caller select another platform's suites, run them under this host anyway, and print a
    # header claiming the run proved something it did not. Select-SuiteEntry keeps a -Platform
    # parameter so a test can ask about the other platform, which is a question, not a run.
    $runPlatform = Get-CurrentSuitePlatform
    $selected = @(Select-SuiteEntry -Entry $entries -Pattern $Suite -Job $Job -Platform $runPlatform)
    $laneRole = Get-AhkFlowLaneRole
} catch {
    # Stop before any child starts. A manifest or selection we cannot trust means the coverage this
    # run reports would be a guess.
    Write-Failure $_.Exception.Message
    exit 1
}

$byName = @{}
foreach ($file in $discovered) { $byName[$file.Name] = $file }
$entryByName = @{}
foreach ($entry in $entries) { $entryByName[$entry.Name] = $entry }

$inActions = $env:GITHUB_ACTIONS -eq 'true'

# Backlog 188. Reuse needs -Gate, AHKFLOW_GATE_REUSE not 'off', and a run outside GitHub Actions.
# CI always runs everything. With reuse off, no evidence is read or written.
$reuseOn = $false
$reusedRows = [System.Collections.Generic.List[object]]::new()
$reuseKeys = @{}
$evidenceRoot = Get-GateEvidenceRoot -RepoRoot $repoRoot
if ($Gate) {
    $offReason = if ($env:AHKFLOW_GATE_REUSE -eq 'off') { 'AHKFLOW_GATE_REUSE=off' } elseif ($inActions) { 'GitHub Actions' } else { $null }
    if ($null -eq $offReason) {
        $reuseOn = $true
        Write-Host 'Gate evidence: on'
    } else {
        Write-Host "Gate evidence: off ($offReason)"
    }
}

# Backlog 188. A Suite's committed baselineSeconds is its time budget. Budgets apply only to a Gate
# run outside GitHub Actions, and they never change the exit code.
$budgetsOn = $Gate -and -not $inActions
$budgetWarned = [System.Collections.Generic.List[string]]::new()

if ($reuseOn) {
    # Read once per run: the tool versions and the runner's own inputs are the same for every Suite.
    $runnerInputs = Get-SuiteInputList -Path $PSCommandPath -Root $repoRoot
    $suiteParent = Split-Path -Parent $SuiteRoot
    $reuseContext = @{
        ToolVersion = Get-GateToolVersion -RunnerRoot $repoRoot
        Job         = $Job
        Platform    = $runPlatform
        LaneRole    = $laneRole
        Root        = $suiteParent
        RunnerRoot  = $repoRoot
    }

    # An eligible Suite's input list and key, built the same way before it runs and after it passes.
    function Get-EntryReuseKey {
        param([object] $Entry)
        $inputs = Get-SuiteInputList -Path $byName[$Entry.Name].FullName -Root $suiteParent -ExtraInput $Entry.Reuse.ExtraInputs
        return [pscustomobject]@{
            Inputs = $inputs
            Key    = Get-SuiteReuseKey -Entry $Entry -InputList $inputs -RunnerInputList $runnerInputs @reuseContext
        }
    }

    $toRun = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $selected) {
        $key = $null
        if ($null -ne $entry.Reuse -and $entry.Reuse.Eligible) { $key = (Get-EntryReuseKey $entry).Key }
        if ($null -ne $key -and $null -ne (Read-GateEvidence -EvidenceRoot $evidenceRoot -SuiteName $entry.Name -Key $key)) {
            Write-Host "REUSED $($entry.Name) (evidence $($key.Substring(0, 12)))"
            $reusedRows.Add([pscustomobject]@{ Name = $entry.Name; ExitCode = 0; Seconds = 0; Reused = $true })
            continue
        }
        if ($null -ne $key) { $reuseKeys[$entry.Name] = $key }
        $toRun.Add($entry)
    }

    # The tracker, the schedule and the worker cap below see only the Suites that run. A reused
    # result is not a timing sample.
    $selected = @($toRun)
}

$suites = @($selected | ForEach-Object { $byName[$_.Name] })

# Reading the variable's text here does not settle precedence - the branches below do, in order.
# "An explicit value wins over the variable" has to mean this: validating the variable's text
# before the -MaxParallel branch is checked would fail the run on a value the caller has already
# overridden. A blank or whitespace variable is no value, so it falls through to the default.
$envMaxParallel = $env:AHKFLOW_SUITE_MAX_PARALLEL
$hasPhysicalCoreCount = $false

# Backlog 145. Get-DefaultSuiteWorkerCount in suite-worker-count.common.ps1 carries the measurement
# behind the 75%, the reason a hosted runner takes every processor instead, and the reason an
# unreadable core count falls back to the old rule.
#
# One chain, highest precedence first, and only the last branch looks at the hardware.
if ($PSBoundParameters.ContainsKey('MaxParallel')) {
    $parsedMaxParallel = 0
    if (-not [int]::TryParse($MaxParallel.Trim(), [ref] $parsedMaxParallel) -or $parsedMaxParallel -lt 1) {
        Write-Failure "-MaxParallel must be a whole number of at least one. Got: '$MaxParallel'"
        exit 1
    }
    $workerCount = $parsedMaxParallel
    $workerSource = '-MaxParallel'
} elseif (-not [string]::IsNullOrWhiteSpace($envMaxParallel)) {
    $parsedMaxParallel = 0
    if (-not [int]::TryParse($envMaxParallel.Trim(), [ref] $parsedMaxParallel) -or $parsedMaxParallel -lt 1) {
        # Falling back to the default here would hide a misconfigured CI job for months.
        Write-Failure "AHKFLOW_SUITE_MAX_PARALLEL must be a whole number of at least one. Got: '$envMaxParallel'"
        exit 1
    }
    $workerCount = $parsedMaxParallel
    $workerSource = 'AHKFLOW_SUITE_MAX_PARALLEL'
} elseif ($inActions) {
    $workerCount = Get-DefaultSuiteWorkerCount -PhysicalCoreCount 0 -AllProcessors
    $workerSource = "GitHub Actions: all $([Environment]::ProcessorCount) logical processors"
} else {
    # Adaptive Worker sizing queries hardware here. Owners reuse this result for their Lane proposal.
    # Overrides skip this query; only an owner still needs a proposal below.
    $physicalCoreCount = Get-PhysicalCoreCount
    $hasPhysicalCoreCount = $true
    $logicalProcessorCount = [Environment]::ProcessorCount

    $workerCount = Get-DefaultSuiteWorkerCount -PhysicalCoreCount $physicalCoreCount -LogicalProcessorCount $logicalProcessorCount
    $workerSource = 'default: ' + (Get-DefaultSuiteWorkerReason -PhysicalCoreCount $physicalCoreCount -LogicalProcessorCount $logicalProcessorCount)
}

$laneProposal = 0
if ($laneRole -eq 'owner') {
    $laneProposal = if ($hasPhysicalCoreCount) {
        Get-AhkFlowLaneProposal -PhysicalCoreCount $physicalCoreCount
    } else {
        Get-AhkFlowLaneProposal
    }
}

# The suites are written for the host that runs this script, so run them under the same one.
$hostExe = [System.Diagnostics.Process]::GetCurrentProcess().Path

Write-Host "Running $($suites.Count) PowerShell suite(s) from $SuiteRoot"
Write-Host "Host: $hostExe"
Write-Host "Job: $Job    Platform: $runPlatform"

$progress = New-ProgressTracker -RunnerKey 'run-powershell-suites' -Unit @($suites | ForEach-Object { $_.Name }) -RepoRoot $repoRoot -NoStore:(-not $keepTimings)

$schedule = @(Get-SuiteSchedule -Entry $selected -History $progress.History)

# ForEach-Object -ThrottleLimit sizes its runspace pool from this number before it starts anything,
# so a very large value throws 'Array dimensions exceeded supported range' and no suite runs at all.
# The validation above accepts any whole number of at least one, and a worker with no suite to take
# buys nothing, so cap the count at the number of suites that share the pool.
#
# The floor is one, not zero. An all-exclusive selection shares nothing, and those suites still run
# one after another, so one is the count the run really uses. Zero would misreport the run, and it
# is not a legal -ThrottleLimit if the pool ever ran.
$sharedCount = @($schedule | Where-Object { $_.Execution -ne 'exclusive' }).Count
$cappedCount = [Math]::Min($workerCount, [Math]::Max(1, $sharedCount))
if ($cappedCount -lt $workerCount) {
    $workerSource = "capped at the $sharedCount suite(s) that share the pool"
}

$workerCount = $cappedCount

# After the cap, so the number printed is the number the run uses.
Write-Host "Workers: $workerCount ($workerSource)"

$parallelProgress = New-ParallelProgressTracker -Tracker $progress

$results = [System.Collections.Generic.List[object]]::new()
foreach ($row in $reusedRows) { $results.Add($row) }

# Invoke-SuiteChild comes from powershell-suites.common.ps1, which this script already dot-sources.
# Prints one suite's whole block, in this runspace. Buffering the child's output and printing it
# here is what stops two suites writing over each other.
function Show-SuiteResult {
    param([object] $Result)

    if ($inActions) { Write-Host "::group::$($Result.Name)" }

    Complete-ParallelProgressUnit -Tracker $parallelProgress -Name $Result.Name -Seconds $Result.Seconds
    Write-Host (Get-ParallelProgressLine -Tracker $parallelProgress -Name $Result.Name -Seconds $Result.Seconds)

    if (-not [string]::IsNullOrWhiteSpace($Result.Output)) {
        Write-Host $Result.Output.TrimEnd()
    }

    if ($inActions) { Write-Host '::endgroup::' }

    if ($Result.ExitCode -ne 0) {
        Write-Failure "FAILED: $($Result.Name) (exit code $($Result.ExitCode))"
    }

    $results.Add([pscustomobject]@{
            Name     = $Result.Name
            ExitCode = $Result.ExitCode
            Seconds  = [math]::Round($Result.Seconds, 1)
            Reused   = $false
        })

    $entry = $entryByName[$Result.Name]

    # Backlog 188. Only a Suite that ran can be over its budget. A reused one never reaches here.
    if ($budgetsOn -and $null -ne $entry) {
        $warning = Get-SuiteBudgetWarning -Entry $entry -Seconds $Result.Seconds
        if ($null -ne $warning) {
            Write-Host $warning -ForegroundColor Yellow
            $budgetWarned.Add($Result.Name)
        }
    }

    # Backlog 188. Evidence only after a pass, and only when the inputs still hash to the key the
    # run started with. A Suite that changed one of its own inputs while it ran proved nothing
    # about the new bytes.
    if ($reuseOn -and $Result.ExitCode -eq 0 -and $reuseKeys.ContainsKey($Result.Name)) {
        $again = Get-EntryReuseKey $entry
        if ($again.Key -eq $reuseKeys[$Result.Name]) {
            Write-GateEvidence -EvidenceRoot $evidenceRoot -SuiteName $Result.Name -Key $again.Key -InputList $again.Inputs -RunnerInputList $runnerInputs -Seconds $Result.Seconds
        }
    }
}

$byPath = @{}
foreach ($file in $suites) { $byPath[$file.Name] = $file.FullName }

# Exclusive suites first, one at a time. Nothing else may run while one of them does, so putting
# them first leaves the pool's longest-first order intact afterwards.
$laneRun = $null
$previousHolder = $null
try {
    if ($laneRole -eq 'owner') {
        $previousHolder = Enter-AhkFlowLaneOwnership
        $laneRun = Register-AhkFlowLaneRun -PoolRoot (Get-AhkFlowLanePoolRoot) -Mode PowerShell -Checkout $repoRoot
        Write-AhkFlowLaneSharingLine -Run $laneRun
        Write-Host 'Lanes: shared pool; one per Suite'
    } elseif ($laneRole -eq 'nested') {
        Write-Host "Lanes: nested; holder $env:AHKFLOW_TEST_LANES_HOLDER"
    } else {
        Write-Host 'Lanes: off; AHKFLOW_TEST_LANES=off'
    }

    foreach ($item in ($schedule | Where-Object { $_.Execution -eq 'exclusive' })) {
        $lanes = $null
        try {
            if ($laneRun) {
                $lanes = Enter-AhkFlowLanes -PoolRoot $laneRun.PoolRoot -Share One -Proposal $laneProposal -Run $laneRun
            }
            Show-SuiteResult (Invoke-SuiteChild -Path $byPath[$item.Name] -Name $item.Name -HostExe $hostExe)
        } catch {
            Show-SuiteResult ([pscustomobject]@{ Name = $item.Name; ExitCode = 1; Seconds = 0; Output = "Could not run the suite: $($_.Exception.Message)" })
        } finally {
            Exit-AhkFlowLanes -Handle $lanes
        }
    }

    $shared = @($schedule | Where-Object { $_.Execution -ne 'exclusive' } |
            ForEach-Object { [pscustomobject]@{ Name = $_.Name; Path = $byPath[$_.Name] } })

    $commonModule = Join-Path $PSScriptRoot 'powershell-suites.common.ps1'
    $laneModule = Join-Path $PSScriptRoot 'test-lanes.common.ps1'

    if ($shared.Count -gt 0) {
        # Longest first. Starting the slowest suite last would leave it running alone at the end, which
        # is exactly the shape that makes a parallel run no faster than a sequential one.
        #
        # Results reach this pipeline as each child exits, so the parent-side ForEach-Object below
        # prints one whole block at a time.
        $shared | ForEach-Object -ThrottleLimit $workerCount -Parallel {
            # Load the module inside this runspace, so Invoke-SuiteChild is defined here. Do not pass
            # the parent's scriptblock instead: Microsoft documents that "Scriptblock invocation always
            # attempts to run in its home runspace, regardless of where it's actually invoked", so a
            # scriptblock made in the parent would run back in the parent - serialising the whole run,
            # which is the one failure this task exists to prevent. See
            # https://learn.microsoft.com/powershell/module/microsoft.powershell.core/foreach-object?view=powershell-7.6
            . $using:commonModule
            . $using:laneModule
            $laneRun = $using:laneRun
            $laneProposal = $using:laneProposal
            $ErrorActionPreference = 'Stop'

            # Fresh runspace: opt out again so a non-zero suite exit code is data, not a throw.
            $PSNativeCommandUseErrorActionPreference = $false

            # Name, ExitCode, Seconds and Output are exactly what Show-SuiteResult reads, so the
            # child's own object is what this runspace emits.
            $item = $_
            $lanes = $null
            try {
                if ($laneRun) {
                    $lanes = Enter-AhkFlowLanes -PoolRoot $laneRun.PoolRoot -Share One -Proposal $laneProposal -Run $laneRun
                }
                Invoke-SuiteChild -Path $item.Path -Name $item.Name -HostExe $using:hostExe
            } catch {
                [pscustomobject]@{ Name = $item.Name; ExitCode = 1; Seconds = 0; Output = "Could not run the suite: $($_.Exception.Message)" }
            } finally {
                Exit-AhkFlowLanes -Handle $lanes
            }
        } | ForEach-Object { Show-SuiteResult $_ }
    }
} finally {
    if ($laneRole -eq 'owner') {
        try { Unregister-AhkFlowLaneRun -Run $laneRun }
        finally { Exit-AhkFlowLaneOwnership -Previous $previousHolder }
    }
}

# A Worker that emitted no result did not prove its selected Suite passed.
$completedNames = @($results | ForEach-Object { $_.Name })
foreach ($item in $selected) {
    if ($item.Name -notin $completedNames) {
        Show-SuiteResult ([pscustomobject]@{ Name = $item.Name; ExitCode = 1; Seconds = 0; Output = 'The Suite Worker returned no result.' })
    }
}

# Once, after every suite has settled. A save per suite would break the case that reads this
# file's last-write time while a child runs. -KnownUnit drops a suite that no longer exists.
Save-ProgressTimings -Tracker $progress -KnownUnit @($discovered.Name)

# Backlog 188. The streak lives beside the timings, and only a run that keeps timings writes it, so
# a run over fake Suites never touches it. Two warnings in a row suggest an audit; nothing starts
# one.
if ($budgetsOn -and $keepTimings) {
    $executedNames = @($results | Where-Object { -not $_.Reused } | ForEach-Object { $_.Name })
    $streakPath = Join-Path $repoRoot "$script:GateOutputFolder\progress\budget-streak.json"
    $repeat = @(Update-SuiteBudgetStreak -Path $streakPath -Executed $executedNames -Warned @($budgetWarned))
    if ($repeat.Count -gt 0) {
        $names = $repeat -join ', '
        Write-Host "These Suites ran over budget in two runs in a row: $names. To audit them, type in Claude Code: Run /test-audit on $names" -ForegroundColor Yellow
    }
}

$failed = @($results | Where-Object { $_.ExitCode -ne 0 })

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('### PowerShell suites')
$lines.Add('')
$lines.Add('| Suite | Result | Exit code | Duration |')
$lines.Add('|---|---|---|---|')
# By name, not by finish order. A parallel run finishes in a different order every time, and a
# table nobody can scan is no use in a CI log.
foreach ($result in ($results | Sort-Object Name)) {
    if ($result.Reused) {
        $lines.Add("| $($result.Name) | reused | 0 | - |")
        continue
    }
    $verdict = if ($result.ExitCode -eq 0) { 'passed' } else { 'failed' }
    $lines.Add("| $($result.Name) | $verdict | $($result.ExitCode) | $($result.Seconds)s |")
}
$lines.Add('')
if ($failed.Count -gt 0) {
    $lines.Add("**$($failed.Count) of $($results.Count) suite(s) failed:** $(($failed.Name) -join ', ')")
} else {
    $lines.Add("All $($results.Count) suite(s) passed.")
}

$summary = $lines -join [Environment]::NewLine

Write-Host ''
Write-Host $summary

if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)) {
    Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $summary -Encoding utf8
}

# Backlog 188. One line per Gate run, beside the evidence folder. A log that cannot be written
# warns and never fails the run.
if ($Gate) {
    try {
        $revision = & git -C $repoRoot rev-parse HEAD 2>$null
        $logLine = [ordered]@{
            startedAtUtc   = $gateStartedAtUtc.ToString('o')
            revision       = if ($LASTEXITCODE -eq 0 -and $revision) { ([string] $revision).Trim() } else { $null }
            reuse          = $reuseOn
            executed       = @($results | Where-Object { -not $_.Reused } | ForEach-Object { $_.Name } | Sort-Object)
            reused         = @($reusedRows | ForEach-Object { $_.Name } | Sort-Object)
            elapsedSeconds = [math]::Round($gateWatch.Elapsed.TotalSeconds, 1)
            budgetWarnings = @($budgetWarned | Sort-Object)
        }
        $logFolder = Split-Path -Parent $evidenceRoot
        if (-not (Test-Path -LiteralPath $logFolder -PathType Container)) {
            New-Item -ItemType Directory -Path $logFolder -Force | Out-Null
        }
        Add-Content -LiteralPath (Join-Path $logFolder 'gate-log.jsonl') -Value ($logLine | ConvertTo-Json -Compress -Depth 4) -Encoding utf8
    } catch {
        Write-Warning "Could not append to the Gate log. $($_.Exception.Message)"
    }
}

if ($failed.Count -gt 0) { exit 1 }
exit 0
