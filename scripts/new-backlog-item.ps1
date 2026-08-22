#Requires -Version 7.0
<#
.SYNOPSIS
    Scaffolds a new backlog/ item from the template, with the next free number filled in.

.DESCRIPTION
    Never pick a backlog number by hand — two items have already ended up sharing one
    (see backlog 061). This script reads backlog/000-backlog-item-template.md, works out the
    next free number across backlog/, backlog/done/, and backlog/blocked/, and writes the new
    file. A finished or blocked item keeps its number reserved, so no folder frees a number.

.EXAMPLE
    pwsh ./scripts/new-backlog-item.ps1 -Title "Downloads page row stays disabled"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Title,

    [string] $BacklogRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'backlog')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'backlog.common.ps1')
# Set-ManifestBacklogItem lives beside Get-ManifestBacklogItem, the reader the plan guard uses.
. (Join-Path $PSScriptRoot 'worktree-git.common.ps1')

$templatePath = Join-Path $BacklogRoot '000-backlog-item-template.md'
if (-not (Test-Path -LiteralPath $templatePath)) {
    throw "Template not found: $templatePath"
}

$number = Get-NextBacklogNumber -BacklogRoot $BacklogRoot
$slug = ConvertTo-BacklogSlug -Title $Title
if (-not $slug) {
    throw "Title '$Title' produced an empty slug."
}

$targetPath = Join-Path $BacklogRoot "$number-$slug.md"

$templateLines = Get-Content -LiteralPath $templatePath
$templateLines[0] = "# $number - $Title"
$content = ($templateLines -join "`n") + "`n"

New-BacklogFile -Path $targetPath -Content $content

Write-Host "Created $targetPath"

# Intake creates the worktree first and files the item inside it, so setup-worktree-local-dev.ps1
# always ran before this file existed and could not record a number. The plan guard reads that
# number at removal time, so it has to be written here or no normal worktree ever gets one.
#
# The newest filing wins. Keeping an older value is what let a finished item with the same title
# bind this worktree to a plan that was never its own.
$worktreeRoot = Split-Path -Parent $BacklogRoot
if (Test-Path -LiteralPath (Join-Path $worktreeRoot 'scripts\.env.worktree')) {
    if (Set-ManifestBacklogItem -WorktreePath $worktreeRoot -ItemNumber $number) {
        Write-Host "Recorded backlog item $number for the worktree at $worktreeRoot"
    } else {
        # Not a warning. An unrecorded number reads as empty at removal time, and empty ALLOWS
        # removal, so a silent failure here is the plan guard quietly switching itself off for
        # this worktree. The item file above is written and kept; only the filing command fails.
        throw ("Created $targetPath, but could not record item $number in " +
            "$worktreeRoot\scripts\.env.worktree. Close whatever holds that file and run this again, " +
            'or the worktree cleanup guard will never check this item''s plan.')
    }
}
