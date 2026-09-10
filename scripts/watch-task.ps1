#Requires -Version 7.0
<#
.SYNOPSIS
  Tail whatever long background run is going now, from the main checkout or any worktree.
.DESCRIPTION
  Claude Code writes each background command's output to
  %LOCALAPPDATA%\Temp\claude\<mangled project path>\<session id>\tasks\<task id>.output.
  The session id is a new GUID for every session, and a git worktree gets its own project
  folder, so the path changes constantly. This script finds the live run and tails it, so a
  human never has to be handed a path.

  It finds the run like this:
    1. It asks git for every checkout this repository has, main and worktrees, and mangles each
       into the folder name Claude Code uses. A folder belongs to the repository when its name
       is one of those, or starts with one of those followed by '-', which is how a session
       started in a subdirectory is still found. A folder that a neighbouring directory claims
       as closely, or more closely, is refused, because the mangling turns a path separator and
       a literal '-' into the same character.
    2. Among <match>\<session id>\tasks\<task id>.output, a file is running when something holds
       it open for writing. That is asked of the operating system, not read from the file, so a
       file left behind by a session that is gone does not count as running. The file's text still
       decides the terminal state: an exit code, killed, or stopped without a terminal marker.
    3. Among the running files it prefers, in order, the caller's own session, then the checkout
       this copy of the script sits in, then the newest by last write time. Each preference is
       skipped when it matches no running task. It tails the winner, following by byte offset so a
       line written in two pieces is printed once, in full. The tail stops when the file ends with
       a terminal marker, or when nothing holds it open any more.

  With no running task it prints the newest stopped task's last lines, terminal state, and path,
  then exits 0. With more than one running it tails the one the preference order in step 3 picks
  and names how many others are running.

.PARAMETER List
  Print tasks with their state, age, and index, then exit. Every running task gets a row, and
  newest stopped tasks fill the rest up to twenty rows.
.PARAMETER Index
  Select one task from the same list -List prints (1-based) instead of the one the preference
  order would pick.
.PARAMETER Tail
  How many trailing lines to print before following. Default 40.
.PARAMETER Root
  The search root. Default %LOCALAPPDATA%\Temp\claude. A test points this at a tree it built.
.PARAMETER NoFollow
  Print the tail once and exit, instead of following a running task until it ends.
#>
[CmdletBinding()]
param(
    [switch] $List,

    # 1-based, matching the numbers -List prints. Left at 0 it means "let the preference order in
    # step 3 pick". The range stops 0 and a negative from reading as that default and quietly
    # ignoring what the caller asked for.
    [ValidateRange(1, [int]::MaxValue)]
    [int] $Index,

    [ValidateRange(1, [int]::MaxValue)]
    [int] $Tail = 40,

    [string] $Root,
    [switch] $NoFollow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ExitMarker = '^\[exited with code (-?\d+)\]\s*$'
$script:KilledMarker = '^\[killed\]\s*$'
$script:TaskStateReadLength = 8192
$script:TailReadLength = 65536
$script:MaxTailTextBytes = 1048576
$script:MaxTailReadFailures = 4

# How many times the follow loop reads to the file's end and asks for its state again before it
# reports what it has. Each round costs one read of a file that has already stopped growing, and
# a round only repeats when a new run replaced the file inside the last one.
$script:MaxSettleRounds = 5

# How many times one read may find the file replaced and start again from its beginning before it
# gives up and leaves the next poll to try. Two covers a run swapping the file once while the
# reader is inside a call; more than that is a writer the reader cannot keep up with anyway.
$script:MaxReplacementRetries = 2

# How many rows -List prints when nothing much is running. Every running task always gets a row,
# and newest stopped tasks fill whatever is left, so a quiet machine still shows recent history
# and a busy one still shows every running task. -Index addresses this same list.
$script:ListRowCount = 20

function ConvertTo-ClaudeProjectFolder {
    <#
      The rule is inferred from the folder names Claude Code writes, not from documentation.
      Each of ':', '\', '/', and '.' becomes '-'. If the rule is ever wrong the script finds
      nothing, which is a visible failure rather than a silent wrong answer.
    #>
    param([Parameter(Mandatory)][string] $Path)

    return ($Path -replace '[:\\/.]', '-')
}

function Get-RepositoryMainRoot {
    param([Parameter(Mandatory)][string] $ScriptRoot)

    $checkoutRoot = Split-Path -Parent $ScriptRoot

    try {
        $commonDir = & git -C $checkoutRoot rev-parse --git-common-dir 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($commonDir)) {
            if (-not [System.IO.Path]::IsPathRooted($commonDir)) {
                $commonDir = Join-Path $checkoutRoot $commonDir
            }
            $resolved = (Resolve-Path -LiteralPath $commonDir).Path
            return (Split-Path -Parent $resolved)
        }
    }
    catch {
        # git is missing or this is not a repository. Fall back to the checkout root.
    }

    return $checkoutRoot
}

function Get-RepositoryCheckoutPath {
    <#
      Every checkout this repository has on disk: the main one and each worktree.

      git worktree list is the source rather than a glob over the main root, because a worktree
      can be created anywhere on disk, and because a name that merely begins with the main root's
      name may belong to a different repository altogether.
    #>
    param([Parameter(Mandatory)][string] $MainRoot)

    $paths = [System.Collections.Generic.List[string]]::new()
    $paths.Add($MainRoot)

    try {
        # git writes paths as UTF-8 bytes. PowerShell decodes a native command's output with
        # [Console]::OutputEncoding, which on Windows is the OEM code page, so a worktree whose
        # name is not plain ASCII comes back mangled and its folder is then never matched.
        # The porcelain path itself is never quoted, so only the decoding has to be fixed.
        $previousEncoding = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
            $lines = @(& git -C $MainRoot worktree list --porcelain 2>$null)
        }
        finally {
            [Console]::OutputEncoding = $previousEncoding
        }

        if ($LASTEXITCODE -eq 0) {
            foreach ($line in $lines) {
                if ($line -match '^worktree\s+(.+)$') {
                    $candidate = $Matches[1].Trim()
                    if ($candidate) { $paths.Add(($candidate -replace '/', '\')) }
                }
            }
        }
    }
    catch {
        # No git, or not a repository. The main root alone still finds the common case.
    }

    $unique = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $paths) {
        $trimmed = $path.TrimEnd('\')
        if ($trimmed -and $seen.Add($trimmed)) { $unique.Add($trimmed) }
    }

    # Returned unrolled. Every caller wraps the call in @(), which re-collects it.
    return $unique.ToArray()
}

function Get-NeighbourPath {
    <#
      The directories that sit beside the given checkouts. They are the names that could be
      confused with a checkout's own, so the matcher needs them to settle which one owns a folder.
    #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]] $CheckoutPath)

    $known = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $CheckoutPath) { [void] $known.Add($path.TrimEnd('\')) }

    $neighbours = [System.Collections.Generic.List[string]]::new()
    $parents = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($path in $CheckoutPath) {
        $parent = Split-Path -Parent $path
        if (-not $parent -or -not $parents.Add($parent)) { continue }

        foreach ($dir in @(Get-ChildItem -LiteralPath $parent -Directory -ErrorAction SilentlyContinue)) {
            $full = $dir.FullName.TrimEnd('\')
            if (-not $known.Contains($full)) { $neighbours.Add($full) }
        }
    }

    return $neighbours.ToArray()
}

function Get-CheckoutClaimLength {
    <#
      How strongly one checkout claims a Claude project folder name: the length of that checkout's
      mangled name when the folder is the checkout or sits inside it, and -1 when it does not.
    #>
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Path
    )

    $mangled = ConvertTo-ClaudeProjectFolder -Path $Path.TrimEnd('\')
    if ($Name.Equals($mangled, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $mangled.Length
    }

    # The separator matters. Without it 'AHKFlowAppOLD' counts as part of 'AHKFlowApp'.
    if ($Name.StartsWith($mangled + '-', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $mangled.Length
    }

    return -1
}

function Get-OwningCheckoutPath {
    <#
      Which checkout a project folder belongs to: the one whose mangled name claims it most
      closely. A worktree inside the main checkout claims its own folder more closely than the
      main checkout does, so the longest claim is the answer and not the first match.

      Returns an empty string when no checkout claims the name.
    #>
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $CheckoutPath
    )

    $best = -1
    $owner = ''
    foreach ($path in $CheckoutPath) {
        $claim = Get-CheckoutClaimLength -Name $Name -Path $path
        if ($claim -gt $best) {
            $best = $claim
            $owner = $path.TrimEnd('\')
        }
    }

    return $owner
}

function Test-WatchTaskFolderName {
    <#
      Decides whether one Claude project folder belongs to this repository.

      The mangling turns a path separator and a literal '-' into the same character, so a folder
      name alone cannot say whether 'AHKFlowApp-tools' is a subdirectory of this repository or a
      different repository sitting beside it. The rule settles that by longest match against real
      directories: a folder belongs to the checkout whose mangled name is the longest one it
      starts with, and it is rejected when some other real directory claims it as closely or
      more closely. Two real directories can mangle to one name, such as 'App.foo' beside
      'App-foo'. An equal claim is that case, and then the name says nothing about which of the
      two owns the folder.

      This is pure so the suite can pin it with names alone.
    #>
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $CheckoutPath,
        [AllowEmptyCollection()][string[]] $NeighbourPath = @()
    )

    $best = -1
    foreach ($path in $CheckoutPath) {
        $claim = Get-CheckoutClaimLength -Name $Name -Path $path
        if ($claim -gt $best) { $best = $claim }
    }

    if ($best -lt 0) {
        return $false
    }

    foreach ($path in $NeighbourPath) {
        if ((Get-CheckoutClaimLength -Name $Name -Path $path) -ge $best) {
            return $false
        }
    }

    return $true
}

function Read-FileEndText {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][int] $Count
    )

    $stream = $null
    try {
        $stream = [System.IO.FileStream]::new(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
    }
    catch {
        return $null
    }

    try {
        $want = [int][Math]::Min([long] $Count, $stream.Length)
        if ($want -le 0) {
            return [pscustomobject]@{ Text = ''; BytesRead = 0 }
        }

        $stream.Position = $stream.Length - $want
        $buffer = [byte[]]::new($want)
        $read = $stream.Read($buffer, 0, $want)
        if ($read -le 0) {
            return [pscustomobject]@{ Text = ''; BytesRead = 0 }
        }

        return [pscustomobject]@{
            Text      = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $read)
            BytesRead = $read
        }
    }
    catch {
        return $null
    }
    finally {
        if ($stream) { $stream.Dispose() }
    }
}

function Get-TaskState {
    param([Parameter(Mandatory)][string] $Path)

    $end = Read-FileEndText -Path $Path -Count $script:TaskStateReadLength
    if ($null -eq $end) {
        return $null
    }

    $lines = @($end.Text -split "`n" | ForEach-Object { $_.TrimEnd("`r") })
    $lastNonEmpty = $null
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($lines[$i].Trim().Length -gt 0) {
            $lastNonEmpty = $lines[$i]
            break
        }
    }

    if ($lastNonEmpty -and $lastNonEmpty -match $script:ExitMarker) {
        return [pscustomobject]@{ Running = $false; ExitCode = [int] $Matches[1]; BytesRead = $end.BytesRead }
    }
    if ($lastNonEmpty -and $lastNonEmpty -match $script:KilledMarker) {
        return [pscustomobject]@{ Running = $false; ExitCode = $null; BytesRead = $end.BytesRead }
    }

    return [pscustomobject]@{ Running = $true; ExitCode = $null; BytesRead = $end.BytesRead }
}

# ERROR_SHARING_VIOLATION as .NET reports it: 0x80070020, which is -2147024864 as an Int32.
$script:SharingViolationHResult = -2147024864

function Test-TaskFileHeldOpen {
    <#
      Whether another handle is holding this file open in a mode that a writer needs. For a task
      output file, the only thing that opens such a handle is the runner writing it, so this is
      "is the task still running".

      The file is opened for reading while write access is denied to everyone else. The open
      fails with a sharing violation whenever some other handle would not share that: a writer,
      or a reader opened with no sharing at all. Nothing but the runner opens these files, so in
      practice the sharing violation is the runner's write handle.

      The exception type is not the test. FileNotFoundException and DirectoryNotFoundException
      both derive from IOException, and a task output file can be deleted between the folder
      listing and this call, so a broad catch would call a file that is gone a running task. Only
      the sharing violation's HResult is treated as running.

      PowerShell wraps a failing .NET constructor in a MethodInvocationException, so the real
      exception is found by walking InnerException.

      For the moment this handle is open it denies write access. A writer that opens the file once
      and keeps it open, which is what the harness does, never notices. The open and the dispose
      are one statement apart to keep that moment as short as it can be.
    #>
    param([Parameter(Mandatory)][string] $Path)

    $stream = $null
    try {
        $stream = [System.IO.FileStream]::new(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read)
        return $false
    }
    catch {
        $failure = $_.Exception
        while ($null -ne $failure -and $failure -isnot [System.IO.IOException]) {
            $failure = $failure.InnerException
        }

        return ($null -ne $failure -and $failure.HResult -eq $script:SharingViolationHResult)
    }
    finally {
        if ($stream) { $stream.Dispose() }
    }
}

function Get-WatchTaskRecord {
    <#
      Returns one record per <session id>\tasks\<task id>.output file under every project folder
      that belongs to this repository, newest first by last write time.

      Running comes from the operating system, not from the file's text: a task is running while
      something holds its output file open for writing. Terminal comes from the text, and the two
      answer different questions. A file with no marker that nobody holds is a task that stopped
      without saying so, which is a state the old rule could not produce.
    #>
    param(
        [Parameter(Mandatory)][string] $SearchRoot,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $CheckoutPath,
        [AllowEmptyCollection()][string[]] $NeighbourPath = @(),
        [AllowEmptyString()][string] $OwnCheckoutPath = ''
    )

    if (-not (Test-Path -LiteralPath $SearchRoot -PathType Container)) {
        return @()
    }

    $projectDirs = @(
        Get-ChildItem -LiteralPath $SearchRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object {
                Test-WatchTaskFolderName -Name $_.Name -CheckoutPath $CheckoutPath -NeighbourPath $NeighbourPath
            }
    )

    $own = $OwnCheckoutPath.TrimEnd('\')

    $outputs = [System.Collections.Generic.List[object]]::new()
    foreach ($dir in $projectDirs) {
        $owner = Get-OwningCheckoutPath -Name $dir.Name -CheckoutPath $CheckoutPath
        $files = @(
            Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Filter '*.output' -ErrorAction SilentlyContinue |
                Where-Object { (Split-Path -Leaf $_.DirectoryName) -eq 'tasks' }
        )
        foreach ($file in $files) {
            $outputs.Add([pscustomobject]@{ File = $file; Checkout = $owner })
        }
    }

    return @(
        $outputs |
            Sort-Object { $_.File.LastWriteTime } -Descending |
            ForEach-Object {
                $file = $_.File
                $owner = $_.Checkout
                # Probe liveness first, then read the state, so the state read is the newer
                # observation. A task that finishes between the two is then read as finished.
                $held = Test-TaskFileHeldOpen -Path $file.FullName
                $state = Get-TaskState -Path $file.FullName

                # The probe ran before the state read, so a replacement run that opened the
                # file in the gap between them is not in $held yet. The state read then finds
                # no terminal marker, and the record would say the task is not running while a
                # writer really holds the file. Select-WatchTaskRecord drops such a record, so
                # the caller could end up following another session. Re-probe once when the
                # two signals disagree, and let the newer observation win. This is the same
                # reconciliation the follow loop does between its liveness probe and its
                # state read.
                if ($null -ne $state -and $state.Running -and -not $held) {
                    $held = Test-TaskFileHeldOpen -Path $file.FullName
                }

                if ($null -ne $state) {
                    $terminal = if ($state.Running) { 'none' }
                                elseif ($null -eq $state.ExitCode) { 'killed' }
                                else { 'exited' }

                    # <project folder>\<session id>\tasks\<task id>.output
                    $sessionDir = $file.Directory.Parent
                    $session = if ($null -eq $sessionDir) { '' } else { $sessionDir.Name }

                    [pscustomobject]@{
                        Path        = $file.FullName
                        LastWrite   = $file.LastWriteTime
                        Running     = $held
                        ExitCode    = $state.ExitCode
                        Terminal    = $terminal
                        Session     = $session
                        Checkout    = $owner
                        OwnCheckout = ($own -ne '' -and $owner.Equals($own, [System.StringComparison]::OrdinalIgnoreCase))
                    }
                }
            }
    )
}

function Select-WatchTaskRecord {
    <#
      Which running task the watcher tails when the caller named no index.

      Three preferences, applied in order, each skipped when it matches no running task, so the
      chain always ends somewhere:

        1. The caller's own session. Claude Code sets CLAUDE_CODE_SESSION_ID for a command it
           runs, and its value is the <session id> folder holding that session's task files. A
           human running the watcher in their own terminal has no such variable, so this is a
           preference and never a filter.
        2. The checkout this copy of the script sits in, read from each record's OwnCheckout
           flag. A checkout holds several sessions, so this signal is weaker than the session
           and comes second. It is skipped when no running task belongs to that checkout.
        3. The newest by last write. $Record arrives newest first, so this is the first survivor.

      Returns $null when nothing is running.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Record,
        [AllowEmptyString()][string] $SessionId = ''
    )

    $candidates = @($Record | Where-Object { $_.Running })
    if ($candidates.Count -eq 0) { return $null }

    if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
        $inSession = @($candidates | Where-Object {
                $_.Session.Equals($SessionId, [System.StringComparison]::OrdinalIgnoreCase)
            })
        if ($inSession.Count -gt 0) { $candidates = $inSession }
    }

    $inCheckout = @($candidates | Where-Object { $_.OwnCheckout })
    if ($inCheckout.Count -gt 0) { $candidates = $inCheckout }

    return $candidates[0]
}

function Format-Age {
    param([Parameter(Mandatory)][datetime] $When)

    $span = (Get-Date) - $When
    if ($span.TotalSeconds -lt 60) { return ('{0}s ago' -f [int] $span.TotalSeconds) }
    if ($span.TotalMinutes -lt 60) { return ('{0}m ago' -f [int] $span.TotalMinutes) }
    if ($span.TotalHours -lt 24) { return ('{0}h ago' -f [int] $span.TotalHours) }
    return ('{0}d ago' -f [int] $span.TotalDays)
}

function New-TailReader {
    <#
      Follows a file by byte offset, not by line count.

      A line count cannot see a runner that writes one line in two pieces: the text that
      completes the line adds no new line to the file, so a watcher comparing line counts skips
      it and the reader never sees it. This reader keeps the byte offset it has consumed and
      holds any text after the last newline in Carry until that line's newline arrives.
    #>
    param(
        [Parameter(Mandatory)][string] $Path,
        [long] $Offset = 0,
        [string] $Carry = ''
    )

    return [pscustomobject]@{
        Path    = $Path
        Offset  = $Offset
        Carry   = $Carry
        Decoder = ([System.Text.UTF8Encoding]::new($false)).GetDecoder()
        LastReadBytes   = 0
        InitialReadBytes = 0
        InitialTruncated = $false
        CarryTruncated = $false
        ReadSucceeded  = $true
        ReadError      = $null
        AtEnd          = $false

        # True when a read gave up part-way and left the rest to the next poll. It returns an
        # empty string to do that, and an empty string also means the end of the file, so a
        # caller that treats the two alike stops reading a file it has not read.
        ReadDeferred   = $false
        FileIdentity   = $null
        CheckpointOffset = 0
        Checkpoint     = $null

        # The start of the file as last seen. A task output file only ever grows, so this text
        # never changes while the reader follows one file. When it does change, the file is a
        # different one and the byte offset means nothing any more.
        Head    = $null
    }
}

# How much of the start of the file the reader remembers, to tell a replacement from an append.
$script:TailHeadLength = 256

function Read-FileHead {
    <#
      The first $Count bytes of an open file, or fewer when the file is shorter.
    #>
    param(
        [Parameter(Mandatory)][System.IO.FileStream] $Stream,
        [Parameter(Mandatory)][int] $Count
    )

    $want = [int][Math]::Min([long] $Count, $Stream.Length)
    if ($want -le 0) {
        # A bare return unrolls a zero-length array to nothing, and the caller is handed $null.
        # The comma wraps it, and the wrapper is what unrolls instead.
        return , [byte[]]::new(0)
    }

    $Stream.Position = 0
    $buffer = [byte[]]::new($want)
    $read = $Stream.Read($buffer, 0, $want)
    if ($read -eq $want) {
        return $buffer
    }

    $exact = [byte[]]::new([Math]::Max(0, $read))
    [System.Array]::Copy($buffer, $exact, $exact.Length)
    return , $exact
}

function Test-SameHead {
    <#
      Whether one file start is still the start of the other. The two can differ in length,
      because the file grows between reads, so only the part they share is compared. Same start,
      same file; a different byte means the file was replaced.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]] $Left,
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]] $Right
    )

    $shared = [Math]::Min($Left.Length, $Right.Length)
    for ($i = 0; $i -lt $shared; $i++) {
        if ($Left[$i] -ne $Right[$i]) { return $false }
    }

    return $true
}

function Test-SameBytes {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]] $Left,
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]] $Right
    )

    if ($Left.Length -ne $Right.Length) { return $false }
    for ($i = 0; $i -lt $Left.Length; $i++) {
        if ($Left[$i] -ne $Right[$i]) { return $false }
    }

    return $true
}

function Read-FileCheckpoint {
    param(
        [Parameter(Mandatory)][System.IO.FileStream] $Stream,
        [Parameter(Mandatory)][long] $EndOffset,
        [Parameter(Mandatory)][int] $Count
    )

    $end = [Math]::Min($EndOffset, $Stream.Length)
    if ($end -le 0) { return , [byte[]]::new(0) }

    $want = [int][Math]::Min([long] $Count, $end)
    $Stream.Position = $end - $want
    $buffer = [byte[]]::new($want)
    $read = $Stream.Read($buffer, 0, $want)
    if ($read -eq $want) { return $buffer }

    $exact = [byte[]]::new([Math]::Max(0, $read))
    [System.Array]::Copy($buffer, $exact, $exact.Length)
    return , $exact
}

function Set-TailReaderCheckpoint {
    <#
      Remembers the last bytes the reader consumed, so the next read can ask whether the file is
      still the one those bytes came from. The bytes come from the read itself and are never read
      back from the file: a re-read describes the file at a later instant, which can already be a
      replacement, and the reader would then compare new bytes against new bytes and see nothing.
    #>
    param(
        [Parameter(Mandatory)][object] $Reader,
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]] $Consumed,
        # How many of $Consumed's bytes the read really returned. It defaults to all of them. Only
        # a caller whose buffer is larger than its read passes a number of its own.
        [int] $Count = $Consumed.Length
    )

    $Reader.CheckpointOffset = $Reader.Offset
    if ($Count -le 0) { return }

    $keptLength = if ($null -eq $Reader.Checkpoint) { 0 } else { $Reader.Checkpoint.Length }
    $keep = [int][Math]::Min($script:TailHeadLength, $keptLength + $Count)
    $tail = [byte[]]::new($keep)

    # Fill from the right. The newest bytes always fit; whatever room is left carries as much of
    # the previous checkpoint as it can hold.
    $fromNew = [int][Math]::Min($Count, $keep)
    [System.Array]::Copy($Consumed, $Count - $fromNew, $tail, $keep - $fromNew, $fromNew)
    $fromOld = $keep - $fromNew
    if ($fromOld -gt 0) {
        [System.Array]::Copy($Reader.Checkpoint, $keptLength - $fromOld, $tail, 0, $fromOld)
    }

    $Reader.Checkpoint = $tail
}

function Read-TailText {
    <#
      Returns the text appended since the last call, and advances the offset. Returns an empty
      string when nothing was added, or when the file cannot be opened this instant.

      The decoder is kept on the reader so a character whose bytes land either side of a read
      boundary is still decoded correctly.
    #>
    param([Parameter(Mandatory)][object] $Reader)

    $Reader.LastReadBytes = 0
    $Reader.ReadSucceeded = $true
    $Reader.ReadError = $null
    $Reader.AtEnd = $false
    $Reader.ReadDeferred = $false

    $stream = $null
    try {
        $stream = [System.IO.FileStream]::new(
            $Reader.Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
    }
    catch {
        $Reader.ReadSucceeded = $false
        $Reader.ReadError = $_.Exception.Message
        return ''
    }

    try {
        # Read first, check second, commit last.
        #
        # The check must never be older than the bytes it approves. Checking first and reading
        # afterwards lets a writer finish in between: the check still sees the old file, the read
        # already returns the new one, and everything the new run wrote before the reader's offset
        # is skipped for good. Reading first makes that impossible, because the check that follows
        # sees any replacement the read could have picked up.
        #
        # A replacement therefore throws away the bytes just read and reads the new file from its
        # start, in this same call. Handing the caller an empty string instead would cost a poll,
        # and a caller that is settling after a finished run has only so many of those.
        $attempt = 0
        while ($true) {
            $attempt++
            $length = $stream.Length

            $available = $length - $Reader.Offset
            $buffer = $null
            $read = 0
            if ($available -gt 0) {
                $stream.Position = $Reader.Offset
                $want = [int][Math]::Min([long] $script:TailReadLength, $available)
                $buffer = [byte[]]::new($want)
                $read = $stream.Read($buffer, 0, $buffer.Length)
                if ($read -lt 0) { $read = 0 }
            }

            # A shorter file was truncated. A file whose start has changed was replaced, and that
            # one can be the same size or longer, so the length alone would say nothing was wrong
            # and the reader would carry on from the old spot, never reading what came before it.
            $head = Read-FileHead -Stream $stream -Count $script:TailHeadLength
            $fileIdentity = [System.IO.File]::GetCreationTimeUtc($Reader.Path).Ticks
            $identityChanged = $null -ne $Reader.FileIdentity -and $Reader.FileIdentity -ne $fileIdentity
            $checkpointChanged = $false
            if ($null -ne $Reader.Checkpoint -and
                $Reader.Checkpoint.Length -gt 0 -and
                $length -ge $Reader.CheckpointOffset) {
                # Ask for exactly as many bytes as the checkpoint holds. A different count would
                # compare two lengths and report every short checkpoint as a replacement.
                $currentCheckpoint = Read-FileCheckpoint `
                    -Stream $stream `
                    -EndOffset $Reader.CheckpointOffset `
                    -Count $Reader.Checkpoint.Length
                $checkpointChanged = -not (Test-SameBytes -Left $Reader.Checkpoint -Right $currentCheckpoint)
            }

            $replaced = ($length -lt $Reader.Offset) -or
                        $identityChanged -or
                        $checkpointChanged -or
                        ($null -ne $Reader.Head -and -not (Test-SameHead -Left $Reader.Head -Right $head))

            $Reader.FileIdentity = $fileIdentity

            if (-not $replaced) { break }

            # Whatever the read returned belongs to a file this reader is no longer following.
            # Nothing was committed, so there is nothing to unwind: drop the bytes and go back to
            # the start of the new file.
            $Reader.Offset = 0
            $Reader.Carry = ''
            $Reader.CarryTruncated = $false
            $Reader.Decoder.Reset()
            $Reader.CheckpointOffset = 0
            $Reader.Checkpoint = $null

            # The head that was just read came from the file this reader is dropping, which is not
            # always the file at the path any more. Keeping it would make the next pass compare a
            # new file against an old start and call that a replacement too. Forget it instead:
            # the pass below reads the head of whatever file it ends up following, and adopts it.
            $Reader.Head = $null

            # A file replaced again while this call was reading it. Leave the reader at the start
            # and let the next poll try, rather than spin here against a writer. The caller is
            # told, because an empty string on its own would read as the end of the file.
            if ($attempt -ge $script:MaxReplacementRetries) {
                $Reader.ReadDeferred = $true
                return ''
            }

            # A run that replaces the path, rather than overwriting the file, leaves this handle
            # on the old file object. The checks above look at the path and see the new file, so
            # the two disagree, and a retry through this handle would read the old output a second
            # time. Open the path again so the retry reads the file the checks just saw.
            $stream.Dispose()
            $stream = $null
            $stream = [System.IO.FileStream]::new(
                $Reader.Path,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
        }

        if ($null -eq $Reader.Head -or $head.Length -gt $Reader.Head.Length) {
            # Keep the longest start seen so far. A file that was still short on the first read
            # gives little to compare against, and it grows as the run writes more.
            $Reader.Head = $head
        }

        if ($read -le 0) {
            $Reader.AtEnd = $true
            return ''
        }

        $Reader.Offset += $read
        $Reader.LastReadBytes = $read
        $Reader.AtEnd = $Reader.Offset -ge $length
        Set-TailReaderCheckpoint -Reader $Reader -Consumed $buffer -Count $read

        $chars = [char[]]::new($Reader.Decoder.GetCharCount($buffer, 0, $read, $false))
        $written = $Reader.Decoder.GetChars($buffer, 0, $read, $chars, 0, $false)
        if ($written -le 0) {
            return ''
        }

        return ([string]::new($chars, 0, $written))
    }
    catch {
        $Reader.ReadSucceeded = $false
        $Reader.ReadError = $_.Exception.Message
        $Reader.AtEnd = $false
        return ''
    }
    finally {
        if ($stream) { $stream.Dispose() }
    }
}

function Read-InitialTailText {
    <#
      Reads backwards in fixed-size blocks until it has enough line breaks for the initial tail.
      The reader is left at the file end so follow mode continues without a gap or repeat.
    #>
    param(
        [Parameter(Mandatory)][object] $Reader,
        [Parameter(Mandatory)][int] $LineCount
    )

    $Reader.InitialReadBytes = 0
    $Reader.InitialTruncated = $false
    $Reader.ReadSucceeded = $true
    $Reader.ReadError = $null
    $Reader.AtEnd = $false
    $Reader.ReadDeferred = $false

    $stream = $null
    try {
        $stream = [System.IO.FileStream]::new(
            $Reader.Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
    }
    catch {
        $Reader.ReadSucceeded = $false
        $Reader.ReadError = $_.Exception.Message
        return ''
    }

    try {
        $end = $stream.Length
        $position = $end
        $newlines = 0
        $chunks = [System.Collections.Generic.List[byte[]]]::new()
        $total = 0

        # How many bytes the scan has read that belong to the line it is still inside. The byte
        # bound applies to one line, not to the whole read, so a tail of large complete lines
        # still returns every line the caller asked for.
        $sinceNewline = 0

        # One extra newline lets us discard a partial first line when the read starts mid-file.
        $wantedNewlines = $LineCount + 1
        while ($position -gt 0 -and
               $newlines -lt $wantedNewlines -and
               $sinceNewline -lt $script:MaxTailTextBytes) {
            # The read is bounded by what is left of this line's allowance as well as by the
            # block size. Checking the allowance only before a fixed-size block let a line that
            # stopped one byte short of the bound pull in another whole block, so the scan read
            # more than the 1 MiB it says it read.
            $allowance = [long] $script:MaxTailTextBytes - [long] $sinceNewline
            $want = [int][Math]::Min([Math]::Min([long] $script:TailReadLength, [long] $position), $allowance)
            $position -= $want
            $stream.Position = $position

            $chunk = [byte[]]::new($want)
            $read = $stream.Read($chunk, 0, $want)
            if ($read -le 0) { break }

            if ($read -lt $want) {
                $exact = [byte[]]::new($read)
                [System.Array]::Copy($chunk, $exact, $read)
                $chunk = $exact
            }

            $chunks.Add($chunk)
            $total += $read

            # The bytes before the earliest newline in this chunk continue the line that newline
            # ends, so they are what the next round keeps counting.
            $firstBreak = -1
            for ($i = 0; $i -lt $chunk.Length; $i++) {
                if ($chunk[$i] -eq 10) {
                    $newlines++
                    if ($firstBreak -lt 0) { $firstBreak = $i }
                }
            }

            if ($firstBreak -ge 0) { $sinceNewline = $firstBreak }
            else { $sinceNewline += $chunk.Length }
        }

        # The scan stopped part-way through one line that is longer than the bound allows.
        $lineCapReached = $position -gt 0 -and
                          $newlines -lt $wantedNewlines -and
                          $sinceNewline -ge $script:MaxTailTextBytes

        $Reader.Offset = $end
        $Reader.Head = Read-FileHead -Stream $stream -Count $script:TailHeadLength
        $Reader.InitialReadBytes = $total
        $Reader.InitialTruncated = $lineCapReached
        $Reader.AtEnd = $true
        $Reader.FileIdentity = [System.IO.File]::GetCreationTimeUtc($Reader.Path).Ticks
        $consumed = if ($chunks.Count -gt 0) { $chunks[0] } else { , [byte[]]::new(0) }
        Set-TailReaderCheckpoint -Reader $Reader -Consumed $consumed

        if ($total -le 0) {
            return ''
        }

        $buffer = [byte[]]::new($total)
        $destination = 0
        for ($i = $chunks.Count - 1; $i -ge 0; $i--) {
            $chunk = $chunks[$i]
            [System.Array]::Copy($chunk, 0, $buffer, $destination, $chunk.Length)
            $destination += $chunk.Length
        }

        # A read that started mid-file can start inside one UTF-8 character, and the decoder
        # turns those orphan bytes into a replacement character. Skipping them costs at most
        # the three continuation bytes of the character whose start is not in this read.
        $from = 0
        if ($position -gt 0) {
            while ($from -lt $buffer.Length -and ($buffer[$from] -band 0xC0) -eq 0x80) {
                $from++
            }
        }

        $count = $buffer.Length - $from
        $chars = [char[]]::new($Reader.Decoder.GetCharCount($buffer, $from, $count, $false))
        $written = $Reader.Decoder.GetChars($buffer, $from, $count, $chars, 0, $false)
        $text = if ($written -gt 0) { [string]::new($chars, 0, $written) } else { '' }

        # A read that started mid-file opens with the tail of a line whose start is not here, so
        # that fragment is dropped. The one exception is the over-long line the bound stopped on.
        # It is all that is left to show, and the caller says so.
        if ($position -gt 0 -and -not $lineCapReached) {
            $lineStart = $text.IndexOf("`n")
            if ($lineStart -ge 0) {
                $text = $text.Substring($lineStart + 1)
            }
        }

        return $text
    }
    catch {
        $Reader.ReadSucceeded = $false
        $Reader.ReadError = $_.Exception.Message
        $Reader.AtEnd = $false
        return ''
    }
    finally {
        if ($stream) { $stream.Dispose() }
    }
}

function Split-TailLine {
    <#
      Adds $Text to the reader's carry and returns every complete line it now holds. Text after
      the last newline stays in the carry, so a line written in two pieces is returned once, in
      full, when its newline arrives.
    #>
    param(
        [Parameter(Mandatory)][object] $Reader,
        [Parameter(Mandatory)][AllowEmptyString()][string] $Text
    )

    $Reader.Carry += $Text

    $lines = [System.Collections.Generic.List[string]]::new()
    while ($true) {
        $break = $Reader.Carry.IndexOf("`n")
        if ($break -lt 0) { break }

        $lines.Add($Reader.Carry.Substring(0, $break).TrimEnd("`r"))
        $Reader.Carry = $Reader.Carry.Substring($break + 1)
        $Reader.CarryTruncated = $false
    }

    $carryBytes = [System.Text.Encoding]::UTF8.GetBytes($Reader.Carry)
    if ($carryBytes.Length -gt $script:MaxTailTextBytes) {
        $start = $carryBytes.Length - $script:MaxTailTextBytes
        while ($start -lt $carryBytes.Length -and ($carryBytes[$start] -band 0xC0) -eq 0x80) {
            $start++
        }

        $Reader.Carry = [System.Text.Encoding]::UTF8.GetString(
            $carryBytes,
            $start,
            $carryBytes.Length - $start)
        if (-not $Reader.CarryTruncated) {
            $lines.Add('Unfinished line truncated: showing its last 1 MiB.')
            $Reader.CarryTruncated = $true
        }
    }

    # Returned unrolled. Every caller wraps the call in @(), which re-collects it.
    return $lines.ToArray()
}

function Show-Tail {
    <#
      Prints the last $Count lines and returns a reader positioned at the end of what it printed,
      so a follower carries on from there with no gap and no repeat.

      With -KeepPartial the text after the last newline is not printed and stays in the reader's
      carry, because that line is not finished yet and the follower will print it in full.
      Without it, that text is printed, which is what a finished task needs.
    #>
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][int] $Count,
        [switch] $KeepPartial
    )

    $reader = New-TailReader -Path $Path
    $text = Read-InitialTailText -Reader $reader -LineCount $Count
    if (-not $reader.ReadSucceeded) {
        throw "Task output could no longer be read: $Path. $($reader.ReadError)"
    }
    if ($reader.InitialTruncated) {
        Write-Host 'Initial tail truncated: one line is longer than 1 MiB. Showing its last 1 MiB and nothing before it.'
        $reader.CarryTruncated = $true
    }
    $lines = @(Split-TailLine -Reader $reader -Text $text)

    # The unfinished last line is printed when the task is over, and it is one of the lines the
    # caller asked for. It takes a slot rather than arriving as an extra on top of them.
    $printPartial = (-not $KeepPartial) -and $reader.Carry.Length -gt 0
    $wantedLines = if ($printPartial) { $Count - 1 } else { $Count }

    $start = [Math]::Max(0, $lines.Count - $wantedLines)
    for ($i = $start; $i -lt $lines.Count; $i++) {
        Write-Host $lines[$i]
    }

    $printedPartial = ''
    if ($printPartial) {
        $printedPartial = $reader.Carry
        Write-Host $reader.Carry
        $reader.Carry = ''
    }

    # Whether the text just consumed already ends the task. The caller needs this because it
    # decided the task was running before this function read anything, and the marker it would
    # otherwise wait for has now been read and printed here.
    #
    # The last text printed is the unfinished tail when there is one, not the last complete line.
    # A task killed mid-write leaves the marker with no newline after it, and reading only
    # complete lines missed that and called the task still running.
    $lastText = $null
    if ($printedPartial.Trim().Length -gt 0) {
        $lastText = $printedPartial
    }
    else {
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            if ($lines[$i].Trim().Length -eq 0) { continue }
            $lastText = $lines[$i]
            break
        }
    }

    $exitCode = $null
    $killed = $false
    if ($null -ne $lastText -and $lastText -match $script:ExitMarker) {
        $exitCode = [int] $Matches[1]
    }
    elseif ($null -ne $lastText -and $lastText -match $script:KilledMarker) {
        $killed = $true
    }

    return [pscustomobject]@{
        Reader   = $reader
        ExitCode = $exitCode
        Killed   = $killed
    }
}

function Watch-Record {
    param(
        [Parameter(Mandatory)][object] $Record,
        [Parameter(Mandatory)][int] $Tail,

        # Where the task came from, when the caller knows. A caller that passes nothing gets the
        # path alone, which is what a case driving one file directly wants.
        [AllowEmptyString()][string] $Session = '',
        [AllowEmptyString()][string] $Checkout = '',
        [AllowEmptyString()][string] $OwnSessionId = '',

        [switch] $NoFollow
    )

    Write-Host "Tailing $($Record.Path)"
    if ($Session -ne '') {
        $mine = if ($Session.Equals($OwnSessionId, [System.StringComparison]::OrdinalIgnoreCase)) { ' (this session)' } else { '' }
        Write-Host "Session: $Session$mine"
    }
    if ($Checkout -ne '') {
        Write-Host "Checkout: $Checkout"
    }
    Write-Host ''

    $following = $Record.Running -and -not $NoFollow

    # Not named $tail. Variable names ignore case here, so that would overwrite the $Tail
    # parameter, which is typed [int], and the assignment would throw.
    try {
        $initial = Show-Tail -Path $Record.Path -Count $Tail -KeepPartial:$following
    }
    catch {
        Write-Host $_.Exception.Message
        return 1
    }
    $reader = $initial.Reader

    if (-not $Record.Running) {
        Write-Host ''
        if ($Record.Terminal -eq 'exited') {
            Write-Host "This task has already finished. Exit code: $($Record.ExitCode)"
        }
        elseif ($Record.Terminal -eq 'killed') {
            Write-Host 'This task has already stopped. State: killed'
        }
        else {
            Write-Host 'This task has already stopped. State: stopped without a terminal marker'
        }
        return 0
    }

    # The scan read the running flag before the tail above ran. A task that finished in between
    # leaves that flag stale, and the marker has already been printed and consumed here, so the
    # follow loop would wait for a line that can never arrive.
    if ($null -ne $initial.ExitCode) {
        Write-Host ''
        Write-Host "Exit code: $($initial.ExitCode)"
        return 0
    }
    if ($initial.Killed) {
        Write-Host ''
        Write-Host 'State: killed'
        return 0
    }

    if ($NoFollow) {
        Write-Host ''
        Write-Host 'This task is still running. Run the command again to see more.'
        return 0
    }

    $tailReadFailures = 0
    $stateReadFailures = 0
    $settleReadFailures = 0
    $catchUpReadFailures = 0
    $settleDeferrals = 0
    while ($true) {
        $text = Read-TailText -Reader $reader
        if (-not $reader.ReadSucceeded) {
            $tailReadFailures++
            if ($tailReadFailures -ge $script:MaxTailReadFailures) {
                Write-Host ''
                Write-Host "Task output could no longer be read after $tailReadFailures attempts: $($reader.Path)"
                return 1
            }

            Start-Sleep -Milliseconds 500
            continue
        }
        $tailReadFailures = 0

        foreach ($line in @(Split-TailLine -Reader $reader -Text $text)) {
            Write-Host $line
        }

        if ($reader.AtEnd) {
            # The marker rule cannot see a writer that stopped without writing one, and the loop
            # would then poll a dead file for ever. Liveness answers the other half. Probe it
            # before the state read, so the state read is the newer observation and a marker
            # written between the two is on the side that wins.
            $held = Test-TaskFileHeldOpen -Path $reader.Path
            $state = Get-TaskState -Path $reader.Path
            if ($null -eq $state) {
                $stateReadFailures++
                if ($stateReadFailures -ge $script:MaxTailReadFailures) {
                    Write-Host ''
                    Write-Host "Task output could no longer be read after $stateReadFailures attempts: $($reader.Path)"
                    return 1
                }
            }
            else {
                $stateReadFailures = 0
            }

            if ($null -ne $state -and (-not $state.Running -or -not $held)) {
                # The state above was read after the tail read returned, so the run can have
                # written its last lines in between. Read to the file's end, then ask the file
                # for its state again.
                #
                # A new run can replace the file between those two steps, and the replacement
                # then decides the verdict while none of it has been read. So repeat the pair
                # until a whole round reads nothing. Only then do the lines printed above and
                # the state reported below belong to the same file.
                $caughtUp = 0
                $settled = $null
                $settledHeld = $false
                $settleRounds = 0
                $catchUpFailed = $false

                # Consecutive rounds that read nothing and found no marker and no writer. The
                # marker rule and liveness are read one after the other, so a marker written in
                # the gap between them is missed by that round; a later round's read catches it.
                # Only after three such rounds in a row is the file really stopped without a
                # marker. Bounded above by MaxSettleRounds as well.
                $confirmRounds = 0
                do {
                    $settleRounds++
                    $roundBytes = 0
                    do {
                        $more = Read-TailText -Reader $reader
                        if (-not $reader.ReadSucceeded) {
                            $catchUpFailed = $true
                            break
                        }
                        if ($more.Length -eq 0) { break }

                        foreach ($line in @(Split-TailLine -Reader $reader -Text $more)) {
                            Write-Host $line
                        }
                        $roundBytes += $more.Length
                    } while (-not $reader.AtEnd)
                    $caughtUp += $roundBytes

                    if ($catchUpFailed) { break }
                    # Probe liveness first, then read the state. The state read is then the newer
                    # observation, so a marker written between the two is on the side that wins.
                    $settledHeld = Test-TaskFileHeldOpen -Path $reader.Path
                    $settled = Get-TaskState -Path $reader.Path

                    if (-not $settledHeld -and $null -ne $settled -and $settled.Running -and $roundBytes -eq 0) {
                        $confirmRounds++
                    }
                    else {
                        $confirmRounds = 0
                    }
                    # A deferred read returns nothing, but the file still has everything the new
                    # run wrote. Settling on it would print the verdict over output that never
                    # reached the screen, so it counts as a round that read something.
                } while ($settleRounds -lt $script:MaxSettleRounds -and
                         $null -ne $settled -and
                         (-not $settled.Running -or -not $settledHeld) -and
                         ($roundBytes -gt 0 -or
                          $reader.ReadDeferred -or
                          (-not $settledHeld -and $settled.Running -and $confirmRounds -lt 3)))

                # A catch-up read that failed is not the same as a file with nothing left to
                # read. Its lines are still on disk, unread. Taking the state now would print
                # the verdict over output that never reached the screen, so the whole pass is
                # retried instead, under a failure count of its own.
                if ($catchUpFailed) {
                    $catchUpReadFailures++
                    if ($catchUpReadFailures -ge $script:MaxTailReadFailures) {
                        Write-Host ''
                        Write-Host "Task output could no longer be read after $catchUpReadFailures attempts: $($reader.Path)"
                        return 1
                    }

                    Start-Sleep -Milliseconds 500
                    continue
                }
                $catchUpReadFailures = 0

                # This read keeps its own failure count. The count above resets on every read
                # that works, so it can never bound a file that reads there and fails here.
                if ($null -eq $settled) {
                    $settleReadFailures++
                    if ($settleReadFailures -ge $script:MaxTailReadFailures) {
                        Write-Host ''
                        Write-Host "Task output could no longer be read after $settleReadFailures attempts: $($reader.Path)"
                        return 1
                    }

                    Start-Sleep -Milliseconds 500
                    continue
                }
                $settleReadFailures = 0

                # The loop above also ends when it runs out of rounds, and that can happen with a
                # read still deferred. It means the file was replaced faster than the reader could
                # follow it, so the last run's output is still on disk and unread. Reporting the
                # state here would print a verdict over output nobody saw, which is the whole
                # defect this item exists to fix, so the pass starts again under a count of its
                # own. A file that keeps doing this is one the reader cannot keep up with, and
                # saying so beats a silent wrong answer.
                if ($reader.ReadDeferred) {
                    $settleDeferrals++
                    if ($settleDeferrals -ge $script:MaxTailReadFailures) {
                        Write-Host ''
                        Write-Host "Task output was replaced faster than it could be read, $settleDeferrals times running: $($reader.Path)"
                        return 1
                    }

                    Start-Sleep -Milliseconds 500
                    continue
                }
                $settleDeferrals = 0

                # A run that is still going keeps the watch going. This covers a replacement that
                # opened during a probe: the round after it opens sees the new writer, so
                # $settledHeld is true here. The carry stays in the reader, because its last line
                # is not finished yet.
                if ($settled.Running -and $settledHeld) {
                    continue
                }
                $state = $settled

                if ($reader.Carry.Trim().Length -gt 0) {
                    Write-Host $reader.Carry
                    $reader.Carry = ''
                }

                # No text at all from the reader, but a terminal file end, means its byte offset
                # went stale. Show the real end so the caller is not left with a silent gap. A run
                # that stopped without a marker is not that: nothing was missed, the run simply
                # ended without saying how.
                if ($text.Length -eq 0 -and $caughtUp -eq 0 -and -not $state.Running) {
                    Write-Host ''
                    Write-Host 'The file changed while it was being followed, so some of its output is not above.'
                    Write-Host 'Its last lines:'
                    Write-Host ''
                    try {
                        Show-Tail -Path $reader.Path -Count $Tail | Out-Null
                    }
                    catch {
                        Write-Host $_.Exception.Message
                        return 1
                    }
                }

                Write-Host ''
                if ($null -ne $state.ExitCode) {
                    Write-Host "Exit code: $($state.ExitCode)"
                }
                elseif (-not $state.Running) {
                    Write-Host 'State: killed'
                }
                else {
                    # No marker and no writer. The run ended without saying how.
                    Write-Host 'State: stopped without a terminal marker'
                }
                return 0
            }
        }

        if ($text.Length -eq 0) {
            Start-Sleep -Milliseconds 500
        }
    }
}

function Invoke-WatchTask {
    param(
        [switch] $List,

        # 0 means no index was asked for. The script parameter's range keeps a caller from
        # reaching this with 0 or a negative of their own.
        [ValidateRange(0, [int]::MaxValue)]
        [int] $Index,

        [ValidateRange(1, [int]::MaxValue)]
        [int] $Tail = 40,

        [string] $Root,
        [switch] $NoFollow
    )

    $searchRoot = if ([string]::IsNullOrWhiteSpace($Root)) {
        Join-Path $env:LOCALAPPDATA 'Temp\claude'
    }
    else {
        $Root
    }

    # The checkout this copy of the script sits in, which is not the main root when the script is
    # run from a worktree. AGENTS.md tells an agent to hand over the watcher path in the checkout
    # the run belongs to, and this is what makes that instruction mean something.
    $ownCheckout = Split-Path -Parent $PSScriptRoot

    $mainRoot = Get-RepositoryMainRoot -ScriptRoot $PSScriptRoot
    $checkouts = @(Get-RepositoryCheckoutPath -MainRoot $mainRoot)
    $neighbours = @(Get-NeighbourPath -CheckoutPath $checkouts)

    $records = @(Get-WatchTaskRecord `
        -SearchRoot $searchRoot `
        -CheckoutPath $checkouts `
        -NeighbourPath $neighbours `
        -OwnCheckoutPath $ownCheckout)

    # Absent in a plain terminal, in which case it is simply skipped.
    $sessionId = if ($null -eq $env:CLAUDE_CODE_SESSION_ID) { '' } else { $env:CLAUDE_CODE_SESSION_ID }

    if ($records.Count -eq 0) {
        Write-Host "No task output files found for this repository under $searchRoot"
        Write-Host "Looked under $($checkouts.Count) checkout(s), starting at: $mainRoot"
        return 1
    }

    $running = @($records | Where-Object { $_.Running })
    $stopped = @($records | Where-Object { -not $_.Running })
    $fill = [Math]::Max(0, $script:ListRowCount - $running.Count)
    $recent = @($running) + @($stopped | Select-Object -First $fill)

    if ($List) {
        $rowIndex = 0
        $rows = foreach ($record in $recent) {
            $rowIndex++
            [pscustomobject]@{
                Index = $rowIndex
                State = if ($record.Running) {
                    'running'
                }
                elseif ($record.Terminal -eq 'exited') {
                    "exited $($record.ExitCode)"
                }
                elseif ($record.Terminal -eq 'killed') {
                    'killed'
                }
                else {
                    'stopped (no marker)'
                }
                Age   = Format-Age -When $record.LastWrite
                Path  = $record.Path
            }
        }
        $rows | Format-Table -AutoSize -Wrap | Out-String | Write-Host
        return 0
    }

    if ($Index -gt 0) {
        if ($Index -gt $recent.Count) {
            Write-Host "No task at index $Index. There are $($recent.Count) recent tasks. Run -List to see them."
            return 1
        }

        $picked = $recent[$Index - 1]
        return (Watch-Record `
            -Record $picked `
            -Tail $Tail `
            -Session $picked.Session `
            -Checkout $picked.Checkout `
            -OwnSessionId $sessionId `
            -NoFollow:$NoFollow)
    }

    $chosen = Select-WatchTaskRecord -Record $records -SessionId $sessionId

    if ($null -eq $chosen) {
        # The no-running-task path, moved off $running.Count and on to the selection result.
        $newest = $records[0]
        Write-Host 'No task is running now. Showing the newest stopped task.'
        Write-Host ''
        try {
            Show-Tail -Path $newest.Path -Count $Tail | Out-Null
        }
        catch {
            Write-Host $_.Exception.Message
            return 1
        }
        Write-Host ''
        Write-Host "Path: $($newest.Path)"
        if ($newest.Terminal -eq 'exited') {
            Write-Host "Exit code: $($newest.ExitCode)"
        }
        elseif ($newest.Terminal -eq 'killed') {
            Write-Host 'State: killed'
        }
        else {
            Write-Host 'State: stopped without a terminal marker'
        }
        return 0
    }

    if ($running.Count -gt 1) {
        $others = $running.Count - 1
        $noun = if ($others -eq 1) { 'task is' } else { 'tasks are' }
        Write-Host "$others other $noun also running. Use -List to see them and -Index to pick one."
        Write-Host ''
    }

    return (Watch-Record `
        -Record $chosen `
        -Tail $Tail `
        -Session $chosen.Session `
        -Checkout $chosen.Checkout `
        -OwnSessionId $sessionId `
        -NoFollow:$NoFollow)
}

# Dot-sourced by the test suite to reach the functions above without running anything.
if ($MyInvocation.InvocationName -ne '.') {
    $code = Invoke-WatchTask -List:$List -Index $Index -Tail $Tail -Root $Root -NoFollow:$NoFollow
    exit $code
}
