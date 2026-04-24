#Requires -Version 5.1
# Create GitHub Issues from Backlog
# Usage:
#   .\scripts\create-github-issues.ps1 -BacklogPath "<path>"           # Dry run (default)
#   .\scripts\create-github-issues.ps1 -BacklogPath "<path>" -Execute  # Create issues
#
# Example:
#   .\create-github-issues.ps1 -BacklogPath "..\..\.claude\backlog"
#   .\create-github-issues.ps1 -BacklogPath "..\..\.claude\backlog" -Execute

param(
    [switch]$Execute,
    [Parameter(Mandatory=$true)]
    [string]$BacklogPath
)

# Epic name to label mapping
$epicMapping = @{
    "Backlog setup" = "epic: backlog setup"
    "Initial project / solution" = "epic: initial project"
    "Foundation" = "epic: foundation"
    "Versioning" = "epic: versioning"
    "Logging" = "epic: logging"
    "Observability" = "epic: observability"
    "CI/CD" = "epic: ci/cd"
    "Authentication and authorization" = "epic: authentication"
    "Hotstrings" = "epic: hotstrings"
    "Hotkeys" = "epic: hotkeys"
    "Profiles" = "epic: profiles"
    "Script generation & download" = "epic: script generation"
}

# Ensure a GitHub label exists, creating it if missing
function Ensure-Label {
    param([string]$Name, [string]$Color, [string]$Description)

    $existing = gh label list --search $Name --json name | ConvertFrom-Json
    if ($existing | Where-Object { $_.name -eq $Name }) {
        return
    }

    Write-Host "  Creating label: $Name" -ForegroundColor DarkGray
    if ($Execute) {
        gh label create $Name --color $Color --description $Description 2>$null
    }
}

Write-Host "Ensuring labels exist..." -ForegroundColor Yellow

foreach ($label in $epicMapping.Values) {
    Ensure-Label -Name $label -Color "7B61FF" -Description "Epic grouping"
}
Ensure-Label -Name "api"         -Color "0075ca" -Description "API layer"
Ensure-Label -Name "ui"          -Color "e4e669" -Description "UI layer"
Ensure-Label -Name "cli"         -Color "d93f0b" -Description "CLI layer"
Ensure-Label -Name "enhancement" -Color "a2eeef" -Description "New feature or request"

Write-Host ""

$backlogPath = $BacklogPath

$files = Get-ChildItem -Path $backlogPath -Filter "*.md" |
         Where-Object { $_.Name -ne "000-backlog-item-template.md" } |
         Sort-Object Name

foreach ($file in $files) {
    $content = Get-Content $file.FullName -Raw
    $firstLine = (Get-Content $file.FullName -First 1) -replace "^#\s*", ""

    $labels = @()

    # Type label
    if ($content -match '\*\*Type\*\*:\s*Feature') { $labels += "enhancement" }

    # Epic label
    if ($content -match '\*\*Epic\*\*:\s*(.+)') {
        $epicName = $Matches[1].Trim()
        if ($epicMapping.ContainsKey($epicName)) {
            $labels += $epicMapping[$epicName]
        }
    }

    # Interface labels
    if ($content -match '\*\*Interfaces\*\*:.*API') { $labels += "api" }
    if ($content -match '\*\*Interfaces\*\*:.*UI') { $labels += "ui" }
    if ($content -match '\*\*Interfaces\*\*:.*CLI') { $labels += "cli" }

    $labelArgs = ($labels | ForEach-Object { "--label `"$_`"" }) -join " "

    Write-Host "Creating: $firstLine" -ForegroundColor Cyan
    Write-Host "  Labels: $($labels -join ', ')" -ForegroundColor Gray

    $command = "gh issue create --title `"$firstLine`" --body-file `"$($file.FullName)`" $labelArgs"

    if ($Execute) {
        Invoke-Expression $command
        Write-Host "  Created" -ForegroundColor Green
    }
    else {
        Write-Host "  [DRY RUN] $command" -ForegroundColor DarkGray
    }
}

if (-not $Execute) {
    Write-Host "`nDry run complete. Run with -Execute to create issues." -ForegroundColor Yellow
}
else {
    Write-Host "`nAll issues created!" -ForegroundColor Green
}
