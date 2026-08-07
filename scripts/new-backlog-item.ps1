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

Write-Host "Created $targetPath"
