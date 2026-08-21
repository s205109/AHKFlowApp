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

# Intake creates the worktree first and files the item inside it, so setup-worktree-local-dev.ps1
# always ran before this file existed and recorded an empty item number. The plan guard reads that
# number at removal time, so the number has to be written here or no normal worktree ever gets one.
# Only an empty or absent value is filled: a worktree serves one item, and a second filing must not
# take the recorded number away from the first.
$worktreeRoot = Split-Path -Parent $BacklogRoot
$manifestPath = Join-Path $worktreeRoot 'scripts\.env.worktree'
if (Test-Path -LiteralPath $manifestPath) {
    $key = 'AHKFLOW_BACKLOG_ITEM'
    try {
        $lines = @(Get-Content -LiteralPath $manifestPath -ErrorAction Stop)
        $recorded = ''
        foreach ($line in $lines) {
            if ($line -match "^\s*$key\s*=\s*(?<value>.*)$") { $recorded = $Matches.value.Trim(); break }
        }

        if (-not $recorded) {
            $updated = @()
            $replaced = $false
            foreach ($line in $lines) {
                if ($line -match "^\s*$key\s*=") { $updated += "$key=$number"; $replaced = $true }
                else { $updated += $line }
            }
            if (-not $replaced) { $updated += "$key=$number" }
            [System.IO.File]::WriteAllText($manifestPath, ($updated -join [Environment]::NewLine) + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
            Write-Host "Recorded backlog item $number in $manifestPath"
        }
    } catch {
        # The item file is written and that is the job. A manifest that could not be updated leaves
        # the plan guard with nothing to judge, which keeps the worktree rather than removing it.
        Write-Warning "Could not record the item number in $manifestPath : $($_.Exception.Message)"
    }
}

Write-Host "Created $targetPath"
