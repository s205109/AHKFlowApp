#Requires -Version 5.1
# Shared PowerShell host resolution and process startup for worktree lifecycle scripts.

function Resolve-PowerShellExecutable {
    $currentProcessPath = [System.Diagnostics.Process]::GetCurrentProcess().Path
    if ($currentProcessPath -and (Test-Path -LiteralPath $currentProcessPath)) {
        return $currentProcessPath
    }

    foreach ($name in @('pwsh.exe', 'powershell.exe')) {
        $psHomeCandidate = Join-Path $PSHOME $name
        if (Test-Path -LiteralPath $psHomeCandidate) {
            return $psHomeCandidate
        }

        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command -and $command.Source -and (Test-Path -LiteralPath $command.Source)) {
            return $command.Source
        }
    }

    throw 'Could not resolve a PowerShell executable. Expected current host, pwsh.exe, or powershell.exe to be available.'
}

# Builds the Win32_ProcessStartup instance that Win32_Process.Create needs so the spawned
# process never shows its console window. Without it the window is created visible, and
# PowerShell's own -WindowStyle Hidden hides it only milliseconds later, which the user sees
# as a black flash.
#
# ShowWindow = 0 is SW_HIDE, applied by the system when it creates the window. It is the only
# setting that works here. CreateFlags does not accept CREATE_NO_WINDOW: Win32_Process.Create
# returns 21 (invalid parameter) and creates nothing. Detached_Process leaves the PowerShell
# host with no console at all, and then the script never runs.
#
# Returns $null when the CIM class is unavailable, so the caller can spawn without startup
# information. A visible flash is better than no spawn at all.
function New-HiddenProcessStartup {
    try {
        return [CimInstance] (New-CimInstance -ClassName Win32_ProcessStartup `
                -Namespace 'root/cimv2' -ClientOnly -Property @{ ShowWindow = [uint16] 0 })
    } catch {
        return $null
    }
}

function Write-Stderr {
    param([string] $Message)
    [Console]::Error.WriteLine($Message)
}
