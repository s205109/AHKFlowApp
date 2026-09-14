#Requires -Version 7.0

# Pins the dotnet test steps of the build-test job in .github/workflows/ci.yml. It reads text with
# regular expressions, the same way tests/ShippingPrClosesItemWorkflow.Tests.ps1 does, because
# PowerShell ships no YAML parser.
#
# Backlog 156 found the step named every result file test-results.trx. All eight test projects
# wrote that one name, each overwrote the one before, and Publish test results read a single file:
# the project that finished last.
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

# The workflow's comments name dotnet test while they explain the steps. A match on the raw text
# would count a comment as part of a test step. Drop every whole-line comment first.
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
# 'run: >' or 'run: |', continues on every following line indented deeper than the key, and comes
# back as one line.
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
        for ($j = $i + 1; $j -lt $lines.Count; $j++) {
            if ($lines[$j].Trim() -eq '') { continue }
            $indent = $lines[$j].Length - $lines[$j].TrimStart().Length
            if ($indent -le $keyColumn) { break }
            $block += $lines[$j].Trim()
        }
        return ($block -join ' ')
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

        $testSteps += [pscustomobject] @{
            Index     = $i
            Text      = $steps[$i]
            Command   = $run
            Arguments = $arguments
            Project   = $project
            Filters   = $filters
            Condition = $condition
        }
    }
    return @($testSteps)
}

# Every problem the dotnet test steps have, one line of text each. No problems means they are right.
function Get-TestStepProblem {
    param([AllowEmptyString()][string] $CiText)

    $problems = @()
    $testSteps = @(Get-DotnetTestStep -CiText $CiText)

    if ($testSteps.Count -eq 0) {
        $problems += 'The build-test job must run dotnet test.'
        return @($problems)
    }

    foreach ($step in $testSteps) {
        if ($step.Command.Contains('LogFileName=')) {
            $problems += 'A dotnet test step must not set LogFileName. Every test project then writes that one file, and each overwrites the one before. Pass --logger trx and let VSTest name each file.'
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

$noTests = Get-Mutation $ciText 'dotnet test' 'dotnet build'
Test-MutationCase 'no dotnet test step' $noTests 'must run dotnet test'

# --- Report ---

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host ''; Write-Host $failure -ForegroundColor Red }
    Write-Host ''
    throw "CiBuildTestSteps tests failed with $($failures.Count) problem(s)."
}

Write-Host 'CiBuildTestSteps tests passed.'
