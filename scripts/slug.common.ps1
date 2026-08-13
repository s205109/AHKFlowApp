#Requires -Version 5.1
# The one slug rule, shared across two PowerShell floors.
#
# new-backlog-item.ps1 names a backlog item file with it, and new-worktree.ps1 names a worktree
# directory with it. Those two names have to agree: before a draft pull request exists, the
# worktree is found by matching its name against the backlog item's file name. See backlog 080.
#
# This file requires 5.1, not 7.0, because a #Requires inside a dot-sourced file is enforced and
# new-worktree.ps1 supports Windows PowerShell 5.1.

Set-StrictMode -Version Latest

function ConvertTo-BacklogSlug {
    param([Parameter(Mandatory)][string] $Title)

    $slug = $Title.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    return $slug.Trim('-')
}
