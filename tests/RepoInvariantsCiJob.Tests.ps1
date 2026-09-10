#Requires -Version 7.0

# Backlog 121. A duplicate backlog number, or a stale citation, used to surface only deep inside
# the powershell-suites job while the .NET build ran for minutes beside it. ci.yml now runs the
# cheap repository-invariant suites first, and every other job waits on them. This suite proves
# that wiring stays in place.
#
# Run it by hand with:  pwsh ./tests/RepoInvariantsCiJob.Tests.ps1

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

$expectedSuites = @(
    'BacklogNumbering.Tests.ps1'
    'BacklogPlanPointer.Tests.ps1'
    'BacklogStaleOpen.Tests.ps1'
    'CitationFreshness.Tests.ps1'
    # Backlog 133. It joins the invariants job because it is the only check that catches a test
    # reaching a target migration directly: that bypass still passes on a cold container, so the
    # C# suites stay green while the rule is broken.
    'RunIndependentSqlTests.Tests.ps1'
    'SkillParity.Tests.ps1'
    # Backlog 127. This one is in the job so that every pull request proves the runner starts,
    # reads a manifest, and selects suites on Linux. It is the only member that is here for the
    # platform rather than for a repository invariant.
    'SuiteRunnerLinux.Tests.ps1'
)

# --- The check script asks the manifest for exactly the invariants job ---

# Backlog 127. The check script used to hold its own copy of the five suite names, and this suite
# read that array. The manifest is now the one record of which job runs which suite, so the drift
# worth testing is no longer inside the script - it is between the script's invocation and the
# manifest.
#
# Do not compare the manifest with itself here. Reading the manifest's invariants entries and then
# comparing them against Select-SuiteEntry -Job invariants over those same entries is a tautology:
# both sides move together on every manifest edit, so the assertion could never go red.
# Select-SuiteEntry's own filtering belongs to tests/CiPowerShellSuiteRunner.Tests.ps1.
#
# So this reads the invocation. Read it from the syntax tree, never from the file text: the parser
# drops comments, so a name that appears only in the description block cannot satisfy it.
function Read-RunnerInvocation {
    param([string] $Path)

    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref] $null, [ref] $errors)

    # Which variables hold the runner's path. Read the assignment, so a call made through a
    # variable is tied to the file that variable actually names.
    #
    # Checking "some '&' call passes -Job invariants" and, separately, "the runner's name appears
    # somewhere in the code" is two claims that never meet. A script could assign the runner path
    # to $runner, never use it, and invoke something else with -Job invariants. Both checks would
    # pass and the invariant job would run the wrong command.
    # Every assignment in the file, grouped by the variable it writes. Grouping matters: a
    # variable that is assigned twice is not the variable either assignment describes.
    $assignmentsByName = @{}
    foreach ($assignment in $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left -is [System.Management.Automation.Language.VariableExpressionAst]
            }, $true)) {
        $name = $assignment.Left.VariablePath.UserPath
        if (-not $assignmentsByName.ContainsKey($name)) {
            $assignmentsByName[$name] = [System.Collections.Generic.List[object]]::new()
        }
        $assignmentsByName[$name].Add($assignment)
    }

    # Whether a variable names the runner at the point a call uses it.
    #
    # Three conditions, and the middle one is the reason this is a function rather than a set
    # built once. A set that remembered "some assignment to $runner named the runner" would still
    # say yes after:
    #
    #     $runner = Join-Path $root 'run-powershell-suites.ps1'
    #     $runner = Join-Path $root 'something-else.ps1'
    #     & $runner -Job 'invariants'
    #
    # so it must be exactly one assignment, it must name the runner, and it must come before the
    # call. A script that assigns the variable twice fails this check even when the second
    # assignment also names the runner. That is deliberate: this test reads the script, it does
    # not run it, so the only honest answer to "which file does this variable hold" is the one a
    # single assignment gives.
    function Test-NamesRunner {
        param([string] $Name, [int] $CallOffset)

        if (-not $assignmentsByName.ContainsKey($Name)) { return $false }
        $forName = @($assignmentsByName[$Name])
        if ($forName.Count -ne 1) { return $false }

        $only = $forName[0]
        if ($only.Extent.EndOffset -gt $CallOffset) { return $false }

        return @($only.Right.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                    $node.Value -eq 'run-powershell-suites.ps1'
                }, $true)).Count -gt 0
    }

    # Every '&' invocation in the file, then only the ones whose target is the runner.
    $calls = @($ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Ampersand
            }, $true))

    $runnerCalls = @($calls | Where-Object {
            $target = @($_.CommandElements)[0]
            if ($target -is [System.Management.Automation.Language.VariableExpressionAst]) {
                return (Test-NamesRunner -Name $target.VariablePath.UserPath -CallOffset $_.Extent.StartOffset)
            }
            # A direct path, literal or interpolated. Read the target expression's own text, never
            # the whole file: a comment is not part of any expression's extent.
            return $target.Extent.Text -like '*run-powershell-suites.ps1*'
        })

    $jobValues = @()
    $narrowing = @()

    foreach ($call in $runnerCalls) {
        $elements = @($call.CommandElements)
        for ($i = 0; $i -lt $elements.Count; $i++) {
            $element = $elements[$i]
            if ($element -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }

            $name = $element.ParameterName

            # -Suite and -Platform both narrow the selection below the manifest's invariants set,
            # which is exactly the miss this test forbids. PowerShell accepts an abbreviated
            # parameter name, so match any prefix of either one.
            if ('Suite'.StartsWith($name, [System.StringComparison]::OrdinalIgnoreCase) -or
                'Platform'.StartsWith($name, [System.StringComparison]::OrdinalIgnoreCase)) {
                $narrowing += "-$name"
                continue
            }

            if (-not 'Job'.StartsWith($name, [System.StringComparison]::OrdinalIgnoreCase)) { continue }

            # '-Job:invariants' carries its value on the parameter; '-Job invariants' carries it
            # in the next element. Read a literal only, so a computed value cannot pass.
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

$checkScript = Join-Path $repoRoot 'scripts/ci/check-repo-invariants.ps1'
Assert-True (Test-Path -LiteralPath $checkScript) 'scripts/ci/check-repo-invariants.ps1 must exist'

if (Test-Path -LiteralPath $checkScript) {
    $checkText = Get-Content -LiteralPath $checkScript -Raw
    $invocation = Read-RunnerInvocation -Path $checkScript

    Assert-True ($invocation.ParseErrorCount -eq 0) 'check-repo-invariants.ps1 must parse cleanly.'

    # One '&' invocation, and it targets the runner. The second number is the one that matters:
    # it counts calls whose target resolves to run-powershell-suites.ps1, so the arguments read
    # below belong to the runner and to nothing else.
    Assert-True ($invocation.RunnerCallCount -eq 1) "check-repo-invariants.ps1 must invoke run-powershell-suites.ps1 exactly once. Found $($invocation.RunnerCallCount) call(s) to it, out of $($invocation.CallCount) '&' invocation(s)."
    Assert-True ($invocation.CallCount -eq 1) "check-repo-invariants.ps1 must make no other '&' invocation. Found $($invocation.CallCount)."

    Assert-True (($invocation.JobValues -join ',') -eq 'invariants') "check-repo-invariants.ps1 must pass -Job invariants. Found: '$($invocation.JobValues -join ',')'"
    Assert-True ($invocation.Narrowing.Count -eq 0) "check-repo-invariants.ps1 must pass no argument that narrows the selection below the manifest's invariants set. Found: $($invocation.Narrowing -join ', ')"
}

# --- The assertion above can go red ---

# A fixture manifest cannot express this drift: the script and this test read the same real
# manifest, so both sides would move together. The red has to come from the invocation instead.
# Two mutations, because the two ways to break it fail differently.
$mutationRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-invariants-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $mutationRoot -Force | Out-Null
try {
    $wrongJob = Join-Path $mutationRoot 'wrong-job.ps1'
    Set-Content -LiteralPath $wrongJob -Value ($checkText -replace "-Job 'invariants'", "-Job 'suites'") -Encoding utf8
    $wrongJobResult = Read-RunnerInvocation -Path $wrongJob
    Assert-True (($wrongJobResult.JobValues -join ',') -ne 'invariants') 'The -Job assertion must go red when the script names another job.'

    $noJob = Join-Path $mutationRoot 'no-job.ps1'
    Set-Content -LiteralPath $noJob -Value ($checkText -replace " -Job 'invariants'", '') -Encoding utf8
    $noJobResult = Read-RunnerInvocation -Path $noJob
    Assert-True ($noJobResult.JobValues.Count -eq 0) 'The -Job assertion must go red when the script passes no -Job at all.'

    $withSuite = Join-Path $mutationRoot 'with-suite.ps1'
    Set-Content -LiteralPath $withSuite -Value ($checkText -replace "-Job 'invariants'", "-Job 'invariants' -Suite 'SkillParity.Tests.ps1'") -Encoding utf8
    $withSuiteResult = Read-RunnerInvocation -Path $withSuite
    Assert-True ($withSuiteResult.Narrowing.Count -gt 0) 'The no-narrowing assertion must go red when the script adds a -Suite filter.'

    # The target, not only the arguments. This is the mutation the earlier version of this test
    # could not catch: the script still assigns the runner's path, and still passes
    # -Job invariants, but invokes something else entirely.
    $wrongTarget = Join-Path $mutationRoot 'wrong-target.ps1'
    Set-Content -LiteralPath $wrongTarget -Value ($checkText -replace '(?m)^& \$runner ', '& $somethingElse ') -Encoding utf8
    $wrongTargetResult = Read-RunnerInvocation -Path $wrongTarget
    Assert-True ($wrongTargetResult.RunnerCallCount -eq 0) 'The invocation assertion must go red when the script invokes a command other than the runner.'
    Assert-True ($wrongTargetResult.JobValues.Count -eq 0) 'Arguments must be read from the runner call only, never from another command.'

    # The assignment, so the variable really names the runner. A script that pointed $runner at
    # another file would still invoke $runner, and the target check alone would not notice.
    $wrongFile = Join-Path $mutationRoot 'wrong-file.ps1'
    Set-Content -LiteralPath $wrongFile -Value ($checkText -replace "'run-powershell-suites\.ps1'", "'some-other-script.ps1'") -Encoding utf8
    $wrongFileResult = Read-RunnerInvocation -Path $wrongFile
    Assert-True ($wrongFileResult.RunnerCallCount -eq 0) 'The invocation assertion must go red when the variable names another file.'

    # Reassignment. The variable is set to the runner and then to something else before the call,
    # so at the moment of the call it names another file. A check that only asked "did any
    # assignment to this variable name the runner" would say yes and be wrong.
    $reassigned = Join-Path $mutationRoot 'reassigned.ps1'
    $reassignedText = $checkText.Replace(
        "& `$runner -Job 'invariants'",
        "`$runner = Join-Path (Split-Path -Parent `$PSScriptRoot) 'some-other-script.ps1'" + [Environment]::NewLine + "& `$runner -Job 'invariants'")
    Assert-True ($reassignedText -ne $checkText) 'The reassignment mutation must actually change the script text.'
    Set-Content -LiteralPath $reassigned -Value $reassignedText -Encoding utf8
    $reassignedResult = Read-RunnerInvocation -Path $reassigned
    Assert-True ($reassignedResult.RunnerCallCount -eq 0) 'The invocation assertion must go red when the variable is reassigned to another file before the call.'
    Assert-True ($reassignedResult.JobValues.Count -eq 0) 'Arguments must not be read from a call whose target was reassigned away from the runner.'
} finally {
    Remove-Item -LiteralPath $mutationRoot -Recurse -Force -ErrorAction SilentlyContinue
}

foreach ($suite in $expectedSuites) {
    Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot "tests/$suite")) "tests/$suite must exist"
}

# --- ci.yml defines repo-invariants, and every other job waits on it ---

$ciPath = Join-Path $repoRoot '.github/workflows/ci.yml'
Assert-True (Test-Path -LiteralPath $ciPath) '.github/workflows/ci.yml must exist'

# YAML allows a job key to be quoted, so 'bicep-lint': names the same job as bicep-lint. Reading
# only the unquoted form would drop that job from the list, and a dropped job is never checked
# for its needs: key.
$jobKeyPattern = '^  (?<quote>[''"]?)(?<name>[A-Za-z0-9_-]+)\k<quote>:\s*$'
$anyJobKeyPattern = '^  [''"]?[A-Za-z0-9_-]+[''"]?:\s*$'

$ciLines = Get-Content -LiteralPath $ciPath
$jobNames = @()
$inJobs = $false
foreach ($line in $ciLines) {
    if ($line -match '^jobs:\s*$') { $inJobs = $true; continue }
    if (-not $inJobs) { continue }
    if ($line -match '^[^\s#]') { break }
    if ($line -match $jobKeyPattern) { $jobNames += $Matches.name }
}

Assert-True ($jobNames -contains 'repo-invariants') "ci.yml must define a 'repo-invariants' job. Found: $($jobNames -join ', ')"

$ciRaw = $ciLines -join "`n"
foreach ($job in ($jobNames | Where-Object { $_ -ne 'repo-invariants' })) {
    $pattern = '(?ms)^  [''"]?' + [regex]::Escape($job) + '[''"]?:\s*$.*?(?=' + $anyJobKeyPattern + '|\z)'
    $block = [regex]::Match($ciRaw, $pattern).Value

    # Read the needs: value, not the job block. The words 'repo-invariants' appear in step names
    # and comments too, and matching those would pass a job that waits on nothing.
    $needsMatch = [regex]::Match($block, '(?m)^\s{4}needs:\s*(?<value>.*)$')
    Assert-True ($needsMatch.Success) "Job '$job' must declare a needs: key"
    if ($needsMatch.Success) {
        $needsValue = $needsMatch.Groups['value'].Value.Trim().Trim('[', ']')
        if ([string]::IsNullOrWhiteSpace($needsValue)) {
            # The block form: needs: on its own line, then one '- job' line per dependency.
            $listMatch = [regex]::Match($block, '(?ms)^\s{4}needs:\s*$(?<items>(\s*\n)*(^\s{6}-\s.*$\n?)+)')
            $needsValue = ($listMatch.Groups['items'].Value -split "`n" |
                ForEach-Object { $_.Trim() -replace '^-\s*', '' } | Where-Object { $_ }) -join ','
        }
        $needsJobs = @($needsValue -split ',' | ForEach-Object { $_.Trim().Trim("'", '"') } | Where-Object { $_ })
        Assert-True ($needsJobs -contains 'repo-invariants') "Job '$job' needs: must name repo-invariants. Found: '$needsValue'"
    }
}

# --- The manifest's invariants job holds exactly the suites this file names ---

# The list above is a literal in this file; the manifest is another file. So this goes red when
# somebody adds a suite to the invariants job, or drops one, without saying so here. That is the
# drift the acceptance criterion asks about: the job must run every suite inside the set and
# nothing outside it.
. (Join-Path $repoRoot 'scripts/powershell-suites.common.ps1')

$manifestPath = Join-Path $repoRoot 'tests/powershell-suites.json'
$discovered = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'tests') -Filter '*.Tests.ps1' -File | ForEach-Object { $_.Name })
$manifestEntries = @(Read-SuiteManifest -Path $manifestPath -DiscoveredName $discovered)

$manifestInvariants = @($manifestEntries | Where-Object { $_.Jobs -contains 'invariants' } | ForEach-Object { $_.Name } | Sort-Object)
Assert-True ((($manifestInvariants) -join ',') -eq (($expectedSuites | Sort-Object) -join ',')) "The manifest's invariants job must hold exactly: $(($expectedSuites | Sort-Object) -join ', '). Found: $($manifestInvariants -join ', ')"

# The job runs on Linux, so every suite in it has to be one a Linux run has passed. An entry
# without 'linux' here would be scheduled by ci.yml and then dropped by the runner's own platform
# filter, and the job would look green having run less than it claims.
foreach ($entry in ($manifestEntries | Where-Object { $_.Jobs -contains 'invariants' })) {
    Assert-True ($entry.Platform -contains 'linux') "$($entry.Name) is in the invariants job, which runs on Linux, so its platform must include linux. Found: $($entry.Platform -join ', ')"
}

# --- The job runs on ubuntu-latest ---

$invariantPattern = '(?ms)^  [''"]?repo-invariants[''"]?:\s*$.*?(?=' + $anyJobKeyPattern + '|\z)'
$invariantBlock = [regex]::Match($ciRaw, $invariantPattern).Value
Assert-True ($invariantBlock -match '(?m)^\s{4}runs-on:\s*ubuntu-latest\s*$') 'repo-invariants must run on ubuntu-latest'

# --- Report ---

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host ''; Write-Host $failure -ForegroundColor Red }
    Write-Host ''
    throw "RepoInvariantsCiJob tests failed with $($failures.Count) problem(s)."
}

Write-Host 'RepoInvariantsCiJob tests passed.'
