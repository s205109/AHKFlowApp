#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('', 'holder', 'contender')][string] $ChildAction = '',
    [string[]] $LockPath = @(),
    [string] $LockPath2 = '',
    [string] $HostLabel = '',
    [switch] $SkipRunspace,
    [switch] $SkipWindowsPowerShellChild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not [string]::IsNullOrWhiteSpace($LockPath2)) { $LockPath += $LockPath2 }

function Open-NativeExclusiveFile([string] $Path) {
    [System.IO.File]::Open($Path, [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
}

function Get-ActualException([System.Exception] $Exception) {
    # PowerShell wraps static method failures. Stop at the exception returned by the native file
    # API: UnauthorizedAccessException can itself carry a lower-level IOException on Linux.
    while ($Exception.GetType().Namespace -eq 'System.Management.Automation' -and
        $null -ne $Exception.InnerException) {
        $Exception = $Exception.InnerException
    }
    $Exception
}

function Format-HResult([int] $Value) {
    $bits = [System.BitConverter]::ToUInt32([System.BitConverter]::GetBytes([int32] $Value), 0)
    '0x{0:X8}' -f $bits
}

function Get-OpenResult([string] $Case, [string] $Path) {
    $stream = $null
    try {
        $stream = Open-NativeExclusiveFile $Path
        [pscustomobject]@{ Case = $Case; Opened = $true; Type = ''; HResult = 0; Hex = '0x00000000' }
    } catch {
        $actual = Get-ActualException $_.Exception
        [pscustomobject]@{
            Case = $Case; Opened = $false; Type = $actual.GetType().FullName
            HResult = [int] $actual.HResult; Hex = Format-HResult $actual.HResult
        }
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Write-Evidence($Result) {
    Write-Output ('EVIDENCE|{0}|{1}|{2}|{3}' -f $Result.Case, $Result.Type, $Result.HResult, $Result.Hex)
}

# The child modes call the native API above directly. Holder streams stay rooted in this list.
if ($ChildAction -eq 'holder') {
    $held = New-Object System.Collections.Generic.List[System.IO.FileStream]
    try {
        foreach ($path in $LockPath) { $held.Add((Open-NativeExclusiveFile $path)) }
        [Console]::Out.WriteLine("READY|$($LockPath.Count)")
        [Console]::Out.Flush()
        while ($true) {
            $command = [Console]::In.ReadLine()
            if ($null -eq $command -or $command -eq 'RELEASE') { break }
        }
    } finally {
        foreach ($stream in $held) { $stream.Dispose() }
    }
    exit 0
}
if ($ChildAction -eq 'contender') {
    for ($i = 0; $i -lt $LockPath.Count; $i++) {
        Write-Evidence (Get-OpenResult "child-contention-$i" $LockPath[$i])
    }
    exit 0
}

$script:Failures = New-Object System.Collections.Generic.List[string]
$script:Children = New-Object System.Collections.Generic.List[object]
$script:SuitePath = $MyInvocation.MyCommand.Path
$script:HostExe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}
function Assert-Equal($Expected, $Actual, [string] $Message) {
    if ([string] $Expected -cne [string] $Actual) {
        throw "$Message (expected '$Expected', got '$Actual')"
    }
}
function Invoke-Case([string] $Name, [scriptblock] $Body) {
    try {
        & $Body
        Write-Host "  PASS  $Name" -ForegroundColor Green
    } catch {
        $script:Failures.Add("$Name :: $($_.Exception.Message)")
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        Write-Host "        $($_.Exception.Message)" -ForegroundColor DarkRed
    }
}
function Quote-Argument([string] $Value) {
    '"' + $Value.Replace('"', '\"') + '"'
}

# Process output is drained as it arrives. This prevents a child from blocking on a full pipe.
function Start-Child([string] $Executable = $script:HostExe, [string[]] $Argument, [switch] $RedirectInput) {
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $Executable
    $info.Arguments = (($Argument | ForEach-Object { Quote-Argument $_ }) -join ' ')
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.RedirectStandardInput = [bool] $RedirectInput
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    if (-not $process.Start()) { throw "Failed to start $Executable" }
    # Begin both drains before waiting. A holder's first line is its acquisition gate.
    $readyTask = if ($RedirectInput) { $process.StandardOutput.ReadLineAsync() } else { $null }
    $stdoutTask = if ($RedirectInput) {
        [System.Threading.Tasks.Task[string]]::FromResult('')
    } else {
        $process.StandardOutput.ReadToEndAsync()
    }
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $child = [pscustomobject]@{
        Process = $process; ReadyTask = $readyTask; StdoutTask = $stdoutTask; StderrTask = $stderrTask
    }
    $script:Children.Add($child)
    $child
}
function Get-Stdout($Child) {
    $prefix = if ($null -ne $Child.ReadyTask -and $Child.ReadyTask.IsCompleted) { $Child.ReadyTask.Result + [Environment]::NewLine } else { '' }
    $suffix = if ($Child.StdoutTask.IsCompleted) { $Child.StdoutTask.Result } else { '' }
    $prefix + $suffix
}
function Get-Stderr($Child) {
    if ($Child.StderrTask.IsCompleted) { return $Child.StderrTask.Result }
    ''
}
function Wait-Exit($Child, [int] $Milliseconds = 10000) {
    if (-not $Child.Process.WaitForExit($Milliseconds)) {
        throw "Child $($Child.Process.Id) timed out. stdout: $(Get-Stdout $Child) stderr: $(Get-Stderr $Child)"
    }
    [void] $Child.StdoutTask.GetAwaiter().GetResult()
    [void] $Child.StderrTask.GetAwaiter().GetResult()
    $Child.Process.ExitCode
}
function Wait-Ready($Child) {
    if (-not $Child.ReadyTask.Wait(10000)) {
        throw "Holder did not acknowledge acquisition. stderr: $(Get-Stderr $Child)"
    }
    if ($Child.ReadyTask.Result -cne 'READY|2') {
        throw "Holder exited before acquisition acknowledgement. stdout: $(Get-Stdout $Child) stderr: $(Get-Stderr $Child)"
    }
}
function Start-Holder([string[]] $Path) {
    $args = @('-NoProfile', '-File', $script:SuitePath, '-ChildAction', 'holder',
        '-LockPath', $Path[0], '-LockPath2', $Path[1])
    $child = Start-Child -Argument $args -RedirectInput
    Wait-Ready $child
    $child
}
function Stop-Children {
    $cleanupErrors = New-Object System.Collections.Generic.List[string]
    foreach ($child in $script:Children) {
        $process = $child.Process
        $childId = $process.Id
        try {
            if (-not $process.HasExited) {
                if ($PSVersionTable.PSEdition -eq 'Core') {
                    $process.Kill($true)
                } elseif ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
                    & taskkill.exe /PID $process.Id /T /F *> $null
                } else {
                    $process.Kill()
                }
            }
        } catch {
            $cleanupErrors.Add("Child $childId termination failed: $($_.Exception.Message)")
        }
        try {
            if (-not $process.WaitForExit(5000)) {
                $cleanupErrors.Add("Child $childId survived the cleanup deadline.")
                continue
            }
            if (-not $child.StdoutTask.Wait(5000)) {
                $cleanupErrors.Add("Child $childId stdout reader did not settle.")
            }
            if (-not $child.StderrTask.Wait(5000)) {
                $cleanupErrors.Add("Child $childId stderr reader did not settle.")
            }
            if ($null -ne $child.ReadyTask -and -not $child.ReadyTask.Wait(5000)) {
                $cleanupErrors.Add("Child $childId acknowledgement reader did not settle.")
            }
        } catch {
            $cleanupErrors.Add("Child $childId reap failed: $($_.Exception.Message)")
        } finally {
            if ($process.HasExited) {
                try { $process.Dispose() } catch {
                    $cleanupErrors.Add("Child $childId dispose failed: $($_.Exception.Message)")
                }
            }
        }
    }
    $script:Children.Clear()
    if ($cleanupErrors.Count -gt 0) { throw ($cleanupErrors -join [Environment]::NewLine) }
    Write-Host 'OUTCOME|cleanup|all-children-reaped-readers-settled'
}
function Get-Filesystem([string] $Path) {
    if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
        return ([System.IO.DriveInfo]::new([System.IO.Path]::GetPathRoot($Path))).DriveFormat
    }
    try {
        $name = & findmnt -T $Path -n -o FSTYPE 2>$null | Select-Object -First 1
        if (-not [string]::IsNullOrWhiteSpace($name)) { return $name.Trim() }
    } catch { }
    'unknown'
}
function Assert-Contention($Expected, $Actual, [string] $Case) {
    Assert-True (-not $Actual.Opened) "$Case unexpectedly opened the held file."
    Assert-Equal $Expected.Type $Actual.Type "$Case exception type differed from process contention."
    Assert-Equal $Expected.HResult $Actual.HResult "$Case HResult differed from process contention."
    Write-Evidence ([pscustomobject]@{
            Case = $Case; Type = $Actual.Type; HResult = $Actual.HResult; Hex = $Actual.Hex
        })
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-lane-primitive-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
$paths = @((Join-Path $tempRoot 'lane-0.lock'), (Join-Path $tempRoot 'entry.lock'))
if ([string]::IsNullOrWhiteSpace($HostLabel)) { $HostLabel = "$($PSVersionTable.PSEdition) host" }
$runtime = try { [System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription } catch { [Environment]::Version.ToString() }
$os = try { [System.Runtime.InteropServices.RuntimeInformation]::OSDescription } catch { [Environment]::OSVersion.VersionString }
Write-Host "HOST|$HostLabel"
Write-Host "PowerShell|$($PSVersionTable.PSVersion)"
Write-Host "Runtime|$runtime"
Write-Host "OS|$os"
Write-Host "LocalApplicationData|$([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData))"
Write-Host "TempRoot|$tempRoot"
Write-Host "Filesystem|$(Get-Filesystem $tempRoot)"
if (-not [string]::IsNullOrWhiteSpace($env:ImageOS)) { Write-Host "RunnerImage|$($env:ImageOS)" }
if (-not [string]::IsNullOrWhiteSpace($env:ImageVersion)) { Write-Host "RunnerImageVersion|$($env:ImageVersion)" }

try {
    $holder = Start-Holder $paths
    Invoke-Case 'Another process cannot open a held Lane or entry lock' {
        $args = @('-NoProfile', '-File', $script:SuitePath, '-ChildAction', 'contender',
            '-LockPath', $paths[0], '-LockPath2', $paths[1])
        $contender = Start-Child -Argument $args
        Assert-Equal 0 (Wait-Exit $contender) "Contender failed. stderr: $(Get-Stderr $contender)"
        $lines = @((Get-Stdout $contender) -split '\r?\n' | Where-Object { $_ -like 'EVIDENCE|*' })
        Assert-Equal 2 $lines.Count 'Contender must report both held files.'
        $script:CrossProcess = @()
        foreach ($line in $lines) {
            $parts = $line.Split('|')
            $script:CrossProcess += [pscustomobject]@{
                Opened = $false; Type = $parts[2]; HResult = [int] $parts[3]; Hex = $parts[4]
            }
            Write-Host $line
        }
        foreach ($observation in $script:CrossProcess) {
            Assert-True (-not [string]::IsNullOrWhiteSpace($observation.Type)) 'Each held file must refuse the contender.'
            Assert-True ($observation.Type -like 'System.IO.*Exception') 'Contention must expose the base System.IO exception.'
        }
    }

    Invoke-Case 'Explicit release frees both files' {
        $holder.Process.StandardInput.WriteLine('RELEASE')
        $holder.Process.StandardInput.Flush()
        Assert-Equal 0 (Wait-Exit $holder) "Holder release failed. stderr: $(Get-Stderr $holder)"
        foreach ($path in $paths) { Assert-True (Get-OpenResult 'after-release' $path).Opened "Open failed after release: $path" }
        Write-Host 'OUTCOME|explicit-release|both-files-opened'
    }

    Invoke-Case 'Holder stdin EOF releases both files' {
        $eofHolder = Start-Holder $paths
        $eofHolder.Process.StandardInput.Close()
        Assert-Equal 0 (Wait-Exit $eofHolder) "Holder did not exit on stdin EOF. stderr: $(Get-Stderr $eofHolder)"
        foreach ($path in $paths) { Assert-True (Get-OpenResult 'after-stdin-eof' $path).Opened "Open failed after stdin EOF: $path" }
        Write-Host 'OUTCOME|stdin-eof|both-files-opened'
    }

    # These handles belong to this process. The second-handle and runspace cases therefore prove
    # same-process sharing enforcement independently of the child-process holder above.
    $parentHeld = New-Object System.Collections.Generic.List[System.IO.FileStream]
    try {
        foreach ($path in $paths) { $parentHeld.Add((Open-NativeExclusiveFile $path)) }
        Invoke-Case 'A second handle in the same process is refused' {
            for ($i = 0; $i -lt 2; $i++) {
                Assert-Contention $script:CrossProcess[$i] (Get-OpenResult "same-process-$i" $paths[$i]) "same-process-$i"
            }
        }
        if (-not $SkipRunspace -and $PSVersionTable.PSVersion.Major -ge 7) {
            Invoke-Case 'Another runspace is refused' {
            $code = {
                param([string[]] $Paths)
                foreach ($path in $Paths) {
                    $stream = $null
                    try {
                        $stream = [System.IO.File]::Open($path, 'OpenOrCreate', 'ReadWrite', 'None')
                        [pscustomobject]@{ Opened = $true; Type = ''; HResult = 0 }
                    } catch {
                        $e = $_.Exception
                        while ($e.GetType().Namespace -eq 'System.Management.Automation' -and
                            $null -ne $e.InnerException) { $e = $e.InnerException }
                        [pscustomobject]@{ Opened = $false; Type = $e.GetType().FullName; HResult = [int] $e.HResult }
                    } finally { if ($null -ne $stream) { $stream.Dispose() } }
                }
            }
            $powerShell = [powershell]::Create().AddScript($code).AddArgument($paths)
            try {
                $async = $powerShell.BeginInvoke()
                Assert-True ($async.AsyncWaitHandle.WaitOne(10000)) 'Runspace timed out.'
                $seen = @($powerShell.EndInvoke($async))
                Assert-Equal 2 $seen.Count 'Runspace must report both held files.'
                for ($i = 0; $i -lt 2; $i++) {
                    $actual = [pscustomobject]@{
                        Opened = $seen[$i].Opened; Type = $seen[$i].Type
                        HResult = $seen[$i].HResult; Hex = Format-HResult $seen[$i].HResult
                    }
                    Assert-Contention $script:CrossProcess[$i] $actual "runspace-contention-$i"
                }
            } finally {
                $powerShell.Stop()
                $powerShell.Dispose()
            }
            }
        } else { Write-Host "SKIP|runspace-contention|$HostLabel" }
    } finally {
        foreach ($stream in $parentHeld) { $stream.Dispose() }
    }
    Invoke-Case 'Killing a holder frees both files' {
        $killed = Start-Holder $paths
        $killed.Process.Kill()
        [void] (Wait-Exit $killed)
        foreach ($path in $paths) { Assert-True (Get-OpenResult 'after-kill' $path).Opened "Open failed after kill: $path" }
        Write-Host 'OUTCOME|forced-kill|both-files-opened'
    }
    Invoke-Case 'Missing parent differs from contention' {
        $missing = Get-OpenResult 'missing-parent' (Join-Path (Join-Path $tempRoot 'missing') 'lock')
        Assert-Equal 'System.IO.DirectoryNotFoundException' $missing.Type 'Missing-parent type must remain specific.'
        Assert-True (($missing.Type -cne $script:CrossProcess[0].Type) -or ($missing.HResult -ne $script:CrossProcess[0].HResult)) 'Missing parent matched contention.'
        Write-Evidence $missing
    }
    Invoke-Case 'Generic injected IOException differs from contention' {
        try { throw [System.IO.IOException]::new('injected unknown I/O failure') } catch {
            $e = Get-ActualException $_.Exception
            $generic = [pscustomobject]@{
                Case = 'generic-injected-io'; Type = $e.GetType().FullName
                HResult = [int] $e.HResult; Hex = Format-HResult $e.HResult
            }
        }
        Assert-Equal 'System.IO.IOException' $generic.Type 'Injected type changed.'
        Assert-True ($generic.HResult -ne $script:CrossProcess[0].HResult) 'Generic IOException matched contention.'
        Write-Evidence $generic
    }
    Invoke-Case 'Access denied differs from contention' {
        $directory = Join-Path $tempRoot 'directory-as-file'
        New-Item -ItemType Directory -Path $directory | Out-Null
        $denied = Get-OpenResult 'access-denied' $directory
        Assert-Equal 'System.UnauthorizedAccessException' $denied.Type 'Opening a directory must expose access denied on this host.'
        Assert-True ($denied.HResult -ne $script:CrossProcess[0].HResult) 'Access denied matched contention.'
        Write-Evidence $denied
    }
    if (-not $SkipWindowsPowerShellChild -and $PSVersionTable.PSEdition -eq 'Core' -and
        [System.IO.Path]::DirectorySeparatorChar -eq '\') {
        Invoke-Case 'Windows PowerShell 5.1 repeats native cases' {
            $legacy = (Get-Command powershell.exe -ErrorAction Stop).Source
            $child = Start-Child -Executable $legacy -Argument @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:SuitePath,
                '-HostLabel', 'Windows PowerShell 5.1 child', '-SkipRunspace', '-SkipWindowsPowerShellChild')
            $exitCode = Wait-Exit $child 30000
            Write-Host (Get-Stdout $child).TrimEnd()
            $legacyError = Get-Stderr $child
            if ($legacyError.Length -gt 0) { Write-Host $legacyError.TrimEnd() }
            Assert-Equal 0 $exitCode 'Windows PowerShell 5.1 proof failed.'
        }
    }
} finally {
    $cleanupFailure = $null
    try { Stop-Children } catch { $cleanupFailure = $_ }
    if ($null -eq $cleanupFailure) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction Stop
    } else {
        Write-Host "CLEANUP-FAILED|fixture-retained|$tempRoot" -ForegroundColor Red
        throw $cleanupFailure
    }
}

if ($script:Failures.Count -gt 0) {
    Write-Host "FAILED|$HostLabel|$($script:Failures.Count) case(s)" -ForegroundColor Red
    foreach ($failure in $script:Failures) { Write-Host "  $failure" -ForegroundColor Red }
    exit 1
}
Write-Host "PASSED|$HostLabel|native Lane file-lock primitive"
exit 0
