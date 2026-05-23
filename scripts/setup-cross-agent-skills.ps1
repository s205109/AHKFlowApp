#Requires -Version 5.1
<#
.SYNOPSIS
    Sets up repo-local cross-agent skill symlinks that point at .agents/.
.DESCRIPTION
    Active skills live as immediate .agents/<skill>/ directories with a SKILL.md file inside.
    .claude/skills/ and .github/skills/ become real directories containing one symlink per
    active skill back to .agents/<skill>. The repo-local Codex plugin skills folder uses
    one hard-linked SKILL.md per skill because Codex plugin installation ignores symlinks.
    Reference docs, disabled dirs, and plugin packaging are ignored.
    Everything stays inside the repo — no user-folder changes.
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

# --- Install committed git hooks via core.hooksPath ---
$hooksDir = Join-Path $repoRoot '.githooks'
if (Test-Path $hooksDir) {
    $currentHooksPath = (git config core.hooksPath 2>$null)
    $normalizedCurrent = if ($currentHooksPath) {
        $currentHooksPath.TrimEnd('\','/').Replace('\','/').ToLowerInvariant()
    } else { '' }
    $pointsToDefault = $normalizedCurrent -match '(^\.git/hooks$|/\.git/hooks$)'

    if ($normalizedCurrent -eq '.githooks') {
        Write-Host "[OK] core.hooksPath = .githooks" -ForegroundColor Green
    } elseif (-not $normalizedCurrent -or $pointsToDefault) {
        git config core.hooksPath .githooks
        Write-Host "[FIX] Set core.hooksPath = .githooks (enables committed hooks)" -ForegroundColor Yellow
    } else {
        Write-Host "[WARN] core.hooksPath is '$currentHooksPath' - committed hooks at .githooks/ inactive. To enable: git config core.hooksPath .githooks" -ForegroundColor Yellow
    }
}

$agentsRoot = Join-Path $repoRoot '.agents'
$claudeRoot = Join-Path $repoRoot '.claude'
$claudeSkills = Join-Path $claudeRoot 'skills'
$githubRoot = Join-Path $repoRoot '.github'
$githubSkills = Join-Path $githubRoot 'skills'
$codexPluginSkills = Join-Path $agentsRoot 'plugins\plugins\ahkflowapp\skills'

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

$ignoredSkillDirs = @('skills', 'plugins', 'skills.disabled', 'disabled', 'reference', 'references')
$skillDirs = Get-ChildItem -Force $agentsRoot -Directory |
    Where-Object {
        $ignoredSkillDirs -notcontains $_.Name -and
        (Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md'))
    }
$skillDirNames = @($skillDirs | ForEach-Object { $_.Name })

# --- Description budget guardrail ---
$maxDescLen = 140
$bloated = @()
foreach ($skillDir in $skillDirs) {
    $skillFile = Join-Path $skillDir.FullName 'SKILL.md'
    $descLine = Select-String -LiteralPath $skillFile -Pattern '^description:' -SimpleMatch:$false | Select-Object -First 1
    if ($descLine) {
        $desc = ($descLine.Line -replace '^description:\s*', '').Trim()
        if ($desc.Length -gt $maxDescLen) {
            $bloated += "$($skillDir.Name): $($desc.Length) chars"
        }
    }
}
if ($bloated.Count -gt 0) {
    Write-Host "[WARN] Skill descriptions over $maxDescLen chars (context budget):" -ForegroundColor Yellow
    foreach ($entry in $bloated) {
        Write-Host "       $entry" -ForegroundColor Yellow
    }
}

function Sync-SkillLinkDirectory {
    param(
        [string] $LinkRoot,
        [string] $DisplayName,
        [string] $TargetPrefix,
        [bool] $ReplaceExistingDirectories = $false
    )

    if (Test-Path $LinkRoot) {
        $item = Get-Item $LinkRoot -Force
        if ($item.LinkType -eq 'SymbolicLink') {
            Remove-Item $LinkRoot -Force
            Write-Host "[FIX] Removed old $DisplayName symlink." -ForegroundColor Yellow
        } elseif ($item.PSIsContainer) {
            Write-Host "[OK] $DisplayName already exists." -ForegroundColor Green
        } else {
            Write-Error "$DisplayName exists but is not a directory. Remove it manually, then re-run."
            exit 1
        }
    }

    New-Item -ItemType Directory -Path $LinkRoot -Force | Out-Null

    foreach ($existingLink in Get-ChildItem -Force $LinkRoot) {
        if ($skillDirNames -contains $existingLink.Name) {
            continue
        }

        if (-not $existingLink.PSIsContainer -and $existingLink.Name -eq 'README.md') {
            continue
        }

        if ($existingLink.LinkType -eq 'SymbolicLink') {
            Remove-Item -LiteralPath $existingLink.FullName -Force
            Write-Host "[FIX] Removed stale $DisplayName/$($existingLink.Name) link." -ForegroundColor Yellow
            continue
        }

        if ($ReplaceExistingDirectories -and $existingLink.PSIsContainer) {
            Remove-Item -LiteralPath $existingLink.FullName -Recurse -Force
            Write-Host "[FIX] Replaced copied $DisplayName/$($existingLink.Name) directory." -ForegroundColor Yellow
            continue
        }

        Write-Error "$DisplayName/$($existingLink.Name) is not an active skill symlink. Remove it manually, then re-run."
        exit 1
    }

    foreach ($skillDir in $skillDirs) {
        $linkPath = Join-Path $LinkRoot $skillDir.Name

        if (Test-Path $linkPath) {
            $existing = Get-Item $linkPath -Force
            if ($existing.LinkType -eq 'SymbolicLink') {
                $target = $existing.Target
                if ($target -is [array]) {
                    $target = $target[0]
                }

                $resolved = $null
                if ($target) {
                    $targetPath = if ([System.IO.Path]::IsPathRooted($target)) {
                        $target
                    } else {
                        Join-Path (Split-Path -Parent $linkPath) $target
                    }

                    $resolvedPath = Resolve-Path -LiteralPath $targetPath -ErrorAction SilentlyContinue
                    if ($resolvedPath) {
                        $resolved = $resolvedPath.Path
                    }
                }

                $expected = (Resolve-Path -LiteralPath $skillDir.FullName).Path
                if ($resolved -and $resolved.TrimEnd('\') -ieq $expected.TrimEnd('\')) {
                    Write-Host "[OK] $DisplayName/$($skillDir.Name) already points to .agents/$($skillDir.Name)." -ForegroundColor Green
                    continue
                }

                Remove-Item $linkPath -Force
                Write-Host "[FIX] Replaced old symlink for $DisplayName/$($skillDir.Name)." -ForegroundColor Yellow
            } elseif ($ReplaceExistingDirectories -and $existing.PSIsContainer) {
                Remove-Item -LiteralPath $linkPath -Recurse -Force
                Write-Host "[FIX] Replaced copied $DisplayName/$($skillDir.Name) directory." -ForegroundColor Yellow
            } else {
                Write-Error "$DisplayName/$($skillDir.Name) exists but is not a symlink. Remove it manually, then re-run."
                exit 1
            }
        }

        Push-Location $LinkRoot
        try {
            cmd /c mklink /D "$($skillDir.Name)" "$TargetPrefix\$($skillDir.Name)" > $null 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to create $DisplayName/$($skillDir.Name)."
                exit 1
            }
        } finally {
            Pop-Location
        }
    }
}

function Sync-CodexPluginSkillDirectory {
    param(
        [string] $LinkRoot,
        [string] $DisplayName
    )

    if (Test-Path $LinkRoot) {
        $item = Get-Item $LinkRoot -Force
        if ($item.LinkType -eq 'SymbolicLink') {
            Remove-Item $LinkRoot -Force
            Write-Host "[FIX] Removed old $DisplayName symlink." -ForegroundColor Yellow
        } elseif ($item.PSIsContainer) {
            Write-Host "[OK] $DisplayName already exists." -ForegroundColor Green
        } else {
            Write-Error "$DisplayName exists but is not a directory. Remove it manually, then re-run."
            exit 1
        }
    }

    New-Item -ItemType Directory -Path $LinkRoot -Force | Out-Null

    foreach ($existingEntry in Get-ChildItem -Force $LinkRoot) {
        if ($skillDirNames -notcontains $existingEntry.Name) {
            Remove-Item -LiteralPath $existingEntry.FullName -Recurse -Force
            Write-Host "[FIX] Removed stale $DisplayName/$($existingEntry.Name)." -ForegroundColor Yellow
            continue
        }

        if ($existingEntry.LinkType -eq 'SymbolicLink') {
            Remove-Item -LiteralPath $existingEntry.FullName -Force
            Write-Host "[FIX] Replaced directory symlink $DisplayName/$($existingEntry.Name)." -ForegroundColor Yellow
        }
    }

    foreach ($skillDir in $skillDirs) {
        $skillLinkDir = Join-Path $LinkRoot $skillDir.Name
        New-Item -ItemType Directory -Path $skillLinkDir -Force | Out-Null

        $skillLink = Join-Path $skillLinkDir 'SKILL.md'
        if (Test-Path $skillLink) {
            $existing = Get-Item $skillLink -Force
            if ($existing.LinkType -eq 'SymbolicLink') {
                Remove-Item -LiteralPath $skillLink -Force
                Write-Host "[FIX] Replaced symlink $DisplayName/$($skillDir.Name)/SKILL.md with a hard link." -ForegroundColor Yellow
            } else {
                Remove-Item -LiteralPath $skillLink -Force
                Write-Host "[FIX] Refreshed hard link $DisplayName/$($skillDir.Name)/SKILL.md." -ForegroundColor Yellow
            }
        }

        New-Item -ItemType HardLink -Path $skillLink -Target (Join-Path $skillDir.FullName 'SKILL.md') | Out-Null
    }
}

Sync-SkillLinkDirectory $claudeSkills '.claude/skills' '..\..\.agents' $false
Sync-SkillLinkDirectory $githubSkills '.github/skills' '..\..\.agents' $false
Sync-CodexPluginSkillDirectory $codexPluginSkills '.agents/plugins/plugins/ahkflowapp/skills'

Write-Host "[DONE] .claude/skills and .github/skills symlink to active .agents/* skills; Codex plugin skills hard-link to the same SKILL.md files" -ForegroundColor Green
