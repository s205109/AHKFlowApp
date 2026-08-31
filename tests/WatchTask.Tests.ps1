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

# The lines a function printed with Write-Host, taken from the information stream and separated
# from whatever the function also returned. Callers pass @(Show-Tail ... 6>&1).
function Get-ShownLine {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Record)

    return @(
        $Record |
            Where-Object { $_ -is [System.Management.Automation.InformationRecord] } |
            ForEach-Object { [string] $_.MessageData.Message }
    )
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

# Two different directories can mangle to the very same folder name, because '.' and a path
# separator both become '-'. The name then says nothing about which one owns the folder, so the
# checkout must not claim it either.
$dottedCheckout = @('C:\repo\App.foo')
$dottedNeighbour = @('C:\repo\App-foo')

Assert-True (
    -not (Test-WatchTaskFolderName -Name 'C--repo-App-foo' -CheckoutPath $dottedCheckout -NeighbourPath $dottedNeighbour)
) 'Folder match: a name a neighbour claims exactly as closely must be refused.'
Assert-True (
    -not (Test-WatchTaskFolderName -Name 'C--repo-App-foo-scripts' -CheckoutPath $dottedCheckout -NeighbourPath $dottedNeighbour)
) 'Folder match: a subdirectory name under an exact collision must be refused too.'
Assert-True (
    Test-WatchTaskFolderName -Name 'C--repo-App-foo' -CheckoutPath $dottedCheckout
) 'Folder match: with no colliding neighbour the checkout still owns its own name.'

# --- Reading the end of a file says whether the task finished, and with which code ---
#
# Get-TaskState is the check that ends the wait when the follower's byte offset has gone stale, so
# it must hold no state and must answer from the file alone. A killed task and a finished task both
# report Running as false, and only the exit code tells them apart.

$root = New-WatchTestRoot
try {
    $endCases = @(
        @{ Name = 'a terminal marker';         Content = "a`n[exited with code 3]`n";                            Running = $false; ExitCode = 3 }
        @{ Name = 'no final newline';          Content = "a`n[exited with code 4]";                              Running = $false; ExitCode = 4 }
        @{ Name = 'a negative code';           Content = "a`n[exited with code -1]`n";                           Running = $false; ExitCode = -1 }
        @{ Name = 'a killed marker';           Content = "a`n[killed]`n";                                        Running = $false; ExitCode = $null }
        @{ Name = 'a running task';            Content = "a`nb`n";                                               Running = $true;  ExitCode = $null }
        @{ Name = 'blank lines only';          Content = "`n`n   `n";                                            Running = $true;  ExitCode = $null }
        @{ Name = 'an empty file';             Content = '';                                                     Running = $true;  ExitCode = $null }
        @{ Name = 'a marker that is not last'; Content = "[exited with code 5]`nmore`n";                          Running = $true;  ExitCode = $null }
        # Longer than the window this reads, so it also proves the window looks at the end.
        @{ Name = 'a file past the window';    Content = (("PADDING-LINE`n" * 2000) + "[exited with code 6]`n"); Running = $false; ExitCode = 6 }
    )

    $caseNumber = 0
    foreach ($case in $endCases) {
        $caseNumber++
        $path = Join-Path $root "end-$caseNumber.output"
        [System.IO.File]::WriteAllText($path, $case.Content)

        $state = Get-TaskState -Path $path
        Assert-True ($null -ne $state) "End state: $($case.Name) must be readable."
        if ($null -eq $state) { continue }

        Assert-True ($state.Running -eq $case.Running) `
            "End state: $($case.Name) must read as Running '$($case.Running)', got '$($state.Running)'."

        $sameCode = if ($null -eq $case.ExitCode) { $null -eq $state.ExitCode } else { $state.ExitCode -eq $case.ExitCode }
        Assert-True $sameCode "End state: $($case.Name) must read as '$($case.ExitCode)', got '$($state.ExitCode)'."
    }
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}

# --- A large unfinished line has a fixed memory bound and a visible truncation notice ---

$root = New-WatchTestRoot
try {
    $singleLinePath = Join-Path $root 'single-line.output'
    [System.IO.File]::WriteAllText($singleLinePath, ('X' * (2 * 1024 * 1024)))

    $reader = New-TailReader -Path $singleLinePath
    Read-InitialTailText -Reader $reader -LineCount 2 | Out-Null
    $initialTruncated = $reader.PSObject.Properties['InitialTruncated']
    Assert-True ($null -ne $initialTruncated) 'Single line: the initial reader must report whether its byte limit truncated output.'
    if ($null -ne $initialTruncated) {
        Assert-True $initialTruncated.Value 'Single line: a 2 MiB unfinished line must reach the initial read limit.'
        Assert-True ($reader.InitialReadBytes -le (1024 * 1024)) "Single line: the initial read must stay within 1 MiB, got $($reader.InitialReadBytes) bytes."
    }

    $shown = Show-Tail -Path $singleLinePath -Count 2 6>&1 | Out-String
    Assert-True ($shown -match 'truncated') 'Single line: the initial tail must say that it omitted part of the unfinished line.'

    $reader = New-TailReader -Path $singleLinePath
    $followOutput = [System.Collections.Generic.List[string]]::new()
    do {
        $text = Read-TailText -Reader $reader
        foreach ($line in @(Split-TailLine -Reader $reader -Text $text)) {
            $followOutput.Add($line)
        }
    } while (-not $reader.AtEnd)

    $carryBytes = [System.Text.Encoding]::UTF8.GetByteCount($reader.Carry)
    Assert-True ($carryBytes -le (1024 * 1024)) "Single line: unfinished follow text must stay within 1 MiB, got $carryBytes bytes."
    Assert-True (($followOutput -join "`n") -match 'truncated') 'Single line: follow mode must emit a truncation notice.'
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}

# --- The unfinished last line counts toward -Tail ---
#
# A task that is no longer running has its last, newline-less line printed. That line is one of
# the lines the caller asked for, not a free extra on top of them.

$root = New-WatchTestRoot
try {
    $partialPath = Join-Path $root 'partial.output'
    [System.IO.File]::WriteAllText($partialPath, "one`ntwo`nthree")

    $printed = Get-ShownLine -Record @(Show-Tail -Path $partialPath -Count 2 6>&1)
    Assert-True (($printed -join '|') -eq 'two|three') "Tail count: -Tail 2 over three lines must print 'two' and 'three', got: $($printed -join '|')"
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}

# --- A tail of large complete lines is not cut short ---
#
# The byte bound exists for one line that never ends. Capping the whole initial read instead made
# -Tail return fewer lines than it was asked for, and blamed an unfinished line that did not exist.

$root = New-WatchTestRoot
try {
    $bigLinesPath = Join-Path $root 'big-lines.output'
    $builder = [System.Text.StringBuilder]::new()
    for ($i = 1; $i -le 15; $i++) {
        [void] $builder.Append(('L{0:d2}-' -f $i))
        [void] $builder.Append('X' * (100 * 1024))
        [void] $builder.Append("`n")
    }
    [System.IO.File]::WriteAllText($bigLinesPath, $builder.ToString())

    $printed = Get-ShownLine -Record @(Show-Tail -Path $bigLinesPath -Count 15 6>&1)
    $starts = @($printed | ForEach-Object { $_.Substring(0, [Math]::Min(4, $_.Length)) })
    $expected = @(1..15 | ForEach-Object { 'L{0:d2}-' -f $_ }) -join ' '

    Assert-True ($printed.Count -eq 15) "Large lines: -Tail 15 must print 15 lines, got $($printed.Count): $($starts -join ' ')"
    Assert-True (($starts -join ' ') -eq $expected) "Large lines: the 15 printed lines must be L01 to L15, got: $($starts -join ' ')"
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}

# --- The byte bound holds when a newline breaks the block alignment ---
#
# The scan reads backwards in 64 KiB blocks and checks the bound before each one. While every
# block is full the running count lands on a multiple of 64 KiB, so it meets the bound exactly.
# A newline inside a block resets that count to the newline's position, and the count can then
# stop one byte short of the bound. The scan read another whole block on top of the 1 MiB it
# promised.
#
# The file below places the last newline 64 KiB + 1 bytes from the end. Counted back from the
# end, that newline is the last byte of the second block, so the count restarts at 65535 and
# every later block adds 65536.

$root = New-WatchTestRoot
try {
    $skewPath = Join-Path $root 'skew.output'
    $trailingLine = 64 * 1024
    [System.IO.File]::WriteAllText($skewPath, (('A' * 1500000) + "`n" + ('X' * $trailingLine)))

    $reader = New-TailReader -Path $skewPath
    Read-InitialTailText -Reader $reader -LineCount 2 | Out-Null

    # The trailing line and the newline before it are a second line, so they are not part of the
    # over-long line's allowance. Everything else read belongs to that one line.
    $overLongBytes = $reader.InitialReadBytes - $trailingLine - 1

    Assert-True $reader.InitialTruncated 'Skewed cap: a 1.5 MB line must still reach the initial read limit.'
    Assert-True ($overLongBytes -le (1024 * 1024)) `
        "Skewed cap: the over-long line must contribute at most 1 MiB, got $overLongBytes bytes."
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}

# --- Running versus finished detection, from file content alone ---

$root = New-WatchTestRoot
try {
    $runningFile = New-FakeTaskOutput -Root $root -ProjectFolder 'proj' -LastWrite (Get-Date) -Lines @(
        'building', 'testing', 'still going'
    )
    $finishedFile = New-FakeTaskOutput -Root $root -ProjectFolder 'proj' -LastWrite (Get-Date) -Lines @(
        'building', 'done', '', '[exited with code 2]', ''
    )
    $killedFile = New-FakeTaskOutput -Root $root -ProjectFolder 'proj' -LastWrite (Get-Date) -Lines @(
        'building', '[killed]'
    )

    $runningState = Get-TaskState -Path $runningFile
    $finishedState = Get-TaskState -Path $finishedFile
    $killedState = Get-TaskState -Path $killedFile

    Assert-True ($runningState.Running -eq $true) 'Detection: a file with no exit line is running.'
    Assert-True ($finishedState.Running -eq $false) 'Detection: a file ending with the exit line is finished.'
    Assert-True ($finishedState.ExitCode -eq 2) "Detection: the exit code is read from the line, got: $($finishedState.ExitCode)"
    Assert-True ($killedState.Running -eq $false) 'Detection: a file ending with [killed] is no longer running.'
    Assert-True ($null -eq $killedState.ExitCode) 'Detection: a killed task has no exit code.'
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}

# --- Discovery and tailing inspect bounded pieces of a large log ---

$root = New-WatchTestRoot
try {
    $largePath = Join-Path $root 'large.output'
    $content = ("PADDING-LINE`n" * 20000) + "LAST-LINE`n[exited with code 0]`n"
    [System.IO.File]::WriteAllText($largePath, $content)
    $length = (Get-Item -LiteralPath $largePath).Length

    $state = Get-TaskState -Path $largePath
    $stateBytes = $state.PSObject.Properties['BytesRead']
    Assert-True ($null -ne $stateBytes) 'Bounded state: the state result must report how many bytes it inspected.'
    if ($null -ne $stateBytes) {
        Assert-True ($stateBytes.Value -lt $length) "Bounded state: discovery must inspect only the file end. Read $($stateBytes.Value) of $length bytes."
    }

    $reader = New-TailReader -Path $largePath
    Read-TailText -Reader $reader | Out-Null
    $followBytes = $reader.PSObject.Properties['LastReadBytes']
    Assert-True ($null -ne $followBytes) 'Bounded follow: the reader must report the size of its last read.'
    if ($null -ne $followBytes) {
        Assert-True ($followBytes.Value -lt $length) "Bounded follow: one poll must read a fixed-size chunk. Read $($followBytes.Value) of $length bytes."
    }

    $initial = Show-Tail -Path $largePath -Count 2
    $initialBytes = $initial.Reader.PSObject.Properties['InitialReadBytes']
    Assert-True ($null -ne $initialBytes) 'Bounded initial tail: the reader must report how many bytes it read to find the last lines.'
    if ($null -ne $initialBytes) {
        Assert-True ($initialBytes.Value -lt $length) "Bounded initial tail: finding two lines must not read the complete log. Read $($initialBytes.Value) of $length bytes."
    }
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
    New-FakeTaskOutput -Root $root -ProjectFolder "$prefix-d" -LastWrite (Get-Date) -Lines @(
        'newer killed run', '[killed]'
    ) | Out-Null

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

# Reads what a job has printed so far without consuming it, so a case can wait for the watcher
# to reach a known point instead of guessing with a sleep.
function Get-JobOutputSoFar {
    param([Parameter(Mandatory)][object] $Job)

    return ((Receive-Job -Job $Job -Keep 2>$null) | Out-String)
}

function Wait-ForJobOutput {
    param(
        [Parameter(Mandatory)][object] $Job,
        [Parameter(Mandatory)][string] $Pattern,
        [int] $TimeoutSeconds = 30
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if ((Get-JobOutputSoFar -Job $Job) -match $Pattern) { return $true }
        Start-Sleep -Milliseconds 200
    }

    return $false
}

# The last line that carries text. The follow path ends with exactly 'Exit code: N'; the
# already-finished path ends with a sentence that also contains those words, so only comparing
# the whole line tells the two apart.
function Get-LastNonEmptyLine {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)

    $lines = @($Text -split "`r?`n" | Where-Object { $_.Trim().Length -gt 0 })
    if ($lines.Count -eq 0) { return '' }
    return $lines[-1].Trim()
}

$root = New-WatchTestRoot
$job = $null
try {
    $session = [guid]::NewGuid().ToString()
    $tasksDir = Join-Path (Join-Path (Join-Path $root "$prefix-live") $session) 'tasks'
    New-Item -ItemType Directory -Path $tasksDir -Force | Out-Null
    $livePath = Join-Path $tasksDir 'task.output'

    # The unfinished half of the split line is already in the file before the watcher starts, so
    # the watcher must read it during its first tail. Nothing here depends on when a poll lands:
    # a sleep between two appends would prove nothing, because a poll arriving after both of them
    # sees one complete line and a line counter would look correct.
    [System.IO.File]::WriteAllText($livePath, "FIRST-LINE`nSPLIT-LINE-START")

    # No Out-String inside the job. That would hold every line back until the watcher exited,
    # and then no case could wait for the watcher to reach a known point.
    $job = Start-Job -ScriptBlock {
        param($exe, $script, $searchRoot)
        & $exe -NoProfile -File $script -Root $searchRoot -Tail 40 2>&1
    } -ArgumentList $hostExe, $watchScript, $root

    # Wait for the watcher to print what was already there. The file holds no exit marker yet, so
    # reaching this point proves the watcher is in the follow loop rather than on the finished
    # path. A fixed sleep proves nothing: a slow start would let the whole file arrive first.
    $entered = Wait-ForJobOutput -Job $job -Pattern 'FIRST-LINE'
    Assert-True $entered 'Follow: the watcher must print the existing text and start following within 30s.'

    # The text that finishes the line adds no new line to the file, so a watcher that counts
    # lines has nothing to notice and drops it.
    [System.IO.File]::AppendAllText($livePath, "-AND-END`n")

    $joined = Wait-ForJobOutput -Job $job -Pattern 'SPLIT-LINE-START-AND-END'
    Assert-True $joined 'Follow: a line written in two pieces must be printed in full.'

    [System.IO.File]::AppendAllText($livePath, "LAST-LINE`n[exited with code 3]`n")

    $finished = Wait-Job -Job $job -Timeout 30
    Assert-True ($null -ne $finished) 'Follow: the watcher must stop by itself when the exit marker arrives, but it was still running after 30s.'

    $output = Get-JobOutputSoFar -Job $job

    Assert-True ($output -match 'FIRST-LINE') "Follow: the text already in the file must be printed. Output: $output"
    Assert-True ($output -match 'SPLIT-LINE-START-AND-END') "Follow: a line written in two pieces must be printed in full. Output: $output"
    Assert-True ($output -match 'LAST-LINE') "Follow: a line appended after that must be printed. Output: $output"

    # A watcher that counts lines prints the unfinished half as a line of its own, and then never
    # prints the rest. Checking whole lines catches that; a substring check cannot, because the
    # finished line contains the unfinished one.
    $ownLine = @($output -split "`r?`n" | Where-Object { $_.Trim() -eq 'SPLIT-LINE-START' })
    Assert-True ($ownLine.Count -eq 0) "Follow: the unfinished half must never be printed as a line of its own. Output: $output"

    $lastLine = Get-LastNonEmptyLine -Text $output
    Assert-True ($lastLine -eq 'Exit code: 3') "Follow: the last line must be exactly 'Exit code: 3', got '$lastLine'. Output: $output"
}
finally {
    if ($job) { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

# --- A successful read resets earlier read failures ---

$retryPath = Join-Path ([System.IO.Path]::GetTempPath()) ("watch-task-retries-$([guid]::NewGuid()).output")
try {
    [System.IO.File]::WriteAllText($retryPath, "START`n")
    $output = & $hostExe -NoProfile -Command @"
. '$watchScript'
`$script:readCall = 0
function Read-TailText {
    param([object] `$Reader)
    `$script:readCall++
    `$Reader.ReadError = `$null
    if (`$script:readCall -in @(1, 3, 5, 7)) {
        `$Reader.ReadSucceeded = `$false
        `$Reader.AtEnd = `$false
        return ''
    }

    `$Reader.ReadSucceeded = `$true
    `$Reader.AtEnd = `$script:readCall -ge 8
    return "RECOVERED-`$script:readCall``n"
}
function Get-TaskState {
    param([string] `$Path)
    return [pscustomobject]@{ Running = `$false; ExitCode = 0; BytesRead = 1 }
}
`$record = [pscustomobject]@{ Path = '$retryPath'; LastWrite = (Get-Date); Running = `$true; ExitCode = `$null }
exit (Watch-Record -Record `$record -Tail 40)
"@ 2>&1 | Out-String
    $exitCode = $LASTEXITCODE

    Assert-True ($exitCode -eq 0) "Read retries: separated failures must not end the watch. Exit: $exitCode. Output: $output"
    Assert-True ($output -notmatch 'could no longer be read') "Read retries: each success must reset the failure count. Output: $output"
    Assert-True ($output -match 'Exit code: 0') "Read retries: the eventual terminal state must be reported. Output: $output"
}
finally {
    Remove-Item -LiteralPath $retryPath -Force -ErrorAction SilentlyContinue
}

# --- An exit-marker-shaped output line does not end the watch unless it is last ---

$root = New-WatchTestRoot
$job = $null
try {
    $session = [guid]::NewGuid().ToString()
    $tasksDir = Join-Path (Join-Path (Join-Path $root "$prefix-marker") $session) 'tasks'
    New-Item -ItemType Directory -Path $tasksDir -Force | Out-Null
    $markerPath = Join-Path $tasksDir 'task.output'
    [System.IO.File]::WriteAllText($markerPath, "STARTED`n")

    $job = Start-Job -ScriptBlock {
        param($exe, $script, $searchRoot)
        & $exe -NoProfile -File $script -Root $searchRoot -Tail 40 2>&1
    } -ArgumentList $hostExe, $watchScript, $root

    $entered = Wait-ForJobOutput -Job $job -Pattern 'STARTED'
    Assert-True $entered 'Trailing marker: the watcher must start following within 30s.'

    [System.IO.File]::AppendAllText($markerPath, "[exited with code 5]`nAFTER-NONTERMINAL-MARKER`n")
    $continued = Wait-ForJobOutput -Job $job -Pattern 'AFTER-NONTERMINAL-MARKER' -TimeoutSeconds 5
    Assert-True $continued 'Trailing marker: output after a marker-shaped line must still be shown.'

    [System.IO.File]::AppendAllText($markerPath, "[exited with code 6]`n")
    $finished = Wait-Job -Job $job -Timeout 20
    Assert-True ($null -ne $finished) 'Trailing marker: the final marker must stop the watcher.'

    $output = Get-JobOutputSoFar -Job $job
    Assert-True ($output -match 'AFTER-NONTERMINAL-MARKER') "Trailing marker: later output must not be hidden. Output: $output"
    $lastLine = Get-LastNonEmptyLine -Text $output
    Assert-True ($lastLine -eq 'Exit code: 6') "Trailing marker: the trailing marker must supply the verdict, got '$lastLine'. Output: $output"
}
finally {
    if ($job) { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

# Overwrites a file from byte zero without emptying it first. WriteAllText truncates before it
# writes, and a watcher can notice that short moment for reasons unrelated to what a case is
# testing. This leaves the file at least as long as it was throughout.
function Set-FileContentInPlace {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Text
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
    try {
        $stream.Position = 0
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()
    }
    finally {
        $stream.Dispose()
    }
}

# --- A longer replacement with the same remembered start is read from the beginning ---

$root = New-WatchTestRoot
$job = $null
try {
    $session = [guid]::NewGuid().ToString()
    $tasksDir = Join-Path (Join-Path (Join-Path $root "$prefix-checkpoint") $session) 'tasks'
    New-Item -ItemType Directory -Path $tasksDir -Force | Out-Null
    $checkpointPath = Join-Path $tasksDir 'task.output'

    $sharedStart = "SHARED-PREFIX-LINE`n" * 20
    $original = $sharedStart + ("ORIGINAL-FILLER-LINE`n" * 20)
    [System.IO.File]::WriteAllText($checkpointPath, $original)

    $job = Start-Job -ScriptBlock {
        param($exe, $script, $searchRoot)
        & $exe -NoProfile -File $script -Root $searchRoot -Tail 100 2>&1
    } -ArgumentList $hostExe, $watchScript, $root

    $entered = Wait-ForJobOutput -Job $job -Pattern 'ORIGINAL-FILLER-LINE'
    Assert-True $entered 'Checkpoint replacement: the watcher must consume the original file.'

    $changedBeforeOffset = 'REPLACEMENT-BEFORE-OLD-OFFSET'
    $replacementStart = $sharedStart + "$changedBeforeOffset`n"
    $paddingLength = $original.Length - $replacementStart.Length + 100
    $replacement = $replacementStart + ('R' * $paddingLength) + "`nREPLACEMENT-SUFFIX`n[exited with code 11]`n"
    Assert-True ($sharedStart.Length -gt 256) 'Checkpoint replacement: the shared start must exceed the head check.'
    Assert-True ($replacement.IndexOf($changedBeforeOffset) -lt $original.Length) 'Checkpoint replacement: changed output must sit before the old offset.'
    Assert-True ($replacement.Length -gt $original.Length) 'Checkpoint replacement: the replacement must extend past the old offset.'

    Set-FileContentInPlace -Path $checkpointPath -Text $replacement

    $finished = Wait-Job -Job $job -Timeout 20
    Assert-True ($null -ne $finished) 'Checkpoint replacement: the terminal replacement must stop the watcher.'

    $output = Get-JobOutputSoFar -Job $job
    Assert-True ($output -match $changedBeforeOffset) "Checkpoint replacement: changed output before the old offset must not be lost. Output: $output"
    Assert-True ((Get-LastNonEmptyLine -Text $output) -eq 'Exit code: 11') "Checkpoint replacement: the final exit code must be reported. Output: $output"
}
finally {
    if ($job) { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

# --- A selected output file that disappears ends with a visible failure ---

$root = New-WatchTestRoot
$job = $null
try {
    $session = [guid]::NewGuid().ToString()
    $tasksDir = Join-Path (Join-Path (Join-Path $root "$prefix-deleted") $session) 'tasks'
    New-Item -ItemType Directory -Path $tasksDir -Force | Out-Null
    $deletedPath = Join-Path $tasksDir 'task.output'
    [System.IO.File]::WriteAllText($deletedPath, "BEFORE-DELETION`n")

    $job = Start-Job -ScriptBlock {
        param($exe, $script, $searchRoot)
        & $exe -NoProfile -File $script -Root $searchRoot -Tail 40 2>&1
    } -ArgumentList $hostExe, $watchScript, $root

    $entered = Wait-ForJobOutput -Job $job -Pattern 'BEFORE-DELETION'
    Assert-True $entered 'Deleted file: the watcher must start following within 30s.'
    Remove-Item -LiteralPath $deletedPath -Force

    $finished = Wait-Job -Job $job -Timeout 8
    Assert-True ($null -ne $finished) 'Deleted file: the watcher must not wait forever after its file disappears.'

    $output = Get-JobOutputSoFar -Job $job
    Assert-True ($output -match 'could no longer be read') "Deleted file: the watcher must explain why it stopped. Output: $output"
}
finally {
    if ($job) { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

# --- A task that finishes between the scan and the tail still ends the watch ---
#
# Get-WatchTaskRecord reads whether a task is running, and Watch-Record tails the file after
# that. A task that finishes in between leaves the record saying "running" while the initial
# tail already prints and consumes the exit marker. The follow loop only sees text added later,
# so it would wait for a line that can never arrive.
#
# The case builds that exact state rather than racing for it: a record that says running,
# against a file that already carries the marker.

$job = $null
$stalePath = Join-Path ([System.IO.Path]::GetTempPath()) ("watch-task-stale-$([guid]::NewGuid()).output")
try {
    [System.IO.File]::WriteAllText($stalePath, "ALREADY-DONE`n[exited with code 3]`n")

    $job = Start-Job -ScriptBlock {
        param($exe, $script, $path)
        # Out-Null drops the exit code Watch-Record returns, which the real script passes to
        # 'exit'. Left in, it would become the last line and hide what the watcher printed.
        & $exe -NoProfile -Command @"
. '$script'
`$record = [pscustomobject]@{ Path = '$path'; LastWrite = (Get-Date); Running = `$true; ExitCode = `$null }
Watch-Record -Record `$record -Tail 40 | Out-Null
"@ 2>&1
    } -ArgumentList $hostExe, $watchScript, $stalePath

    $finished = Wait-Job -Job $job -Timeout 20
    Assert-True ($null -ne $finished) 'Stale running: the watcher must stop when the file already holds the marker, but it was still running after 20s.'

    $output = Get-JobOutputSoFar -Job $job
    Assert-True ($output -match 'ALREADY-DONE') "Stale running: the text already in the file must be printed. Output: $output"

    $lastLine = Get-LastNonEmptyLine -Text $output
    Assert-True ($lastLine -eq 'Exit code: 3') "Stale running: the last line must be exactly 'Exit code: 3', got '$lastLine'. Output: $output"
}
finally {
    if ($job) { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $stalePath -Force -ErrorAction SilentlyContinue
}

# --- The same stale record with -NoFollow does not claim the task is still running ---

$stalePath = Join-Path ([System.IO.Path]::GetTempPath()) ("watch-task-stale-nofollow-$([guid]::NewGuid()).output")
try {
    [System.IO.File]::WriteAllText($stalePath, "ALREADY-DONE`n[exited with code 5]`n")

    $output = & $hostExe -NoProfile -Command @"
. '$watchScript'
`$record = [pscustomobject]@{ Path = '$stalePath'; LastWrite = (Get-Date); Running = `$true; ExitCode = `$null }
Watch-Record -Record `$record -Tail 40 -NoFollow | Out-Null
"@ 2>&1 | Out-String

    Assert-True ($output -notmatch 'still running') "Stale running with -NoFollow: the watcher must not say the task is still running. Output: $output"
    Assert-True ($output -match 'Exit code: 5') "Stale running with -NoFollow: the exit code must be reported. Output: $output"
}
finally {
    Remove-Item -LiteralPath $stalePath -Force -ErrorAction SilentlyContinue
}

# --- A file replaced by a longer one is read again from the start ---
#
# The reader remembers how many bytes it has consumed. A file that is replaced rather than
# appended to can be the same size or longer, so the byte count alone says nothing is wrong, and
# the reader carries on from the old spot. Everything before that spot is never read, and when
# the exit marker is in there the watcher waits for a line that has already been and gone.

$root = New-WatchTestRoot
$job = $null
try {
    $session = [guid]::NewGuid().ToString()
    $tasksDir = Join-Path (Join-Path (Join-Path $root "$prefix-replaced") $session) 'tasks'
    New-Item -ItemType Directory -Path $tasksDir -Force | Out-Null
    $replacedPath = Join-Path $tasksDir 'task.output'

    $original = "ORIGINAL-LINE`n" * 30
    [System.IO.File]::WriteAllText($replacedPath, $original)

    # The replacement below is written over the file in place, never through WriteAllText.
    # WriteAllText empties the file first, and that short moment makes the file shorter than the
    # bytes already read, which the watcher notices for a reason that has nothing to do with
    # replacement. Writing in place removes that luck, so the case tests what it claims.

    $job = Start-Job -ScriptBlock {
        param($exe, $script, $searchRoot)
        & $exe -NoProfile -File $script -Root $searchRoot -Tail 100 2>&1
    } -ArgumentList $hostExe, $watchScript, $root

    $entered = Wait-ForJobOutput -Job $job -Pattern 'ORIGINAL-LINE'
    Assert-True $entered 'Replaced file: the watcher must read the original file and start following within 30s.'

    # The replacement is longer than the original, and its marker sits after new output.
    $replacement = ("REPLACEMENT-LINE`n" * 40) + "[exited with code 7]`n"
    Assert-True ($replacement.Length -gt $original.Length) 'Replaced file: the replacement must be longer, or the case is not testing what it claims.'
    Set-FileContentInPlace -Path $replacedPath -Text $replacement

    $finished = Wait-Job -Job $job -Timeout 25
    Assert-True ($null -ne $finished) 'Replaced file: the watcher must notice the replacement and stop, but it was still running after 25s.'

    $output = Get-JobOutputSoFar -Job $job
    Assert-True ($output -match 'Exit code: 7') "Replaced file: the marker in the replacement must be found. Output: $output"
}
finally {
    if ($job) { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

# --- A replacement that looks identical from the outside still ends the watch ---
#
# Comparing the start of the file cannot separate every replacement from an append. A file of the
# same length, whose first bytes are also the same, looks untouched from every angle the reader
# has, so its saved byte offset survives and no new text ever arrives.
#
# The watcher must not depend on catching that. When nothing new arrives it asks the file itself
# whether it has ended, so the wait always ends whatever the reader believes.

$root = New-WatchTestRoot
$job = $null
try {
    $session = [guid]::NewGuid().ToString()
    $tasksDir = Join-Path (Join-Path (Join-Path $root "$prefix-samesize") $session) 'tasks'
    New-Item -ItemType Directory -Path $tasksDir -Force | Out-Null
    $samePath = Join-Path $tasksDir 'task.output'

    # A shared start longer than the reader remembers, so the prefix check can never tell these
    # two apart. Both files are exactly the same length.
    $sharedStart = "SAME-PREFIX-LINE`n" * 20
    $marker = "[exited with code 9]`n"
    $original = $sharedStart + ('X' * ($marker.Length - 1)) + "`n"
    $replacement = $sharedStart + $marker

    Assert-True ($original.Length -eq $replacement.Length) 'Same-size replacement: both files must be the same length, or the case is not testing what it claims.'
    Assert-True ($sharedStart.Length -gt 256) 'Same-size replacement: the shared start must be longer than the part the reader remembers.'

    [System.IO.File]::WriteAllText($samePath, $original)

    $job = Start-Job -ScriptBlock {
        param($exe, $script, $searchRoot)
        & $exe -NoProfile -File $script -Root $searchRoot -Tail 100 2>&1
    } -ArgumentList $hostExe, $watchScript, $root

    $entered = Wait-ForJobOutput -Job $job -Pattern 'SAME-PREFIX-LINE'
    Assert-True $entered 'Same-size replacement: the watcher must read the original file and start following within 30s.'

    Set-FileContentInPlace -Path $samePath -Text $replacement

    $finished = Wait-Job -Job $job -Timeout 25
    Assert-True ($null -ne $finished) 'Same-size replacement: the watcher must still stop, but it was running after 25s.'

    $output = Get-JobOutputSoFar -Job $job
    Assert-True ($output -match 'Exit code: 9') "Same-size replacement: the exit code must be reported. Output: $output"
}
finally {
    if ($job) { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

# --- A task that ends without a final newline is still reported as finished ---
#
# The marker is normally a line of its own. A task killed mid-write can leave it with no newline
# after it, which makes it the unfinished text at the end of the file rather than a complete
# line. -NoFollow printed that text and then said the task was still running.

$stalePath = Join-Path ([System.IO.Path]::GetTempPath()) ("watch-task-nonewline-$([guid]::NewGuid()).output")
try {
    [System.IO.File]::WriteAllText($stalePath, "ALREADY-DONE`n[exited with code 5]")

    $output = & $hostExe -NoProfile -Command @"
. '$watchScript'
`$record = [pscustomobject]@{ Path = '$stalePath'; LastWrite = (Get-Date); Running = `$true; ExitCode = `$null }
Watch-Record -Record `$record -Tail 40 -NoFollow | Out-Null
"@ 2>&1 | Out-String

    Assert-True ($output -notmatch 'still running') "No final newline: the watcher must not say the task is still running. Output: $output"
    Assert-True ($output -match 'Exit code: 5') "No final newline: the exit code must be reported. Output: $output"
}
finally {
    Remove-Item -LiteralPath $stalePath -Force -ErrorAction SilentlyContinue
}

# --- Output written while the terminal state is read is still printed ---
#
# The follow loop reads new text, and then asks the file whether the task has ended. A run that
# wrote its last lines between those two steps had them dropped: the state said the task was over,
# and the watcher stopped without ever reading the bytes that arrived in the gap.
#
# The case builds that gap rather than racing for it. Get-TaskState is replaced in a child session:
# its first call appends more output and reports the task still running, and its second call
# appends the final lines and reports the task finished.

$job = $null
$gapPath = Join-Path ([System.IO.Path]::GetTempPath()) ("watch-task-gap-$([guid]::NewGuid()).output")
try {
    [System.IO.File]::WriteAllText($gapPath, "FIRST-LINE`n")

    $job = Start-Job -ScriptBlock {
        param($exe, $script, $path)
        & $exe -NoProfile -Command @"
. '$script'

`$script:stateCalls = 0
function Get-TaskState {
    param([Parameter(Mandatory)][string] `$Path)

    `$script:stateCalls++
    if (`$script:stateCalls -eq 1) {
        [System.IO.File]::AppendAllText(`$Path, ('SECOND-LINE' + [char]10))
        return [pscustomobject]@{ Running = `$true; ExitCode = `$null; BytesRead = 0 }
    }

    [System.IO.File]::AppendAllText(`$Path, ('FINAL-LINE' + [char]10 + '[exited with code 8]' + [char]10))
    return [pscustomobject]@{ Running = `$false; ExitCode = 8; BytesRead = 0 }
}

`$record = [pscustomobject]@{ Path = '$path'; LastWrite = (Get-Date); Running = `$true; ExitCode = `$null }
Watch-Record -Record `$record -Tail 40 | Out-Null
"@ 2>&1
    } -ArgumentList $hostExe, $watchScript, $gapPath

    $finished = Wait-Job -Job $job -Timeout 25
    Assert-True ($null -ne $finished) 'Late append: the watcher must stop, but it was still running after 25s.'

    $output = Get-JobOutputSoFar -Job $job
    Assert-True ($output -match 'SECOND-LINE') "Late append: the text read before the state check must be printed. Output: $output"
    Assert-True ($output -match 'FINAL-LINE') "Late append: the text written during the state check must not be lost. Output: $output"

    $lastLine = Get-LastNonEmptyLine -Text $output
    Assert-True ($lastLine -eq 'Exit code: 8') "Late append: the last line must be 'Exit code: 8', got '$lastLine'. Output: $output"
}
finally {
    if ($job) { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $gapPath -Force -ErrorAction SilentlyContinue
}

# --- A replacement that arrives during the catch-up read is not judged by the old file ---
#
# The follow loop reads a terminal state, then reads on to the file end so no late output is lost.
# A new run can replace the file inside that window. The catch-up read notices the replacement and
# prints it, so the watcher must ask the file again what its state is. Reporting the state captured
# before the catch-up would print the old task's exit code over the new task's output, and stop
# following a run that is still going.
#
# The case builds that window rather than racing for it. Get-TaskState is replaced in a child
# session: its first call replaces the file and reports the old task finished with code 7, its
# second call reports the replacement still running, and its third appends the replacement's own
# marker and reports code 9.

$job = $null
$swapPath = Join-Path ([System.IO.Path]::GetTempPath()) ("watch-task-swap-$([guid]::NewGuid()).output")
try {
    [System.IO.File]::WriteAllText($swapPath, "OLD-LINE`n")

    $job = Start-Job -ScriptBlock {
        param($exe, $script, $path)
        & $exe -NoProfile -Command @"
. '$script'

`$script:stateCalls = 0
function Get-TaskState {
    param([Parameter(Mandatory)][string] `$Path)

    `$script:stateCalls++
    if (`$script:stateCalls -eq 1) {
        Remove-Item -LiteralPath `$Path -Force
        [System.IO.File]::WriteAllText(`$Path, ('NEW-RUN-LINE' + [char]10))
        return [pscustomobject]@{ Running = `$false; ExitCode = 7; BytesRead = 0 }
    }
    if (`$script:stateCalls -eq 2) {
        return [pscustomobject]@{ Running = `$true; ExitCode = `$null; BytesRead = 0 }
    }
    if (`$script:stateCalls -eq 3) {
        [System.IO.File]::AppendAllText(`$Path, ('NEW-RUN-END' + [char]10 + '[exited with code 9]' + [char]10))
    }
    return [pscustomobject]@{ Running = `$false; ExitCode = 9; BytesRead = 0 }
}

`$record = [pscustomobject]@{ Path = '$path'; LastWrite = (Get-Date); Running = `$true; ExitCode = `$null }
Watch-Record -Record `$record -Tail 40 | Out-Null
"@ 2>&1
    } -ArgumentList $hostExe, $watchScript, $swapPath

    $finished = Wait-Job -Job $job -Timeout 25
    Assert-True ($null -ne $finished) 'Catch-up swap: the watcher must stop, but it was still running after 25s.'

    $output = Get-JobOutputSoFar -Job $job
    Assert-True ($output -match 'NEW-RUN-LINE') "Catch-up swap: the replacement's output must be printed. Output: $output"
    Assert-True ($output -match 'NEW-RUN-END') "Catch-up swap: the watcher must keep following the replacement. Output: $output"
    Assert-True (-not ($output -match 'Exit code: 7')) `
        "Catch-up swap: the old file's exit code must not be reported over the replacement. Output: $output"

    $lastLine = Get-LastNonEmptyLine -Text $output
    Assert-True ($lastLine -eq 'Exit code: 9') "Catch-up swap: the last line must be 'Exit code: 9', got '$lastLine'. Output: $output"
}
finally {
    if ($job) { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $swapPath -Force -ErrorAction SilentlyContinue
}

# --- A replacement arriving after the catch-up read is still printed before its verdict ---
#
# The catch-up read runs first, then the state is read again. A new run can replace the file
# between those two steps. The state then describes the replacement while nothing of the
# replacement has been read, and the fallback tail does not cover it, because that only runs when
# the whole iteration read nothing at all. The watcher printed the replacement's exit code over
# the old task's output.
#
# The case builds that window. Get-TaskState is replaced in a child session: its first call adds
# a late line to the old file and reports the old task finished with code 7, and its second call
# replaces the file and reports code 9.

$job = $null
$latePath = Join-Path ([System.IO.Path]::GetTempPath()) ("watch-task-late-swap-$([guid]::NewGuid()).output")
try {
    [System.IO.File]::WriteAllText($latePath, "OLD-LINE`n")

    $job = Start-Job -ScriptBlock {
        param($exe, $script, $path)
        & $exe -NoProfile -Command @"
. '$script'

`$script:stateCalls = 0
function Get-TaskState {
    param([Parameter(Mandatory)][string] `$Path)

    `$script:stateCalls++
    if (`$script:stateCalls -eq 1) {
        [System.IO.File]::AppendAllText(`$Path, ('LATE-LINE' + [char]10))
        return [pscustomobject]@{ Running = `$false; ExitCode = 7; BytesRead = 0 }
    }
    if (`$script:stateCalls -eq 2) {
        Remove-Item -LiteralPath `$Path -Force
        [System.IO.File]::WriteAllText(`$Path, ('NEW-RUN-LINE' + [char]10 + '[exited with code 9]' + [char]10))
    }
    return [pscustomobject]@{ Running = `$false; ExitCode = 9; BytesRead = 0 }
}

`$record = [pscustomobject]@{ Path = '$path'; LastWrite = (Get-Date); Running = `$true; ExitCode = `$null }
Watch-Record -Record `$record -Tail 40 | Out-Null
"@ 2>&1
    } -ArgumentList $hostExe, $watchScript, $latePath

    $finished = Wait-Job -Job $job -Timeout 25
    Assert-True ($null -ne $finished) 'Late swap: the watcher must stop, but it was still running after 25s.'

    $output = Get-JobOutputSoFar -Job $job
    Assert-True ($output -match 'LATE-LINE') "Late swap: the old file's last line must be printed. Output: $output"
    Assert-True ($output -match 'NEW-RUN-LINE') `
        "Late swap: the replacement's output must be printed before its exit code. Output: $output"

    $lastLine = Get-LastNonEmptyLine -Text $output
    Assert-True ($lastLine -eq 'Exit code: 9') "Late swap: the last line must be 'Exit code: 9', got '$lastLine'. Output: $output"
}
finally {
    if ($job) { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $latePath -Force -ErrorAction SilentlyContinue
}

# --- A state read that keeps failing after catch-up ends the watch instead of spinning ---
#
# The state is read twice per pass: once to notice the task ended, once after the catch-up read.
# The first read resets the failure count on every success, so it cannot bound a failure that
# only happens on the second read. The second read needs its own count, or the loop repeats with
# no sleep and no end.
#
# The stub answers by call order. The odd calls are the first read and report the task finished.
# The even calls are the read after catch-up and fail.

$job = $null
$settlePath = Join-Path ([System.IO.Path]::GetTempPath()) ("watch-task-settle-$([guid]::NewGuid()).output")
try {
    [System.IO.File]::WriteAllText($settlePath, "ONLY-LINE`n")

    $job = Start-Job -ScriptBlock {
        param($exe, $script, $path)
        & $exe -NoProfile -Command @"
. '$script'

`$script:stateCalls = 0
function Get-TaskState {
    param([Parameter(Mandatory)][string] `$Path)

    `$script:stateCalls++
    if (`$script:stateCalls % 2 -eq 1) {
        return [pscustomobject]@{ Running = `$false; ExitCode = 5; BytesRead = 0 }
    }
    return `$null
}

`$record = [pscustomobject]@{ Path = '$path'; LastWrite = (Get-Date); Running = `$true; ExitCode = `$null }
exit (Watch-Record -Record `$record -Tail 40)
"@ 2>&1
    } -ArgumentList $hostExe, $watchScript, $settlePath

    $finished = Wait-Job -Job $job -Timeout 25
    Assert-True ($null -ne $finished) `
        'Settle failure: a state read that keeps failing must end the watch, but it was still running after 25s.'

    $output = Get-JobOutputSoFar -Job $job
    Assert-True ($output -match 'could no longer be read') `
        "Settle failure: the watcher must say the file could no longer be read. Output: $output"
}
finally {
    if ($job) { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $settlePath -Force -ErrorAction SilentlyContinue
}

# --- A worktree whose name is not plain ASCII is still found ---
#
# git writes its paths as UTF-8 bytes. PowerShell decodes a native command's output with
# [Console]::OutputEncoding, which on Windows is the OEM code page, so those bytes come back as
# the wrong characters and the folder they name is never matched. The checkout list is what the
# watcher uses to decide which task file belongs to this repository, so a worktree missing from
# it can never be watched.

$gitExe = Get-Command git -ErrorAction SilentlyContinue
if ($gitExe) {
    $gitRoot = Join-Path ([System.IO.Path]::GetTempPath()) "watch-task-git-$([guid]::NewGuid())"
    $gitMain = Join-Path $gitRoot 'main'
    # Built from the code point so this file stays plain ASCII on disk.
    $gitAccented = Join-Path $gitRoot ('wt-caf' + [char]0xE9)
    try {
        New-Item -ItemType Directory -Path $gitMain -Force | Out-Null
        & $gitExe.Source -C $gitMain init -q . 2>&1 | Out-Null
        & $gitExe.Source -C $gitMain commit -q --allow-empty -m 'init' 2>&1 | Out-Null
        & $gitExe.Source -C $gitMain worktree add -q $gitAccented -b accented 2>&1 | Out-Null

        $checkouts = @(Get-RepositoryCheckoutPath -MainRoot $gitMain)
        Assert-True ($checkouts -contains $gitAccented) `
            "Accented worktree: it must be in the checkout list, got: $($checkouts -join ' | ')"
    }
    finally {
        Remove-Item -LiteralPath $gitRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
else {
    Write-Host 'Accented worktree check skipped: git is not available.' -ForegroundColor Yellow
}

# --- A catch-up read that fails is retried, not read as a file with nothing left ---
#
# The catch-up read after the task ends returns an empty string both when the file holds nothing
# more and when the read itself failed. Treating the two the same lets the watcher take the
# state and print the verdict while the run's last lines are still on disk, unread.
#
# The case makes that read fail once. Read-TailText is wrapped in a child session: its second
# call reports a failure, every other call does the real read. Get-TaskState adds a late line on
# its first call and reports the task finished, so there is output the failed read would skip.

$job = $null
$catchUpPath = Join-Path ([System.IO.Path]::GetTempPath()) ("watch-task-catchup-$([guid]::NewGuid()).output")
try {
    [System.IO.File]::WriteAllText($catchUpPath, "ONLY-LINE`n")

    $job = Start-Job -ScriptBlock {
        param($exe, $script, $path)
        & $exe -NoProfile -Command @"
. '$script'

`$script:realRead = `${function:Read-TailText}
`$script:readCalls = 0
function Read-TailText {
    param([Parameter(Mandatory)][object] `$Reader)

    `$script:readCalls++
    if (`$script:readCalls -eq 2) {
        `$Reader.ReadSucceeded = `$false
        `$Reader.ReadError = 'stubbed failure'
        `$Reader.AtEnd = `$false
        return ''
    }

    return (& `$script:realRead -Reader `$Reader)
}

`$script:stateCalls = 0
function Get-TaskState {
    param([Parameter(Mandatory)][string] `$Path)

    `$script:stateCalls++
    if (`$script:stateCalls -eq 1) {
        [System.IO.File]::AppendAllText(`$Path, ('LATE-LINE' + [char]10))
    }
    return [pscustomobject]@{ Running = `$false; ExitCode = 7; BytesRead = 0 }
}

`$record = [pscustomobject]@{ Path = '$path'; LastWrite = (Get-Date); Running = `$true; ExitCode = `$null }
exit (Watch-Record -Record `$record -Tail 40)
"@ 2>&1
    } -ArgumentList $hostExe, $watchScript, $catchUpPath

    $finished = Wait-Job -Job $job -Timeout 25
    Assert-True ($null -ne $finished) 'Catch-up failure: the watcher must stop, but it was still running after 25s.'

    $output = Get-JobOutputSoFar -Job $job
    Assert-True ($output -match 'LATE-LINE') `
        "Catch-up failure: the line written before the failed read must still be printed. Output: $output"

    # The fallback re-tail only runs when the whole pass read nothing. Seeing it here means the
    # failed read was taken for an empty file and the verdict was printed over unread output.
    Assert-True ($output -notmatch 'was being followed') `
        "Catch-up failure: a failed read must be retried, not answered with the missing-output notice. Output: $output"

    $lastLine = Get-LastNonEmptyLine -Text $output
    Assert-True ($lastLine -eq 'Exit code: 7') "Catch-up failure: the last line must be 'Exit code: 7', got '$lastLine'. Output: $output"
}
finally {
    if ($job) { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $catchUpPath -Force -ErrorAction SilentlyContinue
}

# --- A tail that starts inside a UTF-8 character drops the orphan bytes, not the text ---
#
# The initial read walks backwards from the end and stops on a byte bound, which can land in the
# middle of a multi-byte character. The decoder turns the leftover bytes of that character into a
# replacement character, and the watcher would print it. The bytes before the first newline are
# normally dropped anyway, so this only shows on a line longer than the bound, where the read is
# all there is to show.
#
# The cap is lowered so the file stays small. The first read is a calibration: it says how many
# bytes back from the end the cut lands, and the real file then puts a two-byte character across
# that exact point.

$utf8Path = Join-Path ([System.IO.Path]::GetTempPath()) ("watch-task-utf8-$([guid]::NewGuid()).output")
$previousCap = $script:MaxTailTextBytes
try {
    $script:MaxTailTextBytes = 4096

    $length = 6000
    $ascii = [byte[]]::new($length)
    for ($i = 0; $i -lt $length; $i++) { $ascii[$i] = [byte][char]'A' }
    $ascii[$length - 1] = 10
    [System.IO.File]::WriteAllBytes($utf8Path, $ascii)

    $calibration = New-TailReader -Path $utf8Path
    Read-InitialTailText -Reader $calibration -LineCount 40 | Out-Null
    Assert-True ($calibration.InitialTruncated) `
        'Split character: the calibration file must be long enough for the byte bound to stop the read.'

    $cut = $length - $calibration.InitialReadBytes
    Assert-True ($cut -gt 0) "Split character: the cut must fall inside the file, got offset $cut."

    # 'e' with an acute accent is two bytes in UTF-8. Its first byte goes one before the cut, so
    # the read starts on its second byte and has no character start to work from.
    $bytes = [byte[]]::new($length)
    [System.Array]::Copy($ascii, $bytes, $length)
    $bytes[$cut - 1] = 0xC3
    $bytes[$cut] = 0xA9
    [System.IO.File]::WriteAllBytes($utf8Path, $bytes)

    $reader = New-TailReader -Path $utf8Path
    $text = Read-InitialTailText -Reader $reader -LineCount 40

    Assert-True ($reader.ReadSucceeded) 'Split character: the read must succeed.'
    Assert-True ($text.IndexOf([char]0xFFFD) -lt 0) `
        'Split character: a tail starting inside a UTF-8 character must not print a replacement character.'
    Assert-True ($text.TrimEnd("`r", "`n").EndsWith('A')) `
        'Split character: the text after the orphan bytes must still be shown.'
}
finally {
    $script:MaxTailTextBytes = $previousCap
    Remove-Item -LiteralPath $utf8Path -Force -ErrorAction SilentlyContinue
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
