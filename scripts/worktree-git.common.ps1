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
