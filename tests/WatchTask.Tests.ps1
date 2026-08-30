#Requires -Version 7.0

# Backlog 123. scripts/watch-task.ps1 finds the live background run for this repository and
# tails it. This suite pins the project-folder name mangling against real observed names,
# proves running-versus-finished detection from file content alone, proves newest-running
# selection, and proves the no-running-task and more-than-one-running paths.
#
# Most script cases build a fake tree of .output files in a temporary folder and pass -Root with
# -NoFollow, so they never enter the follow loop. The follow loop is the script's main job, so it
# has its own case at the end: a real child process follows a file this suite appends to, and the
# case asserts the watcher prints every line and stops by itself when the exit marker arrives.
#
# Run it by hand with:  pwsh ./tests/WatchTask.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# A non-zero exit code from the child watch script is data here, not a terminating error.
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$watchScript = Join-Path $repoRoot 'scripts\watch-task.ps1'
$hostExe = [System.Diagnostics.Process]::GetCurrentProcess().Path

# Dot-source to reach ConvertTo-ClaudeProjectFolder, Get-RepositoryMainRoot, and Get-TaskState
# without running the script.
. $watchScript

$failures = @()

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) {
        $script:failures += $Message
    }
}

function New-WatchTestRoot {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) "watch-task-tests-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    return $root
}

# Writes one fake task output file at <Root>\<ProjectFolder>\<session>\tasks\<id>.output.
function New-FakeTaskOutput {
    param(
        [Parameter(Mandatory)][string] $Root,
        [Parameter(Mandatory)][string] $ProjectFolder,
        [Parameter(Mandatory)][AllowEmptyString()][string[]] $Lines,
        [Parameter(Mandatory)][datetime] $LastWrite
    )

    $session = [guid]::NewGuid().ToString()
    $tasksDir = Join-Path (Join-Path (Join-Path $Root $ProjectFolder) $session) 'tasks'
    New-Item -ItemType Directory -Path $tasksDir -Force | Out-Null
    $file = Join-Path $tasksDir 'task.output'
    Set-Content -LiteralPath $file -Value $Lines -Encoding UTF8
    (Get-Item -LiteralPath $file).LastWriteTime = $LastWrite
    return $file
}

function Invoke-WatchScript {
    param([string[]] $ScriptArgs)

    $output = & $hostExe -NoProfile -File $watchScript @ScriptArgs 2>&1 | Out-String
    return [pscustomobject]@{ Output = $output; ExitCode = $LASTEXITCODE }
}

# --- The project folder name mangling, pinned against real observed names ---

Assert-True (
    (ConvertTo-ClaudeProjectFolder -Path 'C:\Dev\segocom-github\AHKFlowApp') -eq 'C--Dev-segocom-github-AHKFlowApp'
) 'Mangling: a main checkout path must match the observed folder name.'

Assert-True (
    (ConvertTo-ClaudeProjectFolder -Path 'C:\Dev\segocom-github\AHKFlowApp\.claude\worktrees\wt-foo') -eq 'C--Dev-segocom-github-AHKFlowApp--claude-worktrees-wt-foo'
) 'Mangling: a worktree path must match the observed folder name.'

# --- A project folder belongs to this repository only when a checkout owns its name ---
#
# The mangling turns a path separator and a literal '-' into the same character, so the name
# alone cannot separate a subdirectory of this repository from a different repository beside it.
# These cases use made-up paths, because the rule is about names and not about this machine.

$oneCheckout = @('C:\repo\App')
$oneNeighbour = @('C:\repo\App-tools', 'C:\repo\AppOLD', 'C:\repo\Other')

$nameCases = @(
    @{ Name = 'C--repo-App';         Expected = $true;  Why = 'the checkout itself' }
    @{ Name = 'C--repo-App-scripts'; Expected = $true;  Why = 'a subdirectory of the checkout' }
    @{ Name = 'C--repo-AppOLD';      Expected = $false; Why = 'a different directory whose name merely starts the same' }
    @{ Name = 'C--repo-App-tools';   Expected = $false; Why = 'a neighbour directory that owns the name exactly' }
    @{ Name = 'C--repo-Other';       Expected = $false; Why = 'an unrelated neighbour' }
    @{ Name = 'C--repo';             Expected = $false; Why = 'the parent of the checkout' }
)

foreach ($case in $nameCases) {
    $actual = Test-WatchTaskFolderName -Name $case.Name -CheckoutPath $oneCheckout -NeighbourPath $oneNeighbour
    Assert-True ($actual -eq $case.Expected) "Folder match: '$($case.Name)' is $($case.Why), so it must be $($case.Expected). Got $actual."
}

# A worktree can live anywhere, so it is matched as its own checkout rather than by the main
# checkout's name.
$twoCheckouts = @('C:\repo\App', 'D:\worktrees\feature')
Assert-True (Test-WatchTaskFolderName -Name 'D--worktrees-feature' -CheckoutPath $twoCheckouts) 'Folder match: a worktree outside the main checkout must be found.'
Assert-True (Test-WatchTaskFolderName -Name 'D--worktrees-feature-tests' -CheckoutPath $twoCheckouts) 'Folder match: a subdirectory of such a worktree must be found.'
Assert-True (-not (Test-WatchTaskFolderName -Name 'D--worktrees-featureOLD' -CheckoutPath $twoCheckouts)) 'Folder match: a name that merely starts like a worktree must be refused.'

# --- Running versus finished detection, from file content alone ---

$root = New-WatchTestRoot
try {
    $runningFile = New-FakeTaskOutput -Root $root -ProjectFolder 'proj' -LastWrite (Get-Date) -Lines @(
        'building', 'testing', 'still going'
    )
    $finishedFile = New-FakeTaskOutput -Root $root -ProjectFolder 'proj' -LastWrite (Get-Date) -Lines @(
        'building', 'done', '', '[exited with code 2]', ''
    )

    $runningState = Get-TaskState -Path $runningFile
    $finishedState = Get-TaskState -Path $finishedFile

    Assert-True ($runningState.Running -eq $true) 'Detection: a file with no exit line is running.'
    Assert-True ($finishedState.Running -eq $false) 'Detection: a file ending with the exit line is finished.'
    Assert-True ($finishedState.ExitCode -eq 2) "Detection: the exit code is read from the line, got: $($finishedState.ExitCode)"
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}

# The fixture project folder must match the real prefix, because the script derives that prefix
# from this repository and globs '<prefix>*'.
$mainRoot = Get-RepositoryMainRoot -ScriptRoot (Join-Path $repoRoot 'scripts')
$prefix = ConvertTo-ClaudeProjectFolder -Path $mainRoot

# --- Newest-running selection when several files exist ---

$root = New-WatchTestRoot
try {
    New-FakeTaskOutput -Root $root -ProjectFolder "$prefix-a" -LastWrite (Get-Date).AddMinutes(-30) -Lines @(
        'old finished run', '[exited with code 0]', ''
    ) | Out-Null
    New-FakeTaskOutput -Root $root -ProjectFolder "$prefix-b" -LastWrite (Get-Date).AddMinutes(-10) -Lines @(
        'older running run', 'OLDER-RUNNING-MARKER'
    ) | Out-Null
    $newestRunning = New-FakeTaskOutput -Root $root -ProjectFolder "$prefix-c" -LastWrite (Get-Date).AddMinutes(-1) -Lines @(
        'newest running run', 'NEWEST-RUNNING-MARKER'
    )

    $result = Invoke-WatchScript -ScriptArgs @('-Root', $root, '-NoFollow')

    Assert-True ($result.ExitCode -eq 0) "Newest running: exit code must be 0, got $($result.ExitCode). Output: $($result.Output)"
    Assert-True ($result.Output -match 'NEWEST-RUNNING-MARKER') "Newest running: the newest running file must be tailed. Output: $($result.Output)"
    Assert-True ($result.Output -notmatch 'OLDER-RUNNING-MARKER') "Newest running: the older running file must not be tailed. Output: $($result.Output)"
    Assert-True ($result.Output.Contains($newestRunning)) "Newest running: the tailed path must be named. Output: $($result.Output)"
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}

# --- The nothing-is-running path returns the newest finished task and exits 0 ---

$root = New-WatchTestRoot
try {
    New-FakeTaskOutput -Root $root -ProjectFolder "$prefix-a" -LastWrite (Get-Date).AddMinutes(-30) -Lines @(
        'old finished run', 'OLD-FINISHED-MARKER', '[exited with code 0]', ''
    ) | Out-Null
    $newestFinished = New-FakeTaskOutput -Root $root -ProjectFolder "$prefix-b" -LastWrite (Get-Date).AddMinutes(-2) -Lines @(
        'newer finished run', 'NEW-FINISHED-MARKER', '[exited with code 7]', ''
    )

    $result = Invoke-WatchScript -ScriptArgs @('-Root', $root, '-NoFollow')

    Assert-True ($result.ExitCode -eq 0) "Nothing running: exit code must be 0, got $($result.ExitCode). Output: $($result.Output)"
    Assert-True ($result.Output -match 'No task is running now') "Nothing running: the line must say so. Output: $($result.Output)"
    Assert-True ($result.Output -match 'NEW-FINISHED-MARKER') "Nothing running: the newest finished task must be shown. Output: $($result.Output)"
    Assert-True ($result.Output -match 'Exit code: 7') "Nothing running: the newest finished exit code must be printed. Output: $($result.Output)"
    Assert-True ($result.Output.Contains($newestFinished)) "Nothing running: the path must be printed. Output: $($result.Output)"
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}

# --- The more-than-one-running path names the count ---

$root = New-WatchTestRoot
try {
    New-FakeTaskOutput -Root $root -ProjectFolder "$prefix-a" -LastWrite (Get-Date).AddMinutes(-5) -Lines @(
        'running one', 'RUN-ONE'
    ) | Out-Null
    New-FakeTaskOutput -Root $root -ProjectFolder "$prefix-b" -LastWrite (Get-Date).AddMinutes(-1) -Lines @(
        'running two', 'RUN-TWO'
    ) | Out-Null

    $result = Invoke-WatchScript -ScriptArgs @('-Root', $root, '-NoFollow')

    Assert-True ($result.ExitCode -eq 0) "Two running: exit code must be 0, got $($result.ExitCode). Output: $($result.Output)"
    Assert-True ($result.Output -match '1 other task is also running') "Two running: the count line must name one other. Output: $($result.Output)"
    Assert-True ($result.Output -match 'RUN-TWO') "Two running: the newest running file is tailed. Output: $($result.Output)"
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}

# --- No matching files at all is a visible failure ---

$root = New-WatchTestRoot
try {
    $result = Invoke-WatchScript -ScriptArgs @('-Root', $root, '-NoFollow')
    Assert-True ($result.ExitCode -eq 1) "No files: exit code must be 1, got $($result.ExitCode). Output: $($result.Output)"
    Assert-True ($result.Output -match 'No task output files found') "No files: the message must say so. Output: $($result.Output)"
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}

# --- A number outside the allowed range is refused, not quietly ignored ---
#
# -Index 0 used to read the same as "no index given", so the script silently tailed the newest
# running task instead of the one the caller asked for.

$root = New-WatchTestRoot
try {
    New-FakeTaskOutput -Root $root -ProjectFolder "$prefix-a" -LastWrite (Get-Date) -Lines @(
        'running', 'ONLY-MARKER'
    ) | Out-Null

    foreach ($badArgs in @(
            @('-Index', '0'),
            @('-Index', '-1'),
            @('-Tail', '0'),
            @('-Tail', '-5')
        )) {
        $result = Invoke-WatchScript -ScriptArgs (@('-Root', $root, '-NoFollow') + $badArgs)
        $shown = $badArgs -join ' '
        Assert-True ($result.ExitCode -ne 0) "Range: '$shown' must be refused, but the run returned 0. Output: $($result.Output)"
        Assert-True ($result.Output -notmatch 'ONLY-MARKER') "Range: '$shown' must not fall back to tailing a task. Output: $($result.Output)"
    }

    # The first valid index still selects, which proves the range check did not break selection.
    $result = Invoke-WatchScript -ScriptArgs @('-Root', $root, '-NoFollow', '-Index', '1')
    Assert-True ($result.ExitCode -eq 0) "Range: -Index 1 must work, got $($result.ExitCode). Output: $($result.Output)"
    Assert-True ($result.Output -match 'ONLY-MARKER') "Range: -Index 1 must tail the first task. Output: $($result.Output)"
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}

# --- Following a live file prints every line and stops on the exit marker ---
#
# This is the only case that runs the follow loop, and it is the script's main job. It also pins
# the defect that a line counter cannot see: a runner often writes a line in two pieces, and the
# text that completes the line adds no new line to the file. A watcher that tracks how many lines
# it has printed skips that text and the reader never sees it.

$root = New-WatchTestRoot
$job = $null
try {
    $session = [guid]::NewGuid().ToString()
    $tasksDir = Join-Path (Join-Path (Join-Path $root "$prefix-live") $session) 'tasks'
    New-Item -ItemType Directory -Path $tasksDir -Force | Out-Null
    $livePath = Join-Path $tasksDir 'task.output'

    [System.IO.File]::WriteAllText($livePath, "FIRST-LINE`n")

    $job = Start-Job -ScriptBlock {
        param($exe, $script, $searchRoot)
        & $exe -NoProfile -File $script -Root $searchRoot -Tail 40 2>&1 | Out-String
    } -ArgumentList $hostExe, $watchScript, $root

    # Let the watcher find the file and print what is already there.
    Start-Sleep -Seconds 2

    # A line written in two pieces. The file gains no extra line when the second piece lands.
    [System.IO.File]::AppendAllText($livePath, 'SPLIT-LINE-START')
    Start-Sleep -Seconds 2
    [System.IO.File]::AppendAllText($livePath, "-AND-END`n")
    Start-Sleep -Seconds 2

    [System.IO.File]::AppendAllText($livePath, "LAST-LINE`n[exited with code 3]`n")

    $finished = Wait-Job -Job $job -Timeout 30
    Assert-True ($null -ne $finished) 'Follow: the watcher must stop by itself when the exit marker arrives, but it was still running after 30s.'

    $output = if ($finished) { (Receive-Job -Job $job) | Out-String } else { '' }

    Assert-True ($output -match 'FIRST-LINE') "Follow: the text already in the file must be printed. Output: $output"
    Assert-True ($output -match 'SPLIT-LINE-START-AND-END') "Follow: a line written in two pieces must be printed in full. Output: $output"
    Assert-True ($output -match 'LAST-LINE') "Follow: a line appended after that must be printed. Output: $output"
    Assert-True ($output -match 'Exit code: 3') "Follow: the exit code must be the last thing printed. Output: $output"
}
finally {
    if ($job) { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

# --- Report ---

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Host ''
        Write-Host $failure -ForegroundColor Red
    }
    Write-Host ''
    throw "Watch task tests failed with $($failures.Count) problem(s). See the detail above."
}

Write-Host 'Watch task tests passed.' -ForegroundColor Green
