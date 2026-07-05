#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [uri] $ApiBaseUrl,

    [Parameter(Mandatory = $true)]
    [guid] $ClientId,

    [Parameter(Mandatory = $true)]
    [guid] $TenantId,

    [string] $Configuration = "Release",

    [string] $Runtime = "win-x64",

    [string] $OutputDirectory = ".artifacts"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\Common.ps1"

function Assert-NoPlaceholder
{
    param(
        [string] $Name,
        [string] $Value
    )

    if ($Value -match "placeholder-prod")
    {
        throw "$Name must not contain placeholder-prod."
    }
}

function Assert-RequiredJsonKeys
{
    param(
        [object] $Config,
        [string[]] $Keys
    )

    $propertyNames = @($Config.PSObject.Properties | ForEach-Object { $_.Name })
    $missingKeys = @($Keys | Where-Object { $_ -notin $propertyNames })

    if ($missingKeys.Count -gt 0)
    {
        throw "appsettings.json is missing required keys: $($missingKeys -join ', ')"
    }
}

if (-not $ApiBaseUrl.IsAbsoluteUri -or $ApiBaseUrl.Scheme -ne [System.Uri]::UriSchemeHttps)
{
    throw "ApiBaseUrl must be an absolute HTTPS URL."
}

if ($ClientId -eq [guid]::Empty)
{
    throw "ClientId must not be empty."
}

if ($TenantId -eq [guid]::Empty)
{
    throw "TenantId must not be empty."
}

$apiBaseUrlValue = $ApiBaseUrl.AbsoluteUri.TrimEnd("/")
$clientIdValue = $ClientId.ToString()
$tenantIdValue = $TenantId.ToString()

Assert-NoPlaceholder -Name "ApiBaseUrl" -Value $apiBaseUrlValue

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$projectPath = Join-Path $repoRoot "src\Tools\AHKFlowApp.CLI\AHKFlowApp.CLI.csproj"
$installDocPath = Join-Path $repoRoot "docs\cli\windows-install.md"

if (-not (Test-Path -LiteralPath $projectPath -PathType Leaf))
{
    throw "CLI project not found: $projectPath"
}

if (-not (Test-Path -LiteralPath $installDocPath -PathType Leaf))
{
    throw "Install documentation not found: $installDocPath"
}

$resolvedOutputDirectory = if ([System.IO.Path]::IsPathRooted($OutputDirectory))
{
    $OutputDirectory
}
else
{
    Join-Path $repoRoot $OutputDirectory
}

$stagingRoot = Join-Path $repoRoot ".tmp\cli-release"
$publishDirectory = Join-Path $stagingRoot "publish"
$packageDirectory = Join-Path $stagingRoot "package"
$zipPath = Join-Path $resolvedOutputDirectory "ahkflow-$Runtime.zip"

Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $publishDirectory | Out-Null
New-Item -ItemType Directory -Path $packageDirectory | Out-Null
New-Item -ItemType Directory -Path $resolvedOutputDirectory -Force | Out-Null

Write-Step "Publishing ahkflow CLI ($Runtime, $Configuration)"

dotnet publish $projectPath `
    --configuration $Configuration `
    --runtime $Runtime `
    --self-contained true `
    --output $publishDirectory `
    -p:PublishSingleFile=true `
    -p:EnableCompressionInSingleFile=true `
    -p:DebugType=None `
    -p:DebugSymbols=false

if ($LASTEXITCODE -ne 0)
{
    throw "dotnet publish failed with exit code $LASTEXITCODE."
}

$publishedExe = Join-Path $publishDirectory "ahkflow.exe"
$publishedAppSettings = Join-Path $publishDirectory "appsettings.json"

if (-not (Test-Path -LiteralPath $publishedExe -PathType Leaf))
{
    throw "Published executable not found: $publishedExe"
}

if (-not (Test-Path -LiteralPath $publishedAppSettings -PathType Leaf))
{
    throw "Published appsettings.json not found: $publishedAppSettings"
}

$config = Get-Content -LiteralPath $publishedAppSettings -Raw | ConvertFrom-Json
Assert-RequiredJsonKeys -Config $config -Keys @("ApiBaseUrl", "ClientId", "TenantId")
$config.ApiBaseUrl = $apiBaseUrlValue
$config.ClientId = $clientIdValue
$config.TenantId = $tenantIdValue
$config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $publishedAppSettings -Encoding utf8

Copy-Item -LiteralPath $publishedExe -Destination (Join-Path $packageDirectory "ahkflow.exe")
Copy-Item -LiteralPath $publishedAppSettings -Destination (Join-Path $packageDirectory "appsettings.json")
Copy-Item -LiteralPath $installDocPath -Destination (Join-Path $packageDirectory "INSTALL.md")

$packageFiles = @(Get-ChildItem -LiteralPath $packageDirectory -File | Sort-Object Name)
$expectedFiles = @("ahkflow.exe", "appsettings.json", "INSTALL.md")
$actualFiles = @($packageFiles | ForEach-Object { $_.Name } | Sort-Object)
$missingFiles = @($expectedFiles | Where-Object { $_ -notin $actualFiles })
$extraFiles = @($actualFiles | Where-Object { $_ -notin $expectedFiles })

if ($missingFiles.Count -gt 0 -or $extraFiles.Count -gt 0)
{
    throw "Package directory contents are invalid. Missing: $($missingFiles -join ', '); Extra: $($extraFiles -join ', ')"
}

$configText = Get-Content -LiteralPath (Join-Path $packageDirectory "appsettings.json") -Raw
if ($configText -match "placeholder-prod" -or $configText -match "00000000-0000-0000-0000-000000000000")
{
    throw "Packaged appsettings.json still contains placeholder values."
}

$stableTimestamp = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
$zipStream = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)

try
{
    $zipArchive = [System.IO.Compression.ZipArchive]::new($zipStream, [System.IO.Compression.ZipArchiveMode]::Create, $false)

    try
    {
        foreach ($file in $packageFiles)
        {
            $entry = $zipArchive.CreateEntry($file.Name, [System.IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = $stableTimestamp

            $entryStream = $entry.Open()
            $sourceStream = [System.IO.File]::OpenRead($file.FullName)

            try
            {
                $sourceStream.CopyTo($entryStream)
            }
            finally
            {
                $sourceStream.Dispose()
                $entryStream.Dispose()
            }
        }
    }
    finally
    {
        $zipArchive.Dispose()
    }
}
finally
{
    $zipStream.Dispose()
}

Write-Success "Created $zipPath"
