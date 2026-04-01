#Requires -Version 7.0
<#
.SYNOPSIS
    Sets up GitHub Copilot CLI skill symlinks pointing to .claude/skills/.
.DESCRIPTION
    Creates symbolic links in .github/skills/ for portable skills.
    Requires Windows Developer Mode and git core.symlinks=true.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = git rev-parse --show-toplevel 2>$null
if (-not $repoRoot) {
    Write-Error "Not inside a git repository."
    exit 1
}

Push-Location $repoRoot
try {
    # --- Prerequisite: Windows Developer Mode ---
    $devMode = Get-ItemPropertyValue `
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' `
        -Name 'AllowDevelopmentWithoutDevLicense' -ErrorAction SilentlyContinue
    if ($devMode -ne 1) {
        Write-Error @"
Windows Developer Mode is not enabled.
Enable it: Settings > System > For developers > Developer Mode = On
"@
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

    # --- Create .github/skills/ directory ---
    $skillsDir = Join-Path $repoRoot '.github' 'skills'
    if (-not (Test-Path $skillsDir)) {
        New-Item -ItemType Directory -Path $skillsDir -Force | Out-Null
    }

    # --- Portable skills to symlink (excludes Claude-specific) ---
    $portableSkills = @(
        'cck-api-versioning'
        'cck-authentication'
        'cck-blazor-mudblazor'
        'cck-build-fix'
        'cck-ci-cd'
        'cck-clean-architecture'
        'cck-configuration'
        'cck-dependency-injection'
        'cck-docker'
        'cck-ef-core'
        'cck-error-handling'
        'cck-httpclient-factory'
        'cck-logging'
        'cck-migration-workflow'
        'cck-modern-csharp'
        'cck-openapi'
        'cck-project-structure'
        'cck-resilience'
        'cck-scaffolding'
        'cck-security-scan'
        'cck-testing'
        'cck-verify'
    )

    $created = 0
    $skipped = 0
    foreach ($skill in $portableSkills) {
        $linkPath = Join-Path $skillsDir $skill
        $targetPath = Join-Path $repoRoot '.claude' 'skills' $skill

        if (Test-Path $linkPath) {
            $skipped++
            continue
        }

        if (-not (Test-Path $targetPath)) {
            Write-Warning "Source skill not found: $targetPath"
            continue
        }

        # Relative target for portability: ../../.claude/skills/<skill>
        $relativeTarget = "../../.claude/skills/$skill"
        New-Item -ItemType SymbolicLink -Path $linkPath -Target $relativeTarget | Out-Null
        $created++
    }

    Write-Host ""
    Write-Host "Symlinks: $created created, $skipped already existed." -ForegroundColor Cyan
    Write-Host "[DONE] Copilot CLI skill symlinks are ready." -ForegroundColor Green
}
finally {
    Pop-Location
}
