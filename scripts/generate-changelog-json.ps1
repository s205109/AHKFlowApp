#Requires -Version 7.0
[CmdletBinding()]
param(
    [switch]$Check,
    [string]$InputPath,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($InputPath)) {
    $InputPath = Join-Path $repoRoot 'CHANGELOG.md'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repoRoot 'src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/changelog.json'
}

$allowedSections = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($section in @('Added', 'Changed', 'Deprecated', 'Removed', 'Fixed', 'Security')) {
    [void]$allowedSections.Add($section)
}

function New-ChangelogEntry {
    param(
        [string]$Version,
        [AllowNull()]$Date
    )

    [pscustomobject]@{
        Version = $Version
        Date = $Date
        IsUnreleased = $Version -eq 'Unreleased'
        Sections = [System.Collections.Generic.List[object]]::new()
    }
}

function New-ChangelogSection {
    param([string]$Name)

    [pscustomobject]@{
        Name = $Name
        Items = [System.Collections.Generic.List[string]]::new()
    }
}

if (-not (Test-Path -LiteralPath $InputPath)) {
    throw "Changelog file not found: $InputPath"
}

$entries = [System.Collections.Generic.List[object]]::new()
$currentEntry = $null
$currentSection = $null
$lineNumber = 0

foreach ($line in [System.IO.File]::ReadLines($InputPath)) {
    $lineNumber++

    if ($line -match '^# Changelog\s*$') {
        continue
    }

    if ([string]::IsNullOrWhiteSpace($line)) {
        continue
    }

    if ($line -match '^## \[(?<version>[^\]]+)\](?: - (?<date>\d{4}-\d{2}-\d{2}))?\s*$') {
        $date = if ([string]::IsNullOrWhiteSpace($Matches['date'])) { $null } else { $Matches['date'] }
        $currentEntry = New-ChangelogEntry -Version $Matches['version'] -Date $date
        $entries.Add($currentEntry)
        $currentSection = $null
        continue
    }

    if ($line -match '^### (?<name>.+?)\s*$') {
        if ($null -eq $currentEntry) {
            throw "Section before release heading at line $lineNumber."
        }

        $sectionName = $Matches['name']
        if (-not $allowedSections.Contains($sectionName)) {
            throw "Unsupported changelog section '$sectionName' at line $lineNumber."
        }

        $currentSection = New-ChangelogSection -Name $sectionName
        $currentEntry.Sections.Add($currentSection)
        continue
    }

    if ($line -match '^- (?<item>.+?)\s*$') {
        if ($null -eq $currentSection) {
            throw "List item before section heading at line $lineNumber."
        }

        $currentSection.Items.Add($Matches['item'])
        continue
    }

    if ($null -eq $currentEntry) {
        continue
    }

    throw "Unsupported changelog syntax at line $lineNumber`: $line"
}

if ($entries.Count -eq 0) {
    throw "No changelog entries found in $InputPath."
}

$document = [ordered]@{
    schemaVersion = 1
    entries = @(
        foreach ($entry in $entries) {
            [ordered]@{
                version = $entry.Version
                date = $entry.Date
                isUnreleased = $entry.IsUnreleased
                sections = @(
                    foreach ($section in $entry.Sections) {
                        [ordered]@{
                            name = $section.Name
                            items = @($section.Items)
                        }
                    }
                )
            }
        }
    )
}

$json = ($document | ConvertTo-Json -Depth 8)
$normalizedJson = ($json -replace "`r`n", "`n") + "`n"

if ($Check) {
    if (-not (Test-Path -LiteralPath $OutputPath)) {
        throw "Generated changelog asset is missing: $OutputPath"
    }

    $existing = [System.IO.File]::ReadAllText($OutputPath) -replace "`r`n", "`n"
    if ($existing -ne $normalizedJson) {
        throw "Generated changelog asset is out of date. Run: pwsh ./scripts/generate-changelog-json.ps1"
    }

    Write-Host 'Generated changelog asset is current.'
    exit 0
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($OutputPath, $normalizedJson, $utf8NoBom)
Write-Host "Generated $OutputPath"
