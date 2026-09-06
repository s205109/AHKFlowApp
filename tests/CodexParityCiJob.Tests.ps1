#Requires -Version 7.0

# Backlog 136. tests/powershell-suites.json is the one record of which CI job runs which suite.
# The codex-skills-hash-parity job used to name its suite in ci.yml, so the manifest's
# codex-parity entry was read by nothing. This suite proves the job goes through the runner, and
# that the manifest's codex-parity set is the set this file names.
#
# tests/RepoInvariantsCiJob.Tests.ps1 does the same job for the repo-invariants job. That one
# parses a .ps1 file and follows a variable; this one parses a YAML run: string. The two are
# deliberately separate.
#
# Run it by hand with:  pwsh ./tests/CodexParityCiJob.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$failures = @()
function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { $script:failures += $Message }
}

$jobName = 'codex-skills-hash-parity'

# The suites the codex-parity job runs. This is a literal here and the manifest is another file,
# so the comparison below is two-sided: it goes red when somebody adds a suite to that job, or
# drops one, without saying so here. That is the drift the acceptance criterion asks about.
$expectedSuites = @(
    'CodexSkillsHashParity.Tests.ps1'
)

# --- Read the job block out of ci.yml ---

# YAML allows a job key to be quoted, so 'codex-skills-hash-parity': names the same job as the
# unquoted form. Both patterns come from tests/RepoInvariantsCiJob.Tests.ps1, which reads the
# same file the same way.
$anyJobKeyPattern = '^  [''"]?[A-Za-z0-9_-]+[''"]?:\s*$'

$ciPath = Join-Path $repoRoot '.github/workflows/ci.yml'
Assert-True (Test-Path -LiteralPath $ciPath) '.github/workflows/ci.yml must exist'

$ciRaw = (Get-Content -LiteralPath $ciPath) -join "`n"
$jobPattern = '(?ms)^  [''"]?' + [regex]::Escape($jobName) + '[''"]?:\s*$.*?(?=' + $anyJobKeyPattern + '|\z)'
$jobBlock = [regex]::Match($ciRaw, $jobPattern).Value

Assert-True (-not [string]::IsNullOrWhiteSpace($jobBlock)) "ci.yml must define a '$jobName' job."

# Every run: command inside one job block, as text.
#
# A run: value is either a scalar on the same line, or a block scalar whose text sits on the
# indented lines below it. Both forms are read, because a step rewritten from one to the other
# must not make this suite pass by reading nothing.
function Get-RunCommand {
    param([string] $Block)

    $lines = $Block -split "`n"
    $commands = [System.Collections.Generic.List[string]]::new()

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $match = [regex]::Match($lines[$i], '^(?<indent>\s*)(?:-\s+)?run:\s*(?<value>.*?)\s*$')
        if (-not $match.Success) { continue }

        $value = $match.Groups['value'].Value

        # '|', '>', '|-', '>+2' and so on introduce a block scalar and carry no command text.
        if ($value -match '^[|>][-+]?[0-9]*$') {
            $keyIndent = $match.Groups['indent'].Value.Length
            $text = [System.Collections.Generic.List[string]]::new()
            for ($j = $i + 1; $j -lt $lines.Count; $j++) {
                $next = $lines[$j]
                if ([string]::IsNullOrWhiteSpace($next)) { continue }
                $nextIndent = $next.Length - $next.TrimStart().Length
                if ($nextIndent -le $keyIndent) { break }
                $text.Add($next.Trim())
            }
            $commands.Add(($text -join "`n"))
            continue
        }

        $commands.Add($value)
    }

    return $commands.ToArray()
}

# What one run: command does with the runner.
#
# Read it from the syntax tree, never from the text. The parser drops comments, so a name that
# appears only in a YAML comment above the step cannot satisfy this.
function Read-RunnerInvocation {
    param([string] $Command)

    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Command, [ref] $null, [ref] $errors)

    $calls = @($ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst]
            }, $true))

    # The command's own target text, never the whole string: a second command on the line is a
    # different call and its arguments are not the runner's.
    $runnerCalls = @($calls | Where-Object {
            @($_.CommandElements)[0].Extent.Text -like '*run-powershell-suites.ps1*'
        })

    $jobValues = @()
    $narrowing = @()

    foreach ($call in $runnerCalls) {
        $elements = @($call.CommandElements)
        for ($i = 0; $i -lt $elements.Count; $i++) {
            $element = $elements[$i]
            if ($element -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }

            $name = $element.ParameterName

            # -Suite picks a subset and -SuiteRoot points the run at another folder. Either one
            # narrows the selection below the manifest's codex-parity set, which is the miss this
            # suite forbids. PowerShell accepts an abbreviated name, so match any prefix of either.
            if ('Suite'.StartsWith($name, [System.StringComparison]::OrdinalIgnoreCase) -or
                'SuiteRoot'.StartsWith($name, [System.StringComparison]::OrdinalIgnoreCase)) {
                $narrowing += "-$name"
                continue
            }

            if (-not 'Job'.StartsWith($name, [System.StringComparison]::OrdinalIgnoreCase)) { continue }

            # '-Job:codex-parity' carries its value on the parameter; '-Job codex-parity' carries
            # it in the next element. Read a literal only, so a computed value cannot pass.
            $argument = $element.Argument
            if ($null -eq $argument -and ($i + 1) -lt $elements.Count) { $argument = $elements[$i + 1] }
            if ($argument -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                $jobValues += $argument.Value
            } else {
                $jobValues += '<not a literal>'
            }
        }
    }

    return [pscustomobject]@{
        ParseErrorCount = @($errors).Count
        CallCount       = $calls.Count
        RunnerCallCount = $runnerCalls.Count
        JobValues       = $jobValues
        Narrowing       = $narrowing
    }
}

# Every suite file a run: command names directly. A job that starts a suite this way runs it
# whatever the manifest says, which is the drift this whole item closes.
function Get-DirectSuiteCall {
    param([string[]] $Command)

    $found = @()
    foreach ($text in $Command) {
        foreach ($match in [regex]::Matches($text, '[A-Za-z0-9_.-]+\.Tests\.ps1')) {
            $found += $match.Value
        }
    }
    return $found
}

# --- The job starts its suites through the runner ---

$runCommands = @(Get-RunCommand -Block $jobBlock)
Assert-True ($runCommands.Count -ge 1) "The '$jobName' job must have at least one run: step."

$directCalls = @(Get-DirectSuiteCall -Command $runCommands)
Assert-True ($directCalls.Count -eq 0) "The '$jobName' job must name no suite file. The manifest is the list. Found: $($directCalls -join ', ')"

$invocations = @($runCommands | ForEach-Object { Read-RunnerInvocation -Command $_ })

$parseErrors = @($invocations | Where-Object { $_.ParseErrorCount -gt 0 }).Count
Assert-True ($parseErrors -eq 0) "Every run: command in the '$jobName' job must parse as PowerShell. $parseErrors did not."

$runnerCallCount = ($invocations | Measure-Object -Property RunnerCallCount -Sum).Sum
Assert-True ($runnerCallCount -eq 1) "The '$jobName' job must invoke run-powershell-suites.ps1 exactly once. Found $runnerCallCount."

$jobValues = @($invocations | ForEach-Object { $_.JobValues })
Assert-True (($jobValues -join ',') -eq 'codex-parity') "The '$jobName' job must pass -Job codex-parity. Found: '$($jobValues -join ',')'"

$narrowing = @($invocations | ForEach-Object { $_.Narrowing })
Assert-True ($narrowing.Count -eq 0) "The '$jobName' job must pass no argument that narrows the selection below the manifest's codex-parity set. Found: $($narrowing -join ', ')"

# --- The assertions above can go red ---

# Each mutation changes the command the way a future edit might, then reads it back. A test that
# cannot be made to fail proves nothing.
$goodCommand = './scripts/run-powershell-suites.ps1 -Job codex-parity'

$wrongJob = Read-RunnerInvocation -Command ($goodCommand -replace 'codex-parity', 'suites')
Assert-True (($wrongJob.JobValues -join ',') -ne 'codex-parity') 'The -Job assertion must go red when the job names another set.'

$noJob = Read-RunnerInvocation -Command ($goodCommand -replace ' -Job codex-parity', '')
Assert-True ($noJob.JobValues.Count -eq 0) 'The -Job assertion must go red when the step passes no -Job at all.'

$withSuite = Read-RunnerInvocation -Command "$goodCommand -Suite 'CodexSkillsHashParity.Tests.ps1'"
Assert-True ($withSuite.Narrowing.Count -gt 0) 'The no-narrowing assertion must go red when the step adds a -Suite filter.'

$withSuiteRoot = Read-RunnerInvocation -Command "$goodCommand -SuiteRoot 'other'"
Assert-True ($withSuiteRoot.Narrowing.Count -gt 0) 'The no-narrowing assertion must go red when the step points the run at another folder.'

$wrongTarget = Read-RunnerInvocation -Command ($goodCommand -replace 'run-powershell-suites\.ps1', 'something-else.ps1')
Assert-True ($wrongTarget.RunnerCallCount -eq 0) 'The invocation assertion must go red when the step runs another command.'
Assert-True ($wrongTarget.JobValues.Count -eq 0) 'Arguments must be read from the runner call only, never from another command.'

# The shape this item replaced. It must be caught, or the whole change could be reverted quietly.
$oldStyle = @(Get-DirectSuiteCall -Command @('./tests/CodexSkillsHashParity.Tests.ps1'))
Assert-True ($oldStyle.Count -eq 1) 'The direct-suite assertion must go red when a step names a suite file.'

# Get-RunCommand reads both YAML forms. A step rewritten as a block scalar must still be read,
# not silently skipped.
$scalarBlock = @'
  a-job:
    steps:
      - name: One
        run: ./scripts/run-powershell-suites.ps1 -Job codex-parity
'@
$blockScalarBlock = @'
  a-job:
    steps:
      - name: One
        run: |
          ./scripts/run-powershell-suites.ps1 -Job codex-parity
'@
$fromScalar = @(Get-RunCommand -Block $scalarBlock)
$fromBlockScalar = @(Get-RunCommand -Block $blockScalarBlock)
Assert-True ($fromScalar.Count -eq 1) "Get-RunCommand must read a same-line run:. Got $($fromScalar.Count)."
Assert-True ($fromBlockScalar.Count -eq 1) "Get-RunCommand must read a block-scalar run:. Got $($fromBlockScalar.Count)."
$fromBlockScalarJob = ((Read-RunnerInvocation -Command $fromBlockScalar[0]).JobValues -join ',')
Assert-True ($fromBlockScalarJob -eq 'codex-parity') "A block-scalar run: must yield the same invocation as a same-line one. Got: '$fromBlockScalarJob'"

# --- The manifest's codex-parity job holds exactly the suites this file names ---

. (Join-Path $repoRoot 'scripts/powershell-suites.common.ps1')

$manifestPath = Join-Path $repoRoot 'tests/powershell-suites.json'
$discovered = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'tests') -Filter '*.Tests.ps1' -File | ForEach-Object { $_.Name })
$manifestEntries = @(Read-SuiteManifest -Path $manifestPath -DiscoveredName $discovered)

$inJob = @($manifestEntries | Where-Object { $_.Jobs -contains 'codex-parity' })
$manifestCodex = @($inJob | ForEach-Object { $_.Name } | Sort-Object)
Assert-True ((($manifestCodex) -join ',') -eq (($expectedSuites | Sort-Object) -join ',')) "The manifest's codex-parity job must hold exactly: $(($expectedSuites | Sort-Object) -join ', '). Found: $($manifestCodex -join ', ')"

# The job runs on Linux, so every suite in it has to be one a Linux run has passed. An entry
# without 'linux' here would be scheduled by ci.yml and then dropped by the runner's platform
# filter, and the job would look green having run nothing.
foreach ($entry in $inJob) {
    Assert-True ($entry.Platform -contains 'linux') "$($entry.Name) is in the codex-parity job, which runs on Linux, so its platform must include linux. Found: $($entry.Platform -join ', ')"
}

# --- The job runs on ubuntu-latest ---

# The bash setup script the suite compares against refuses to run under Windows Git Bash, so
# Linux is the only platform this job can use.
Assert-True ($jobBlock -match '(?m)^\s{4}runs-on:\s*ubuntu-latest\s*$') "$jobName must run on ubuntu-latest"
Assert-True (($jobBlock -replace '(?m)^\s{4}runs-on:\s*ubuntu-latest\s*$', '') -notmatch '(?m)^\s{4}runs-on:') "$jobName must declare runs-on once."

# --- Report ---

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host ''; Write-Host $failure -ForegroundColor Red }
    Write-Host ''
    throw "CodexParityCiJob tests failed with $($failures.Count) problem(s)."
}

Write-Host 'CodexParityCiJob tests passed.'
