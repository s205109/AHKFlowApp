#Requires -Version 5.1

# Backlog 204. The Slice runner. A Slice is one 'dotnet test' process over one test project. The
# coverage step and the Integration Mode of test-fast.ps1 hand their Slices to this file. It
# decides how many may run at once and in which order they start, starts each one with its own
# log, and ends every process it started when a run stops early.
#
# This file must load in Windows PowerShell 5.1, because test-fast.ps1 runs there. So it uses no
# ternary operator, no '??', no [Type]::new() and no three-argument Join-Path. The caller
# dot-sources test-lanes.common.ps1 first.

# The budget is the most Slices one run may start at once. A run that owns its Lanes may use every
# Lane it holds. A nested run, or a run with Lanes off, holds none of its own, so it takes half of
# the machine's proposal, the same share a Half run would get (D3).
function Get-AhkFlowSliceBudget {
    param(
        [Parameter(Mandatory = $true)][object] $LaneRun,
        [int] $Proposal
    )
    if ($LaneRun.Role -eq 'owner') {
        return [int]@($LaneRun.Lanes.Streams).Count
    }
    if (-not $PSBoundParameters.ContainsKey('Proposal')) { $Proposal = Get-AhkFlowLaneProposal }
    return [int](Get-AhkFlowLaneShareCount -Share Half -Capacity $Proposal)
}

# Turns the -SlicesAtOnce value into a number. 'Budget', in any case, means the whole budget. A
# whole number above the budget is lowered to the budget (D8).
function Resolve-AhkFlowSlicesAtOnce {
    param(
        [AllowEmptyString()][string] $Requested,
        [Parameter(Mandatory = $true)][int] $Budget
    )
    if ($null -eq $Requested) { $Requested = '' }
    $value = 0
    if ($Requested -ieq 'Budget') {
        $value = $Budget
    }
    elseif ($Requested -match '^[1-9][0-9]*$') {
        $parsed = 0
        if ([int]::TryParse($Requested, [ref]$parsed) -and $parsed -lt $Budget) { $value = $parsed }
        else { $value = $Budget }
    }
    else {
        throw "-SlicesAtOnce takes a whole number of at least 1, or Budget. Got: '$Requested'."
    }
    Write-Host "Slices at once: $value (asked for $Requested, budget $Budget)"
    return [int]$value
}

function New-AhkFlowSlice {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][string] $Command,
        [AllowEmptyString()][string[]] $Argument = @(),
        [Parameter(Mandatory = $true)][string] $LogPath
    )
    return [pscustomobject]@{ Name = $Name; Command = $Command; Argument = @($Argument); LogPath = $LogPath }
}

# At the value 1 the Slices start in the given order, so a sequential run behaves as it did before
# this file existed. Side by side, the longest Slice starts first, so it does not start last and
# hold up the end of the run. A Slice with no stored seconds counts as the longest. A stored name
# with no Slice changes nothing (D5). Equal seconds keep the given order. Sort-Object is not
# trusted to be stable in 5.1, so the input position is an explicit second key.
function Get-AhkFlowSliceOrder {
    param(
        [Parameter(Mandatory = $true)][object[]] $Slice,
        [System.Collections.IDictionary] $History,
        [Parameter(Mandatory = $true)][int] $SlicesAtOnce
    )
    if ($SlicesAtOnce -le 1) { return @($Slice) }

    $keyed = New-Object System.Collections.Generic.List[object]
    for ($index = 0; $index -lt $Slice.Count; $index++) {
        $seconds = [double]::MaxValue
        if ($null -ne $History -and $History.Contains($Slice[$index].Name)) { $seconds = [double]$History[$Slice[$index].Name] }
        $keyed.Add([pscustomobject]@{ Seconds = $seconds; Position = $index; Slice = $Slice[$index] })
    }

    # Seconds highest first, then position lowest first. Each position is unique, so the order
    # never depends on whether the sort is stable.
    $sorted = $keyed | Sort-Object -Property @{ Expression = 'Seconds'; Descending = $true }, @{ Expression = 'Position'; Ascending = $true }
    return @($sorted | ForEach-Object { $_.Slice })
}

# Builds one command line from separate arguments, so the child's runtime splits it back into the
# same values. These are the rules CommandLineToArgvW and the .NET runtime read: an argument that
# is empty or holds a space, a tab or a quote is quoted; a quote inside is written as \"; and the
# backslashes right before a quote, or at the end of a quoted argument, are doubled.
function ConvertTo-AhkFlowArgumentString {
    param([AllowEmptyString()][string[]] $Argument = @())
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($value in @($Argument)) {
        if ($null -eq $value) { $value = '' }
        if ($value.Length -gt 0 -and $value.IndexOfAny([char[]]@(' ', "`t", '"')) -lt 0) {
            $parts.Add($value)
            continue
        }
        $builder = New-Object System.Text.StringBuilder
        [void]$builder.Append('"')
        $backslashes = 0
        foreach ($character in $value.ToCharArray()) {
            if ($character -eq '\') {
                $backslashes++
                continue
            }
            if ($character -eq '"') {
                [void]$builder.Append('\', 2 * $backslashes + 1)
                [void]$builder.Append('"')
            }
            else {
                if ($backslashes -gt 0) { [void]$builder.Append('\', $backslashes) }
                [void]$builder.Append($character)
            }
            $backslashes = 0
        }
        if ($backslashes -gt 0) { [void]$builder.Append('\', 2 * $backslashes) }
        [void]$builder.Append('"')
        $parts.Add($builder.ToString())
    }
    return ($parts -join ' ')
}

function Get-AhkFlowCurrentHostPath {
    return [System.Diagnostics.Process]::GetCurrentProcess().Path
}

function ConvertTo-AhkFlowSingleQuoted {
    param([AllowEmptyString()][string] $Value)
    if ($null -eq $Value) { $Value = '' }
    # PowerShell reads U+2018 to U+201B as single quotes as well, so each one is doubled too.
    return "'" + ($Value -replace "['\u2018-\u201B]", '$0$0') + "'"
}

function ConvertTo-AhkFlowEncodedCommand {
    param([Parameter(Mandatory = $true)][string] $Text)
    return [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Text))
}

# Finds the program a Slice starts. Get-Command returns the command that runs when its name is
# typed, so a dotnet.ps1 stub that a suite puts first on PATH wins over dotnet.exe. A script stub
# runs through the current host with -EncodedCommand, not -File, because 'pwsh -File' splits a
# value such as '--collect:XPlat Code Coverage' in two. The first statement keeps 5.1 from writing
# progress records to standard error as CLIXML.
function Resolve-AhkFlowSliceStart {
    param(
        [Parameter(Mandatory = $true)][string] $Command,
        [AllowEmptyString()][string[]] $Argument = @()
    )
    $found = @(Get-Command -Name $Command -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($found.Count -eq 1) {
        $item = $found[0]
        if ($item.CommandType -eq 'Application') {
            return [pscustomobject]@{ FilePath = $item.Source; Arguments = (ConvertTo-AhkFlowArgumentString -Argument $Argument) }
        }
        if ($item.CommandType -eq 'ExternalScript') {
            $quoted = @(@($Argument) | ForEach-Object { ConvertTo-AhkFlowSingleQuoted -Value $_ })
            $call = (@(ConvertTo-AhkFlowSingleQuoted -Value $item.Source) + $quoted) -join ' '
            $text = "`$ProgressPreference = 'SilentlyContinue'; `$global:LASTEXITCODE = 0; try { & $call } catch { [Console]::Error.WriteLine(`$_.ToString()); exit 1 }; exit `$LASTEXITCODE"
            $encoded = ConvertTo-AhkFlowEncodedCommand -Text $text
            return [pscustomobject]@{ FilePath = (Get-AhkFlowCurrentHostPath); Arguments = "-NoProfile -NonInteractive -EncodedCommand $encoded" }
        }
    }
    throw "Cannot find the command '$Command' for a Slice."
}

# --- The processes ---
#
# An owner holds every process of one Slice, and the operating system keeps that membership. On
# Windows an owner is a Job Object, joined before the Slice can start a child. A child "is
# associated with the immediate job" by default (Microsoft Learn, AssignProcessToJobObject), and
# a job that sets no limit never allows breakaway. Elsewhere an owner is a process group that
# setsid makes for the root. So the runner never rebuilds a process tree from parent ids, which
# are lost when a parent exits, and it never kills by a process id.
#
# Known limit on Linux: a process that starts its own session or process group leaves the Slice's
# group, and the stop does not reach it. On Windows nothing leaves the job.

$script:AhkFlowSliceJobSource = @'
using System;
using System.Runtime.InteropServices;

namespace AhkFlow
{
    public static class SliceJob
    {
        [StructLayout(LayoutKind.Sequential)]
        public struct BasicAccounting
        {
            public long TotalUserTime;
            public long TotalKernelTime;
            public long ThisPeriodTotalUserTime;
            public long ThisPeriodTotalKernelTime;
            public uint TotalPageFaultCount;
            public uint TotalProcesses;
            public uint ActiveProcesses;
            public uint TotalTerminatedProcesses;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct BasicLimit
        {
            public long PerProcessUserTimeLimit;
            public long PerJobUserTimeLimit;
            public uint LimitFlags;
            public UIntPtr MinimumWorkingSetSize;
            public UIntPtr MaximumWorkingSetSize;
            public uint ActiveProcessLimit;
            public UIntPtr Affinity;
            public uint PriorityClass;
            public uint SchedulingClass;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct IoCounters
        {
            public ulong ReadOperationCount;
            public ulong WriteOperationCount;
            public ulong OtherOperationCount;
            public ulong ReadTransferCount;
            public ulong WriteTransferCount;
            public ulong OtherTransferCount;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct ExtendedLimit
        {
            public BasicLimit Basic;
            public IoCounters Io;
            public UIntPtr ProcessMemoryLimit;
            public UIntPtr JobMemoryLimit;
            public UIntPtr PeakProcessMemoryUsed;
            public UIntPtr PeakJobMemoryUsed;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool SetInformationJobObject(IntPtr job, int infoClass, ref ExtendedLimit info, uint length);

        // JobObjectExtendedLimitInformation is class 9, and JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE is
        // 0x2000: the job ends its processes when its last handle closes.
        public static bool SetKillOnClose(IntPtr job)
        {
            ExtendedLimit info = new ExtendedLimit();
            info.Basic.LimitFlags = 0x2000;
            return SetInformationJobObject(job, 9, ref info, (uint)Marshal.SizeOf(typeof(ExtendedLimit)));
        }

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern IntPtr CreateJobObject(IntPtr attributes, string name);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool TerminateJobObject(IntPtr job, uint exitCode);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool IsProcessInJob(IntPtr process, IntPtr job, out bool result);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool CloseHandle(IntPtr handle);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool QueryInformationJobObject(IntPtr job, int infoClass, out BasicAccounting info, int length, IntPtr returnLength);

        [DllImport("kernel32.dll", SetLastError = true, EntryPoint = "QueryInformationJobObject")]
        public static extern bool QueryProcessIdList(IntPtr job, int infoClass, IntPtr info, int length, IntPtr returnLength);

        // Information class 1: JOBOBJECT_BASIC_ACCOUNTING_INFORMATION.
        public static int GetActiveProcessCount(IntPtr job)
        {
            BasicAccounting info;
            if (!QueryInformationJobObject(job, 1, out info, Marshal.SizeOf(typeof(BasicAccounting)), IntPtr.Zero))
            {
                throw new InvalidOperationException("QueryInformationJobObject failed with Win32 error " + Marshal.GetLastWin32Error() + ".");
            }
            return (int)info.ActiveProcesses;
        }

        // Information class 3: JOBOBJECT_BASIC_PROCESS_ID_LIST. Two DWORDs, then ULONG_PTR ids.
        public static long[] GetProcessIds(IntPtr job)
        {
            int capacity = 256;
            while (true)
            {
                int size = 8 + IntPtr.Size * capacity;
                IntPtr buffer = Marshal.AllocHGlobal(size);
                try
                {
                    if (QueryProcessIdList(job, 3, buffer, size, IntPtr.Zero))
                    {
                        int count = Marshal.ReadInt32(buffer, 4);
                        long[] ids = new long[count];
                        for (int i = 0; i < count; i++)
                        {
                            ids[i] = Marshal.ReadIntPtr(buffer, 8 + i * IntPtr.Size).ToInt64();
                        }
                        return ids;
                    }
                    int error = Marshal.GetLastWin32Error();
                    if (error != 234 || capacity > 65536)
                    {
                        throw new InvalidOperationException("QueryInformationJobObject failed with Win32 error " + error + ".");
                    }
                    capacity = capacity * 4;
                }
                finally
                {
                    Marshal.FreeHGlobal(buffer);
                }
            }
        }
    }
}
'@

function Test-AhkFlowSliceOnWindows {
    return ([System.IO.Path]::DirectorySeparatorChar -eq '\')
}

function Initialize-AhkFlowSliceJob {
    if (-not (Test-AhkFlowSliceOnWindows)) { return }
    if ($null -ne ('AhkFlow.SliceJob' -as [type])) { return }
    Add-Type -TypeDefinition $script:AhkFlowSliceJobSource -Language CSharp
}

function Get-AhkFlowWin32Message {
    param([int] $Code)
    return (New-Object System.ComponentModel.Win32Exception($Code)).Message
}

function New-AhkFlowSliceOwner {
    if (Test-AhkFlowSliceOnWindows) {
        Initialize-AhkFlowSliceJob
        $job = [AhkFlow.SliceJob]::CreateJobObject([IntPtr]::Zero, $null)
        if ($job -eq [IntPtr]::Zero) {
            $code = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "Could not create a job for a Slice: $(Get-AhkFlowWin32Message $code)"
        }
        # A closed terminal or a killed host runs no 'finally'. The operating system then closes
        # the job handle, and this limit ends the Slice's processes, so none outlives the lock (D7).
        if (-not [AhkFlow.SliceJob]::SetKillOnClose($job)) {
            $code = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            [void][AhkFlow.SliceJob]::CloseHandle($job)
            throw "Could not set the job of a Slice to end its processes when it closes: $(Get-AhkFlowWin32Message $code)"
        }
        return [pscustomobject]@{ Kind = 'job'; Job = $job; GroupId = $null }
    }
    return [pscustomobject]@{ Kind = 'group'; Job = $null; GroupId = $null }
}

function New-AhkFlowRedirectedStart {
    param([string] $FilePath, [string] $Arguments, [string] $WorkingDirectory)
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $FilePath
    $info.Arguments = $Arguments
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    if ($WorkingDirectory) { $info.WorkingDirectory = $WorkingDirectory }
    return $info
}

# The script the Windows launcher runs. It waits for one line on standard input, then starts the
# real program and passes its exit code through.
function Get-AhkFlowSliceLauncherText {
    param(
        [Parameter(Mandatory = $true)][object] $Start,
        [Parameter(Mandatory = $true)][string] $WorkingDirectory
    )
    # Input that closes without the start line means the runner is gone, so nothing starts. The
    # line only has to end with 'start': Windows PowerShell 5.1 puts a UTF-8 byte order mark first
    # when the console input encoding is UTF-8, and this console reads it as extra characters.
    return "`$ProgressPreference = 'SilentlyContinue'; `$line = [Console]::In.ReadLine(); if (`$null -eq `$line -or -not `$line.EndsWith('start')) { exit 1 }; " +
        "`$i = New-Object System.Diagnostics.ProcessStartInfo; " +
        "`$i.FileName = $(ConvertTo-AhkFlowSingleQuoted $Start.FilePath); " +
        "`$i.Arguments = $(ConvertTo-AhkFlowSingleQuoted $Start.Arguments); " +
        "`$i.WorkingDirectory = $(ConvertTo-AhkFlowSingleQuoted $WorkingDirectory); " +
        "`$i.UseShellExecute = `$false; `$p = [System.Diagnostics.Process]::Start(`$i); `$p.WaitForExit(); exit `$p.ExitCode"
}

# Starts the root process of a Slice inside its owner and returns it, with standard output and
# standard error redirected.
#
# On Windows the root is a launcher: the current host, waiting for one line on standard input
# before it starts the real program. The runner puts the launcher in the job first, then sends
# that line. So no process of the Slice can exist outside the job. The program inherits the
# launcher's output pipes, and the launcher passes its exit code through.
function Start-AhkFlowOwnedProcess {
    param(
        [Parameter(Mandatory = $true)][object] $Start,
        [Parameter(Mandatory = $true)][object] $Owner,
        [Parameter(Mandatory = $true)][string] $WorkingDirectory,
        [string] $Name = 'the Slice'
    )
    if ($Owner.Kind -eq 'job') {
        $text = Get-AhkFlowSliceLauncherText -Start $Start -WorkingDirectory $WorkingDirectory
        $arguments = '-NoProfile -NonInteractive -EncodedCommand ' + (ConvertTo-AhkFlowEncodedCommand -Text $text)
        $process = [System.Diagnostics.Process]::Start((New-AhkFlowRedirectedStart -FilePath (Get-AhkFlowCurrentHostPath) -Arguments $arguments -WorkingDirectory $WorkingDirectory))
        if (-not [AhkFlow.SliceJob]::AssignProcessToJobObject($Owner.Job, $process.Handle)) {
            $code = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            try { $process.Kill() } catch { }
            throw "Slice $Name could not join its job: $(Get-AhkFlowWin32Message $code)."
        }
        $process.StandardInput.WriteLine('start')
        $process.StandardInput.Close()
        return $process
    }

    $setsid = @(Get-Command -Name 'setsid' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($setsid.Count -eq 0) { throw 'The Slice runner needs the setsid command on this system.' }
    $arguments = (ConvertTo-AhkFlowArgumentString -Argument @($Start.FilePath)) + ' ' + $Start.Arguments
    $process = [System.Diagnostics.Process]::Start((New-AhkFlowRedirectedStart -FilePath $setsid[0].Source -Arguments $arguments -WorkingDirectory $WorkingDirectory))
    $Owner.GroupId = $process.Id
    $process.StandardInput.Close()
    return $process
}

function Get-AhkFlowGroupRow {
    param([Parameter(Mandatory = $true)][object] $Owner)
    $rows = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Owner.GroupId) { return @() }
    foreach ($line in @(& ps -e -o 'pid=,pgid=,stat=' 2>$null)) {
        $fields = @(([string]$line).Trim() -split '\s+')
        if ($fields.Count -lt 3) { continue }
        if ($fields[1] -ne [string]$Owner.GroupId) { continue }
        # A 'Z' process is "defunct ("zombie") process, terminated but not reaped by its parent"
        # (man7, ps(1)). It has already exited.
        if ($fields[2].StartsWith('Z')) { continue }
        $rows.Add([int]$fields[0])
    }
    return $rows.ToArray()
}

function Test-AhkFlowOwnerActive {
    param([Parameter(Mandatory = $true)][object] $Owner)
    if ($Owner.Kind -eq 'job') {
        return ([AhkFlow.SliceJob]::GetActiveProcessCount($Owner.Job) -gt 0)
    }
    return (@(Get-AhkFlowGroupRow -Owner $Owner).Count -gt 0)
}

# The ids of the owner's processes as the operating system lists them now. Messages use them. No
# kill uses them.
function Get-AhkFlowOwnedProcessId {
    param([Parameter(Mandatory = $true)][object] $Owner)
    if ($Owner.Kind -eq 'job') {
        return @([AhkFlow.SliceJob]::GetProcessIds($Owner.Job) | ForEach-Object { [int]$_ })
    }
    return @(Get-AhkFlowGroupRow -Owner $Owner)
}

# Ends every process of the owner at once. It takes an owner, never a process id. On Windows
# TerminateJobObject "terminates all processes currently associated with the job" (Microsoft
# Learn). Elsewhere a kill of the negative group id reaches "every process in the process group"
# (man7, kill(2)); the '--' keeps the negative value from being read as an option.
function Invoke-AhkFlowOwnerKill {
    param([Parameter(Mandatory = $true)][object] $Owner)
    if ($Owner.Kind -eq 'job') {
        [void][AhkFlow.SliceJob]::TerminateJobObject($Owner.Job, 1)
        return
    }
    if ($null -eq $Owner.GroupId) { return }
    & kill -s KILL -- ('-' + [string]$Owner.GroupId) 2>$null | Out-Null
}

# Returns only when no owner has a process left. It has no overall time limit: a limit would let
# the caller release the test-run lock and the Lanes while a process still runs (D7).
function Stop-AhkFlowOwnedProcess {
    param(
        [AllowEmptyCollection()][object[]] $Owner = @(),
        [int] $RoundSeconds = 30
    )
    while ($true) {
        $active = @(@($Owner) | Where-Object { $null -ne $_ -and (Test-AhkFlowOwnerActive -Owner $_) })
        if ($active.Count -eq 0) { return }
        foreach ($item in $active) {
            try { Invoke-AhkFlowOwnerKill -Owner $item }
            catch { Write-Host "A kill of a Slice's processes failed: $($_.Exception.Message)" -ForegroundColor Red }
        }
        $deadline = [DateTime]::UtcNow.AddSeconds($RoundSeconds)
        while ([DateTime]::UtcNow -lt $deadline) {
            $active = @($active | Where-Object { Test-AhkFlowOwnerActive -Owner $_ })
            if ($active.Count -eq 0) { return }
            Start-Sleep -Milliseconds 200
        }
        $ids = @($active | ForEach-Object { Get-AhkFlowOwnedProcessId -Owner $_ })
        Write-Host "Still running after $RoundSeconds s: $($ids -join ', '). The run keeps the test-run lock and its Lanes until they exit." -ForegroundColor Red
    }
}

# Closes a job handle. The job ends its processes when its last handle closes, so a process that a
# finished Slice left behind ends here too.
function Close-AhkFlowSliceOwner {
    param([Parameter(Mandatory = $true)][object] $Owner)
    if ($Owner.Kind -eq 'job' -and $null -ne $Owner.Job -and $Owner.Job -ne [IntPtr]::Zero) {
        [void][AhkFlow.SliceJob]::CloseHandle($Owner.Job)
        $Owner.Job = [IntPtr]::Zero
    }
}

function Close-AhkFlowSliceFile {
    param([Parameter(Mandatory = $true)][object] $Entry)
    foreach ($name in @('Out', 'Err')) {
        if ($null -ne $Entry.$name) {
            try { $Entry.$name.Dispose() } catch { }
            $Entry.$name = $null
        }
    }
}

function Start-AhkFlowSliceEntry {
    param(
        [Parameter(Mandatory = $true)][object] $Slice,
        [Parameter(Mandatory = $true)][string] $WorkingDirectory,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]] $Owners
    )
    $result = [pscustomobject]@{ Name = $Slice.Name; ExitCode = $null; Seconds = $null; LogPath = $Slice.LogPath }
    $entry = [pscustomobject]@{
        Slice = $Slice; Owner = $null; Process = $null; Out = $null; Err = $null
        OutTask = $null; ErrTask = $null; Watch = $null; Result = $result
        Exited = $false; DrainDeadline = $null
    }
    try {
        $folder = Split-Path -Parent $Slice.LogPath
        if ($folder) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
        $start = Resolve-AhkFlowSliceStart -Command $Slice.Command -Argument $Slice.Argument
        $entry.Owner = New-AhkFlowSliceOwner
        $Owners.Add($entry.Owner)
        $entry.Out = New-Object System.IO.FileStream($Slice.LogPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite, 1)
        $entry.Err = New-Object System.IO.FileStream(($Slice.LogPath + '.stderr'), [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite, 1)
        $entry.Watch = [System.Diagnostics.Stopwatch]::StartNew()
        $entry.Process = Start-AhkFlowOwnedProcess -Start $start -Owner $entry.Owner -WorkingDirectory $WorkingDirectory -Name $Slice.Name
        $entry.OutTask = $entry.Process.StandardOutput.BaseStream.CopyToAsync($entry.Out)
        $entry.ErrTask = $entry.Process.StandardError.BaseStream.CopyToAsync($entry.Err)
    }
    catch {
        Close-AhkFlowSliceFile -Entry $entry
        throw "Slice $($Slice.Name) could not start: $($_.Exception.Message)"
    }
    Write-Host "start $($Slice.Name)  log $($Slice.LogPath)"
    return $entry
}

# The root of a Slice has exited. Its seconds and its exit code are final now, and its place goes
# to the next Slice at once. A process the Slice left behind is named here, and its owner stays
# in the run-wide list, so a later stop still ends it.
function Set-AhkFlowSliceExited {
    param([Parameter(Mandatory = $true)][object] $Entry)
    $Entry.Watch.Stop()
    $Entry.Result.ExitCode = $Entry.Process.ExitCode
    $Entry.Result.Seconds = [Math]::Round($Entry.Watch.Elapsed.TotalSeconds, 1)
    $Entry.Exited = $true
    $Entry.DrainDeadline = [DateTime]::UtcNow.AddSeconds(30)
    if (Test-AhkFlowOwnerActive -Owner $Entry.Owner) {
        # A console host serves the hidden console of the Slice, and it lives while any process
        # still shares that console. It is in the job, but the Slice did not start it, so the
        # message leaves it out. The stop still ends it with the rest of the job.
        $ids = @(Get-AhkFlowOwnedProcessId -Owner $Entry.Owner | Where-Object {
                $process = Get-Process -Id $_ -ErrorAction SilentlyContinue
                $null -ne $process -and $process.ProcessName -ne 'conhost'
            })
    }
    else { $ids = @() }
    if ($ids.Count -gt 0) {
        $word = 'process'
        if ($ids.Count -gt 1) { $word = 'processes' }
        Write-Host "Slice $($Entry.Slice.Name) left $($ids.Count) $word running: $($ids -join ', ')." -ForegroundColor Yellow
    }
}

# Whether the log copy of an exited Slice is done, or has waited its 30 s. A process the Slice left
# behind can hold the output pipe open, because a child inherits it, and then the copy never ends.
function Test-AhkFlowSliceDrained {
    param([Parameter(Mandatory = $true)][object] $Entry)
    if ([DateTime]::UtcNow -ge $Entry.DrainDeadline) { return $true }
    foreach ($task in @($Entry.OutTask, $Entry.ErrTask)) {
        if ($null -ne $task -and -not $task.IsCompleted) { return $false }
    }
    return $true
}

function Complete-AhkFlowSliceEntry {
    param(
        [Parameter(Mandatory = $true)][object] $Entry,
        [Parameter(Mandatory = $true)][object] $Parallel
    )
    $name = $Entry.Slice.Name
    $whole = $true
    foreach ($task in @($Entry.OutTask, $Entry.ErrTask)) {
        if ($null -ne $task -and -not $task.IsCompleted) { $whole = $false }
    }
    if (-not $whole) {
        Write-Host "The log of $name may be incomplete: a child process still holds its output." -ForegroundColor Yellow
    }
    Close-AhkFlowSliceFile -Entry $Entry

    $errorPath = $Entry.Slice.LogPath + '.stderr'
    if (Test-Path -LiteralPath $errorPath) {
        $errorText = [System.IO.File]::ReadAllText($errorPath)
        if ($errorText.Length -gt 0) {
            $logText = [System.IO.File]::ReadAllText($Entry.Slice.LogPath)
            $separator = ''
            if ($logText.Length -gt 0 -and -not $logText.EndsWith("`n")) { $separator = [Environment]::NewLine }
            [System.IO.File]::AppendAllText($Entry.Slice.LogPath, $separator + '--- standard error ---' + [Environment]::NewLine + $errorText)
        }
        Remove-Item -LiteralPath $errorPath -Force -ErrorAction SilentlyContinue
    }

    $seconds = $Entry.Watch.Elapsed.TotalSeconds
    $exitCode = $Entry.Result.ExitCode
    Complete-ParallelProgressUnit -Tracker $Parallel -Name $name -Seconds $seconds
    $line = Get-ParallelProgressLine -Tracker $Parallel -Name $name -Seconds $seconds
    if ($exitCode -eq 0) { Write-Host "$line  passed" -ForegroundColor Green }
    else { Write-Host "$line  FAILED (exit $exitCode)" -ForegroundColor Red }
}

# Runs the Slices in the given order, with at most -SlicesAtOnce running. Every Slice runs to the
# end, whatever another one's exit code. A Slice that cannot start makes it throw, after the
# cleanup below. One 'finally' covers Ctrl+C, a Slice that cannot start, and an error in the
# runner: it ends every process of every Slice, finished Slices included, and returns only when
# none is left (D7). The caller releases the lock and the Lanes in its own 'finally', which runs
# after this one.
function Invoke-AhkFlowSliceSet {
    param(
        [Parameter(Mandatory = $true)][object[]] $Slice,
        [Parameter(Mandatory = $true)][int] $SlicesAtOnce,
        [Parameter(Mandatory = $true)][string] $WorkingDirectory,
        [Parameter(Mandatory = $true)][object] $Tracker,
        [int] $StopRoundSeconds = 30
    )
    if ($SlicesAtOnce -lt 1) { $SlicesAtOnce = 1 }
    $parallel = New-ParallelProgressTracker -Tracker $Tracker
    $parallel.Done = $Tracker.Index
    $owners = New-Object System.Collections.Generic.List[object]
    $running = New-Object System.Collections.Generic.List[object]
    $results = New-Object System.Collections.Generic.List[object]
    $next = 0
    $completed = $false
    try {
        while ($next -lt $Slice.Count -or $running.Count -gt 0) {
            # A Slice holds its place only while its root runs. Its log may still drain afterwards.
            while (@($running | Where-Object { -not $_.Exited }).Count -lt $SlicesAtOnce -and $next -lt $Slice.Count) {
                $entry = Start-AhkFlowSliceEntry -Slice $Slice[$next] -WorkingDirectory $WorkingDirectory -Owners $owners
                $running.Add($entry)
                $results.Add($entry.Result)
                $next++
            }
            $changed = $false
            foreach ($entry in @($running | Where-Object { -not $_.Exited -and $_.Process.HasExited })) {
                Set-AhkFlowSliceExited -Entry $entry
                $changed = $true
            }
            foreach ($entry in @($running | Where-Object { $_.Exited -and (Test-AhkFlowSliceDrained -Entry $_) })) {
                [void]$running.Remove($entry)
                Complete-AhkFlowSliceEntry -Entry $entry -Parallel $parallel
                $changed = $true
            }
            if (-not $changed -and $running.Count -gt 0) { Start-Sleep -Milliseconds 200 }
        }
        $completed = $true
    }
    finally {
        # Every exit stops what is left, a completed run too. A process group on Linux has no limit
        # that ends its processes when it closes, so a left-behind process would outlive the lock.
        Stop-AhkFlowOwnedProcess -Owner $owners.ToArray() -RoundSeconds $StopRoundSeconds
        if (-not $completed) {
            foreach ($entry in $running) { Close-AhkFlowSliceFile -Entry $entry }
        }
        foreach ($owner in $owners) { Close-AhkFlowSliceOwner -Owner $owner }
        $Tracker.Index = $parallel.Done
    }
    return $results.ToArray()
}

function Write-AhkFlowSliceLog {
    param([AllowEmptyCollection()][object[]] $Result = @())
    foreach ($item in @($Result)) {
        Write-Host "=== $($item.Name): $($item.LogPath) ==="
        if (Test-Path -LiteralPath $item.LogPath) { Write-Host ([System.IO.File]::ReadAllText($item.LogPath)) }
        else { Write-Host '(no log was written)' }
    }
}

function Save-AhkFlowSliceResult {
    param(
        [AllowEmptyCollection()][object[]] $Result = @(),
        [Parameter(Mandatory = $true)][string] $Path
    )
    $rows = @(@($Result) | ForEach-Object {
        [pscustomobject]@{
            Name = $_.Name
            ExitCode = $_.ExitCode
            Seconds = $_.Seconds
            Folder = (Split-Path -Leaf (Split-Path -Parent $_.LogPath))
            Log = (Split-Path -Leaf $_.LogPath)
        }
    })
    $folder = Split-Path -Parent $Path
    if ($folder) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    $json = ConvertTo-Json -InputObject @($rows) -Depth 3
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
}
