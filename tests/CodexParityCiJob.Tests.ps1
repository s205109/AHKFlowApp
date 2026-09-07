#Requires -Version 7.0

# Backlog 136. tests/powershell-suites.json is the one record of which CI job runs which suite.
# The codex-skills-hash-parity job used to name its suite in ci.yml, so the manifest's
# codex-parity entry was read by nothing. This suite proves the job hands the whole choice to
# the runner, which is what makes the manifest the only place that choice is written down.
#
# It holds no list of suite names on purpose. A list here would be a second place to write the
# same thing, which is the problem the item set out to remove. What it checks instead is that
# the job's command can select nothing but the manifest's codex-parity set.
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

# The script the job must call, forward-slashed and with no leading './'. Every accepted
# spelling normalises to exactly this.
$runnerPath = 'scripts/run-powershell-suites.ps1'

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

# One YAML scalar, decoded to the text the shell would receive.
#
# A quoted scalar is still the same command. Handing the quotes to the PowerShell parser turns
# the whole command into a string literal, and this suite would then fail a rewrite that changed
# nothing about what runs.
function ConvertFrom-YamlScalar {
    param([string] $Value)

    $text = $Value.Trim()
    if ($text.Length -lt 2) { return $text }

    # Single-quoted: no escapes at all, except '' for one quote character.
    if ($text.StartsWith("'") -and $text.EndsWith("'")) {
        return $text.Substring(1, $text.Length - 2).Replace("''", "'")
    }

    # Double-quoted: backslash escapes. Only the two that can appear in a shell command are
    # decoded; the rest are left alone rather than guessed at.
    if ($text.StartsWith('"') -and $text.EndsWith('"')) {
        return $text.Substring(1, $text.Length - 2) -replace '\\(["\\])', '$1'
    }

    return $text
}

# Every run: command inside one job block, as the text the shell would receive.
#
# A run: value is either a scalar on the same line, or a block scalar whose text sits on the
# indented lines below it. Every form is read, because a step rewritten from one to another must
# not make this suite pass by reading nothing, and must not fail it either.
function Get-RunCommand {
    param([string] $Block)

    $lines = $Block -split "`n"
    $commands = [System.Collections.Generic.List[string]]::new()

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $match = [regex]::Match($lines[$i], '^(?<indent>\s*)(?:-\s+)?run:\s*(?<value>.*?)\s*$')
        if (-not $match.Success) { continue }

        $value = $match.Groups['value'].Value

        # '|', '>', '|-', '>+2' and so on introduce a block scalar and carry no command text.
        $blockScalar = [regex]::Match($value, '^(?<style>[|>])[-+]?[0-9]*$')
        if ($blockScalar.Success) {
            # '|' keeps the line breaks; '>' folds them into single spaces. Reading a folded
            # scalar as a literal one splits one command into two statements, and the second
            # statement carries the arguments that make the first one correct.
            $separator = if ($blockScalar.Groups['style'].Value -eq '>') { ' ' } else { "`n" }

            $keyIndent = $match.Groups['indent'].Value.Length
            $text = [System.Collections.Generic.List[string]]::new()
            for ($j = $i + 1; $j -lt $lines.Count; $j++) {
                $next = $lines[$j]
                if ([string]::IsNullOrWhiteSpace($next)) { continue }
                $nextIndent = $next.Length - $next.TrimStart().Length
                if ($nextIndent -le $keyIndent) { break }
                $text.Add($next.Trim())
            }
            $commands.Add(($text -join $separator))
            continue
        }

        $commands.Add((ConvertFrom-YamlScalar -Value $value))
    }

    return $commands.ToArray()
}

# True when this command's target is the runner itself.
#
# An exact comparison, not a wildcard. A wildcard accepts any script whose name merely contains
# the runner's, so 'not-the-real-run-powershell-suites.ps1.bak' would pass. Quotes are stripped
# and separators normalised first, so the spellings a workflow may legally use all resolve to
# the same path.
#
# A wrapper such as 'pwsh -File ./scripts/run-powershell-suites.ps1' is deliberately not
# accepted. The job declares 'shell: pwsh' and calls the script directly, and this suite can
# only reason about arguments it can see on the runner's own call.
function Test-TargetIsRunner {
    param([System.Management.Automation.Language.Ast] $Target, [string] $RunnerPath)

    $text = $Target.Extent.Text.Trim()
    if ($text.Length -ge 2 -and
        (($text.StartsWith("'") -and $text.EndsWith("'")) -or ($text.StartsWith('"') -and $text.EndsWith('"')))) {
        $text = $text.Substring(1, $text.Length - 2)
    }

    $text = ($text -replace '\\', '/') -replace '^\./', ''
    return $text -eq $RunnerPath
}

# What one run: command does with the runner.
#
# Read it from the syntax tree, never from the text. The parser drops comments, so a name that
# appears only in a YAML comment above the step cannot satisfy this.
function Read-RunnerInvocation {
    param([string] $Command, [string] $RunnerPath = 'scripts/run-powershell-suites.ps1')

    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Command, [ref] $null, [ref] $errors)

    $calls = @($ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst]
            }, $true))

    $allRunnerCalls = @($calls | Where-Object {
            Test-TargetIsRunner -Target (@($_.CommandElements)[0]) -RunnerPath $RunnerPath
        })

    # Only a statement at the top of the script runs unconditionally. A call inside an if, a
    # loop, a try, or a function body may never execute at all, and a job that ran no suite
    # must not look green. So the counted calls are the top-level ones, and anything nested is
    # reported separately rather than quietly ignored.
    $topLevel = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $ast.EndBlock) {
        foreach ($statement in $ast.EndBlock.Statements) {
            if ($statement -isnot [System.Management.Automation.Language.PipelineAst]) { continue }
            foreach ($element in $statement.PipelineElements) {
                if ($element -is [System.Management.Automation.Language.CommandAst] -and
                    (Test-TargetIsRunner -Target (@($element.CommandElements)[0]) -RunnerPath $RunnerPath)) {
                    $topLevel.Add($element)
                }
            }
        }
    }

    $jobValues = @()
    $narrowing = @()

    foreach ($call in $topLevel) {
        $elements = @($call.CommandElements)
        for ($i = 0; $i -lt $elements.Count; $i++) {
            $element = $elements[$i]

            # A splatted variable carries its argument names inside a hashtable, so no parameter
            # node exists for this loop to read. That is not a clean call: it could hold -Suite
            # or -SuiteRoot and look identical here. Reject it rather than pass what cannot be
            # read.
            if ($element -is [System.Management.Automation.Language.VariableExpressionAst] -and $element.Splatted) {
                $narrowing += "@$($element.VariablePath.UserPath) (splatted, so its arguments cannot be read)"
                continue
            }

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
        ParseErrorCount       = @($errors).Count
        CallCount             = $calls.Count
        RunnerCallCount       = $topLevel.Count
        NestedRunnerCallCount = $allRunnerCalls.Count - $topLevel.Count
        JobValues             = $jobValues
        Narrowing             = $narrowing
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

$invocations = @($runCommands | ForEach-Object { Read-RunnerInvocation -Command $_ -RunnerPath $runnerPath })

$parseErrors = @($invocations | Where-Object { $_.ParseErrorCount -gt 0 }).Count
Assert-True ($parseErrors -eq 0) "Every run: command in the '$jobName' job must parse as PowerShell. $parseErrors did not."

$runnerCallCount = ($invocations | Measure-Object -Property RunnerCallCount -Sum).Sum
Assert-True ($runnerCallCount -eq 1) "The '$jobName' job must invoke $runnerPath exactly once, as a top-level statement. Found $runnerCallCount."

$nestedCount = ($invocations | Measure-Object -Property NestedRunnerCallCount -Sum).Sum
Assert-True ($nestedCount -eq 0) "The '$jobName' job must not call the runner from inside a condition, a loop, or a function body: such a call may never run. Found $nestedCount."

$jobValues = @($invocations | ForEach-Object { $_.JobValues })
Assert-True (($jobValues -join ',') -eq 'codex-parity') "The '$jobName' job must pass -Job codex-parity. Found: '$($jobValues -join ',')'"

$narrowing = @($invocations | ForEach-Object { $_.Narrowing })
Assert-True ($narrowing.Count -eq 0) "The '$jobName' job must pass no argument that narrows the selection below the manifest's codex-parity set. Found: $($narrowing -join ', ')"

# --- The assertions above can go red ---

# Each mutation changes the command the way a future edit might, then reads it back. A test that
# cannot be made to fail proves nothing.
$goodCommand = './scripts/run-powershell-suites.ps1 -Job codex-parity'

$wrongJob = Read-RunnerInvocation -Command ($goodCommand -replace 'codex-parity', 'suites') -RunnerPath $runnerPath
Assert-True (($wrongJob.JobValues -join ',') -ne 'codex-parity') 'The -Job assertion must go red when the job names another set.'

$noJob = Read-RunnerInvocation -Command ($goodCommand -replace ' -Job codex-parity', '') -RunnerPath $runnerPath
Assert-True ($noJob.JobValues.Count -eq 0) 'The -Job assertion must go red when the step passes no -Job at all.'

$withSuite = Read-RunnerInvocation -Command "$goodCommand -Suite 'CodexSkillsHashParity.Tests.ps1'" -RunnerPath $runnerPath
Assert-True ($withSuite.Narrowing.Count -gt 0) 'The no-narrowing assertion must go red when the step adds a -Suite filter.'

$withSuiteRoot = Read-RunnerInvocation -Command "$goodCommand -SuiteRoot 'other'" -RunnerPath $runnerPath
Assert-True ($withSuiteRoot.Narrowing.Count -gt 0) 'The no-narrowing assertion must go red when the step points the run at another folder.'

$wrongTarget = Read-RunnerInvocation -Command ($goodCommand -replace 'run-powershell-suites\.ps1', 'something-else.ps1') -RunnerPath $runnerPath
Assert-True ($wrongTarget.RunnerCallCount -eq 0) 'The invocation assertion must go red when the step runs another command.'
Assert-True ($wrongTarget.JobValues.Count -eq 0) 'Arguments must be read from the runner call only, never from another command.'

# The shape this item replaced. It must be caught, or the whole change could be reverted quietly.
$oldStyle = @(Get-DirectSuiteCall -Command @('./tests/CodexSkillsHashParity.Tests.ps1'))
Assert-True ($oldStyle.Count -eq 1) 'The direct-suite assertion must go red when a step names a suite file.'

# Get-RunCommand reads every YAML scalar form. A step rewritten from one to another must still
# be read, not silently skipped and not wrongly rejected.
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
$fromBlockScalarJob = ((Read-RunnerInvocation -Command $fromBlockScalar[0] -RunnerPath $runnerPath).JobValues -join ',')
Assert-True ($fromBlockScalarJob -eq 'codex-parity') "A block-scalar run: must yield the same invocation as a same-line one. Got: '$fromBlockScalarJob'"

# --- Review round: shapes that must not satisfy this suite ---

# Splatting. The runner's arguments arrive in a hashtable, so no parameter node carries their
# names, and a reader that only inspects those nodes sees a clean call.
$splattedSuiteRoot = Read-RunnerInvocation -Command "`$options = @{ SuiteRoot = 'other' }`n$goodCommand @options" -RunnerPath $runnerPath
Assert-True ($splattedSuiteRoot.Narrowing.Count -gt 0) 'A splatted -SuiteRoot must be rejected: this suite cannot read what the hashtable holds.'

$splattedSuite = Read-RunnerInvocation -Command "`$options = @{ Suite = 'CodexSkillsHashParity.Tests.ps1' }`n$goodCommand @options" -RunnerPath $runnerPath
Assert-True ($splattedSuite.Narrowing.Count -gt 0) 'A splatted -Suite must be rejected: this suite cannot read what the hashtable holds.'

# A call that never runs. The job would be green having run no suite at all.
$deadCall = Read-RunnerInvocation -Command "if (`$false) {`n    $goodCommand`n}" -RunnerPath $runnerPath
Assert-True ($deadCall.RunnerCallCount -eq 0) 'A runner call inside an if block must not count: it may never run.'
Assert-True ($deadCall.NestedRunnerCallCount -eq 1) 'A runner call inside an if block must be reported as nested, not ignored.'

$inFunction = Read-RunnerInvocation -Command "function Never { $goodCommand }" -RunnerPath $runnerPath
Assert-True ($inFunction.RunnerCallCount -eq 0) 'A runner call inside a function body must not count: nothing calls it.'
Assert-True ($inFunction.NestedRunnerCallCount -eq 1) 'A runner call inside a function body must be reported as nested, not ignored.'

# A target whose name merely contains the runner's.
$lookalike = Read-RunnerInvocation -Command './scripts/not-the-real-run-powershell-suites.ps1.bak -Job codex-parity' -RunnerPath $runnerPath
Assert-True ($lookalike.RunnerCallCount -eq 0) 'A script whose name only contains the runner''s must not count as the runner.'
Assert-True ($lookalike.NestedRunnerCallCount -eq 0) 'A lookalike target is not the runner anywhere, nested or not.'

# Spellings that are the runner and must keep counting.
foreach ($spelling in @(
        './scripts/run-powershell-suites.ps1 -Job codex-parity',
        'scripts/run-powershell-suites.ps1 -Job codex-parity',
        '.\scripts\run-powershell-suites.ps1 -Job codex-parity',
        '& ''./scripts/run-powershell-suites.ps1'' -Job codex-parity')) {
    $accepted = Read-RunnerInvocation -Command $spelling -RunnerPath $runnerPath
    Assert-True ($accepted.RunnerCallCount -eq 1) "This spelling names the runner and must count: $spelling"
}

# YAML scalar forms a workflow may legally use for the same command. Rejecting one of these
# would fail a rewrite that changed nothing about what runs.
$quotedForms = @{
    'double-quoted' = "  a-job:`n    steps:`n      - name: One`n        run: `"./scripts/run-powershell-suites.ps1 -Job codex-parity`""
    'single-quoted' = "  a-job:`n    steps:`n      - name: One`n        run: './scripts/run-powershell-suites.ps1 -Job codex-parity'"
}
foreach ($form in $quotedForms.GetEnumerator()) {
    $captured = @(Get-RunCommand -Block $form.Value)
    Assert-True ($captured.Count -eq 1) "Get-RunCommand must read a $($form.Key) run:. Got $($captured.Count)."
    if ($captured.Count -eq 1) {
        $read = Read-RunnerInvocation -Command $captured[0] -RunnerPath $runnerPath
        Assert-True ($read.RunnerCallCount -eq 1) "A $($form.Key) run: must still name the runner. Got $($read.RunnerCallCount) call(s)."
        Assert-True (($read.JobValues -join ',') -eq 'codex-parity') "A $($form.Key) run: must still pass -Job codex-parity. Got: '$($read.JobValues -join ',')'"
    }
}

# A folded block scalar joins its lines with a space. Joining with a newline instead would split
# one command into two statements and drop its arguments.
$foldedBlock = "  a-job:`n    steps:`n      - name: One`n        run: >`n          ./scripts/run-powershell-suites.ps1`n          -Job codex-parity"
$fromFolded = @(Get-RunCommand -Block $foldedBlock)
Assert-True ($fromFolded.Count -eq 1) "Get-RunCommand must read a folded run:. Got $($fromFolded.Count)."
if ($fromFolded.Count -eq 1) {
    $foldedRead = Read-RunnerInvocation -Command $fromFolded[0] -RunnerPath $runnerPath
    Assert-True ($foldedRead.RunnerCallCount -eq 1) "A folded run: must name the runner once. Got $($foldedRead.RunnerCallCount)."
    Assert-True (($foldedRead.JobValues -join ',') -eq 'codex-parity') "A folded run: must keep its -Job argument. Got: '$($foldedRead.JobValues -join ',')'"
}

# --- The manifest's codex-parity job can be selected, and runs where it says ---

# No list of suite names lives here. The job hands its whole selection to the runner, and the
# runner reads the manifest, so the names are written down once. What still needs checking is
# that the set the runner would select is one a run can actually cover.

. (Join-Path $repoRoot 'scripts/powershell-suites.common.ps1')

$manifestPath = Join-Path $repoRoot 'tests/powershell-suites.json'
$discovered = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'tests') -Filter '*.Tests.ps1' -File | ForEach-Object { $_.Name })
$manifestEntries = @(Read-SuiteManifest -Path $manifestPath -DiscoveredName $discovered)

$inJob = @($manifestEntries | Where-Object { $_.Jobs -contains 'codex-parity' })

# An empty set makes the job fail at run time rather than silently pass, but it fails in CI on
# Linux, minutes later and in another job's log. Saying so here is cheaper to read.
Assert-True ($inJob.Count -gt 0) 'The manifest names no suite for the codex-parity job, so that job has nothing to run.'

# The job runs on Linux, so every suite in it has to be one a Linux run has passed. An entry
# without 'linux' here would be scheduled by ci.yml and then dropped by the runner's platform
# filter, and the job would look green having run nothing.
foreach ($entry in $inJob) {
    Assert-True ($entry.Platform -contains 'linux') "$($entry.Name) is in the codex-parity job, which runs on Linux, so its platform must include linux. Found: $($entry.Platform -join ', ')"
}

# The set the job's own command would select on its own platform. This is the claim the whole
# suite exists to make, and it is asked of the runner rather than restated here.
$selected = @(Select-SuiteEntry -Entry $manifestEntries -Job 'codex-parity' -Platform 'linux')
Assert-True ($selected.Count -eq $inJob.Count) "The runner must select every codex-parity suite on Linux. Manifest holds $($inJob.Count), runner selects $($selected.Count)."

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
