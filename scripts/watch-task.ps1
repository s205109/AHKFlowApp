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
    2. Among <match>\<session id>\tasks\<task id>.output, a file is running when its content
       does not end with '[exited with code N]' or '[killed]'. This needs no state of its own.
    3. It picks the newest running file by last write time and tails it, following by byte
       offset so a line written in two pieces is printed once, in full. The tail stops on its
       own when a terminal marker is the last line, and prints the exit code or killed state last.

  With no running task it prints the newest stopped task's last lines, terminal state, and path,
  then exits 0. With more than one running it tails the newest and names the count.

.PARAMETER List
  Print the recent tasks with their state, age, and index, then exit.
.PARAMETER Index
  Select one task from the same list -List prints (1-based) instead of the newest running one.
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

    # 1-based, matching the numbers -List prints. Left at 0 it means "pick the newest running
    # task". The range stops 0 and a negative from reading as that default and quietly ignoring
    # what the caller asked for.
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

    # Returns the length of the mangled path when $Name is that path or sits inside it, else -1.
    function Get-ClaimLength {
        param([string] $Path)

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

    $best = -1
    foreach ($path in $CheckoutPath) {
        $claim = Get-ClaimLength -Path $path
        if ($claim -gt $best) { $best = $claim }
    }

    if ($best -lt 0) {
        return $false
    }

    foreach ($path in $NeighbourPath) {
        if ((Get-ClaimLength -Path $path) -ge $best) {
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

function Get-WatchTaskRecord {
    <#
      Returns one record per <session id>\tasks\*.output file under every project folder that
      belongs to this repository, newest first by last write time.
    #>
    param(
        [Parameter(Mandatory)][string] $SearchRoot,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $CheckoutPath,
        [AllowEmptyCollection()][string[]] $NeighbourPath = @()
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

    $outputs = [System.Collections.Generic.List[object]]::new()
    foreach ($dir in $projectDirs) {
        $files = @(
            Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Filter '*.output' -ErrorAction SilentlyContinue |
                Where-Object { (Split-Path -Leaf $_.DirectoryName) -eq 'tasks' }
        )
        foreach ($file in $files) { $outputs.Add($file) }
    }

    return @(
        $outputs |
            Sort-Object LastWriteTime -Descending |
            ForEach-Object {
                $state = Get-TaskState -Path $_.FullName
                if ($null -ne $state) {
                    [pscustomobject]@{
                        Path      = $_.FullName
                        LastWrite = $_.LastWriteTime
                        Running   = $state.Running
                        ExitCode  = $state.ExitCode
                    }
                }
            }
    )
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
        return [byte[]]::new(0)
    }

    $Stream.Position = 0
    $buffer = [byte[]]::new($want)
    $read = $Stream.Read($buffer, 0, $want)
    if ($read -eq $want) {
        return $buffer
    }

    $exact = [byte[]]::new([Math]::Max(0, $read))
    [System.Array]::Copy($buffer, $exact, $exact.Length)
    return $exact
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
    if ($end -le 0) { return [byte[]]::new(0) }

    $want = [int][Math]::Min([long] $Count, $end)
    $Stream.Position = $end - $want
    $buffer = [byte[]]::new($want)
    $read = $Stream.Read($buffer, 0, $want)
    if ($read -eq $want) { return $buffer }

    $exact = [byte[]]::new([Math]::Max(0, $read))
    [System.Array]::Copy($buffer, $exact, $exact.Length)
    return $exact
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
        [Parameter(Mandatory)][int] $Count
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
            $Reader.Head = $head
            $Reader.CheckpointOffset = 0
            $Reader.Checkpoint = $null
            $Reader.AtEnd = $false

            # A file replaced again while this call was reading it. Leave the reader at the start
            # and let the next poll try, rather than spin here against a writer.
            if ($attempt -ge $script:MaxReplacementRetries) {
                return ''
            }
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
        Set-TailReaderCheckpoint `
            -Reader $Reader `
            -Consumed $(if ($chunks.Count -gt 0) { $chunks[0] } else { [byte[]]::new(0) }) `
            -Count $(if ($chunks.Count -gt 0) { $chunks[0].Length } else { 0 })

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
        [switch] $NoFollow
    )

    Write-Host "Tailing $($Record.Path)"
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
        if ($null -eq $Record.ExitCode) {
            Write-Host 'This task has already stopped. State: killed'
        }
        else {
            Write-Host "This task has already finished. Exit code: $($Record.ExitCode)"
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

            if ($null -ne $state -and -not $state.Running) {
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
                $settleRounds = 0
                $catchUpFailed = $false
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
                    $settled = Get-TaskState -Path $reader.Path
                } while ($roundBytes -gt 0 -and
                         $null -ne $settled -and
                         -not $settled.Running -and
                         $settleRounds -lt $script:MaxSettleRounds)

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

                # A replacement that is still running keeps the watch going. The carry stays in
                # the reader, because its last line is not finished yet.
                if ($settled.Running) {
                    continue
                }
                $state = $settled

                if ($reader.Carry.Trim().Length -gt 0) {
                    Write-Host $reader.Carry
                    $reader.Carry = ''
                }

                # No text at all from the reader, but a terminal file end, means its byte offset
                # went stale. Show the real end so the caller is not left with a silent gap.
                if ($text.Length -eq 0 -and $caughtUp -eq 0) {
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
                if ($null -eq $state.ExitCode) {
                    Write-Host 'State: killed'
                }
                else {
                    Write-Host "Exit code: $($state.ExitCode)"
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

    $mainRoot = Get-RepositoryMainRoot -ScriptRoot $PSScriptRoot
    $checkouts = @(Get-RepositoryCheckoutPath -MainRoot $mainRoot)
    $neighbours = @(Get-NeighbourPath -CheckoutPath $checkouts)

    $records = @(Get-WatchTaskRecord -SearchRoot $searchRoot -CheckoutPath $checkouts -NeighbourPath $neighbours)

    if ($records.Count -eq 0) {
        Write-Host "No task output files found for this repository under $searchRoot"
        Write-Host "Looked under $($checkouts.Count) checkout(s), starting at: $mainRoot"
        return 1
    }

    $recent = @($records | Select-Object -First 20)

    if ($List) {
        $rowIndex = 0
        $rows = foreach ($record in $recent) {
            $rowIndex++
            [pscustomobject]@{
                Index = $rowIndex
                State = if ($record.Running) {
                    'running'
                }
                elseif ($null -eq $record.ExitCode) {
                    'killed'
                }
                else {
                    "exited $($record.ExitCode)"
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
        return (Watch-Record -Record $recent[$Index - 1] -Tail $Tail -NoFollow:$NoFollow)
    }

    $running = @($records | Where-Object { $_.Running })

    if ($running.Count -eq 0) {
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
        if ($null -eq $newest.ExitCode) {
            Write-Host 'State: killed'
        }
        else {
            Write-Host "Exit code: $($newest.ExitCode)"
        }
        return 0
    }

    if ($running.Count -gt 1) {
        $others = $running.Count - 1
        $noun = if ($others -eq 1) { 'task is' } else { 'tasks are' }
        Write-Host "$others other $noun also running. Use -List to see them and -Index to pick one."
        Write-Host ''
    }

    return (Watch-Record -Record $running[0] -Tail $Tail -NoFollow:$NoFollow)
}

# Dot-sourced by the test suite to reach the functions above without running anything.
if ($MyInvocation.InvocationName -ne '.') {
    $code = Invoke-WatchTask -List:$List -Index $Index -Tail $Tail -Root $Root -NoFollow:$NoFollow
    exit $code
}
