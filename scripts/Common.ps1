#Requires -Version 5.1
# Shared output and prerequisite helpers for AHKFlowApp deployment scripts.
# Dot-source from a script: . "$PSScriptRoot\Common.ps1"

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Success([string]$Message) {
    Write-Host "  + $Message" -ForegroundColor Green
}

function Write-Warn([string]$Message) {
    Write-Host "  ! $Message" -ForegroundColor Yellow
}

function Write-Fail([string]$Message) {
    Write-Host "`n  x $Message" -ForegroundColor Red
}

function Confirm-Command([string]$Name, [string]$InstallUrl) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Write-Fail "$Name is not installed."
        Write-Host "    Install from: $InstallUrl" -ForegroundColor Yellow
        throw "Missing prerequisite: $Name"
    }
    Write-Success "$Name found"
}
