#Requires -Version 5.1
<#
.SYNOPSIS
    Sets up .agents/skills/ as the canonical skills folder in the repo.
.DESCRIPTION
    Skills live in .agents/skills/ (repo-local).
    .claude/skills/ becomes a folder-level symlink to .agents/skills/ so Claude Code
    reads them. Everything stays inside the repo — no user-folder changes.
    Requires Windows Developer Mode and git core.symlinks=true.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Repo root ---
$repoRoot = (git rev-parse --show-toplevel 2>$null).Trim()
if (-not $repoRoot) {
    Write-Error "Not inside a git repository."
    exit 1
}

# --- Prerequisite: Windows Developer Mode ---
$devMode = (Get-ItemProperty `
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' `
    -Name 'AllowDevelopmentWithoutDevLicense' -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense
if ($devMode -ne 1) {
    Write-Error "Windows Developer Mode is not enabled.`nEnable it: Settings > System > For developers > Developer Mode = On"
    exit 1
}
Write-Host "[OK] Windows Developer Mode is enabled." -ForegroundColor Green

# --- Prerequisite: git core.symlinks ---
$symlinks = git config core.symlinks 2>$null
if ($symlinks -ne 'true') {
    Write-Host "[FIX] Setting git config core.symlinks = true" -ForegroundColor Yellow
    git config core.symlinks true
}
Write-Host "[OK] git core.symlinks = true" -ForegroundColor Green

$agentsSkills = Join-Path $repoRoot '.agents\skills'
$agentsRoot = Join-Path $repoRoot '.agents'
$claudeSkills  = Join-Path $repoRoot '.claude\skills'

# --- Ensure .agents/skills/ exists and exposes repo skills ---
if (-not (Test-Path $agentsRoot)) {
    Write-Error ".agents does not exist in the repo."
    exit 1
}

if (-not (Test-Path $agentsSkills)) {
    New-Item -ItemType Directory -Path $agentsSkills -Force | Out-Null
    Write-Host "[OK] Created .agents/skills/" -ForegroundColor Green
} else {
    Write-Host "[OK] .agents/skills/ already exists." -ForegroundColor Green
}

$skillDirs = Get-ChildItem -Force $agentsRoot -Directory |
    Where-Object { $_.Name -ne 'skills' }

foreach ($skillDir in $skillDirs) {
    $linkPath = Join-Path $agentsSkills $skillDir.Name

    if (Test-Path $linkPath) {
        $existing = Get-Item $linkPath -Force
        if ($existing.LinkType -eq 'SymbolicLink') {
            Write-Host "[OK] .agents/skills/$($skillDir.Name) already exists as a symlink." -ForegroundColor Green
            continue
        }

        Write-Error ".agents/skills/$($skillDir.Name) exists but is not a symlink. Remove it manually, then re-run."
        exit 1
    }

    Push-Location $agentsSkills
    try {
        cmd /c mklink /D "$($skillDir.Name)" "..\$($skillDir.Name)" > $null 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to create .agents/skills/$($skillDir.Name)."
            exit 1
        }
    } finally {
        Pop-Location
    }
}

# --- Create .claude/skills/ as a folder-level symlink ---
if (Test-Path $claudeSkills) {
    $item = Get-Item $claudeSkills -Force
    if ($item.LinkType -eq 'SymbolicLink') {
        Write-Host "[OK] .claude/skills already exists as a symlink. Nothing to do." -ForegroundColor Green
        exit 0
    }
    Write-Error ".claude/skills exists but is not a symlink. Remove it manually, then re-run."
    exit 1
}

# Relative target: from .claude/ go up one level then into .agents/skills
New-Item -ItemType Directory -Path (Join-Path $repoRoot '.claude') -Force | Out-Null
Push-Location (Join-Path $repoRoot '.claude')
try {
    cmd /c mklink /D "skills" "..\.agents\skills" > $null 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "mklink failed. Ensure Developer Mode is enabled."
        exit 1
    }
} finally {
    Pop-Location
}

Write-Host "[DONE] .claude/skills -> .agents/skills (repo-local, relative symlink)" -ForegroundColor Green
