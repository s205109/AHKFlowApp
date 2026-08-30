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

# --- Reading the end of a file says whether the task finished, and with which code ---
#
# This is the check that ends the wait when the follower's byte offset has gone stale, so it must
# hold no state and must answer from the file alone.

$root = New-WatchTestRoot
try {
    $endCases = @(
        @{ Name = 'a terminal marker';        Content = "a`n[exited with code 3]`n";                              Expected = 3 }
        @{ Name = 'no final newline';         Content = "a`n[exited with code 4]";                                Expected = 4 }
        @{ Name = 'a negative code';          Content = "a`n[exited with code -1]`n";                             Expected = -1 }
        @{ Name = 'a running task';           Content = "a`nb`n";                                                 Expected = $null }
        @{ Name = 'blank lines only';         Content = "`n`n   `n";                                              Expected = $null }
        @{ Name = 'an empty file';            Content = '';                                                       Expected = $null }
        @{ Name = 'a marker that is not last'; Content = "[exited with code 5]`nmore`n";                           Expected = $null }
        # Longer than the window this reads, so it also proves the window looks at the end.
        @{ Name = 'a file past the window';   Content = (("PADDING-LINE`n" * 2000) + "[exited with code 6]`n");   Expected = 6 }
    )

    $caseNumber = 0
    foreach ($case in $endCases) {
        $caseNumber++
        $path = Join-Path $root "end-$caseNumber.output"
        [System.IO.File]::WriteAllText($path, $case.Content)

        $actual = Get-FileEndExitCode -Path $path
        $same = if ($null -eq $case.Expected) { $null -eq $actual } else { $actual -eq $case.Expected }
        Assert-True $same "End state: $($case.Name) must read as '$($case.Expected)', got '$actual'."
    }
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

    # The replacement is longer than the original, and its marker sits at the very front, well
    # before the point the reader had reached.
    $replacement = "[exited with code 7]`n" + ("REPLACEMENT-LINE`n" * 40)
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
