#Requires -Version 7.0

# Backlog 123. scripts/watch-task.ps1 finds the live background run for this repository and
# tails it. This suite pins the project-folder name mangling against real observed names,
# proves running-versus-finished detection from file content alone, proves newest-running
# selection, and proves the no-running-task and more-than-one-running paths.
#
# Each script case builds a fake tree of .output files in a temporary folder and passes -Root
# with -NoFollow, so no case enters the follow loop.
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
