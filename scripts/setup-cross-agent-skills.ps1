#Requires -Version 5.1
<#
.SYNOPSIS
    Sets up repo-local Claude skill symlinks that point at .agents/.
.DESCRIPTION
    Skills live directly in .agents/ (repo-local).
    .claude/skills/ becomes a real directory containing one symlink per skill
    back to .agents/<skill>. Everything stays inside the repo — no user-folder changes.
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

$agentsRoot = Join-Path $repoRoot '.agents'
$claudeRoot = Join-Path $repoRoot '.claude'
$claudeSkills = Join-Path $claudeRoot 'skills'

# --- Ensure .agents/ exists ---
if (-not (Test-Path $agentsRoot)) {
    Write-Error ".agents does not exist in the repo."
    exit 1
}

Write-Host "[OK] .agents/ exists." -ForegroundColor Green

$agentsSkills = Join-Path $agentsRoot 'skills'
if (Test-Path $agentsSkills) {
    $item = Get-Item $agentsSkills -Force
    if ($item.LinkType -eq 'SymbolicLink') {
        Remove-Item $agentsSkills -Force
        Write-Host "[FIX] Removed stale .agents/skills symlink." -ForegroundColor Yellow
    } elseif ($item.PSIsContainer) {
        $children = Get-ChildItem -Force $agentsSkills
        $hasOnlySymlinks = $children -and @($children | Where-Object { $_.LinkType -ne 'SymbolicLink' }).Count -eq 0

        if (-not $children -or $hasOnlySymlinks) {
            Remove-Item $agentsSkills -Recurse -Force
            Write-Host "[FIX] Removed stale .agents/skills directory." -ForegroundColor Yellow
        } else {
            Write-Error ".agents/skills exists but should not. Remove it manually, then re-run."
            exit 1
        }
    } else {
        Write-Error ".agents/skills exists but should not. Remove it manually, then re-run."
        exit 1
    }
}

# --- Ensure .claude/skills/ is a real directory ---
if (Test-Path $claudeSkills) {
    $item = Get-Item $claudeSkills -Force
    if ($item.LinkType -eq 'SymbolicLink') {
        Remove-Item $claudeSkills -Force
        Write-Host "[FIX] Removed old .claude/skills symlink." -ForegroundColor Yellow
    } else {
        Write-Host "[OK] .claude/skills/ already exists." -ForegroundColor Green
    }
}

New-Item -ItemType Directory -Path $claudeSkills -Force | Out-Null

$skillDirs = Get-ChildItem -Force $agentsRoot -Directory |
    Where-Object { $_.Name -ne 'skills' }

foreach ($skillDir in $skillDirs) {
    $linkPath = Join-Path $claudeSkills $skillDir.Name

    if (Test-Path $linkPath) {
        $existing = Get-Item $linkPath -Force
        if ($existing.LinkType -eq 'SymbolicLink') {
            $resolved = $existing.ResolveLinkTarget($true).FullName
            $expected = $skillDir.FullName
            if ($resolved -eq $expected) {
                Write-Host "[OK] .claude/skills/$($skillDir.Name) already points to .agents/$($skillDir.Name)." -ForegroundColor Green
                continue
            }

            Remove-Item $linkPath -Force
            Write-Host "[FIX] Replaced old symlink for $($skillDir.Name)." -ForegroundColor Yellow
        } else {
            Write-Error ".claude/skills/$($skillDir.Name) exists but is not a symlink. Remove it manually, then re-run."
            exit 1
        }
    }

    Push-Location $claudeSkills
    try {
        cmd /c mklink /D "$($skillDir.Name)" "..\..\.agents\$($skillDir.Name)" > $null 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to create .claude/skills/$($skillDir.Name)."
            exit 1
        }
    } finally {
        Pop-Location
    }
}

Write-Host "[DONE] .claude/skills contains symlinks to .agents/*" -ForegroundColor Green
