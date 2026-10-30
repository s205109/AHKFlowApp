#Requires -Version 7.0

<#
.SYNOPSIS
    Runs the control runs and defect runs of the backlog 193 architecture pilot.

.DESCRIPTION
    The script runs the nine Lane Suites against a local clone, never against this worktree. Each
    Suite runs in its own pwsh process inside its own Windows job object, so every child it starts
    ends before the next trial starts.

    Modes:
      Verify    checks that each edit of each defect patch finds its text exactly once.
      SuiteSet  runs the Suites of the inputs file once, three at a time, longest budget first.
      Attempt   runs an opening control, one SuiteSet per defect, then a closing control.
      Timing    runs a warm-up pass of A and of B, then A B B A B A A B. A pass runs each Suite
                once, alone. A is the before clone and B the after clone.

    The script refuses to start while a Lane variable is set. It refuses any checkout that is not
    one of its own clones under .superpowers\193-pilot\ in the repository that holds this script.
    It runs git reset and git clean only inside such a clone.

    Windows only, because it uses Windows job objects.

.EXAMPLE
    pwsh ./scripts/measure-architecture-pilot.ps1 -Mode SuiteSet -OutDir .superpowers\193-pilot\results\budgets -Checkout .superpowers\193-pilot\before -Commit <sha>
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('Verify', 'SuiteSet', 'Attempt', 'Timing')][string] $Mode,
    [string] $Inputs,
    [string] $OutDir,
    [string] $Checkout,
    [string] $Commit,
    [ValidateSet('Before', 'After')][string] $Side,
    [string[]] $DefectId,
    # Timing only: the two clones, their commits, and each side's clean opening control file.
    [string] $BeforeCheckout,
    [string] $BeforeCommit,
    [string] $AfterCheckout,
    [string] $AfterCommit,
    [string] $BeforeCases,
    [string] $AfterCases,
    # Test-only: makes the job assignment fail, so a case can prove the run stops.
    [switch] $FailJobAssignment
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:PilotRoot = [IO.Path]::GetFullPath((Join-Path $script:RepoRoot '.superpowers\193-pilot')).TrimEnd('\')
$script:LaneVariables = @('AHKFLOW_TEST_LANES', 'AHKFLOW_TEST_LANES_HOLDER', 'AHKFLOW_TEST_LANES_ROOT')
$script:Pwsh = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$script:TrialNumber = 0
$script:Parallel = 3

if (-not $IsWindows) { throw 'Refused: this script uses Windows job objects and runs on Windows only.' }
foreach ($name in $script:LaneVariables) {
    if (-not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($name))) {
        throw "Refused: $name is set. Run the script from a shell with no Lane variable."
    }
}

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class PilotJob
{
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr CreateJobObject(IntPtr attributes, string name);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool TerminateJobObject(IntPtr job, uint exitCode);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool QueryInformationJobObject(IntPtr job, int infoClass, IntPtr info, int length, out int returnLength);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr handle);

    // Each method returns 0 on success, or the Win32 error code read at once after the call.
    public static int Create(out IntPtr job)
    {
        job = CreateJobObject(IntPtr.Zero, null);
        return job == IntPtr.Zero ? Marshal.GetLastWin32Error() : 0;
    }

    public static int Assign(IntPtr job, IntPtr process)
    {
        return AssignProcessToJobObject(job, process) ? 0 : Marshal.GetLastWin32Error();
    }

    public static int Terminate(IntPtr job)
    {
        return TerminateJobObject(job, 1) ? 0 : Marshal.GetLastWin32Error();
    }

    public static int Close(IntPtr job)
    {
        return CloseHandle(job) ? 0 : Marshal.GetLastWin32Error();
    }

    // JobObjectBasicProcessIdList (3): two DWORD counts, then the ULONG_PTR list at offset 8.
    public static int ProcessIds(IntPtr job, out long[] ids)
    {
        ids = new long[0];
        const int capacity = 4096;
        int size = 8 + IntPtr.Size * capacity;
        IntPtr buffer = Marshal.AllocHGlobal(size);
        try
        {
            int returned;
            if (!QueryInformationJobObject(job, 3, buffer, size, out returned)) { return Marshal.GetLastWin32Error(); }
            int count = Marshal.ReadInt32(buffer, 4);
            var list = new List<long>();
            for (int i = 0; i < count; i++) { list.Add(Marshal.ReadIntPtr(buffer, 8 + i * IntPtr.Size).ToInt64()); }
            ids = list.ToArray();
            return 0;
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }

    // JobObjectBasicAccountingInformation (1): ActiveProcesses is the DWORD at offset 40.
    public static int ActiveProcesses(IntPtr job, out int active)
    {
        active = -1;
        IntPtr buffer = Marshal.AllocHGlobal(48);
        try
        {
            int returned;
            if (!QueryInformationJobObject(job, 1, buffer, 48, out returned)) { return Marshal.GetLastWin32Error(); }
            active = Marshal.ReadInt32(buffer, 40);
            return 0;
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }
}
'@

function Assert-Win32 {
    param([int] $Code, [string] $Call)
    if ($Code -ne 0) { throw "$Call failed with Win32 error $Code." }
}

function Read-PilotInputs {
    $path = if ($Inputs) { $Inputs } else { Join-Path $script:RepoRoot 'docs\development\architecture-pilot-inputs.json' }
    Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Get-FullPath([string] $Path) { [IO.Path]::GetFullPath($Path).TrimEnd('\') }

# The four checkout rules. The top-level rule comes before the mark, so a folder with a broken
# .git folder never reads the mark of the repository above it.
function Assert-PilotCheckout {
    param([string] $Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Refused: -Checkout is required for this mode.' }
    $full = Get-FullPath $Path
    if ((Split-Path -Parent $full) -ne $script:PilotRoot) { throw "Refused: $full is not a direct child of $($script:PilotRoot)." }
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { throw "Refused: $full does not exist." }
    $item = Get-Item -LiteralPath $full -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Refused: $full is a reparse point." }
    $top = & git -C $full rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$top)) { throw "Refused: $full is not a Git checkout." }
    $topFull = Get-FullPath ([string]$top).Trim()
    if ($topFull -ne $full) { throw "Refused: the Git top level of $full is $topFull." }
    $mark = & git -C $full config --local --get ahkflow.pilot 2>$null
    if ($LASTEXITCODE -ne 0 -or ([string]$mark).Trim() -ne '193') { throw "Refused: $full has no ahkflow.pilot ownership mark." }
    $full
}

function Assert-PilotCommit {
    param([string] $Path, [string] $Sha)
    if ($Sha -notmatch '^[0-9a-f]{40}$') { throw "Refused: -Commit must be a full SHA, got '$Sha'." }
    $head = (& git -C $Path rev-parse HEAD).Trim()
    if ($head -ne $Sha) { throw "The checkout $Path is at $head, not at $Sha." }
}

function Reset-PilotCheckout {
    param([string] $Path, [string] $Sha)
    $full = Assert-PilotCheckout $Path
    & git -C $full reset --quiet --hard $Sha
    if ($LASTEXITCODE -ne 0) { throw "git reset failed in $full." }
    & git -C $full clean -xdfq
    if ($LASTEXITCODE -ne 0) { throw "git clean failed in $full." }
    Assert-PilotCommit $full $Sha
    $status = & git -C $full status --porcelain --untracked-files=all --ignored
    if (@($status | Where-Object { $_ }).Count -gt 0) { throw "The checkout $full is not clean after the reset: $($status -join '; ')" }
}

function Get-PilotPatch {
    param($Defect, [string] $PatchSide)
    $edits = if ($PatchSide -eq 'After') { $Defect.after } else { $Defect.before }
    @($edits)
}

# Applies the edits in order to in-memory bytes. Each find must occur exactly once at its turn.
# Latin1 maps each byte to one character, so the string replace is an exact byte replace.
function Get-PilotPatchResult {
    param([string] $Path, $Defect, [string] $PatchSide)
    $latin1 = [Text.Encoding]::Latin1
    $files = [ordered]@{}
    $problems = [Collections.Generic.List[string]]::new()
    $number = 0
    foreach ($edit in (Get-PilotPatch $Defect $PatchSide)) {
        $number++
        $target = Get-FullPath (Join-Path $Path $edit.file)
        if (-not $target.StartsWith($Path + '\', [StringComparison]::OrdinalIgnoreCase)) {
            $problems.Add("Defect $($Defect.id), edit ${number}: $($edit.file) is outside the checkout.")
            continue
        }
        if (-not $files.Contains($target)) {
            if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { $problems.Add("Defect $($Defect.id), edit ${number}: $($edit.file) does not exist."); continue }
            $bytes = [IO.File]::ReadAllBytes($target)
            $files[$target] = @{ Old = $bytes; Text = $latin1.GetString($bytes) }
        }
        $find = $latin1.GetString([Text.Encoding]::UTF8.GetBytes([string]$edit.find))
        $replace = $latin1.GetString([Text.Encoding]::UTF8.GetBytes([string]$edit.replace))
        $text = $files[$target].Text
        $count = 0
        $at = $text.IndexOf($find, [StringComparison]::Ordinal)
        while ($find.Length -gt 0 -and $at -ge 0) { $count++; $at = $text.IndexOf($find, $at + $find.Length, [StringComparison]::Ordinal) }
        if ($count -ne 1) { $problems.Add("Defect $($Defect.id), edit ${number}: the find text occurs $count times in $($edit.file)."); continue }
        $files[$target].Text = $text.Replace($find, $replace)
    }
    foreach ($key in $files.Keys) { $files[$key].New = $latin1.GetBytes($files[$key].Text) }
    [pscustomobject]@{ Files = $files; Problems = @($problems) }
}

function Get-Sha256([byte[]] $Bytes) { [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)) }

function New-GateScript {
    param([string] $Folder, [string] $SuitePath)
    $q = { param($s) "'" + $s.Replace("'", "''") + "'" }
    @"
`$ErrorActionPreference = 'Continue'
`$go = $(& $q (Join-Path $Folder 'go'))
while (-not (Test-Path -LiteralPath `$go)) { Start-Sleep -Milliseconds 20 }
`$output = $(& $q (Join-Path $Folder 'output.txt'))
`$watch = [Diagnostics.Stopwatch]::StartNew()
& $(& $q $script:Pwsh) -NoProfile -File $(& $q $SuitePath) 2>&1 | ForEach-Object { [IO.File]::AppendAllText(`$output, [string]`$_ + [Environment]::NewLine) }
`$code = `$LASTEXITCODE
`$watch.Stop()
Set-Content -LiteralPath $(& $q (Join-Path $Folder 'seconds.txt')) -Value `$watch.Elapsed.TotalSeconds.ToString([Globalization.CultureInfo]::InvariantCulture)
exit `$code
"@
}

# Starts one Suite behind a gate. The gate waits for the go file, so the Suite and all its children
# start only after the gate is in the job.
function Start-PilotSuite {
    param([string] $TrialFolder, [int] $Number, $Suite, [string] $Path)
    $folder = Join-Path $TrialFolder ([string]$Number)
    New-Item -ItemType Directory -Force (Join-Path $folder 'pool'), (Join-Path $folder 'tmp') | Out-Null
    $gate = Join-Path $folder 'gate.ps1'
    Set-Content -LiteralPath $gate -Value (New-GateScript $folder (Join-Path $Path "tests\$($Suite.name)"))
    $info = [Diagnostics.ProcessStartInfo]::new($script:Pwsh)
    foreach ($argument in @('-NoProfile', '-File', $gate)) { $info.ArgumentList.Add($argument) }
    $info.WorkingDirectory = $Path
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($name in $script:LaneVariables) { [void]$info.Environment.Remove($name) }
    $info.Environment['AHKFLOW_TEST_LANES_HOLDER'] = "pilot-$Number"
    $info.Environment['AHKFLOW_TEST_LANES_ROOT'] = Join-Path $folder 'pool'
    $info.Environment['TEMP'] = Join-Path $folder 'tmp'
    $info.Environment['TMP'] = Join-Path $folder 'tmp'
    $info.Environment['AHKFLOW_SUITE_CASE_START'] = '1'
    $process = [Diagnostics.Process]::Start($info)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $job = [IntPtr]::Zero
    $code = [PilotJob]::Create([ref] $job)
    if ($code -eq 0) {
        $handle = if ($FailJobAssignment) { [IntPtr]::Zero } else { $process.Handle }
        $code = [PilotJob]::Assign($job, $handle)
        if ($code -ne 0) {
            $process.Kill(); [void]$process.WaitForExit(5000)
            [void][PilotJob]::Close($job)
            Assert-Win32 $code 'AssignProcessToJobObject'
        }
    }
    else {
        $process.Kill(); [void]$process.WaitForExit(5000)
        Assert-Win32 $code 'CreateJobObject'
    }
    Set-Content -LiteralPath (Join-Path $folder 'go') -Value go
    [pscustomobject]@{
        Suite = $Suite; Number = $Number; Folder = $folder; Process = $process; Job = $job
        Stdout = $stdout; Stderr = $stderr; Watch = [Diagnostics.Stopwatch]::StartNew()
        Limit = 3 * [double]$Suite.budgetSeconds
    }
}

function Get-JobProcessIds {
    param([IntPtr] $Job)
    $ids = [long[]]@()
    Assert-Win32 ([PilotJob]::ProcessIds($Job, [ref] $ids)) 'QueryInformationJobObject(JobObjectBasicProcessIdList)'
    @($ids)
}

function Get-JobActiveCount {
    param([IntPtr] $Job)
    $active = 0
    Assert-Win32 ([PilotJob]::ActiveProcesses($Job, [ref] $active)) 'QueryInformationJobObject(JobObjectBasicAccountingInformation)'
    $active
}

# Reads the case lines. A FAIL line takes the next line that starts with eight spaces as its
# message. START lines are matched to later results by name, latest open start first, so a case
# that runs a child Suite inside it still matches.
function Read-PilotCaseLines {
    param([string] $Text)
    $lines = @($Text -split "`r?`n")
    $starts = [Collections.Generic.List[string]]::new()
    $passes = [Collections.Generic.List[string]]::new()
    $fails = [Collections.Generic.List[object]]::new()
    $open = [Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^  START  (.+)$') { $starts.Add($Matches[1]); $open.Add($Matches[1]); continue }
        $name = $null
        if ($line -match '^  PASS  (.+)$') { $name = $Matches[1]; $passes.Add($name) }
        elseif ($line -match '^  FAIL  (.+)$') {
            $name = $Matches[1]
            $message = if ($i + 1 -lt $lines.Count -and $lines[$i + 1].StartsWith('        ')) { $lines[$i + 1].Trim() } else { '' }
            $fails.Add([pscustomobject]@{ Name = $name; Message = $message })
        }
        if ($null -ne $name) {
            $index = $open.LastIndexOf($name)
            if ($index -ge 0) { $open.RemoveAt($index) }
        }
    }
    [pscustomobject]@{ Starts = @($starts); Passes = @($passes); Fails = @($fails); Unfinished = @($open) }
}

function Stop-PilotSuite {
    param($Running)
    $timedOut = -not $Running.Process.HasExited
    $waited = $Running.Watch.Elapsed.TotalSeconds
    # A child that is still closing when the gate exits gets two seconds to finish. A real leftover
    # is still running after that.
    $settle = [Diagnostics.Stopwatch]::StartNew()
    while (-not $timedOut -and (Get-JobActiveCount $Running.Job) -gt 0 -and $settle.Elapsed.TotalSeconds -lt 2) { Start-Sleep -Milliseconds 50 }
    $left = @(foreach ($id in (Get-JobProcessIds $Running.Job)) {
            $process = Get-Process -Id $id -ErrorAction SilentlyContinue
            $command = (Get-CimInstance Win32_Process -Filter "ProcessId = $id" -ErrorAction SilentlyContinue).CommandLine
            [pscustomobject]@{ Id = $id; Name = $(if ($process) { $process.ProcessName } else { '' }); CommandLine = [string]$command }
        })
    Assert-Win32 ([PilotJob]::Terminate($Running.Job)) 'TerminateJobObject'
    [void]$Running.Process.WaitForExit(10000)
    [void]$Running.Stdout.Wait(5000); [void]$Running.Stderr.Wait(5000)
    $outputPath = Join-Path $Running.Folder 'output.txt'
    $output = if (Test-Path -LiteralPath $outputPath) { [IO.File]::ReadAllText($outputPath) } else { '' }
    $secondsPath = Join-Path $Running.Folder 'seconds.txt'
    $seconds = if (Test-Path -LiteralPath $secondsPath) { [double]::Parse((Get-Content -LiteralPath $secondsPath -Raw).Trim(), [Globalization.CultureInfo]::InvariantCulture) } else { $null }
    $exitCode = if ($timedOut) { $null } else { $Running.Process.ExitCode }
    $cases = Read-PilotCaseLines $output
    $reasons = [Collections.Generic.List[string]]::new()
    if ($timedOut) { $reasons.Add("timed out after $([Math]::Round($waited, 1)) seconds") }
    elseif ($exitCode -ne 0) { $reasons.Add("exited $exitCode") }
    if (-not $timedOut -and $left.Count -gt 0) { $reasons.Add("left $($left.Count) process(es) in its job") }
    if ($cases.Fails.Count -gt 0) { $reasons.Add("printed $($cases.Fails.Count) FAIL line(s)") }
    if ($cases.Passes.Count -eq 0) { $reasons.Add('printed no PASS line') }
    if ($cases.Unfinished.Count -gt 0) { $reasons.Add("left $($cases.Unfinished.Count) case(s) without a result") }
    [pscustomobject]@{
        Name = $Running.Suite.name; BudgetSeconds = [double]$Running.Suite.budgetSeconds
        ExitCode = $exitCode; TimedOut = $timedOut; Seconds = $seconds; WaitedSeconds = [Math]::Round($waited, 2)
        LeftProcesses = $left; Starts = $cases.Starts; Passes = $cases.Passes; Fails = $cases.Fails
        Unfinished = $cases.Unfinished; Clean = ($reasons.Count -eq 0); Reasons = @($reasons)
        GateOutput = ($Running.Stdout.Result + $Running.Stderr.Result).Trim()
        Output = $output; Job = $Running.Job
    }
}

# The one trial runner. It runs the given Suites, three at a time, longest budget first, or with
# -Sequential one at a time in the given order. Then it proves that every job is empty and removes
# the trial folder before it returns.
function Invoke-PilotTrial {
    param([string] $Label, [string] $Path, [object[]] $Suites, [hashtable] $Extra = @{}, [switch] $Sequential)
    $script:TrialNumber++
    $trialFolder = Join-Path ([IO.Path]::GetTempPath()) ('p193-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force $trialFolder | Out-Null
    $queue = [Collections.Generic.Queue[object]]::new()
    $number = 0
    $parallel = if ($Sequential) { 1 } else { $script:Parallel }
    $order = if ($Sequential) { @($Suites) } else { @($Suites | Sort-Object -Property @{ Expression = { [double]$_.budgetSeconds }; Descending = $true } -Stable) }
    foreach ($suite in $order) {
        $number++
        $queue.Enqueue([pscustomobject]@{ Number = $number; Suite = $suite })
    }
    $running = [Collections.Generic.List[object]]::new()
    $results = [Collections.Generic.List[object]]::new()
    $jobs = [Collections.Generic.List[IntPtr]]::new()
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        while ($queue.Count -gt 0 -or $running.Count -gt 0) {
            while ($queue.Count -gt 0 -and $running.Count -lt $parallel) {
                $next = $queue.Dequeue()
                $started = Start-PilotSuite $trialFolder $next.Number $next.Suite $Path
                $jobs.Add($started.Job)
                $running.Add($started)
            }
            foreach ($item in @($running)) {
                if ($item.Process.HasExited -or $item.Watch.Elapsed.TotalSeconds -gt $item.Limit) {
                    $results.Add((Stop-PilotSuite $item))
                    [void]$running.Remove($item)
                }
            }
            Start-Sleep -Milliseconds 50
        }
    }
    finally {
        foreach ($item in $running) { [void][PilotJob]::Terminate($item.Job) }
        $cleanup = [Diagnostics.Stopwatch]::StartNew()
        $busy = @($jobs)
        while ($busy.Count -gt 0 -and $cleanup.Elapsed.TotalSeconds -lt 10) {
            $busy = @($busy | Where-Object { (Get-JobActiveCount $_) -gt 0 })
            if ($busy.Count -gt 0) { Start-Sleep -Milliseconds 100 }
        }
        foreach ($job in $jobs) { [void][PilotJob]::Close($job) }
        if ($busy.Count -gt 0) { throw "Trial $Label cleanup failed: $($busy.Count) job(s) still hold running processes." }
        $removed = $false
        $cleanup.Restart()
        while (-not $removed -and $cleanup.Elapsed.TotalSeconds -lt 10) {
            try { Remove-Item -LiteralPath $trialFolder -Recurse -Force; $removed = $true }
            catch { Start-Sleep -Milliseconds 200 }
        }
        if (-not $removed) { throw "Trial $Label cleanup failed: the trial folder $trialFolder could not be removed." }
    }
    $base = '{0:D2}-{1}' -f $script:TrialNumber, $Label
    $ordered = foreach ($suite in $Suites) { $results | Where-Object { $_.Name -eq $suite.name } | Select-Object -First 1 }
    $suiteRecords = foreach ($result in $ordered) {
        Set-Content -LiteralPath (Join-Path $OutDir "$base.$($result.Name).log") -Value $result.Output
        $result | Select-Object -Property * -ExcludeProperty Output, Job
    }
    $trial = [ordered]@{
        Label = $Label; Mode = $Mode; Side = $Side; Commit = $Commit; Checkout = $Path
        Seconds = [Math]::Round($watch.Elapsed.TotalSeconds, 2)
        Clean = (@($ordered | Where-Object { -not $_.Clean }).Count -eq 0)
        Suites = @($suiteRecords)
    }
    foreach ($key in $Extra.Keys) { $trial[$key] = $Extra[$key] }
    $trial | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutDir "$base.json")
    foreach ($result in $ordered) {
        $state = if ($result.Clean) { 'clean' } else { 'NOT CLEAN: ' + ($result.Reasons -join '; ') }
        Write-Host ("  {0,-38} {1}" -f $result.Name, $state)
    }
    [pscustomobject]$trial
}

function Initialize-OutDir {
    if ([string]::IsNullOrWhiteSpace($OutDir)) { throw 'Refused: -OutDir is required for this mode.' }
    if ((Test-Path -LiteralPath $OutDir) -and @(Get-ChildItem -LiteralPath $OutDir -Force).Count -gt 0) {
        throw "Refused: $OutDir is not empty. Give each run its own folder."
    }
    New-Item -ItemType Directory -Force $OutDir | Out-Null
    $script:OutDir = (Resolve-Path -LiteralPath $OutDir).Path
}

function Get-PassKey {
    param($Trial)
    $keys = foreach ($suite in $Trial.Suites) { $suite.Name + ': ' + ((@($suite.Passes) | Sort-Object) -join ' | ') }
    $keys -join "`n"
}

function Select-PilotDefects {
    param($Data)
    $all = @($Data.defects)
    if (-not $DefectId) { return $all }
    foreach ($id in $DefectId) { if (-not ($all | Where-Object { $_.id -eq $id })) { throw "No defect named $id in the inputs file." } }
    @($all | Where-Object { $_.id -in $DefectId })
}

function Assert-Side { if (-not $Side) { throw "Refused: -Side is required for -Mode $Mode." } }

# Reads a side's expected cases: the trial file of its clean opening control.
function Read-PilotExpectedCases {
    param([string] $Path, [string] $Name)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Refused: $Name must name the trial file of a clean opening control." }
    $trial = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($trial.Clean -ne $true) { throw "Refused: $Name names a control run that is not clean." }
    $trial
}

# The contention check. A child with no Lane variable starts a run on the real pool through this
# worktree's module, then ends it. The run start prints the sharing line when another registered
# run exists. Half exists in the module before and after the refactor.
function Test-PilotContention {
    $q = { param($s) "'" + $s.Replace("'", "''") + "'" }
    $module = Join-Path $script:RepoRoot 'scripts\test-lanes.common.ps1'
    $command = ". $(& $q $module); `$state = Enter-AhkFlowLaneRun -Mode PilotCheck -Checkout $(& $q $script:RepoRoot) -Share Half; Exit-AhkFlowLaneRun -State `$state"
    $info = [Diagnostics.ProcessStartInfo]::new($script:Pwsh)
    foreach ($argument in @('-NoProfile', '-Command', $command)) { $info.ArgumentList.Add($argument) }
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($name in $script:LaneVariables) { [void]$info.Environment.Remove($name) }
    $process = [Diagnostics.Process]::Start($info)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(10000)) {
            $process.Kill($true); [void]$process.WaitForExit(5000)
            return [pscustomobject]@{ Passed = $false; Reason = 'the contention check ran past 10 seconds' }
        }
        $process.WaitForExit()
        $output = $stdout.Result + $stderr.Result
        if ($process.ExitCode -ne 0) { return [pscustomobject]@{ Passed = $false; Reason = "the contention check exited $($process.ExitCode): $($output.Trim())" } }
        if ($output -match '(?m)^Sharing the test Lane pool with:') { return [pscustomobject]@{ Passed = $false; Reason = 'another registered test run shares the real Lane pool' } }
        [pscustomobject]@{ Passed = $true; Reason = '' }
    }
    finally { $process.Dispose() }
}

$data = Read-PilotInputs
$suites = @($data.suites)

switch ($Mode) {
    'Verify' {
        Assert-Side
        $path = Assert-PilotCheckout $Checkout
        Assert-PilotCommit $path $Commit
        $problems = @(foreach ($defect in (Select-PilotDefects $data)) {
                if ((Get-PilotPatch $defect $Side).Count -eq 0) { "Defect $($defect.id) has no $Side patch." }
                (Get-PilotPatchResult $path $defect $Side).Problems
            })
        if ($problems.Count -gt 0) { throw ("Verify failed:`n" + ($problems -join "`n")) }
        Write-Host "Verify: every $Side edit of $(@(Select-PilotDefects $data).Count) defect(s) is found exactly once."
    }
    'SuiteSet' {
        Initialize-OutDir
        Reset-PilotCheckout $Checkout $Commit
        $trial = Invoke-PilotTrial 'suiteset' (Assert-PilotCheckout $Checkout) $suites
        if (-not $trial.Clean) { Write-Host 'SuiteSet: not clean.'; exit 2 }
        Write-Host 'SuiteSet: clean.'
    }
    'Attempt' {
        Assert-Side
        Initialize-OutDir
        $defects = Select-PilotDefects $data
        $attempt = [ordered]@{ Side = $Side; Commit = $Commit; Checkout = $null; Status = $null; Reasons = @(); Defects = @() }
        $attemptPath = Join-Path $script:OutDir 'attempt.json'
        Reset-PilotCheckout $Checkout $Commit
        $path = Assert-PilotCheckout $Checkout
        $attempt.Checkout = $path
        $opening = Invoke-PilotTrial 'opening-control' $path $suites
        if (-not $opening.Clean) {
            $attempt.Status = 'opening control failed'
            $attempt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $attemptPath
            Write-Host "Attempt: $($attempt.Status)."
            exit 2
        }
        $records = [Collections.Generic.List[object]]::new()
        foreach ($defect in $defects) {
            Reset-PilotCheckout $path $Commit
            $patch = Get-PilotPatchResult $path $defect $Side
            if ($patch.Problems.Count -gt 0) { throw ("Defect $($defect.id) does not apply:`n" + ($patch.Problems -join "`n")) }
            if ($patch.Files.Count -eq 0) { throw "Defect $($defect.id) has no $Side patch." }
            $saved = foreach ($file in $patch.Files.Keys) { [pscustomobject]@{ Path = $file; Bytes = $patch.Files[$file].Old; Sha256 = (Get-Sha256 $patch.Files[$file].Old) } }
            $restored = $false
            try {
                foreach ($file in $patch.Files.Keys) { [IO.File]::WriteAllBytes($file, $patch.Files[$file].New) }
                Write-Host "Defect $($defect.id):"
                $trial = Invoke-PilotTrial "defect-$($defect.id)" $path $suites @{ DefectId = $defect.id }
            }
            finally {
                foreach ($file in $saved) { [IO.File]::WriteAllBytes($file.Path, $file.Bytes) }
                $restored = @($saved | Where-Object { (Get-Sha256 ([IO.File]::ReadAllBytes($_.Path))) -ne $_.Sha256 }).Count -eq 0
                if (-not $restored) { throw "Defect $($defect.id): a patched file does not match its saved hash after the restore." }
            }
            $records.Add([pscustomobject]@{
                    Id = $defect.id; Clean = $trial.Clean; Restored = $restored
                    Files = @($saved | ForEach-Object { [pscustomobject]@{ Path = $_.Path; Sha256 = $_.Sha256 } })
                })
        }
        $attempt.Defects = @($records)
        Reset-PilotCheckout $path $Commit
        $closing = Invoke-PilotTrial 'closing-control' $path $suites
        $reasons = [Collections.Generic.List[string]]::new()
        if (-not $closing.Clean) { $reasons.Add('a Suite of the closing control is not clean') }
        if ((Get-PassKey $closing) -cne (Get-PassKey $opening)) { $reasons.Add('the closing control PASS names differ from the opening control') }
        $attempt.Reasons = @($reasons)
        $attempt.Status = if ($reasons.Count -eq 0) { 'clean' } else { 'closing control failed' }
        $attempt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $attemptPath
        Write-Host "Attempt: $($attempt.Status)."
        if ($attempt.Status -ne 'clean') { exit 2 }
    }
    'Timing' {
        Initialize-OutDir
        $sides = @{
            A = [pscustomobject]@{ Name = 'Before'; Path = (Assert-PilotCheckout $BeforeCheckout); Commit = $BeforeCommit; Expected = (Read-PilotExpectedCases $BeforeCases '-BeforeCases') }
            B = [pscustomobject]@{ Name = 'After'; Path = (Assert-PilotCheckout $AfterCheckout); Commit = $AfterCommit; Expected = (Read-PilotExpectedCases $AfterCases '-AfterCases') }
        }
        $timing = [ordered]@{ Status = $null; Passes = @(); Rejected = @() }
        $timingPath = Join-Path $script:OutDir 'timing.json'
        $passes = [Collections.Generic.List[object]]::new()
        $rejected = [Collections.Generic.List[object]]::new()
        # A rejected pass runs again in the same position. Three replacements are allowed in all,
        # warm-up passes included, so the fourth rejection ends the timing.
        foreach ($position in @('warm-A', 'warm-B', '1-A', '2-B', '3-B', '4-A', '5-B', '6-A', '7-A', '8-B')) {
            $key = $position.Substring($position.Length - 1)
            $passSide = $sides[$key]
            $valid = $false
            while (-not $valid -and $rejected.Count -le 3) {
                Reset-PilotCheckout $passSide.Path $passSide.Commit
                $start = Test-PilotContention
                Write-Host "Pass ${position}:"
                $trial = Invoke-PilotTrial "pass-$position" $passSide.Path $suites @{ Position = $position; Side = $passSide.Name; Commit = $passSide.Commit } -Sequential
                $end = Test-PilotContention
                $reasons = [Collections.Generic.List[string]]::new()
                if (-not $start.Passed) { $reasons.Add("at the start, $($start.Reason)") }
                if (-not $end.Passed) { $reasons.Add("at the end, $($end.Reason)") }
                foreach ($suite in $trial.Suites) { if (-not $suite.Clean) { $reasons.Add("$($suite.Name) is not clean: $($suite.Reasons -join '; ')") } }
                if ((Get-PassKey $trial) -cne (Get-PassKey $passSide.Expected)) { $reasons.Add('the PASS names differ from the expected cases of its side') }
                $seconds = (@($trial.Suites | ForEach-Object { if ($null -ne $_.Seconds) { [double]$_.Seconds } else { 0 } }) | Measure-Object -Sum).Sum
                $record = [pscustomobject]@{
                    Position = $position; Side = $passSide.Name; Seconds = [Math]::Round($seconds, 2)
                    Suites = @($trial.Suites | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Seconds = $_.Seconds } })
                    Reasons = @($reasons)
                }
                if ($reasons.Count -eq 0) { $passes.Add($record); $valid = $true; Write-Host "Pass ${position}: $($record.Seconds) seconds." }
                else { $rejected.Add($record); Write-Host "Pass ${position} rejected: $($reasons -join '; ')" }
                $timing.Passes = @($passes); $timing.Rejected = @($rejected)
                $timing | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $timingPath
            }
            if (-not $valid) { break }
        }
        $timing.Status = if ($rejected.Count -gt 3) { 'inconclusive' } else { 'clean' }
        $timing | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $timingPath
        Write-Host "Timing: $($timing.Status)."
        if ($timing.Status -ne 'clean') { exit 2 }
    }
}
