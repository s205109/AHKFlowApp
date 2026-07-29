#Requires -Version 5.1
# Links a worktree's docs\superpowers at the main checkout's copy instead of duplicating it.
#
# docs\superpowers holds a second, private git repo (AHKFlowApp-plans). The public repo's
# .gitignore excludes it, so `git worktree add` never checks it out and a new worktree cannot
# see the spec or plan it is meant to implement.
#
# A copy is the wrong tool: it goes stale the moment a plan is revised, and a second clone would
# let a worktree accumulate commits that never reach the canonical repo. A symlink keeps both
# paths pointing at one working copy, so there is nothing to keep in sync.
#
# The link exists so a worktree can READ its plans. Writing and committing plans still happens
# from the main checkout path -- see the planning workflow in .claude/CLAUDE.md.
#
# Requires Write-Stderr from worktree-powershell.common.ps1; dot-source that first.

function Add-PlansSymlink {
    param(
        [string] $RepoRoot,
        [string] $WorktreePath
    )

    $sourcePath = Join-Path $RepoRoot 'docs\superpowers'
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        return
    }

    $linkPath = Join-Path $WorktreePath 'docs\superpowers'
    $resolvedSource = (Resolve-Path -LiteralPath $sourcePath).Path

    if (Test-Path -LiteralPath $linkPath) {
        $existing = Get-Item -LiteralPath $linkPath -Force
        if ($existing.LinkType -eq 'SymbolicLink') {
            $target = $existing.Target
            if ($target -is [array]) { $target = $target[0] }
            $resolvedTarget = if ($target) {
                (Resolve-Path -LiteralPath $target -ErrorAction SilentlyContinue).Path
            } else {
                $null
            }

            if ($resolvedTarget -and $resolvedTarget.TrimEnd('\') -ieq $resolvedSource.TrimEnd('\')) {
                return
            }

            Remove-Item -LiteralPath $linkPath -Force
        } else {
            # A real directory here is unexpected -- the path is gitignored, so git never creates
            # one. It may hold work someone put there by hand, so warn instead of deleting.
            Write-Stderr "docs\superpowers already exists in the worktree and is not a symlink; leaving it alone: $linkPath"
            return
        }
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $linkPath) -Force | Out-Null

    Push-Location (Split-Path -Parent $linkPath)
    try {
        cmd /c mklink /D 'superpowers' $resolvedSource > $null 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Stderr 'Failed to link docs\superpowers into the worktree; continuing without it.'
            return
        }
    } finally {
        Pop-Location
    }

    Write-Stderr "Linked docs\superpowers -> $resolvedSource"
}
