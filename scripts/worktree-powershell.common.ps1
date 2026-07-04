#Requires -Version 5.1
# Shared PowerShell host resolution for worktree lifecycle scripts.

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
