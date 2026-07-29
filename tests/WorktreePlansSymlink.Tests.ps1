#Requires -Version 5.1

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

# Mirrors the production wiring: new-worktree.ps1 dot-sources the PowerShell common file (for
# Write-Stderr) before the plans common file that depends on it.
. (Join-Path $repoRoot 'scripts\worktree-powershell.common.ps1')
. (Join-Path $repoRoot 'scripts\worktree-plans.common.ps1')

function New-PlansFixture {
    param([string] $Slug = 'plans')

    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("wtplans-$Slug-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path (Join-Path $root 'main\docs\superpowers') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $root 'main\docs\superpowers\marker.md') -Value 'seed' -Encoding utf8
    return $root
}

function Remove-Fixture {
    param([string] $Path)

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            return
        } catch {
            if ($attempt -eq 3) { return }
            Start-Sleep -Milliseconds 200
        }
    }
}

function Get-LinkTarget {
    param([string] $Path)

    $item = Get-Item -LiteralPath $Path -Force
    $target = $item.Target
    if ($target -is [array]) { $target = $target[0] }
    return $target
}

# --- Case 1: a fresh worktree gets a symlink, and reads the main checkout's content ---------
$fixture = New-PlansFixture 'fresh'
try {
    $main = Join-Path $fixture 'main'
    $wt = Join-Path $fixture 'wt'
    New-Item -ItemType Directory -Path $wt -Force | Out-Null

    Add-PlansSymlink -RepoRoot $main -WorktreePath $wt

    $link = Join-Path $wt 'docs\superpowers'
    Assert-True (Test-Path -LiteralPath $link) 'A fresh worktree must receive docs\superpowers.'
    Assert-True ((Get-Item -LiteralPath $link -Force).LinkType -eq 'SymbolicLink') 'docs\superpowers must be a symlink, not a copied directory.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $link 'marker.md')) -ceq 'seed') "The worktree must read the main checkout's plan content through the link."

    # Case 3 (live sync): the link is not a snapshot. A plan revised in the main checkout after
    # the worktree exists must be visible immediately -- this is the whole reason it is not a copy.
    Set-Content -LiteralPath (Join-Path $main 'docs\superpowers\later-plan.md') -Value 'revised' -Encoding utf8
    Assert-True ((Get-Content -LiteralPath (Join-Path $link 'later-plan.md')) -ceq 'revised') 'A plan written after linking must be visible through the worktree path.'

    # Case 2 (idempotent): re-running against an existing, correct link is a no-op. new-worktree.ps1
    # calls this on every run, including when reusing a worktree.
    Add-PlansSymlink -RepoRoot $main -WorktreePath $wt
    Assert-True ((Get-Item -LiteralPath $link -Force).LinkType -eq 'SymbolicLink') 'Re-running must leave the symlink in place.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $link 'marker.md')) -ceq 'seed') 'Re-running must not disturb linked content.'
} finally {
    Remove-Fixture $fixture
}

# --- Case 4: no plans repo cloned -> skip silently, create nothing --------------------------
# A contributor who never cloned the private repo must still get a working worktree.
$fixture = New-PlansFixture 'missing'
try {
    $wt = Join-Path $fixture 'wt'
    New-Item -ItemType Directory -Path $wt -Force | Out-Null

    Add-PlansSymlink -RepoRoot (Join-Path $fixture 'no-such-repo') -WorktreePath $wt

    Assert-True (-not (Test-Path -LiteralPath (Join-Path $wt 'docs\superpowers'))) 'With no plans repo to link, nothing may be created.'
} finally {
    Remove-Fixture $fixture
}

# --- Case 5: a real directory already present -> leave it alone ------------------------------
# Never delete data. The path is gitignored, so anything real there was put there by a human.
$fixture = New-PlansFixture 'realdir'
try {
    $main = Join-Path $fixture 'main'
    $wt = Join-Path $fixture 'wt'
    New-Item -ItemType Directory -Path (Join-Path $wt 'docs\superpowers') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $wt 'docs\superpowers\handwritten.txt') -Value 'do not delete' -Encoding utf8

    Add-PlansSymlink -RepoRoot $main -WorktreePath $wt

    $existing = Get-Item -LiteralPath (Join-Path $wt 'docs\superpowers') -Force
    Assert-True ($existing.LinkType -ne 'SymbolicLink') 'A real directory must not be replaced by a symlink.'
    Assert-True (Test-Path -LiteralPath (Join-Path $wt 'docs\superpowers\handwritten.txt')) 'Content in a real directory must survive untouched.'
} finally {
    Remove-Fixture $fixture
}

# --- Case 6: a symlink aimed at the wrong target is repointed --------------------------------
# Happens when the main checkout moves. A stale link silently serves the wrong repo's plans.
$fixture = New-PlansFixture 'wrongtarget'
try {
    $main = Join-Path $fixture 'main'
    $wt = Join-Path $fixture 'wt'
    New-Item -ItemType Directory -Path (Join-Path $fixture 'elsewhere\docs\superpowers') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $fixture 'elsewhere\docs\superpowers\other.md') -Value 'wrong repo' -Encoding utf8
    New-Item -ItemType Directory -Path (Join-Path $wt 'docs') -Force | Out-Null

    Push-Location (Join-Path $wt 'docs')
    try {
        cmd /c mklink /D 'superpowers' (Join-Path $fixture 'elsewhere\docs\superpowers') > $null 2>&1
    } finally {
        Pop-Location
    }

    Add-PlansSymlink -RepoRoot $main -WorktreePath $wt

    $link = Join-Path $wt 'docs\superpowers'
    $target = Get-LinkTarget $link
    $expected = (Resolve-Path -LiteralPath (Join-Path $main 'docs\superpowers')).Path
    Assert-True ((Resolve-Path -LiteralPath $target).Path.TrimEnd('\') -ieq $expected.TrimEnd('\')) "A wrong-target symlink must be repointed at the main checkout (target was '$target')."
    Assert-True (Test-Path -LiteralPath (Join-Path $link 'marker.md')) 'After repointing, the main checkout content must be reachable.'
} finally {
    Remove-Fixture $fixture
}

# --- Case 7: removing the worktree must not touch the main checkout's plans ------------------
# remove-worktree-local-dev.ps1 tears worktrees down with Remove-Item -Recurse -Force. If that
# followed the link, a worktree cleanup would delete the real plans repo.
$fixture = New-PlansFixture 'removal'
try {
    $main = Join-Path $fixture 'main'
    $wt = Join-Path $fixture 'wt'
    New-Item -ItemType Directory -Path $wt -Force | Out-Null

    Add-PlansSymlink -RepoRoot $main -WorktreePath $wt
    Remove-Item -LiteralPath $wt -Recurse -Force

    Assert-True (Test-Path -LiteralPath (Join-Path $main 'docs\superpowers\marker.md')) 'Removing a worktree must never delete the main checkout plans.'
} finally {
    Remove-Fixture $fixture
}

# --- Case 8: paths containing spaces ---------------------------------------------------------
# mklink is invoked through cmd, so an unquoted space would silently produce a broken link.
$fixture = New-PlansFixture 'spaces'
try {
    $main = Join-Path $fixture 'main repo'
    $wt = Join-Path $fixture 'work tree'
    New-Item -ItemType Directory -Path (Join-Path $main 'docs\superpowers') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $main 'docs\superpowers\marker.md') -Value 'spaced' -Encoding utf8
    New-Item -ItemType Directory -Path $wt -Force | Out-Null

    Add-PlansSymlink -RepoRoot $main -WorktreePath $wt

    $link = Join-Path $wt 'docs\superpowers'
    Assert-True (Test-Path -LiteralPath $link) 'A path containing spaces must still produce a link.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $link 'marker.md')) -ceq 'spaced') 'Content must be readable through a link whose path contains spaces.'
} finally {
    Remove-Fixture $fixture
}

# --- The .gitignore pattern must hide the symlink, not just a real directory -----------------
# A pattern ending in '/' matches directories only. Every worktree's docs\superpowers is now a
# symlink, so a trailing slash would leave it showing as untracked in git status.
$gitignorePath = Join-Path $repoRoot '.gitignore'
$plansRules = @(Get-Content -LiteralPath $gitignorePath | Where-Object { $_.Trim() -eq 'docs/superpowers' -or $_.Trim() -eq 'docs/superpowers/' })
Assert-True ($plansRules.Count -ge 1) '.gitignore must carry a docs/superpowers rule.'
Assert-True (-not ($plansRules -contains 'docs/superpowers/')) '.gitignore must use "docs/superpowers" without a trailing slash, or the worktree symlink is not ignored.'

# --- The @-picker script must follow symlinks and suppress the mirror duplicates -------------
# Without --follow, rg does not descend into the docs\superpowers link and the picker shows no
# plans at all inside a worktree -- the bug this change exists to fix.
$suggestionPath = Join-Path $repoRoot '.claude\file-suggestion.sh'
$suggestion = Get-Content -LiteralPath $suggestionPath -Raw
Assert-True ($suggestion -match '(?m)^\s*rg --files[^\r\n]*--follow') '.claude/file-suggestion.sh must pass --follow, or worktree plans stay invisible to the @ picker.'

# --follow also walks the pre-existing skill-mirror symlinks, so .ignore must deny them or every
# skill file and AGENTS.md is listed two or three times.
$ignoreLines = @(Get-Content -LiteralPath (Join-Path $repoRoot '.ignore') | ForEach-Object { $_.Trim() })
foreach ($rule in @('.claude/skills/', '.github/skills/', '.github/AGENTS.md')) {
    Assert-True ($ignoreLines -contains $rule) ".ignore must deny '$rule' so --follow does not duplicate it in the @ picker."
}

# End-to-end picker behavior, when the tools it needs are present. rg is required by the script
# itself; bash and rg are not guaranteed on every runner, so assert only when both exist.
$hasBash = [bool] (Get-Command bash -ErrorAction SilentlyContinue)
$hasRg = [bool] (Get-Command rg -ErrorAction SilentlyContinue)
if ($hasBash -and $hasRg) {
    $suggestionUnixPath = './.claude/file-suggestion.sh'
    Push-Location $repoRoot
    try {
        $env:CLAUDE_PROJECT_DIR = $repoRoot
        $picked = '{"query":"AGENTS.md"}' | & bash $suggestionUnixPath 2>$null
        $agentsHits = @($picked | Where-Object { $_.Trim() -eq 'AGENTS.md' -or $_.Trim() -eq '.github/AGENTS.md' })
        Assert-True (-not ($agentsHits -contains '.github/AGENTS.md')) 'The @ picker must not list the .github/AGENTS.md symlink mirror.'
        Assert-True ($agentsHits -contains 'AGENTS.md') 'The @ picker must still list the real root AGENTS.md.'

        $skillPicked = '{"query":"dck-build-fix"}' | & bash $suggestionUnixPath 2>$null
        $mirrorHits = @($skillPicked | Where-Object { $_ -like '.claude/skills/*' -or $_ -like '.github/skills/*' })
        Assert-True ($mirrorHits.Count -eq 0) "The @ picker must not list .claude/skills or .github/skills mirrors (got: $($mirrorHits -join ', '))."
    } finally {
        Remove-Item Env:\CLAUDE_PROJECT_DIR -ErrorAction SilentlyContinue
        Pop-Location
    }
} else {
    Write-Host 'Skipped the live @-picker checks: bash and/or rg not available on this host.'
}

Write-Host 'Worktree plans symlink tests passed.'
