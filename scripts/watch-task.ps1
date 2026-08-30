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
    1. It mangles this repository's main checkout root into the folder name Claude Code uses,
       then globs that name followed by '*'. The trailing '*' picks up the repository's
       worktrees, because a worktree's folder name is the main name with its own path appended.
    2. Among <match>\<session id>\tasks\<task id>.output, a file is running when its content
       does not end with a '[exited with code N]' line. This needs no state of its own.
    3. It picks the newest running file by last write time and tails it. The tail stops on its
       own when '[exited with code N]' appears, and prints the exit code last.

  With no running task it prints the newest finished task's last lines, its exit code, and its
  path, then exits 0. With more than one running it tails the newest and names the count.

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
        $lines = @(& git -C $MainRoot worktree list --porcelain 2>$null)
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
      starts with, and it is rejected when some other real directory claims it more closely.

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
        if ((Get-ClaimLength -Path $path) -gt $best) {
            return $false
        }
    }

    return $true
}

function Get-TaskState {
    param([Parameter(Mandatory)][string] $Path)

    $lines = @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)
    $lastNonEmpty = $null
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($lines[$i].Trim().Length -gt 0) {
            $lastNonEmpty = $lines[$i]
            break
        }
    }

    if ($lastNonEmpty -and $lastNonEmpty -match $script:ExitMarker) {
        return [pscustomobject]@{ Running = $false; ExitCode = [int] $Matches[1] }
    }

    return [pscustomobject]@{ Running = $true; ExitCode = $null }
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
                [pscustomobject]@{
                    Path      = $_.FullName
                    LastWrite = $_.LastWriteTime
                    Running   = $state.Running
                    ExitCode  = $state.ExitCode
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
    }
}

function Read-TailText {
    <#
      Returns the text appended since the last call, and advances the offset. Returns an empty
      string when nothing was added, or when the file cannot be opened this instant.

      The decoder is kept on the reader so a character whose bytes land either side of a read
      boundary is still decoded correctly.
    #>
    param([Parameter(Mandatory)][object] $Reader)

    $stream = $null
    try {
        $stream = [System.IO.FileStream]::new(
            $Reader.Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
    }
    catch {
        return ''
    }

    try {
        if ($stream.Length -lt $Reader.Offset) {
            # The file was replaced or truncated. Start again rather than read from a stale spot.
            $Reader.Offset = 0
            $Reader.Carry = ''
            $Reader.Decoder.Reset()
        }

        $available = $stream.Length - $Reader.Offset
        if ($available -le 0) {
            return ''
        }

        $stream.Position = $Reader.Offset
        $buffer = [byte[]]::new($available)
        $read = $stream.Read($buffer, 0, $buffer.Length)
        if ($read -le 0) {
            return ''
        }

        $Reader.Offset += $read

        $chars = [char[]]::new($Reader.Decoder.GetCharCount($buffer, 0, $read, $false))
        $written = $Reader.Decoder.GetChars($buffer, 0, $read, $chars, 0, $false)
        if ($written -le 0) {
            return ''
        }

        return ([string]::new($chars, 0, $written))
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
    $lines = @(Split-TailLine -Reader $reader -Text (Read-TailText -Reader $reader))

    $start = [Math]::Max(0, $lines.Count - $Count)
    for ($i = $start; $i -lt $lines.Count; $i++) {
        Write-Host $lines[$i]
    }

    if (-not $KeepPartial -and $reader.Carry.Length -gt 0) {
        Write-Host $reader.Carry
        $reader.Carry = ''
    }

    return $reader
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
    $reader = Show-Tail -Path $Record.Path -Count $Tail -KeepPartial:$following

    if (-not $Record.Running) {
        Write-Host ''
        Write-Host "This task has already finished. Exit code: $($Record.ExitCode)"
        return 0
    }

    if ($NoFollow) {
        Write-Host ''
        Write-Host 'This task is still running. Run the command again to see more.'
        return 0
    }

    while ($true) {
        Start-Sleep -Milliseconds 500

        foreach ($line in @(Split-TailLine -Reader $reader -Text (Read-TailText -Reader $reader))) {
            Write-Host $line

            if ($line -match $script:ExitMarker) {
                Write-Host ''
                Write-Host "Exit code: $($Matches[1])"
                return 0
            }
        }

        # The marker is normally a line of its own, but a task that ends without a final newline
        # would leave it in the carry, and waiting for a newline that never comes would hang.
        if ($reader.Carry -match $script:ExitMarker) {
            Write-Host $reader.Carry
            Write-Host ''
            Write-Host "Exit code: $($Matches[1])"
            return 0
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
                State = if ($record.Running) { 'running' } else { "exited $($record.ExitCode)" }
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
        Write-Host 'No task is running now. Showing the newest finished task.'
        Write-Host ''
        Show-Tail -Path $newest.Path -Count $Tail | Out-Null
        Write-Host ''
        Write-Host "Path: $($newest.Path)"
        Write-Host "Exit code: $($newest.ExitCode)"
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
