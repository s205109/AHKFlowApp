#Requires -Version 5.1
<#
.SYNOPSIS
    Creates GitHub issues from backlog markdown files.

.DESCRIPTION
    Reads backlog files from .claude\backlog, ensures the expected labels exist,
    and creates GitHub issues via the gh CLI. Runs as a dry run by default.

.PARAMETER Execute
    Creates issues for real instead of printing the gh commands.

.PARAMETER BacklogPath
    Optional path to the backlog folder. Defaults to .claude\backlog at the repo root.

.EXAMPLE
    .\scripts\create-github-issues.ps1

.EXAMPLE
    .\scripts\create-github-issues.ps1 -Execute
#>
[CmdletBinding()]
param(
    [switch]$Execute,
    [string]$BacklogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

$repoRoot = Split-Path $PSScriptRoot -Parent
$resolvedBacklogPath = if ($BacklogPath)
{
    $BacklogPath
}
else
{
    Join-Path $repoRoot '.claude\backlog'
}

if (-not (Test-Path $resolvedBacklogPath))
{
    Write-Fail "Backlog path not found: $resolvedBacklogPath"
    exit 1
}

Confirm-Command 'gh' 'https://cli.github.com/'
Assert-GitHubAuth

$epicMapping = @{
    'Backlog setup' = 'epic: backlog setup'
    'Initial project / solution' = 'epic: initial project'
    'Foundation' = 'epic: foundation'
    'Versioning' = 'epic: versioning'
    'Logging' = 'epic: logging'
    'Observability' = 'epic: observability'
    'CI/CD' = 'epic: ci/cd'
    'Authentication and authorization' = 'epic: authentication'
    'Hotstrings' = 'epic: hotstrings'
    'Hotkeys' = 'epic: hotkeys'
    'Profiles' = 'epic: profiles'
    'Script generation & download' = 'epic: script generation'
}

function Ensure-Label
{
    param(
        [string]$Name,
        [string]$Color,
        [string]$Description
    )

    $existing = gh label list --search $Name --json name | ConvertFrom-Json
    if ($existing | Where-Object { $_.name -eq $Name })
    {
        return
    }

    Write-Host "  Creating label: $Name" -ForegroundColor DarkGray
    if ($Execute)
    {
        gh label create $Name --color $Color --description $Description 2>$null | Out-Null
    }
}

Write-Step 'Ensuring labels exist...'

foreach ($label in $epicMapping.Values)
{
    Ensure-Label -Name $label -Color '7B61FF' -Description 'Epic grouping'
}

Ensure-Label -Name 'api' -Color '0075ca' -Description 'API layer'
Ensure-Label -Name 'ui' -Color 'e4e669' -Description 'UI layer'
Ensure-Label -Name 'cli' -Color 'd93f0b' -Description 'CLI layer'
Ensure-Label -Name 'enhancement' -Color 'a2eeef' -Description 'New feature or request'

$files = Get-ChildItem -Path $resolvedBacklogPath -Filter '*.md' |
    Where-Object { $_.Name -ne '000-backlog-item-template.md' } |
    Sort-Object Name

foreach ($file in $files)
{
    $content = Get-Content $file.FullName -Raw
    $firstLine = ($content -split '\r?\n', 2)[0] -replace '^#\s*', ''
    $labels = @()

    if ($content -match '\*\*Type\*\*:\s*Feature')
    {
        $labels += 'enhancement'
    }

    if ($content -match '\*\*Epic\*\*:\s*(.+)')
    {
        $epicName = $Matches[1].Trim()
        if ($epicMapping.ContainsKey($epicName))
        {
            $labels += $epicMapping[$epicName]
        }
    }

    if ($content -match '\*\*Interfaces\*\*:.*API') { $labels += 'api' }
    if ($content -match '\*\*Interfaces\*\*:.*UI') { $labels += 'ui' }
    if ($content -match '\*\*Interfaces\*\*:.*CLI') { $labels += 'cli' }

    Write-Host "Creating: $firstLine" -ForegroundColor Cyan
    Write-Host "  Labels: $($labels -join ', ')" -ForegroundColor Gray

    $issueArgs = @('issue', 'create', '--title', $firstLine, '--body-file', $file.FullName)
    foreach ($label in $labels)
    {
        $issueArgs += @('--label', $label)
    }

    if ($Execute)
    {
        & gh @issueArgs
        if ($LASTEXITCODE -ne 0)
        {
            Write-Fail "Failed to create issue: $firstLine"
            exit 1
        }

        Write-Success "Created"
    }
    else
    {
        Write-Host "  [DRY RUN] gh $($issueArgs -join ' ')" -ForegroundColor DarkGray
    }
}

if (-not $Execute)
{
    Write-Host "`nDry run complete. Run with -Execute to create issues." -ForegroundColor Yellow
}
else
{
    Write-Host "`nAll issues created!" -ForegroundColor Green
}
