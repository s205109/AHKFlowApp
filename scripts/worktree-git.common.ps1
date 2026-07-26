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

function Test-RefExists {
    param(
        [string] $Root,
        [string] $Ref
    )

    # Deliberately broader than a branch probe: a base ref may legitimately be a local branch, a
    # remote-tracking ref, a tag, or a raw SHA. The '^{commit}' suffix rejects a ref that resolves
    # to something that cannot be branched from.
    & git -C $Root rev-parse --verify --quiet "$Ref^{commit}" *> $null
    return $LASTEXITCODE -eq 0
}

# Which ref a new worktree's branch starts from. Pure so the precedence is testable without a
# repo: an existing branch owns its own history, an explicit -BaseRef stacks on unmerged work,
# and HEAD is the default that preserves the historical behavior.
function Resolve-WorktreeSourceRef {
    param(
        [string] $BranchName,
        [bool] $BranchExists,
        [string] $BaseRef
    )

    # Silently ignoring -BaseRef here would hand back a worktree based on something other than
    # what was asked for — the exact confusion the parameter exists to prevent.
    if ($BaseRef -and $BranchExists) {
        throw "Branch '$BranchName' already exists, so -BaseRef '$BaseRef' cannot apply. Omit -BaseRef to check out the existing branch, or pick a new -BranchName."
    }

    if ($BranchExists) {
        return $BranchName
    }

    if ($BaseRef) {
        return $BaseRef
    }

    return 'HEAD'
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

    # The branch prefixes from AGENTS.md 'Git Workflow' — deliberately NOT the conventional
    # commit types listed alongside them ('refactor:', 'test:', 'docs:', 'chore:'), which name
    # commits rather than branches. An unrecognized leading segment is topic text, not a type.
    $type = 'fix'
    $topic = $safe
    if ($safe -match '^(?<type>feature|fix|hotfix)/(?<topic>.+)$') {
        $type = $Matches.type
        $topic = $Matches.topic
    }

    if ($topic -notmatch '^wt-') {
        $topic = "wt-$topic"
    }

    return "$type/$topic"
}
