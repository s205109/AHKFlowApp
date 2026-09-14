#Requires -Version 7.0

# Pins the dotnet test steps of the build-test job in .github/workflows/ci.yml. It reads text with
# regular expressions, the same way tests/ShippingPrClosesItemWorkflow.Tests.ps1 does, because
# PowerShell ships no YAML parser.
#
# Backlog 156 found two faults, and this suite pins both fixes.
#
# One result file name. The step named every result file test-results.trx. All eight test projects
# wrote that one name, each overwrote the one before, and Publish test results read a single file.
#
# E2E beside Docker. One dotnet test call ran every test project at the same time on one runner.
# One project left its SQL container for Ryuk, which removed it 10 seconds after that project
# exited. The removal changed the runner's network. Chromium then failed the downloads of an E2E
# page that was booting at that moment, with net::ERR_NETWORK_CHANGED. So the E2E project now runs
# in a step of its own, before the other test projects.
#
# Run it by hand with:  pwsh ./tests/CiBuildTestSteps.Tests.ps1

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

$E2EProject = 'tests/AHKFlowApp.E2E.Tests/AHKFlowApp.E2E.Tests.csproj'
$E2EExclusion = 'FullyQualifiedName!~AHKFlowApp.E2E.Tests.'

# The workflow's comments name dotnet test and the E2E project while they explain the steps. A
# match on the raw text would count a comment as part of a test step. Drop every whole-line
# comment first.
function Remove-CommentLine {
    param([AllowEmptyString()][string] $Text)
    $kept = @(($Text -split "`r?`n") | Where-Object { $_ -notmatch '^\s*#' })
    return ($kept -join "`n")
}

# The steps of one job, in file order, one string each. A step starts at a line that opens with
# '- ' at the six-space step indent, and runs until the next step or the next job.
function Get-JobStep {
    param([AllowEmptyString()][string] $Text, [string] $Job)

    $steps = @()
    $inJob = $false
    $current = $null
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^  [''"]?[A-Za-z0-9_-]+[''"]?:\s*$') {
            if ($null -ne $current) { $steps += $current; $current = $null }
            $inJob = $line -match ('^  [''"]?' + [regex]::Escape($Job) + '[''"]?:\s*$')
            continue
        }
        if (-not $inJob) { continue }
        if ($line -match '^      - ') {
            if ($null -ne $current) { $steps += $current }
            $current = $line
            continue
        }
        if ($null -ne $current) { $current += "`n" + $line }
    }
    if ($null -ne $current) { $steps += $current }
    return @($steps)
}

# The value of one key of a step, or $null when the step has no such key. A block value, as in
# 'run: >' or 'run: |', continues on every following line indented deeper than the key.
#
# A folded block whose lines share one indent reaches the shell as one line, so it comes back as
# one line. YAML keeps the line breaks of a literal block, of a more-indented line, and of a blank
# line inside a folded block, so those come back as separate lines.
function Get-StepValue {
    param([string] $StepText, [string] $Key)

    $lines = @($StepText -split "`n")
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $match = [regex]::Match($lines[$i], '^(?<indent>\s*(?:-\s+)?)' + [regex]::Escape($Key) + ':\s*(?<rest>.*)$')
        if (-not $match.Success) { continue }

        $rest = $match.Groups['rest'].Value.Trim()
        if ($rest -notmatch '^[>|][+-]?$') { return $rest }

        $keyColumn = $match.Groups['indent'].Length
        $block = @()
        $oneLine = $rest.StartsWith('>')
        $contentIndent = -1
        $sawBlank = $false
        for ($j = $i + 1; $j -lt $lines.Count; $j++) {
            if ($lines[$j].Trim() -eq '') { $sawBlank = $true; continue }
            $indent = $lines[$j].Length - $lines[$j].TrimStart().Length
            if ($indent -le $keyColumn) { break }
            if ($contentIndent -lt 0) { $contentIndent = $indent }
            elseif ($sawBlank -or $indent -ne $contentIndent) { $oneLine = $false }
            $sawBlank = $false
            $block += $lines[$j].Trim()
        }
        $separator = if ($oneLine) { ' ' } else { "`n" }
        return ($block -join $separator)
    }
    return $null
}

# The words of a shell command. A double-quoted part stays inside its word, the way the shell reads
# it, so --collect:"XPlat Code Coverage" is one word.
function Split-CommandWord {
    param([string] $Command)
    return @([regex]::Matches($Command, '(?:[^\s"]+|"[^"]*")+') | ForEach-Object { $_.Value })
}

# The build-test steps whose run: command calls dotnet test. A step name or a comment that mentions
# dotnet test does not make a test step; only the command does.
#
# Arguments are the words after 'dotnet test'. Project is the first of them when it is not an
# option: dotnet test takes its project or solution there, and with none it runs the solution in
# the working directory. Filters holds every --filter value without its quotes. Condition is the
# step's if: expression without its ${{ }} wrapper, or $null when the step has no if:.
# SingleCommand is true when the run: value is one shell command: no line break reaches the shell,
# and no ;, & or | stands outside quotes.
function Get-DotnetTestStep {
    param([AllowEmptyString()][string] $CiText)

    $steps = @(Get-JobStep -Text (Remove-CommentLine -Text $CiText) -Job 'build-test')
    $testSteps = @()
    for ($i = 0; $i -lt $steps.Count; $i++) {
        $run = Get-StepValue -StepText $steps[$i] -Key 'run'
        if ($null -eq $run) { continue }

        $words = @(Split-CommandWord -Command $run)
        $at = -1
        for ($w = 0; $w -lt $words.Count - 1; $w++) {
            if ($words[$w] -ceq 'dotnet' -and $words[$w + 1] -ceq 'test') { $at = $w; break }
        }
        if ($at -lt 0) { continue }

        $arguments = @($words | Select-Object -Skip ($at + 2))

        $project = $null
        if ($arguments.Count -gt 0 -and -not $arguments[0].StartsWith('-')) { $project = $arguments[0] }

        $filters = @()
        for ($a = 0; $a -lt $arguments.Count; $a++) {
            if ($arguments[$a] -ceq '--filter' -and $a + 1 -lt $arguments.Count) {
                $filters += $arguments[$a + 1]
            }
            elseif ($arguments[$a] -match '^--filter[:=](?<value>.+)$') {
                $filters += $Matches.value
            }
        }
        $filters = @($filters | ForEach-Object { $_ -replace '^"(.*)"$', '$1' })

        $condition = Get-StepValue -StepText $steps[$i] -Key 'if'
        if ($null -ne $condition) {
            $condition = ($condition -replace '^\$\{\{\s*(.*?)\s*\}\}$', '$1') -replace '\s+', ' '
        }

        $unquoted = ($run -replace '"[^"]*"', '') -replace "'[^']*'", ''
        $singleCommand = (-not $run.Contains("`n")) -and ($unquoted -notmatch '[;&|]')

        $testSteps += [pscustomobject] @{
            Index         = $i
            Text          = $steps[$i]
            Command       = $run
            Arguments     = $arguments
            Project       = $project
            Filters       = $filters
            Condition     = $condition
            SingleCommand = $singleCommand
        }
    }
    return @($testSteps)
}

# Every problem the dotnet test steps have, one line of text each. No problems means they are right.
function Get-TestStepProblem {
    param([AllowEmptyString()][string] $CiText)

    $problems = @()
    $testSteps = @(Get-DotnetTestStep -CiText $CiText)

    foreach ($step in $testSteps) {
        if ($step.Command.Contains('LogFileName=')) {
            $problems += 'A dotnet test step must not set LogFileName. Every test project then writes that one file, and each overwrites the one before. Pass --logger trx and let VSTest name each file.'
        }

        # The checks below read one dotnet test call. A second command in the same step would run
        # unchecked, and a second dotnet test with no filter runs the E2E tests beside the Docker
        # projects again.
        if (-not $step.SingleCommand) {
            $problems += 'Every dotnet test step must run exactly one command: one dotnet test call, with no second line and no ;, & or | outside quotes. A second command runs without these checks.'
        }
    }

    if ($testSteps.Count -lt 2) {
        $problems += 'The build-test job must run dotnet test in two steps: the E2E project alone, then every other test project.'
        return @($problems)
    }

    # An argument of the command, not text anywhere in the step. A step name can hold the path while
    # the command runs the whole solution.
    $e2eSteps = @($testSteps | Where-Object { $_.Arguments -ccontains $E2EProject })
    if ($e2eSteps.Count -ne 1) {
        $problems += "Exactly one dotnet test step must pass $E2EProject as an argument. Found $($e2eSteps.Count)."
        return @($problems)
    }
    $e2e = $e2eSteps[0]

    if ($e2e.Project -cne $E2EProject) {
        $problems += "The E2E step must pass $E2EProject as the first argument of dotnet test, so dotnet test runs that project and no other."
    }

    $e2eId = [regex]::Match($e2e.Text, '(?m)^\s+id:\s*(?<id>[A-Za-z0-9_-]+)\s*$')
    if (-not $e2eId.Success) {
        $problems += 'The E2E step must carry an id:, so the steps after it can read its outcome.'
    }

    foreach ($other in @($testSteps | Where-Object { $_.Index -ne $e2e.Index })) {
        # The whole value, not a part of it. A longer filter can bring the E2E tests back:
        # FullyQualifiedName!~AHKFlowApp.E2E.Tests.|FullyQualifiedName~AHKFlowApp.E2E.Tests. still
        # holds the exclusion, and runs every E2E test.
        if ($other.Filters.Count -ne 1 -or $other.Filters[0] -cne $E2EExclusion) {
            $problems += "Every other dotnet test step must pass exactly one filter, --filter `"$E2EExclusion`". Any other filter can run the E2E tests again, beside the projects that remove Docker containers. Found: $($other.Filters -join ' ; ')"
        }

        # First, not last. Ryuk removes a finished project's containers 10 seconds after that
        # project exits. With E2E last, those removals land while the E2E step starts its boots.
        if ($other.Index -lt $e2e.Index) {
            $problems += 'The E2E step must run before every other dotnet test step. Ryuk removes the containers of the other projects after they exit.'
        }

        # The whole expression, compared exactly. The expression language has many ways to say
        # "only after success", and no pattern rules them all out. Each part is there for a reason.
        # !cancelled() replaces the implicit success(): without a status function, a failed E2E
        # step skips this step. always() would also run it on a cancelled run. The two outcomes
        # run it after E2E passed or failed, and skip it when E2E was skipped, as after a failed
        # build.
        if ($e2eId.Success) {
            $id = $e2eId.Groups['id'].Value
            $expected = "!cancelled() && steps.filter.outputs.code == 'true' && (steps.$id.outcome == 'success' || steps.$id.outcome == 'failure')"
            if ($other.Condition -cne $expected) {
                $problems += "Every other dotnet test step must run after the E2E step passed or failed, and only then. Its if: must be `${{ $expected }}. Found: $($other.Condition)"
            }
        }
    }

    return @($problems)
}

$ciPath = Join-Path $repoRoot '.github/workflows/ci.yml'
$ciText = [System.IO.File]::ReadAllText($ciPath)

# --- The real file ---

foreach ($problem in @(Get-TestStepProblem -CiText $ciText)) {
    Assert-True $false $problem
}

# The cases below mutate the real file by exact text, so they only make sense once it is right.
if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host ''; Write-Host $failure -ForegroundColor Red }
    Write-Host ''
    throw "CiBuildTestSteps tests failed with $($failures.Count) problem(s)."
}

# --- Each assertion can go red ---

# A replacement that changes nothing proves nothing, and its case would pass for the wrong reason.
function Get-Mutation {
    param([string] $Text, [string] $Old, [string] $New)
    if (-not $Text.Contains($Old)) {
        throw "The mutation target '$Old' is not in the text. Fix this suite, not the workflow."
    }
    return $Text.Replace($Old, $New)
}

function Test-MutationCase {
    param([string] $Name, [string] $CiText, [string] $Expected)
    $found = @(Get-TestStepProblem -CiText $CiText)
    $hit = @($found | Where-Object { $_.Contains($Expected) })
    Assert-True ($hit.Count -gt 0) "Mutation '$Name' must report a problem containing '$Expected'. Got: $($found -join ' | ')"
}

$fixedName = Get-Mutation $ciText '--logger trx' '--logger "trx;LogFileName=test-results.trx"'
Test-MutationCase 'one fixed result file name again' $fixedName 'must not set LogFileName'

# The regression the split exists for: back to one dotnet test call for everything.
$oneCall = Get-Mutation $ciText "dotnet test $E2EProject" 'echo no separate E2E step'
Test-MutationCase 'one dotnet test call again' $oneCall 'in two steps'

# The E2E step runs the whole solution, and only its name still holds the project path.
$nameOnly = Get-Mutation (Get-Mutation $ciText "dotnet test $E2EProject" 'dotnet test') '- name: E2E tests with coverage' "- name: $E2EProject"
Test-MutationCase 'E2E path only in the step name' $nameOnly 'as an argument. Found 0.'

$notFirst = Get-Mutation $ciText "dotnet test $E2EProject" "dotnet test --no-restore $E2EProject"
Test-MutationCase 'E2E path not the first argument' $notFirst 'as the first argument'

$noFilter = Get-Mutation $ciText "--filter `"$E2EExclusion`"" '--blame'
Test-MutationCase 'second step runs E2E again' $noFilter 'must pass exactly one filter'

$widerFilter = Get-Mutation $ciText "--filter `"$E2EExclusion`"" "--filter `"$E2EExclusion|FullyQualifiedName~AHKFlowApp.E2E.Tests.`""
Test-MutationCase 'filter brings E2E back' $widerFilter 'must pass exactly one filter'

# One step, two commands. The checks read the first dotnet test call, so the second one would run
# every E2E test beside the Docker projects, unchecked.
$secondRun = @(
    '        run: >'
    '          dotnet test --configuration Release --no-build --verbosity normal'
    "          --filter `"$E2EExclusion`""
    '          --logger trx'
    '          --collect:"XPlat Code Coverage"'
    '          --results-directory TestResults'
    '          --settings coverlet.runsettings'
) -join "`n"
$twoLines = @(
    '        run: |'
    "          dotnet test --no-build --filter `"$E2EExclusion`""
    '          dotnet test --no-build'
) -join "`n"
$literalBlock = Get-Mutation $ciText $secondRun $twoLines
Test-MutationCase 'a second command on its own line' $literalBlock 'must run exactly one command'

$stepEnd = "          --settings coverlet.runsettings`n      - name: Merge coverage reports"

$chained = Get-Mutation $ciText $stepEnd "          --settings coverlet.runsettings && dotnet test --no-build`n      - name: Merge coverage reports"
Test-MutationCase 'a second command after &&' $chained 'must run exactly one command'

# YAML does not fold a more-indented line or a blank line, so each keeps its line break.
$deeperLine = Get-Mutation $ciText $stepEnd "          --settings coverlet.runsettings`n            dotnet test --no-build`n      - name: Merge coverage reports"
Test-MutationCase 'a second command on a more-indented line' $deeperLine 'must run exactly one command'

$afterBlank = Get-Mutation $ciText $stepEnd "          --settings coverlet.runsettings`n`n          dotnet test --no-build`n      - name: Merge coverage reports"
Test-MutationCase 'a second command after a blank line' $afterBlank 'must run exactly one command'

$noId = Get-Mutation $ciText 'id: e2e_tests' 'continue-on-error: false'
Test-MutationCase 'E2E step has no id' $noId 'must carry an id:'

# Without a status function GitHub applies success(), so a red E2E step skips the other tests.
$implicitSuccess = Get-Mutation $ciText '!cancelled() && ' ''
Test-MutationCase 'no status function' $implicitSuccess 'Its if: must be'

$successOnly = Get-Mutation $ciText " || steps.e2e_tests.outcome == 'failure'" ''
Test-MutationCase 'a red E2E step skips the other tests' $successOnly 'Its if: must be'

$afterSkip = Get-Mutation $ciText "steps.e2e_tests.outcome == 'failure')" "steps.e2e_tests.outcome == 'failure' || steps.e2e_tests.outcome == 'skipped')"
Test-MutationCase 'runs after a skipped E2E step' $afterSkip 'Its if: must be'

$onCancel = Get-Mutation $ciText '!cancelled()' 'always()'
Test-MutationCase 'runs on a cancelled run' $onCancel 'Its if: must be'

$earlyStep = Get-Mutation $ciText '      - name: E2E tests with coverage' "      - name: Early tests`n        run: dotnet test --no-build --filter `"$E2EExclusion`"`n      - name: E2E tests with coverage"
Test-MutationCase 'another test step before E2E' $earlyStep 'must run before every other dotnet test step'

# The opposite direction. A comment that names dotnet test and the E2E project must never count as
# a step. The real file already holds such comments, so the real-file check above depends on this.
$commented = Get-Mutation $ciText '      - name: E2E tests with coverage' "      # dotnet test $E2EProject`n      - name: E2E tests with coverage"
$commentProblems = @(Get-TestStepProblem -CiText $commented)
Assert-True ($commentProblems.Count -eq 0) "A comment that names dotnet test must not be a problem. Got: $($commentProblems -join ' | ')"

# --- Report ---

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host ''; Write-Host $failure -ForegroundColor Red }
    Write-Host ''
    throw "CiBuildTestSteps tests failed with $($failures.Count) problem(s)."
}

Write-Host 'CiBuildTestSteps tests passed.'
