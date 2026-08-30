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
    [int] $Index,
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
      Returns one record per <SearchRoot>\<Prefix>*\<session id>\tasks\*.output file, newest
      first by last write time.
    #>
    param(
        [Parameter(Mandatory)][string] $SearchRoot,
        [Parameter(Mandatory)][string] $Prefix
    )

    if (-not (Test-Path -LiteralPath $SearchRoot -PathType Container)) {
        return @()
    }

    $projectDirs = @(
        Get-ChildItem -LiteralPath $SearchRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "$Prefix*" }
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

function Show-Tail {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][int] $Count
    )

    $lines = @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)
    $start = [Math]::Max(0, $lines.Count - $Count)
    for ($i = $start; $i -lt $lines.Count; $i++) {
        Write-Host $lines[$i]
    }
    return $lines.Count
}

function Watch-Record {
    param(
        [Parameter(Mandatory)][object] $Record,
        [Parameter(Mandatory)][int] $Tail,
        [switch] $NoFollow
    )

    Write-Host "Tailing $($Record.Path)"
    Write-Host ''
    $printed = Show-Tail -Path $Record.Path -Count $Tail

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
        $lines = @(Get-Content -LiteralPath $Record.Path -ErrorAction SilentlyContinue)
        if ($lines.Count -gt $printed) {
            for ($i = $printed; $i -lt $lines.Count; $i++) {
                Write-Host $lines[$i]
            }
            $printed = $lines.Count
        }

        $lastNonEmpty = $null
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            if ($lines[$i].Trim().Length -gt 0) {
                $lastNonEmpty = $lines[$i]
                break
            }
        }

        if ($lastNonEmpty -and $lastNonEmpty -match $script:ExitMarker) {
            Write-Host ''
            Write-Host "Exit code: $($Matches[1])"
            return 0
        }
    }
}

function Invoke-WatchTask {
    param(
        [switch] $List,
        [int] $Index,
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
    $prefix = ConvertTo-ClaudeProjectFolder -Path $mainRoot

    $records = @(Get-WatchTaskRecord -SearchRoot $searchRoot -Prefix $prefix)

    if ($records.Count -eq 0) {
        Write-Host "No task output files found for this repository under $searchRoot"
        Write-Host "Looked for folders matching: $prefix*"
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

    if ($PSBoundParameters.ContainsKey('Index') -and $Index -gt 0) {
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
