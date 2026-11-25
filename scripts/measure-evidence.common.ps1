#Requires -Version 5.1
<#
.SYNOPSIS
  Reads the evidence that scripts/measure-test-modes.ps1 kept for each measured run.
.DESCRIPTION
  Backlog 204. A timing session or a Soak keeps one folder per run: run.json, the Slice results
  with their TRX and log files, and for Coverage the merged Summary.json. These functions turn
  that evidence into answers: which test, Slice or run failed and why, the coverage figures of a
  run, whether a setting saves time, and whether a Soak failure is one the sequence already shows.
  scripts/measure-verdict.ps1 prints the answers as tables.

  Every function reads files only. None of them deletes or changes anything.
#>

function Get-AhkFlowFailureCause {
    <#
      The cause of a failure, as one short line that two runs of the same failure share.

      It is the first line of the message, because an assertion's message carries no exception
      type. Each GUID becomes <guid>, then each run of digits becomes #, so a port, a count or an
      id does not split one failure into many.
    #>
    param([AllowNull()][AllowEmptyString()][string] $Message)

    if ([string]::IsNullOrWhiteSpace($Message)) { return '(no message)' }
    $line = @($Message -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })[0].Trim()
    $line = [regex]::Replace($line, '(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b', '<guid>')
    return [regex]::Replace($line, '[0-9]+', '#')
}

function Get-AhkFlowJsonValue {
    # A property of an object read from JSON, or $null when it has no such property.
    param([object] $Object, [string] $Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function New-AhkFlowRunFailureEntry {
    param([string] $Kind, [string] $Slice, [string] $Test, [string] $Cause)
    $key = switch ($Kind) {
        'test' { "test|$Slice|$Test|$Cause" }
        'slice' { "slice|$Slice|$Cause" }
        'evidence' { "evidence|$Slice|$Cause" }
        default {
            # A run failure of one Slice keys on that Slice, so crashes in two Slices stay apart.
            if ([string]::IsNullOrEmpty($Slice)) { "run|$Cause" } else { "run|$Slice|$Cause" }
        }
    }
    return [pscustomobject]@{ Kind = $Kind; Slice = $Slice; Test = $Test; Cause = $Cause; Key = $key }
}

function Read-AhkFlowTrxXml {
    # One TRX file as XML, or $null when the file is missing, empty or not valid XML.
    param([Parameter(Mandatory = $true)][string] $TrxPath)

    try { $raw = Get-Content -LiteralPath $TrxPath -Raw } catch { return $null }
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    try { return [xml]$raw } catch { return $null }
}

function Get-AhkFlowTrxFailure {
    <#
      The results of one TRX file whose outcome is not Passed, NotExecuted or Inconclusive, each
      with its test name and message. A file nobody can read gives nothing; the caller already
      reports it through its test count.
    #>
    param([Parameter(Mandatory = $true)][string] $TrxPath)

    $trx = Read-AhkFlowTrxXml -TrxPath $TrxPath
    if ($null -eq $trx) { return @() }

    $failures = New-Object System.Collections.Generic.List[object]
    foreach ($result in $trx.GetElementsByTagName('UnitTestResult')) {
        $outcome = $result.GetAttribute('outcome')
        if ($outcome -eq 'Passed' -or $outcome -eq 'NotExecuted' -or $outcome -eq 'Inconclusive') { continue }
        $messageNode = $result.GetElementsByTagName('Message') | Select-Object -First 1
        $message = ''
        if ($null -ne $messageNode) { $message = $messageNode.InnerText }
        $failures.Add([pscustomobject]@{ Test = $result.GetAttribute('testName'); Message = $message })
    }
    return $failures.ToArray()
}

function Get-AhkFlowTrxRunError {
    <#
      The text of each RunInfo with outcome Error in one TRX file, trimmed, in file order.

      Backlog 220 exists for one such text: "The active test run was aborted. Reason: Test host
      process crashed". A crashed test host leaves passed results and this one RunInfo. Only Error
      counts, because a passing run can hold a RunInfo with outcome Warning, such as "No test
      matches the given testcase filter". A file nobody can read gives nothing, as in
      Get-AhkFlowTrxFailure.
    #>
    param([Parameter(Mandatory = $true)][string] $TrxPath)

    $trx = Read-AhkFlowTrxXml -TrxPath $TrxPath
    if ($null -eq $trx) { return @() }

    $errors = New-Object System.Collections.Generic.List[string]
    foreach ($info in $trx.GetElementsByTagName('RunInfo')) {
        if ($info.GetAttribute('outcome') -ne 'Error') { continue }
        $textNode = $info.GetElementsByTagName('Text') | Select-Object -First 1
        $text = ''
        if ($null -ne $textNode) { $text = $textNode.InnerText.Trim() }
        $errors.Add($text)
    }
    return $errors.ToArray()
}

function Get-AhkFlowRunFailure {
    <#
      Every failure one run folder shows, as objects of Kind 'test', 'slice', 'evidence' or 'run'.

      A run whose run.json says Failed always gives at least one failure. The order of the checks
      matters: a run whose results are not its own gives only that.

      Each run error in a Slice's TRX, such as a test host crash, is a run failure of that Slice.
      It counts whatever else the Slice shows: next to a failing test, and also when the Slice
      exited 0. It replaces that Slice's Slice failure, because it already explains the exit code.

      A run failure with no Slice is given only when nothing else explains why the run failed. A
      coverage threshold failure after clean Slices is such a run failure.
    #>
    param(
        [Parameter(Mandatory = $true)][string] $RunFolder,
        [Parameter(Mandatory = $true)][string] $Mode
    )

    $failures = New-Object System.Collections.Generic.List[object]
    $runPath = Join-Path $RunFolder 'run.json'
    if (-not (Test-Path -LiteralPath $runPath -PathType Leaf)) {
        $failures.Add((New-AhkFlowRunFailureEntry -Kind 'evidence' -Cause 'no run.json'))
        return $failures.ToArray()
    }
    $run = Get-Content -LiteralPath $runPath -Raw | ConvertFrom-Json
    $failed = [bool](Get-AhkFlowJsonValue $run 'Failed')
    $message = Get-AhkFlowJsonValue $run 'Message'

    if ((Get-AhkFlowJsonValue $run 'EvidenceOwned') -eq $false) {
        $failures.Add((New-AhkFlowRunFailureEntry -Kind 'evidence' -Cause "no evidence from this attempt: $(Get-AhkFlowFailureCause -Message $message)"))
        return $failures.ToArray()
    }

    $results = Join-Path $RunFolder 'results'
    $slicesPath = Join-Path $results 'slices.json'
    if (-not (Test-Path -LiteralPath $slicesPath -PathType Leaf)) {
        $failures.Add((New-AhkFlowRunFailureEntry -Kind 'evidence' -Cause 'no Slice results: the run failed before its Slices'))
        return $failures.ToArray()
    }
    # Piped, not wrapped: Windows PowerShell 5.1 hands a JSON array on as one object.
    $slices = @(Get-Content -LiteralPath $slicesPath -Raw | ConvertFrom-Json | ForEach-Object { $_ })

    $coverageLines = @()
    if ($Mode -eq 'Coverage') {
        $listPath = Join-Path $results 'coverage-files.txt'
        if (Test-Path -LiteralPath $listPath -PathType Leaf) {
            $coverageLines = @(Get-Content -LiteralPath $listPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    ForEach-Object { $_.Trim().Replace('/', '\') })
        }
    }

    $missingCoverage = $false
    foreach ($slice in $slices) {
        $name = [string](Get-AhkFlowJsonValue $slice 'Name')
        $folderName = [string](Get-AhkFlowJsonValue $slice 'Folder')
        $exitCode = [int](Get-AhkFlowJsonValue $slice 'ExitCode')
        $folder = Join-Path $results $folderName

        $testFailures = 0
        $runErrors = 0
        $trxPath = Get-AhkFlowLatestTrxPath -ResultsDirectory $folder
        if (-not $trxPath) {
            $failures.Add((New-AhkFlowRunFailureEntry -Kind 'evidence' -Slice $name -Cause 'no TRX file'))
        }
        else {
            if ((Get-AhkFlowTestCount -TrxPath $trxPath) -lt 1) {
                $failures.Add((New-AhkFlowRunFailureEntry -Kind 'evidence' -Slice $name -Cause 'TRX counts no test'))
            }
            foreach ($testFailure in @(Get-AhkFlowTrxFailure -TrxPath $trxPath)) {
                $testFailures++
                $failures.Add((New-AhkFlowRunFailureEntry -Kind 'test' -Slice $name -Test $testFailure.Test `
                            -Cause (Get-AhkFlowFailureCause -Message $testFailure.Message)))
            }
            foreach ($runError in @(Get-AhkFlowTrxRunError -TrxPath $trxPath)) {
                $runErrors++
                $failures.Add((New-AhkFlowRunFailureEntry -Kind 'run' -Slice $name -Cause (Get-AhkFlowFailureCause -Message $runError)))
            }
        }

        if ($exitCode -ne 0 -and $testFailures -eq 0 -and $runErrors -eq 0) {
            $cause = "exit code $exitCode"
            $logPath = Join-Path $folder ([string](Get-AhkFlowJsonValue $slice 'Log'))
            if (Test-Path -LiteralPath $logPath -PathType Leaf) {
                $line = Get-Content -LiteralPath $logPath |
                    Where-Object { $_ -match '(?i)\b(error|aborted|crash|crashed|exception)\b' } |
                    Select-Object -First 1
                if ($line) { $cause = Get-AhkFlowFailureCause -Message $line }
            }
            $failures.Add((New-AhkFlowRunFailureEntry -Kind 'slice' -Slice $name -Cause $cause))
        }

        if ($Mode -eq 'Coverage') {
            $prefix = $folderName + '\'
            if (@($coverageLines | Where-Object { $_.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) {
                $missingCoverage = $true
                $failures.Add((New-AhkFlowRunFailureEntry -Kind 'evidence' -Slice $name -Cause 'no coverage file'))
            }
        }
    }

    if ($Mode -eq 'Coverage' -and -not $missingCoverage -and
        -not (Test-Path -LiteralPath (Join-Path $RunFolder 'report\Summary.json') -PathType Leaf)) {
        $failures.Add((New-AhkFlowRunFailureEntry -Kind 'evidence' -Cause 'no merged report'))
    }

    if ($failed -and $failures.Count -eq 0) {
        $failures.Add((New-AhkFlowRunFailureEntry -Kind 'run' -Cause (Get-AhkFlowFailureCause -Message $message)))
    }
    return $failures.ToArray()
}

function Get-AhkFlowCoverageFigure {
    <#
      The coverage figures of one reportgenerator Summary.json: one entry per assembly, with its
      four figures and a Classes map that holds the same four figures per class.

      The result is always an array, also for one assembly, so a caller can collect several runs'
      figures without them running together.
    #>
    param([Parameter(Mandatory = $true)][string] $SummaryPath)

    # Get-Content drops the byte order mark that reportgenerator may write.
    $summary = Get-Content -LiteralPath $SummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $coverage = Get-AhkFlowJsonValue $summary 'coverage'
    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($assembly in @(Get-AhkFlowJsonValue $coverage 'assemblies' | ForEach-Object { $_ })) {
        $classes = [ordered]@{}
        foreach ($class in @(Get-AhkFlowJsonValue $assembly 'classesinassembly' | ForEach-Object { $_ })) {
            $classes[[string]$class.name] = [pscustomobject]@{
                CoverableLines = [int](Get-AhkFlowJsonValue $class 'coverablelines')
                TotalBranches = [int](Get-AhkFlowJsonValue $class 'totalbranches')
                CoveredLines = [int](Get-AhkFlowJsonValue $class 'coveredlines')
                CoveredBranches = [int](Get-AhkFlowJsonValue $class 'coveredbranches')
            }
        }
        $entries.Add([pscustomobject]@{
                Name = [string]$assembly.name
                CoverableLines = [int](Get-AhkFlowJsonValue $assembly 'coverablelines')
                TotalBranches = [int](Get-AhkFlowJsonValue $assembly 'totalbranches')
                CoveredLines = [int](Get-AhkFlowJsonValue $assembly 'coveredlines')
                CoveredBranches = [int](Get-AhkFlowJsonValue $assembly 'coveredbranches')
                Classes = $classes
            })
    }
    return , $entries.ToArray()
}

function New-AhkFlowFigureDifference {
    param([string] $Check, [string] $Assembly, [string] $Class, [string] $Field, [object] $Expected, [object] $Actual)
    return [pscustomobject]@{ Check = $Check; Assembly = $Assembly; Class = $Class; Field = $Field; Expected = $Expected; Actual = $Actual }
}

function Compare-AhkFlowCoverageFigure {
    <#
      The differences between one run's coverage figures and the reference runs (D12).

      Completeness compares with Reference[0]: the same assemblies and classes, and per assembly
      exactly the same CoverableLines and TotalBranches. With -Outcome it also checks that each
      class's CoveredLines and CoveredBranches lie between the lowest and the highest value the
      reference runs show.

      Reference is a list of runs, and each run is the array Get-AhkFlowCoverageFigure returns.
      Pass one run as @(, $figures), or PowerShell spreads its assemblies into separate runs.
    #>
    param(
        [Parameter(Mandatory = $true)][object[]] $Reference,
        [Parameter(Mandatory = $true)][object] $Candidate,
        [switch] $Outcome
    )

    $differences = New-Object System.Collections.Generic.List[object]
    $baseByName = [ordered]@{}
    foreach ($assembly in @($Reference[0])) { $baseByName[$assembly.Name] = $assembly }
    $candidateByName = [ordered]@{}
    foreach ($assembly in @($Candidate)) { $candidateByName[$assembly.Name] = $assembly }

    foreach ($name in $baseByName.Keys) {
        if (-not $candidateByName.Contains($name)) {
            $differences.Add((New-AhkFlowFigureDifference 'completeness' $name $null 'assembly' 'present' 'missing'))
        }
    }
    foreach ($name in $candidateByName.Keys) {
        if (-not $baseByName.Contains($name)) {
            $differences.Add((New-AhkFlowFigureDifference 'completeness' $name $null 'assembly' 'absent' 'present'))
            continue
        }
        $base = $baseByName[$name]
        $candidate = $candidateByName[$name]
        foreach ($field in 'CoverableLines', 'TotalBranches') {
            if ($base.$field -ne $candidate.$field) {
                $differences.Add((New-AhkFlowFigureDifference 'completeness' $name $null $field $base.$field $candidate.$field))
            }
        }
        foreach ($class in $base.Classes.Keys) {
            if (-not $candidate.Classes.Contains($class)) {
                $differences.Add((New-AhkFlowFigureDifference 'completeness' $name $class 'class' 'present' 'missing'))
            }
        }
        foreach ($class in $candidate.Classes.Keys) {
            if (-not $base.Classes.Contains($class)) {
                $differences.Add((New-AhkFlowFigureDifference 'completeness' $name $class 'class' 'absent' 'present'))
            }
        }
    }

    if ($Outcome) {
        foreach ($name in $candidateByName.Keys) {
            $candidate = $candidateByName[$name]
            foreach ($class in $candidate.Classes.Keys) {
                foreach ($field in 'CoveredLines', 'CoveredBranches') {
                    $values = @(foreach ($run in $Reference) {
                            $assembly = @($run) | Where-Object { $_.Name -eq $name } | Select-Object -First 1
                            if ($null -ne $assembly -and $assembly.Classes.Contains($class)) { $assembly.Classes[$class].$field }
                        })
                    if ($values.Count -eq 0) { continue }
                    $lowest = ($values | Measure-Object -Minimum).Minimum
                    $highest = ($values | Measure-Object -Maximum).Maximum
                    $actual = $candidate.Classes[$class].$field
                    if ($actual -lt $lowest -or $actual -gt $highest) {
                        $differences.Add((New-AhkFlowFigureDifference 'outcome' $name $class $field "$lowest..$highest" $actual))
                    }
                }
            }
        }
    }
    return $differences.ToArray()
}

function Test-AhkFlowTimeSaving {
    <#
      True when a setting saves time: its slowest run is faster than the fastest sequence run
      (D10). A median can hide a slow run, and this rule cannot.
    #>
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][double[]] $Sequence,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][double[]] $Candidate
    )
    if ($Sequence.Count -eq 0 -or $Candidate.Count -eq 0) { return $false }
    $slowest = ($Candidate | Measure-Object -Maximum).Maximum
    $fastest = ($Sequence | Measure-Object -Minimum).Minimum
    return [bool]($slowest -lt $fastest)
}

function Get-AhkFlowSoakVerdict {
    <#
      One verdict per failure key of a candidate Soak (D11).

      A failure is 'existing' only when the sequence Soak shows the same key at least as often.
      Everything else is 'not cleared'. An evidence failure or a run failure is never cleared,
      even when the sequence Soak shows the same key. Such a failure says the run itself went
      wrong, such as a crashed test host, and a crash in the sequence does not make it harmless.
    #>
    param(
        [AllowEmptyCollection()][object[]] $Candidate = @(),
        [AllowNull()][AllowEmptyCollection()][object[]] $Sequence = @()
    )

    $sequenceCount = @{}
    foreach ($failure in @($Sequence | Where-Object { $null -ne $_ })) {
        $sequenceCount[$failure.Key] = 1 + [int]$sequenceCount[$failure.Key]
    }

    $groups = [ordered]@{}
    foreach ($failure in @($Candidate | Where-Object { $null -ne $_ })) {
        if (-not $groups.Contains($failure.Key)) { $groups[$failure.Key] = @{ First = $failure; Count = 0 } }
        $groups[$failure.Key].Count++
    }

    foreach ($key in $groups.Keys) {
        $first = $groups[$key].First
        $count = $groups[$key].Count
        $seen = [int]$sequenceCount[$key]
        $verdict = 'not cleared'
        if ($first.Kind -ne 'evidence' -and $first.Kind -ne 'run' -and $seen -ge $count) { $verdict = 'existing' }
        [pscustomobject]@{
            Key = $key; Kind = $first.Kind; Slice = $first.Slice; Test = $first.Test; Cause = $first.Cause
            CandidateCount = $count; SequenceCount = $seen; Verdict = $verdict
        }
    }
}
