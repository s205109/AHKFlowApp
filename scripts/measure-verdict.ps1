#Requires -Version 5.1
<#
.SYNOPSIS
  Prints the verdict tables of backlog 204 for a timing session and its Soaks, as Markdown.
.DESCRIPTION
  Reads the session folders that scripts/measure-test-modes.ps1 writes, through the functions in
  scripts/measure-evidence.common.ps1. It reads files only, and it changes nothing.

  For the timing session it prints every setting's counted runs, median and spread, whether each
  side-by-side setting saves time against at-1, every run's failures, and for Coverage the
  completeness and outcome differences. For each Soak session it prints the passes and failures
  per Slice, and each failure's verdict against the sequence Soak.
.EXAMPLE
  pwsh .\scripts\measure-verdict.ps1 -Timing TestResults\measure-test-modes\Coverage\session-20261116-100000
.EXAMPLE
  pwsh .\scripts\measure-verdict.ps1 -Timing <timing session> -Soak <soak session> -SequenceSoak <sequence soak session>
#>
[CmdletBinding()]
param(
    # The timing session folder.
    [Parameter(Mandatory = $true)][string] $Timing,

    # The Soak session folders to judge. A comma list in one value works too.
    [string[]] $Soak = @(),

    # The Soak session of the sequence, setting 1. Without it, every Soak failure is 'not cleared'.
    [string] $SequenceSoak
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\test-results.common.ps1"
. "$PSScriptRoot\measure-evidence.common.ps1"

function Read-SessionRecord {
    param([Parameter(Mandatory = $true)][string] $Session)
    $path = Join-Path $Session 'record.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "No record.json in $Session." }
    $record = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    return [pscustomobject]@{
        Mode = [string]$record.Mode
        Kind = [string]$record.Kind
        Revision = [string]$record.Revision
        Settings = @($record.Settings | ForEach-Object { [string]$_ })
        Runs = @($record.Runs | ForEach-Object { $_ })
    }
}

function Format-Cell {
    # A Markdown table cell: a '|' inside the text would end the cell.
    param([object] $Value)
    if ($null -eq $Value -or "$Value" -eq '') { return '-' }
    return ("$Value" -replace '\|', '\|')
}

function Get-SessionFigure {
    # The coverage figures of the runs of one setting and kind that kept a merged report.
    param([string] $Session, [object[]] $Runs)
    $figures = New-Object System.Collections.Generic.List[object]
    foreach ($run in $Runs) {
        $summary = Join-Path (Join-Path $Session $run.Folder) 'report\Summary.json'
        if (Test-Path -LiteralPath $summary -PathType Leaf) {
            $figures.Add([pscustomobject]@{ Run = $run; Figure = (Get-AhkFlowCoverageFigure -SummaryPath $summary) })
        }
    }
    return $figures.ToArray()
}

function Write-FigureDifference {
    # Prints the differences of each run against the reference, with one summary line first.
    param([string] $Label, [object[]] $Reference, [object[]] $Candidates, [switch] $Outcome)
    $rows = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in $Candidates) {
        $differences = @(Compare-AhkFlowCoverageFigure -Reference $Reference -Candidate $candidate.Figure -Outcome:$Outcome)
        if ($Outcome) { $differences = @($differences | Where-Object { $_.Check -eq 'outcome' }) }
        foreach ($d in $differences) {
            $rows.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} |' -f (Format-Cell $candidate.Run.Setting), (Format-Cell $candidate.Run.Label),
                    (Format-Cell $d.Assembly), (Format-Cell $d.Class), (Format-Cell $d.Field), (Format-Cell $d.Expected), (Format-Cell $d.Actual)))
        }
    }
    Write-Output ('{0}: {1} difference(s) in {2} run(s)' -f $Label, $rows.Count, @($Candidates).Count)
    if ($rows.Count -gt 0) {
        Write-Output ''
        Write-Output '| Setting | Run | Assembly | Class | Field | Expected | Actual |'
        Write-Output '|---|---|---|---|---|---|---|'
        foreach ($row in $rows) { Write-Output $row }
    }
    Write-Output ''
}

$timingRecord = Read-SessionRecord -Session $Timing
$mode = $timingRecord.Mode

Write-Output "## Timing session $(Split-Path -Leaf $Timing)"
Write-Output ''
Write-Output "Mode $mode at revision $($timingRecord.Revision)."
Write-Output ''
Write-Output '| Setting | Counted runs (s) | Median (s) | Spread | Failed runs |'
Write-Output '|---|---|---|---|---|'
$secondsBySetting = @{}
foreach ($setting in $timingRecord.Settings) {
    $mine = @($timingRecord.Runs | Where-Object { $_.Setting -eq $setting -and $_.Kind -eq 'counted' })
    $seconds = @($mine | Where-Object { -not $_.Failed } | ForEach-Object { [double]$_.ElapsedSeconds })
    $secondsBySetting[$setting] = $seconds
    $failedCount = @($mine | Where-Object { $_.Failed }).Count
    $median = '-'
    $spread = '-'
    if ($seconds.Count -gt 0) {
        $median = '{0:N2}' -f (Get-AhkFlowMedian -Values $seconds)
        $spread = '{0:N1} %' -f (Get-AhkFlowRelativeSpread -Values $seconds)
    }
    Write-Output ('| {0} | {1} | {2} | {3} | {4} |' -f $setting, (Format-Cell (($seconds | ForEach-Object { '{0:N2}' -f $_ }) -join ' / ')),
        $median, $spread, $failedCount)
}
Write-Output ''

if ($secondsBySetting.ContainsKey('1')) {
    foreach ($setting in $timingRecord.Settings) {
        if ($setting -eq '1') { continue }
        $saves = Test-AhkFlowTimeSaving -Sequence $secondsBySetting['1'] -Candidate $secondsBySetting[$setting]
        Write-Output ('{0} saves time: {1}' -f $setting, $(if ($saves) { 'yes' } else { 'no' }))
    }
}
else {
    Write-Output 'saves time: not judged, because the session has no setting 1.'
}
Write-Output ''

Write-Output '### Failures'
Write-Output ''
$failureRows = New-Object System.Collections.Generic.List[string]
$blocked = New-Object System.Collections.Generic.List[string]
foreach ($run in $timingRecord.Runs) {
    foreach ($failure in @(Get-AhkFlowRunFailure -RunFolder (Join-Path $Timing $run.Folder) -Mode $mode)) {
        $failureRows.Add(('| {0} | {1} | {2} | {3} | {4} | {5} |' -f (Format-Cell $run.Setting), (Format-Cell $run.Label), $failure.Kind,
                (Format-Cell $failure.Slice), (Format-Cell $failure.Test), (Format-Cell $failure.Cause)))
        if ($run.Setting -ne '1' -and ($failure.Kind -eq 'evidence' -or $failure.Kind -eq 'run') -and -not $blocked.Contains($run.Setting)) {
            $blocked.Add($run.Setting)
        }
    }
}
if ($failureRows.Count -eq 0) {
    Write-Output 'No run failed.'
}
else {
    Write-Output '| Setting | Run | Kind | Slice | Test | Cause |'
    Write-Output '|---|---|---|---|---|---|'
    foreach ($row in $failureRows) { Write-Output $row }
}
Write-Output ''
foreach ($setting in $blocked) {
    Write-Output "$setting blocked: a run has an evidence failure or a run failure."
}
if ($blocked.Count -gt 0) { Write-Output '' }

# The reference for every coverage check: the counted runs of setting 1 that kept a report.
$reference = @()
if ($mode -eq 'Coverage') {
    Write-Output '### Coverage'
    Write-Output ''
    $referenceRuns = @(Get-SessionFigure -Session $Timing -Runs @($timingRecord.Runs | Where-Object { $_.Setting -eq '1' -and $_.Kind -eq 'counted' }))
    $referenceList = New-Object System.Collections.Generic.List[object]
    foreach ($item in $referenceRuns) { $referenceList.Add($item.Figure) }
    $reference = $referenceList.ToArray()
    if ($reference.Count -eq 0) {
        Write-Output 'completeness: not judged, because no counted run of setting 1 kept a report.'
        Write-Output ''
    }
    else {
        Write-FigureDifference -Label 'completeness' -Reference $reference -Candidates @(Get-SessionFigure -Session $Timing -Runs $timingRecord.Runs)
        Write-FigureDifference -Label 'outcome' -Reference $reference -Outcome -Candidates @(
            Get-SessionFigure -Session $Timing -Runs @($timingRecord.Runs | Where-Object { $_.Setting -ne '1' -and $_.Kind -eq 'counted' }))
    }
}

# A failure is 'existing' only when the sequence shows it at the same code, so any other session
# is refused rather than read.
function Assert-SequenceSoak {
    param([object] $Sequence, [object] $Judged, [string] $JudgedSession)
    $problems = New-Object System.Collections.Generic.List[string]
    if ($Sequence.Kind -ne 'soak') { $problems.Add("its Kind is '$($Sequence.Kind)', not 'soak'") }
    if (($Sequence.Settings -join ',') -ne '1') { $problems.Add("its setting is '$($Sequence.Settings -join ',')', not '1'") }
    if ($Sequence.Mode -ne $Judged.Mode) { $problems.Add("its Mode is $($Sequence.Mode), not $($Judged.Mode)") }
    if ($Sequence.Revision -ne $Judged.Revision) { $problems.Add("its revision is $($Sequence.Revision), not $($Judged.Revision)") }
    if ($problems.Count -gt 0) {
        throw "$SequenceSoak is not a sequence Soak for $JudgedSession`: $($problems -join '; ')."
    }
}

$sequenceFailures = @()
$sequenceRecord = $null
if (-not [string]::IsNullOrWhiteSpace($SequenceSoak)) {
    $sequenceRecord = Read-SessionRecord -Session $SequenceSoak
    $sequenceFailures = @(foreach ($run in $sequenceRecord.Runs) {
            Get-AhkFlowRunFailure -RunFolder (Join-Path $SequenceSoak $run.Folder) -Mode $sequenceRecord.Mode
        })
}

foreach ($session in @($Soak | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
    $record = Read-SessionRecord -Session $session
    if ($null -ne $sequenceRecord) { Assert-SequenceSoak -Sequence $sequenceRecord -Judged $record -JudgedSession $session }
    $passed = @($record.Runs | Where-Object { -not $_.Failed }).Count
    Write-Output "## Soak session $(Split-Path -Leaf $session)"
    Write-Output ''
    Write-Output ('{0} at {1}: passed {2} of {3} runs.' -f $record.Mode, ($record.Settings -join ', '), $passed, $record.Runs.Count)
    Write-Output ''

    $perSlice = [ordered]@{}
    $failures = New-Object System.Collections.Generic.List[object]
    foreach ($run in $record.Runs) {
        $runFolder = Join-Path $session $run.Folder
        $slicesPath = Join-Path $runFolder 'results\slices.json'
        if (Test-Path -LiteralPath $slicesPath -PathType Leaf) {
            foreach ($slice in @(Get-Content -LiteralPath $slicesPath -Raw | ConvertFrom-Json | ForEach-Object { $_ })) {
                if (-not $perSlice.Contains($slice.Name)) { $perSlice[$slice.Name] = @{ Passed = 0; Failed = 0 } }
                if ([int]$slice.ExitCode -eq 0) { $perSlice[$slice.Name].Passed++ } else { $perSlice[$slice.Name].Failed++ }
            }
        }
        foreach ($failure in @(Get-AhkFlowRunFailure -RunFolder $runFolder -Mode $record.Mode)) { $failures.Add($failure) }
    }

    Write-Output '| Slice | Passed | Failed |'
    Write-Output '|---|---|---|'
    foreach ($name in $perSlice.Keys) {
        Write-Output ('| {0} | {1} | {2} |' -f $name, $perSlice[$name].Passed, $perSlice[$name].Failed)
    }
    Write-Output ''

    $verdicts = @(Get-AhkFlowSoakVerdict -Candidate $failures.ToArray() -Sequence $sequenceFailures)
    if ($verdicts.Count -eq 0) {
        Write-Output 'No Soak run failed.'
    }
    else {
        Write-Output '| Kind | Slice | Test | Cause | Runs | Sequence runs | Verdict |'
        Write-Output '|---|---|---|---|---|---|---|'
        foreach ($v in $verdicts) {
            Write-Output ('| {0} | {1} | {2} | {3} | {4} | {5} | {6} |' -f $v.Kind, (Format-Cell $v.Slice), (Format-Cell $v.Test),
                (Format-Cell $v.Cause), $v.CandidateCount, $v.SequenceCount, $v.Verdict)
        }
    }
    Write-Output ''

    if ($record.Mode -eq 'Coverage' -and $reference.Count -gt 0) {
        Write-FigureDifference -Label 'Soak completeness' -Reference $reference -Candidates @(Get-SessionFigure -Session $session -Runs $record.Runs)
    }
}

Write-Output "Done: printed the verdict tables for $(Split-Path -Leaf $Timing)."
