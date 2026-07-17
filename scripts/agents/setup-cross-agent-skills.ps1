#Requires -Version 5.1
<#
.SYNOPSIS
    Sets up repo-local cross-agent skill symlinks that point at .agents/.
.DESCRIPTION
    Active skills live as immediate .agents/<skill>/ directories with a SKILL.md file inside.
    .claude/skills/ and .github/skills/ become real directories containing one symlink per
    active skill back to .agents/<skill>. The repo-local Codex plugin skills folder mirrors
    each skill directory with hard-linked files (SKILL.md plus companion files such as
    templates and agents/openai.yaml) because Codex plugin installation ignores symlinks.
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
# Codex marketplace convention (matches Codex's bundled openai-primary-runtime marketplace):
# manifest lives at .agents/plugins/marketplace.json, payloads at <repo-root>/plugins/<name>/,
# and manifest "path" entries resolve relative to the marketplace root. Do not co-locate them.
$codexPluginSkills = Join-Path $repoRoot 'plugins\ahkflowapp\skills'

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
        if (Test-Path $skillLinkDir) {
            Remove-Item -LiteralPath $skillLinkDir -Recurse -Force
        }

        foreach ($sourceFile in Get-ChildItem -LiteralPath $skillDir.FullName -Recurse -File -Force) {
            $relative = $sourceFile.FullName.Substring($skillDir.FullName.Length).TrimStart('\')
            $linkPath = Join-Path $skillLinkDir $relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $linkPath) -Force | Out-Null
            New-Item -ItemType HardLink -Path $linkPath -Target $sourceFile.FullName | Out-Null
        }
    }
}

function Get-CodexSkillsHash {
    param([string] $SkillsRoot)

    # Deterministic content hash of the Codex skills payload. Hashes git blob OIDs
    # (git hash-object applies clean filters) so line-ending differences between
    # platforms/checkouts don't change the version. Must stay in sync with the
    # equivalent computation in setup-cross-agent-skills.sh: ordinal-sorted
    # forward-slash skills-root-relative paths, SHA-256 over "<blob-oid>  <path>\n" lines.
    $rootFull = (Resolve-Path -LiteralPath $SkillsRoot).Path.TrimEnd('\')
    $relatives = Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force |
        ForEach-Object { $_.FullName.Substring($rootFull.Length).TrimStart('\').Replace('\', '/') }
    $sorted = [System.Collections.Generic.List[string]]::new()
    foreach ($rel in $relatives) { $sorted.Add($rel) }
    $sorted.Sort([System.StringComparer]::Ordinal)

    Push-Location $rootFull
    try {
        # Paths passed as arguments: piping to native stdin appends CR on Windows PowerShell,
        # which git would treat as part of the path.
        $blobs = @(& git hash-object -- @($sorted))
        if ($LASTEXITCODE -ne 0 -or $blobs.Count -ne $sorted.Count) {
            Write-Error "git hash-object failed while hashing Codex skills payload."
            exit 1
        }
    } finally {
        Pop-Location
    }

    $builder = [System.Text.StringBuilder]::new()
    for ($i = 0; $i -lt $sorted.Count; $i++) {
        [void]$builder.Append("$($blobs[$i])  $($sorted[$i])`n")
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($builder.ToString()))
        return ([System.BitConverter]::ToString($digest) -replace '-', '').Substring(0, 12).ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Update-CodexPluginVersion {
    param(
        [string] $PluginJsonPath,
        [string] $SkillsRoot
    )

    if (-not (Test-Path -LiteralPath $PluginJsonPath)) {
        Write-Host "[WARN] $PluginJsonPath not found - skipping Codex plugin version bump." -ForegroundColor Yellow
        return
    }

    $hash = Get-CodexSkillsHash $SkillsRoot
    $content = [System.IO.File]::ReadAllText($PluginJsonPath)
    if ($content -notmatch '"version":\s*"([^"]+)"') {
        Write-Host "[WARN] No version field in plugin.json - skipping Codex plugin version bump." -ForegroundColor Yellow
        return
    }

    $current = $Matches[1]
    $base = $current.Split('+')[0]
    $newVersion = "$base+codex.$hash"
    if ($newVersion -eq $current) {
        Write-Host "[OK] Codex plugin version $current matches skills content." -ForegroundColor Green
        return
    }

    $updated = $content -replace '("version":\s*")[^"]+(")', "`${1}$newVersion`${2}"
    [System.IO.File]::WriteAllText($PluginJsonPath, $updated, [System.Text.UTF8Encoding]::new($false))
    Write-Host "[FIX] Codex plugin version bumped to $newVersion - commit plugin.json." -ForegroundColor Yellow
}

function Update-CodexInstalledPlugin {
    if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
        Write-Host "[OK] Codex CLI not on PATH - skipping installed plugin refresh." -ForegroundColor Green
        return
    }

    Write-Host "[..] Refreshing installed Codex plugin cache (codex plugin add ahkflowapp@ahkflowapp-local)..."
    # EAP=Continue: under Stop, stderr output from a native command redirected via 2>&1 becomes terminating.
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        codex plugin add 'ahkflowapp@ahkflowapp-local' --json 2>&1 | Out-Null
    } finally {
        $ErrorActionPreference = $previousEap
    }
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Codex plugin cache refreshed. Start a new Codex session to pick up skill changes." -ForegroundColor Green
    } else {
        Write-Host "[WARN] 'codex plugin add ahkflowapp@ahkflowapp-local' failed (is the ahkflowapp-local marketplace registered?). Run it manually to refresh the Codex plugin cache." -ForegroundColor Yellow
    }
}

Sync-SkillLinkDirectory $claudeSkills '.claude/skills' '..\..\.agents' $false
Sync-SkillLinkDirectory $githubSkills '.github/skills' '..\..\.agents' $false
Sync-CodexPluginSkillDirectory $codexPluginSkills 'plugins/ahkflowapp/skills'
Update-CodexPluginVersion (Join-Path $repoRoot 'plugins\ahkflowapp\.codex-plugin\plugin.json') $codexPluginSkills
Update-CodexInstalledPlugin

Write-Host "[DONE] .claude/skills and .github/skills symlink to active .agents/* skills; Codex plugin skills mirror the same skill directories with hard-linked files" -ForegroundColor Green
