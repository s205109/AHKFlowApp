#Requires -Version 5.1
# The one slug rule, shared across two PowerShell floors.
#
# new-backlog-item.ps1 names a backlog item file with it, and new-worktree.ps1 names a worktree
# directory with it. Those two names have to agree: before a draft pull request exists, the
# worktree is found by matching its name against the backlog item's file name. See backlog 080.
#
# A title longer than -MaxLength is truncated with an 8-hex-char SHA-256 suffix, the same
# <slug>-<hash8> pattern Get-WorktreeComposeProjectForBranch (worktree-docker.common.ps1) and
# Get-WorktreeDatabaseNameForBranch (worktree-database.common.ps1) use for their own name
# budgets. Because both callers share this one function with no length argument of their own,
# the worktree name and the backlog item file name keep agreeing even when truncated.
#
# This file requires 5.1, not 7.0, because a #Requires inside a dot-sourced file is enforced and
# new-worktree.ps1 supports Windows PowerShell 5.1.

Set-StrictMode -Version Latest

function ConvertTo-BacklogSlug {
    param(
        [Parameter(Mandatory)][string] $Title,
        [int] $MaxLength = 40
    )

    $slug = $Title.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    $slug = $slug.Trim('-')

    if ($slug.Length -gt $MaxLength) {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($slug)
            $hash = ([System.BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant().Substring(0, 8)
        } finally {
            $sha.Dispose()
        }

        $budget = $MaxLength - 9 # '-' + 8-char hash
        $truncated = $slug.Substring(0, [Math]::Max(0, $budget)).Trim('-')
        $slug = if ($truncated) { "$truncated-$hash" } else { $hash }
    }

    return $slug
}
