#Requires -Version 5.1
<#
.SYNOPSIS
    Frees ports used by this worktree's AHKFlowApp dev stack.

.DESCRIPTION
    If scripts/.env.local exists (written by start-local-stack.ps1), kills processes on the manifest's ports - but only if the owning process's command line references this worktree's path. Otherwise falls back to 5600/5601 with the same ownership check.
    Refuses to kill processes whose command line does not reference this worktree.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$ManifestPath = Join-Path $PSScriptRoot '.env.local'

function Read-ManifestValue([string] $Path, [string] $Key) {
    $escapedKey = [regex]::Escape($Key)
    foreach ($line in Get-Content $Path) {
        if ($line -match "^$escapedKey=(.*)$") { return $Matches[1].Trim() }
    }
    return $null
}

function Get-ListeningProcessIdsByPort([int] $Port) {
    $processIds = @()
    $connections = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if ($connections) {
        $processIds += $connections | ForEach-Object { $_.OwningProcess }
    }

    if (-not $processIds) {
        $escapedPort = [regex]::Escape(":$Port")
        $processIds += netstat -ano |
            Select-String -Pattern "^\s*TCP\s+\S+$escapedPort\s+\S+\s+LISTENING\s+(\d+)\s*$" |
            ForEach-Object { [int]$_.Matches[0].Groups[1].Value }
    }

    return $processIds | Sort-Object -Unique
}

$ports = @()
$worktreePath = $RepoRoot
if (Test-Path $ManifestPath) {
    $apiPort = Read-ManifestValue -Path $ManifestPath -Key 'AHKFLOW_API_PORT'
    $uiPort = Read-ManifestValue -Path $ManifestPath -Key 'AHKFLOW_UI_PORT'
    $manifestWorktree = Read-ManifestValue -Path $ManifestPath -Key 'AHKFLOW_WORKTREE_PATH'
    if ($apiPort) { $ports += [int]$apiPort }
    if ($uiPort) { $ports += [int]$uiPort }
    if ($manifestWorktree) { $worktreePath = $manifestWorktree }
    Write-Host "Using manifest ports: $($ports -join ', ') (worktree: $worktreePath)"
} else {
    $ports = @(5600, 5601)
    Write-Host "No manifest found - falling back to fixed ports 5600, 5601 (worktree: $worktreePath)"
}

foreach ($port in $ports) {
    $processIds = Get-ListeningProcessIdsByPort -Port $port
    foreach ($procId in $processIds) {
        $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
        if (-not $proc) { continue }

        $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$procId" -ErrorAction SilentlyContinue
        $commandLine = if ($cim) { $cim.CommandLine } else { '' }

        if ([string]::IsNullOrWhiteSpace($commandLine)) {
            Write-Warning "Refusing to kill PID $procId on port $port - could not read command line to verify ownership for $worktreePath."
            continue
        }

        if ($commandLine -and $commandLine.IndexOf($worktreePath, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            Write-Host "Killing $($proc.Name) (PID $procId) on port $port"
            Stop-Process -Id $procId -Force
        } else {
            Write-Warning "Refusing to kill PID $procId on port $port - command line does not reference $worktreePath."
            Write-Warning "  Command: $commandLine"
        }
    }
}

Write-Host "Done."
