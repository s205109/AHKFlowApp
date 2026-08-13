#Requires -Version 5.1
<#
.SYNOPSIS
  Asserts that the detached worktree removal watcher never shows a console window.
.DESCRIPTION
  remove-worktree-local-dev.ps1 spawns its watcher through Win32_Process.Create so the
  watcher escapes Claude's job object. Windows gives that process a console window unless the
  call passes ProcessStartupInformation with ShowWindow = 0. PowerShell's own
  -WindowStyle Hidden is too late: it hides the window after the host has started, and the
  user sees the gap as a black flash on every removal.

  This suite spawns a real probe process the same way the script does and asserts that no
  visible window ever belongs to it.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True {
    param([bool] $Condition, [string] $Message)

    if (-not $Condition) {
        throw $Message
    }
}

Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class WorktreeWindowScan {
    delegate bool EnumProc(IntPtr window, IntPtr param);

    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc callback, IntPtr param);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr window, StringBuilder text, int count);

    // Returns "handle:classname" for every visible top-level window owned by the process,
    // or an empty string when it owns none.
    public static string VisibleWindowsFor(uint targetProcessId) {
        var found = new List<string>();
        EnumWindows((window, param) => {
            uint owner;
            GetWindowThreadProcessId(window, out owner);
            if (owner == targetProcessId && IsWindowVisible(window)) {
                var name = new StringBuilder(256);
                GetClassName(window, name, name.Capacity);
                found.Add(window.ToString() + ":" + name.ToString());
            }
            return true;
        }, IntPtr.Zero);
        return string.Join(", ", found);
    }
}
'@

# --- the shared helper builds a hidden startup instance -----------------------------------

$helperPath = Join-Path $repoRoot 'scripts\worktree-powershell.common.ps1'
Assert-True (Test-Path -LiteralPath $helperPath) "Expected the shared PowerShell helper to exist: $helperPath"

. $helperPath

$startup = New-HiddenProcessStartup
Assert-True ($null -ne $startup) 'New-HiddenProcessStartup returned $null; Win32_ProcessStartup should be available on Windows.'
Assert-True ($startup.ShowWindow -eq 0) "Expected ShowWindow = 0 (SW_HIDE), got '$($startup.ShowWindow)'."

# --- a process spawned with it never shows a window ---------------------------------------

$probeId = [guid]::NewGuid().ToString('N')
$probeScript = Join-Path ([System.IO.Path]::GetTempPath()) "ahkflowapp-window-probe-$probeId.ps1"
$probeMarker = Join-Path ([System.IO.Path]::GetTempPath()) "ahkflowapp-window-probe-$probeId.started"

# The marker tells the scan below when the PowerShell host has finished starting. The window
# this suite guards against is created before that point, so the scan must cover the whole
# startup, however slow the machine is that day.
Set-Content -LiteralPath $probeScript -Encoding utf8 -Value @"
New-Item -ItemType File -Path '$probeMarker' -Force | Out-Null
Start-Sleep -Seconds 3
"@

$probeProcessId = 0
try {
    $psExe = Resolve-PowerShellExecutable
    $commandLine = '"{0}" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{1}"' -f $psExe, $probeScript

    $result = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
        CommandLine               = $commandLine
        CurrentDirectory          = [System.IO.Path]::GetTempPath()
        ProcessStartupInformation = $startup
    } -ErrorAction Stop

    # 21 is "invalid parameter". Win32_ProcessStartup rejects CreateFlags values it does not
    # document, CREATE_NO_WINDOW among them, and then no process is created at all. Fail here
    # rather than let the removal silently fall back to the killable Start-Process path.
    Assert-True ($result.ReturnValue -eq 0) "Win32_Process.Create returned $($result.ReturnValue); expected 0. The startup information is not accepted."

    $probeProcessId = [uint32] $result.ProcessId
    Assert-True ($probeProcessId -ne 0) 'Win32_Process.Create reported success but returned no process id.'

    # Poll rather than sample once: the window this guards against appeared 135-369 ms after the
    # spawn on a developer machine, so a single check right after the call would miss it.
    #
    # Scan until the host has started, plus a short tail, rather than for a fixed span. A fixed
    # span turns into a false pass on a loaded CI runner, where the process can start after the
    # scan has already given up.
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $seen = ''
    $hostStartedAt = $null
    while ($stopwatch.ElapsedMilliseconds -lt 30000) {
        $seen = [WorktreeWindowScan]::VisibleWindowsFor($probeProcessId)
        if ($seen) { break }

        if ($null -eq $hostStartedAt) {
            if (Test-Path -LiteralPath $probeMarker) { $hostStartedAt = $stopwatch.ElapsedMilliseconds }
        } elseif (($stopwatch.ElapsedMilliseconds - $hostStartedAt) -ge 500) {
            break
        }

        Start-Sleep -Milliseconds 5
    }

    Assert-True ([string]::IsNullOrEmpty($seen)) "A visible window appeared for the spawned watcher after $($stopwatch.ElapsedMilliseconds)ms: $seen"

    # No marker means the probe never ran, so the scan proved nothing. Detached_Process fails
    # exactly this way: Create returns 0 and the child does nothing.
    Assert-True ($null -ne $hostStartedAt) 'The probe process never started; the window scan proved nothing.'
} finally {
    if ($probeProcessId -ne 0) {
        Stop-Process -Id $probeProcessId -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $probeScript, $probeMarker -Force -ErrorAction SilentlyContinue
}

# --- the removal script actually passes it ------------------------------------------------

$removeScriptPath = Join-Path $repoRoot 'scripts\remove-worktree-local-dev.ps1'
$removeScriptContent = Get-Content -LiteralPath $removeScriptPath -Raw

Assert-True ($removeScriptContent -match 'ProcessStartupInformation') 'remove-worktree-local-dev.ps1 must pass ProcessStartupInformation to Win32_Process.Create, or the watcher window flashes.'
Assert-True ($removeScriptContent -match 'New-HiddenProcessStartup') 'remove-worktree-local-dev.ps1 should build its startup information with the shared New-HiddenProcessStartup helper.'

Write-Host 'Worktree watcher window tests passed.'
