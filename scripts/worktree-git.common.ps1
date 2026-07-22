#Requires -Version 5.1
# Shared git-worktree probes used by new-worktree.ps1 and setup-worktree-local-dev.ps1.
# Both scripts must agree on what "a linked worktree" means, so keep it defined once.
function Resolve-GitPath {
    param([string] $Root, [string] $Kind)

    $path = (& git -C $Root rev-parse $Kind 2>$null).Trim()
    if (-not $path) {
        throw "Could not resolve git path: $Kind."
    }

    if ([System.IO.Path]::IsPathRooted($path)) {
        return (Resolve-Path -LiteralPath $path).Path
    }

    return (Resolve-Path -LiteralPath (Join-Path $Root $path)).Path
}

function Test-LinkedWorktree {
    param([string] $Root)

    $gitDir = Resolve-GitPath $Root '--git-dir'
    $commonDir = Resolve-GitPath $Root '--git-common-dir'
    return $gitDir.TrimEnd('\') -ine $commonDir.TrimEnd('\')
}

# AGENTS.md: worktree-born branches are '<type>/wt-<topic>'. The Claude WorktreeCreate hook
# only ever supplies a worktree name, so an untyped name cannot express intent and falls back
# to the 'fix/' type; a type prefix the caller did supply is preserved.
function ConvertTo-WorktreeBranchName {
    param([string] $Value)

    # Same sanitization as the worktree directory name, except '/' survives so a type prefix
    # can be expressed. Collapsed and trimmed because git rejects '//' and a trailing '/'.
    $safe = ($Value.Trim() -replace '[^A-Za-z0-9._/-]+', '-') -replace '/{2,}', '/'
    $safe = $safe.Trim([char[]] @('-', '/'))
    if (-not $safe) {
        throw 'Worktree branch name cannot be empty.'
    }

    $type = 'fix'
    $topic = $safe
    if ($safe -match '^(?<type>fix|feature|hotfix|refactor|test|docs|chore)/(?<topic>.+)$') {
        $type = $Matches.type
        $topic = $Matches.topic
    }

    if ($topic -notmatch '^wt-') {
        $topic = "wt-$topic"
    }

    return "$type/$topic"
}
