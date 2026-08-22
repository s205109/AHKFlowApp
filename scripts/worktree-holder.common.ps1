#Requires -Version 5.1
# Finds the processes that stop a worktree folder from being renamed.
#
# There are two kinds of holder and neither query finds the other:
#
#   * A process with the folder as its CURRENT DIRECTORY. This is what
#     `claude --worktree <name>` does. It has no open file, so a handle query sees nothing.
#   * A process with an OPEN FILE below the folder. An editor is the usual case. Its executable
#     and its current directory are both somewhere else, so a current-directory query sees
#     nothing.
#
# So three layers run and their results are MERGED, not short-circuited. Stopping at the first
# match would hide the second holder, and the human would close one window and try again.
#
# Every layer is wrapped: its own failure removes only its own results. Layer 3 fails with
# access denied for a process at a higher integrity level than the caller, which is normal.

$script:HolderCwdTypeAdded = $false
$script:HolderRmTypeAdded = $false

function Add-HolderCwdType {
    if ($script:HolderCwdTypeAdded) { return $true }
    try {
        Add-Type -Namespace AhkFlow -Name Peb -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)]
public struct PROCESS_BASIC_INFORMATION {
    public IntPtr Reserved1;
    public IntPtr PebBaseAddress;
    public IntPtr Reserved2_0;
    public IntPtr Reserved2_1;
    public IntPtr UniqueProcessId;
    public IntPtr Reserved3;
}

[DllImport("ntdll.dll")]
public static extern int NtQueryInformationProcess(IntPtr h, int c, ref PROCESS_BASIC_INFORMATION i, int l, ref int r);

[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr OpenProcess(int access, bool inherit, int pid);

[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, int size, ref IntPtr read);

[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool CloseHandle(IntPtr h);
'@ -ErrorAction Stop
        $script:HolderCwdTypeAdded = $true
        return $true
    } catch {
        return $false
    }
}

function Add-HolderRestartManagerType {
    if ($script:HolderRmTypeAdded) { return $true }
    try {
        Add-Type -Namespace AhkFlow -Name Rm -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)]
public struct RM_UNIQUE_PROCESS { public int dwProcessId; public System.Runtime.InteropServices.ComTypes.FILETIME ProcessStartTime; }

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct RM_PROCESS_INFO {
    public RM_UNIQUE_PROCESS Process;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string strAppName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]  public string strServiceShortName;
    public int ApplicationType;
    public uint AppStatus;
    public uint TSSessionId;
    [MarshalAs(UnmanagedType.Bool)] public bool bRestartable;
}

[DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
public static extern int RmStartSession(out uint session, int flags, System.Text.StringBuilder key);

[DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
public static extern int RmRegisterResources(uint session, uint nFiles, string[] files,
    uint nApps, RM_UNIQUE_PROCESS[] apps, uint nServices, string[] services);

[DllImport("rstrtmgr.dll")]
public static extern int RmGetList(uint session, out uint needed, ref uint count,
    [In, Out] RM_PROCESS_INFO[] info, ref uint reason);

[DllImport("rstrtmgr.dll")]
public static extern int RmEndSession(uint session);
'@ -ErrorAction Stop
        $script:HolderRmTypeAdded = $true
        return $true
    } catch {
        return $false
    }
}

# Layer 1. Cheap, no P/Invoke, and it catches a running API, UI, or test host started from the
# worktree.
function Get-HolderByExecutablePath {
    param([string] $Prefix)

    $found = @()
    foreach ($process in (Get-Process -ErrorAction SilentlyContinue)) {
        # Never write `continue` inside a try block. In PowerShell it escapes the try, skips the
        # loop that contains it, and continues a loop in the CALLER instead. Read the value in
        # the try, and decide after it.
        $path = $null
        try {
            $path = $process.Path
        } catch {
            $path = $null  # Access denied reading the path is normal and not worth reporting.
        }
        if ($path -and $path.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $found += [pscustomobject]@{
                ProcessId = $process.Id; Name = $process.ProcessName; Path = $path; Layer = 'executable'
            }
        }
    }
    # Return the holders plainly, never as `, $found`. That wrapper is meant to keep a single
    # holder an array, but it survives only one level of enumeration: called through `& { ... }`
    # it arrives as one item that IS the array, and every caller then reads it as one holder.
    # Callers wrap with @() instead, which is correct for none, one, and many.
    return $found
}

# Layer 2. Restart Manager names processes holding an OPEN FILE. It never sees a
# current-directory hold, which is why layer 3 exists as well as this one.
function Get-HolderByOpenFile {
    param([string] $Root)

    if (-not (Add-HolderRestartManagerType)) { return @() }

    $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction SilentlyContinue |
        Select-Object -First 500 -ExpandProperty FullName)
    if ($files.Count -eq 0) { return @() }

    $session = [uint32] 0
    $key = New-Object System.Text.StringBuilder 256
    if ([AhkFlow.Rm]::RmStartSession([ref] $session, 0, $key) -ne 0) { return @() }

    try {
        $rc = [AhkFlow.Rm]::RmRegisterResources($session, [uint32] $files.Count, $files, 0, $null, 0, $null)
        if ($rc -ne 0) { return @() }

        $needed = [uint32] 0
        $count = [uint32] 0
        $reason = [uint32] 0
        $null = [AhkFlow.Rm]::RmGetList($session, [ref] $needed, [ref] $count, $null, [ref] $reason)
        if ($needed -eq 0) { return @() }

        $count = $needed
        $info = New-Object 'AhkFlow.Rm+RM_PROCESS_INFO[]' $needed
        if ([AhkFlow.Rm]::RmGetList($session, [ref] $needed, [ref] $count, $info, [ref] $reason) -ne 0) {
            return @()
        }

        $found = @()
        for ($i = 0; $i -lt $count; $i++) {
            # Never name this $pid: it is a read-only automatic variable, and assigning to it
            # throws "Cannot overwrite variable PID because it is read-only or constant."
            $holderPid = $info[$i].Process.dwProcessId
            $name = $info[$i].strAppName
            $path = ''
            try { $path = (Get-Process -Id $holderPid -ErrorAction Stop).Path } catch { }
            $found += [pscustomobject]@{ ProcessId = $holderPid; Name = $name; Path = $path; Layer = 'open file' }
        }
        return $found
    } finally {
        $null = [AhkFlow.Rm]::RmEndSession($session)
    }
}

# Reads one process's current directory out of its PEB. Returns '' when it cannot be read, which
# is normal for a process running at a higher integrity level than this one.
#
# This is a function of its own so that the loop in layer 3 never needs `continue` inside a try
# block. In PowerShell such a `continue` escapes the try, skips the loop that contains it, and
# continues a loop in the CALLER instead. That silently dropped every later process and every
# later layer. `return` inside a try is safe, and runs the finally as expected.
function Get-ProcessCurrentDirectory {
    param([Parameter(Mandatory)][int] $ProcessId)

    if (-not (Add-HolderCwdType)) { return '' }

    $handle = [IntPtr]::Zero
    try {
        # PROCESS_QUERY_INFORMATION | PROCESS_VM_READ
        $handle = [AhkFlow.Peb]::OpenProcess(0x0410, $false, $ProcessId)
        if ($handle -eq [IntPtr]::Zero) { return '' }

        $info = New-Object AhkFlow.Peb+PROCESS_BASIC_INFORMATION
        $returned = 0
        if ([AhkFlow.Peb]::NtQueryInformationProcess($handle, 0, [ref] $info, [System.Runtime.InteropServices.Marshal]::SizeOf($info), [ref] $returned) -ne 0) {
            return ''
        }

        # PEB -> ProcessParameters (offset 0x20 on x64) -> CurrentDirectory.DosPath
        # UNICODE_STRING at offset 0x38: Length (ushort), MaximumLength (ushort), Buffer (ptr at 0x40).
        $pointerBuffer = New-Object byte[] 8
        $read = [IntPtr]::Zero
        if (-not [AhkFlow.Peb]::ReadProcessMemory($handle, [IntPtr]::Add($info.PebBaseAddress, 0x20), $pointerBuffer, 8, [ref] $read)) { return '' }
        $parameters = [IntPtr][System.BitConverter]::ToInt64($pointerBuffer, 0)
        if ($parameters -eq [IntPtr]::Zero) { return '' }

        $lengthBuffer = New-Object byte[] 2
        if (-not [AhkFlow.Peb]::ReadProcessMemory($handle, [IntPtr]::Add($parameters, 0x38), $lengthBuffer, 2, [ref] $read)) { return '' }
        $length = [System.BitConverter]::ToUInt16($lengthBuffer, 0)
        if ($length -le 0 -or $length -gt 1024) { return '' }

        if (-not [AhkFlow.Peb]::ReadProcessMemory($handle, [IntPtr]::Add($parameters, 0x40), $pointerBuffer, 8, [ref] $read)) { return '' }
        $bufferAddress = [IntPtr][System.BitConverter]::ToInt64($pointerBuffer, 0)
        if ($bufferAddress -eq [IntPtr]::Zero) { return '' }

        $text = New-Object byte[] $length
        if (-not [AhkFlow.Peb]::ReadProcessMemory($handle, $bufferAddress, $text, $length, [ref] $read)) { return '' }
        return [System.Text.Encoding]::Unicode.GetString($text)
    } catch {
        return ''
    } finally {
        if ($handle -ne [IntPtr]::Zero) { $null = [AhkFlow.Peb]::CloseHandle($handle) }
    }
}

# Layer 3. The current-directory holder, read out of each process's PEB. This is the one that
# finds claude.exe.
function Get-HolderByCurrentDirectory {
    param([string] $Root)

    if (-not (Add-HolderCwdType)) { return @() }

    # The folder itself, or anything below it. Matching on the bare root would also match a
    # sibling that starts with the same text: every worktree lives in one parent folder, so
    # wt-feature-extra would be reported as holding wt-feature. A process's current directory
    # may or may not carry a trailing separator, so both readings of the folder itself count.
    $root = $Root.TrimEnd('\', '/')
    $prefix = $root + [System.IO.Path]::DirectorySeparatorChar

    $found = @()
    foreach ($process in (Get-Process -ErrorAction SilentlyContinue)) {
        $currentDirectory = Get-ProcessCurrentDirectory -ProcessId $process.Id
        if (-not $currentDirectory) { continue }
        $trimmed = $currentDirectory.TrimEnd('\', '/')
        $isHolder = [string]::Equals($trimmed, $root, [System.StringComparison]::OrdinalIgnoreCase) -or
            $currentDirectory.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
        if (-not $isHolder) { continue }

        $path = ''
        try { $path = $process.Path } catch { $path = '' }
        $found += [pscustomobject]@{
            ProcessId = $process.Id; Name = $process.ProcessName; Path = $path; Layer = 'current directory'
        }
    }
    # Return the holders plainly, never as `, $found`. That wrapper is meant to keep a single
    # holder an array, but it survives only one level of enumeration: called through `& { ... }`
    # it arrives as one item that IS the array, and every caller then reads it as one holder.
    # Callers wrap with @() instead, which is correct for none, one, and many.
    return $found
}

# The merged answer. Always returns an array, possibly empty: "no holder identified" is a real
# result and the caller must be able to say it rather than guess.
function Get-WorktreeFolderHolder {
    param([Parameter(Mandatory)][string] $Path)

    $full = ([System.IO.Path]::GetFullPath($Path)).TrimEnd('\', '/')
    $prefix = $full + [System.IO.Path]::DirectorySeparatorChar

    $all = @()
    foreach ($layer in @(
        { Get-HolderByExecutablePath -Prefix $prefix },
        { Get-HolderByOpenFile -Root $full },
        { Get-HolderByCurrentDirectory -Root $full })) {
        try {
            # Keep only real holder records: a layer that failed part-way can still emit
            # something else, and the merge below reads .ProcessId on every item.
            #
            # Filter with Where-Object, never with `continue` inside this try block. In
            # PowerShell a `continue` inside a try does not bind to an inner loop: it leaves the
            # try and continues THIS loop, so the layers that have not run yet are skipped.
            $all += @(& $layer | Where-Object { $_ -and $_.PSObject.Properties.Match('ProcessId').Count })
        } catch { }
    }

    $seen = @{}
    $unique = @()
    foreach ($holder in $all) {
        if ($seen.ContainsKey($holder.ProcessId)) { continue }
        $seen[$holder.ProcessId] = $true
        $unique += $holder
    }

    return $unique
}

function Format-HolderSummary {
    param([object[]] $Holder)

    $list = @($Holder)
    if ($list.Count -eq 0) { return '' }

    $named = @($list | Select-Object -First 2 | ForEach-Object { "$($_.Name) (PID $($_.ProcessId))" })
    $text = $named -join ' and '
    if ($list.Count -gt 2) { $text += ", and $($list.Count - 2) more" }
    return $text
}
