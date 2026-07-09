#Requires -Version 5.1
<#
.SYNOPSIS
    Assigns deterministic localhost ports and writes worktree-local config.
.DESCRIPTION
    The main checkout keeps API/UI ports 5600/5601. Linked worktrees receive the
    first available adjacent pair in 5602-5699, persisted in scripts/.env.worktree.
    Rerunning the script reuses an existing valid manifest.
#>

[CmdletBinding()]
param(
    [string] $RepoRoot,
    [switch] $Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PortRangeStart = 5602
$PortRangeEnd = 5699
$ReservedApiPort = 5600
$ReservedUiPort = 5601
$SolutionMarker = 'AHKFlowApp.slnx'
$EnvVarPrefix = 'AHKFLOW_'
$ApiPortKey = "${EnvVarPrefix}API_PORT"
$UiPortKey = "${EnvVarPrefix}UI_PORT"
$ApiUrlKey = "${EnvVarPrefix}API_URL"
$UiUrlKey = "${EnvVarPrefix}UI_URL"
$DbNameKey = "${EnvVarPrefix}DB_NAME"
$SqlPortRangeStart = 14330
$SqlPortRangeEnd = 14399
$ReservedSqlPort = 1433
$SqlPortKey = "${EnvVarPrefix}SQL_PORT"
$ComposeProjectKey = "${EnvVarPrefix}COMPOSE_PROJECT"
# Marker env var identifying launch profiles that boot Docker SQL; every profile carrying it
# with value 'true' gets its Docker SQL env vars (compose project + SQL port) patched per
# worktree, so variants like "Docker SQL (No Auth)" stay isolated too.
$DockerSqlStartFlag = 'AHKFLOW_START_DOCKER_SQL'
$RootKey = "${EnvVarPrefix}ROOT"
$BackendAppSettingsRelativePath = 'src/Backend/AHKFlowApp.API/appsettings.json'
$FrontendAppSettingsRelativePath = 'src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.json'
$FrontendDevelopmentConfigRelativePath = 'src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.Development.json'
$BackendDevelopmentConfigRelativePath = 'src/Backend/AHKFlowApp.API/appsettings.Development.json'
$BackendLaunchSettingsRelativePath = 'src/Backend/AHKFlowApp.API/Properties/launchSettings.json'
$VsCodeLaunchSettingsRelativePath = '.vscode/launch.json'
$FrontendLaunchSettingsRelativePath = 'src/Frontend/AHKFlowApp.UI.Blazor/Properties/launchSettings.json'

. (Join-Path $PSScriptRoot 'worktree-git.common.ps1')
. (Join-Path $PSScriptRoot 'worktree-json.common.ps1')

function Resolve-RepoRoot {
    param([string] $Candidate)

    if ($Candidate) {
        return (Resolve-Path -LiteralPath $Candidate).Path
    }

    $root = (& git rev-parse --show-toplevel 2>$null).Trim()
    if (-not $root) {
        throw 'Not inside a git repository.'
    }

    return (Resolve-Path -LiteralPath $root).Path
}

function Resolve-GitCommonDirectory {
    param([string] $Root)

    return Resolve-GitPath $Root '--git-common-dir'
}

function Get-MainCheckoutRoot {
    param([string] $Root)

    $commonDir = Resolve-GitCommonDirectory $Root
    if ((Split-Path -Leaf $commonDir) -ieq '.git') {
        return (Split-Path -Parent $commonDir)
    }

    return $Root
}

function Read-ManifestValues {
    param([string] $ManifestPath)

    $values = @{}
    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        return $values
    }

    foreach ($line in Get-Content -LiteralPath $ManifestPath) {
        if ($line -match '^\s*([^#][^=]+?)\s*=\s*(.*?)\s*$') {
            $values[$matches[1].Trim()] = $matches[2].Trim()
        }
    }

    return $values
}

function Get-ManifestPort {
    param(
        [hashtable] $Values,
        [string] $Key
    )

    if (-not $Values.ContainsKey($Key)) {
        return $null
    }

    $port = 0
    if ([int]::TryParse([string] $Values[$Key], [ref] $port) -and $port -gt 0 -and $port -le 65535) {
        return $port
    }

    return $null
}

function Get-ManifestPortPair {
    param([string] $ManifestPath)

    $values = Read-ManifestValues $ManifestPath
    $apiPort = Get-ManifestPort $values $ApiPortKey
    $uiPort = Get-ManifestPort $values $UiPortKey

    if ($apiPort -and $uiPort) {
        return [pscustomobject]@{
            ApiPort = $apiPort
            UiPort = $uiPort
        }
    }

    return $null
}

function Get-WorktreePaths {
    param([string] $Root)

    $paths = New-Object System.Collections.Generic.List[string]

    $output = & git -C $Root worktree list --porcelain 2>$null
    foreach ($line in $output) {
        if ($line -like 'worktree *') {
            $path = $line.Substring('worktree '.Length)
            if ($path) {
                $paths.Add($path)
            }
        }
    }

    return $paths
}

function Assert-NotNestedLinkedWorktree {
    param([string] $Root, [string] $MainCheckoutRoot)

    # Every registered worktree except the main checkout is a linked worktree, so
    # if the current worktree sits physically inside any of those, it is nested.
    # (Properly placed worktrees live under the main checkout, hence the main skip.)
    $current = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
    $main = [System.IO.Path]::GetFullPath($MainCheckoutRoot).TrimEnd('\')

    foreach ($worktreePath in Get-WorktreePaths $Root) {
        if (-not (Test-Path -LiteralPath $worktreePath)) {
            continue
        }

        $candidate = (Resolve-Path -LiteralPath $worktreePath).Path.TrimEnd('\')
        if ($candidate -ieq $current -or $candidate -ieq $main) {
            continue
        }

        if ($current.StartsWith($candidate + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to prepare nested linked worktree '$current'. It lives inside linked worktree '$candidate'; create worktrees only from the main checkout."
        }
    }
}

function Get-ListeningPorts {
    $ports = New-Object System.Collections.Generic.List[int]

    try {
        $connections = Get-NetTCPConnection -State Listen -ErrorAction Stop |
            Where-Object { $_.LocalPort -ge $PortRangeStart -and $_.LocalPort -le $PortRangeEnd }

        foreach ($connection in $connections) {
            $ports.Add([int] $connection.LocalPort)
        }
    } catch {
        $netstatOutput = & netstat -ano -p tcp 2>$null
        foreach ($line in $netstatOutput) {
            if ($line -match '^\s*TCP\s+\S+:(\d+)\s+\S+\s+LISTENING\s+\d+\s*$') {
                $port = [int] $matches[1]
                if ($port -ge $PortRangeStart -and $port -le $PortRangeEnd) {
                    $ports.Add($port)
                }
            }
        }
    }

    return $ports
}

function Get-UsedPorts {
    param([string] $Root)

    $usedPorts = New-Object 'System.Collections.Generic.HashSet[int]'
    [void] $usedPorts.Add($ReservedApiPort)
    [void] $usedPorts.Add($ReservedUiPort)

    foreach ($worktreePath in Get-WorktreePaths $Root) {
        $manifestPath = Join-Path $worktreePath 'scripts\.env.worktree'
        $pair = Get-ManifestPortPair $manifestPath
        if ($pair) {
            [void] $usedPorts.Add([int] $pair.ApiPort)
            [void] $usedPorts.Add([int] $pair.UiPort)
        }
    }

    foreach ($port in Get-ListeningPorts) {
        [void] $usedPorts.Add($port)
    }

    return $usedPorts
}

function Get-AvailablePortPair {
    param([System.Collections.Generic.HashSet[int]] $UsedPorts)

    for ($apiPort = $PortRangeStart; $apiPort -lt $PortRangeEnd; $apiPort += 2) {
        $uiPort = $apiPort + 1
        if (-not $UsedPorts.Contains($apiPort) -and -not $UsedPorts.Contains($uiPort)) {
            return [pscustomobject]@{
                ApiPort = $apiPort
                UiPort = $uiPort
            }
        }
    }

    throw "No available adjacent API/UI port pair found in $PortRangeStart-$PortRangeEnd."
}

function Get-ListeningPortsInRange {
    param([int] $Start, [int] $End)

    $ports = New-Object System.Collections.Generic.List[int]
    try {
        $connections = Get-NetTCPConnection -State Listen -ErrorAction Stop |
            Where-Object { $_.LocalPort -ge $Start -and $_.LocalPort -le $End }
        foreach ($connection in $connections) { $ports.Add([int] $connection.LocalPort) }
    } catch {
        $netstatOutput = & netstat -ano -p tcp 2>$null
        foreach ($line in $netstatOutput) {
            if ($line -match '^\s*TCP\s+\S+:(\d+)\s+\S+\s+LISTENING\s+\d+\s*$') {
                $port = [int] $matches[1]
                if ($port -ge $Start -and $port -le $End) { $ports.Add($port) }
            }
        }
    }
    return $ports
}

function Get-UsedSqlPorts {
    param([string] $Root)

    $used = New-Object 'System.Collections.Generic.HashSet[int]'
    [void] $used.Add($ReservedSqlPort)

    foreach ($worktreePath in Get-WorktreePaths $Root) {
        $values = Read-ManifestValues (Join-Path $worktreePath 'scripts\.env.worktree')
        $port = Get-ManifestPort $values $SqlPortKey
        if ($port) { [void] $used.Add([int] $port) }
    }

    foreach ($port in Get-ListeningPortsInRange $SqlPortRangeStart $SqlPortRangeEnd) {
        [void] $used.Add([int] $port)
    }

    return $used
}

function Get-AvailableSqlPort {
    param([System.Collections.Generic.HashSet[int]] $UsedPorts)

    for ($port = $SqlPortRangeStart; $port -le $SqlPortRangeEnd; $port++) {
        if (-not $UsedPorts.Contains($port)) { return $port }
    }
    throw "No available SQL port found in $SqlPortRangeStart-$SqlPortRangeEnd."
}

function Get-WorktreeComposeProject {
    param([string] $Root)

    $branch = (& git -C $Root rev-parse --abbrev-ref HEAD 2>$null).Trim()
    if (-not $branch) { throw 'Could not resolve branch name for the compose project.' }
    return Get-WorktreeComposeProjectForBranch -Branch $branch
}

function Resolve-WorktreeSqlPort {
    param([string] $Root, [string] $ManifestPath, [string] $LockPath)

    $recorded = Get-ManifestPort (Read-ManifestValues $ManifestPath) $SqlPortKey
    if ($recorded) { return [int] $recorded }

    return [int] (Invoke-WithFileLock $LockPath {
        $again = Get-ManifestPort (Read-ManifestValues $ManifestPath) $SqlPortKey
        if ($again) { return [int] $again }
        $port = Get-AvailableSqlPort (Get-UsedSqlPorts $Root)
        Set-ManifestValue $ManifestPath $SqlPortKey ([string] $port)
        return $port
    })
}

function Resolve-WorktreeComposeProject {
    param([string] $Root, [string] $ManifestPath)

    $recorded = (Read-ManifestValues $ManifestPath)[$ComposeProjectKey]
    if ($recorded) { return $recorded }

    $name = Get-WorktreeComposeProject $Root
    Set-ManifestValue $ManifestPath $ComposeProjectKey $name
    return $name
}

function Invoke-WithFileLock {
    param(
        [string] $LockPath,
        [scriptblock] $ScriptBlock
    )

    New-Item -ItemType Directory -Path (Split-Path -Parent $LockPath) -Force | Out-Null

    $stream = $null
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(30)
    while (-not $stream) {
        try {
            $stream = [System.IO.File]::Open($LockPath, 'OpenOrCreate', 'ReadWrite', 'None')
        } catch [System.IO.IOException] {
            if ([DateTimeOffset]::UtcNow -gt $deadline) {
                throw "Timed out waiting for port allocation lock: $LockPath"
            }

            Start-Sleep -Milliseconds 200
        }
    }

    try {
        & $ScriptBlock
    } finally {
        $stream.Dispose()
    }
}

function Write-JsonFile {
    param(
        [string] $Path,
        [object] $Value
    )

    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    $json = Format-Json ($Value | ConvertTo-Json -Depth 8)
    [System.IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
}

function Update-TrackedWorktreeJsonOverride {
    param(
        [string] $Root,
        [string] $RelativePath,
        [scriptblock] $PatchJson
    )

    if (-not (Test-LinkedWorktree $Root)) {
        return
    }

    $jsonPath = Join-Path $Root ($RelativePath -replace '/', '\')
    if (-not (Test-Path -LiteralPath $jsonPath)) {
        return
    }

    & git -C $Root update-index --no-skip-worktree -- $RelativePath 2>$null

    # launch.json / launchSettings.json may carry comments and trailing commas (JSONC), which
    # Windows PowerShell 5.1's ConvertFrom-Json rejects; ConvertFrom-Jsonc tolerates them.
    $jsonObject = ConvertFrom-Jsonc (Get-Content -LiteralPath $jsonPath -Raw)
    & $PatchJson $jsonObject

    $json = Format-Json ($jsonObject | ConvertTo-Json -Depth 16)
    [System.IO.File]::WriteAllText($jsonPath, $json + [Environment]::NewLine, [System.Text.Encoding]::UTF8)

    & git -C $Root update-index --skip-worktree -- $RelativePath
}

# Set $Object.$Section.$Property = $Value on a parsed JSON object, creating the section
# and/or property when absent. Used to override appsettings keys regardless of whether the
# target's committed file already declares them.
function Set-JsonSectionValue {
    param(
        [object] $Object,
        [string] $Section,
        [string] $Property,
        [object] $Value
    )

    if (($Object.PSObject.Properties.Name) -notcontains $Section) {
        $Object | Add-Member -NotePropertyName $Section -NotePropertyValue ([pscustomobject]@{})
    }

    $sectionObject = $Object.$Section
    if (($sectionObject.PSObject.Properties.Name) -notcontains $Property) {
        $sectionObject | Add-Member -NotePropertyName $Property -NotePropertyValue $Value
    } else {
        $sectionObject.$Property = $Value
    }
}

function Write-VsCodeWorktreeLaunchConfig {
    param(
        [string] $Root,
        [string] $ApiUrl,
        [string] $UiUrl
    )

    Update-TrackedWorktreeJsonOverride $Root $VsCodeLaunchSettingsRelativePath {
        param([object] $Launch)

        foreach ($configuration in $Launch.configurations) {
            if ($configuration.name -eq 'UI: http') {
                $configuration.url = $UiUrl
            }

            # Rebase a standalone Chrome opener for the API (e.g. the Swagger browser launched
            # via serverReadyAction startDebugging), whose url hardcodes the API host:port. The
            # UI's blazorwasm config is handled above; only chrome configs point at the API here.
            if ((($configuration.PSObject.Properties.Name) -contains 'type') -and
                ($configuration.type -eq 'chrome') -and
                (($configuration.PSObject.Properties.Name) -contains 'url') -and
                ($configuration.url -match '^(https?://[^/]+)(.*)$')) {
                $configuration.url = $ApiUrl + $matches[2]
            }

            # Rebase a hardcoded API browser URL (e.g. http://localhost:5600/swagger). A
            # pattern-derived "%s/..." uriFormat is left untouched: it already follows the
            # API's actual bound port from its "Now listening on:" output.
            if (($configuration.PSObject.Properties.Name) -contains 'serverReadyAction') {
                $serverReadyAction = $configuration.serverReadyAction
                if ((($serverReadyAction.PSObject.Properties.Name) -contains 'uriFormat') -and
                    ($serverReadyAction.uriFormat -match '^(https?://[^/]+)(.*)$')) {
                    $serverReadyAction.uriFormat = $ApiUrl + $matches[2]
                }
            }
        }
    }
}

function Write-BackendWorktreeLaunchSettings {
    param(
        [string] $Root,
        [string] $ApiUrl
    )

    Update-TrackedWorktreeJsonOverride $Root $BackendLaunchSettingsRelativePath {
        param([object] $LaunchSettings)

        # Only "Project" profiles bind via applicationUrl; leave Docker/Executable/IISExpress alone.
        foreach ($profile in $LaunchSettings.profiles.PSObject.Properties.Value) {
            $names = $profile.PSObject.Properties.Name
            if (($names -contains 'commandName') -and ($profile.commandName -eq 'Project') -and
                ($names -contains 'applicationUrl')) {
                $profile.applicationUrl = $ApiUrl
            }
        }
    }
}

function Write-FrontendWorktreeLaunchSettings {
    param(
        [string] $Root,
        [string] $UiUrl
    )

    $relativePath = $FrontendLaunchSettingsRelativePath
    Update-TrackedWorktreeJsonOverride $Root $relativePath {
        param([object] $LaunchSettings)

        foreach ($profile in $LaunchSettings.profiles.PSObject.Properties.Value) {
            if ($profile.PSObject.Properties.Name -contains 'applicationUrl') {
                $profile.applicationUrl = $UiUrl
            }
        }
    }
}

function Write-BackendWorktreeAppSettings {
    param(
        [string] $Root,
        [string] $UiUrl,
        [string] $ConnectionString
    )

    Update-TrackedWorktreeJsonOverride $Root $BackendAppSettingsRelativePath {
        param([object] $Config)

        Set-JsonSectionValue $Config 'Cors' 'AllowedOrigins' @($UiUrl)
        Set-JsonSectionValue $Config 'ConnectionStrings' 'DefaultConnection' $ConnectionString
    }
}

function Write-FrontendWorktreeAppSettings {
    param(
        [string] $Root,
        [string] $ApiUrl
    )

    Update-TrackedWorktreeJsonOverride $Root $FrontendAppSettingsRelativePath {
        param([object] $Config)

        Set-JsonSectionValue $Config 'ApiHttpClient' 'BaseAddress' $ApiUrl
    }
}

# The frontend's gitignored appsettings.Development.json (local dev config such as auth) is not
# checked out into a fresh worktree. Write a deterministic no-auth config so agent worktrees get
# full CRUD via the test auth provider without ever inheriting the main checkout's real Azure AD
# IDs. In Development this file loads after appsettings.json, so its BaseAddress/Auth win.
function Write-FrontendWorktreeDevelopmentConfig {
    param(
        [string] $Root,
        [string] $ApiUrl
    )

    if (-not (Test-LinkedWorktree $Root)) {
        return
    }

    # The file is gitignored, so it is written directly (no skip-worktree bookkeeping needed).
    $worktreePath = Join-Path $Root ($FrontendDevelopmentConfigRelativePath -replace '/', '\')
    Write-JsonFile $worktreePath ([pscustomobject]@{
        Auth = [pscustomobject]@{ UseTestProvider = $true }
        ApiHttpClient = [pscustomobject]@{ BaseAddress = $ApiUrl }
    })
}

# The backend's gitignored appsettings.Development.json is likewise absent in a fresh worktree, so
# without this the worktree API runs real MSAL JWT validation and rejects the frontend's test-auth
# calls (401). Write the no-auth toggle; CORS + connection string stay in Write-BackendWorktreeAppSettings.
function Write-BackendWorktreeDevelopmentConfig {
    param(
        [string] $Root
    )

    if (-not (Test-LinkedWorktree $Root)) {
        return
    }

    $worktreePath = Join-Path $Root ($BackendDevelopmentConfigRelativePath -replace '/', '\')
    Write-JsonFile $worktreePath ([pscustomobject]@{
        Auth = [pscustomobject]@{ UseTestProvider = $true }
    })
}

. (Join-Path $PSScriptRoot 'worktree-database.common.ps1')
. (Join-Path $PSScriptRoot 'worktree-docker.common.ps1')

# $Root is the worktree (its branch names the database); $ConfigRoot is the main
# checkout, whose tracked appsettings owns the base database name and server, so
# setup and teardown (which only sees the main checkout) always agree.
function Get-WorktreeDatabaseName {
    param([string] $Root, [string] $ConfigRoot)

    $branch = (& git -C $Root rev-parse --abbrev-ref HEAD 2>$null).Trim()
    if (-not $branch) { throw 'Could not resolve branch name for the worktree database.' }

    $base = (Get-WorktreeDatabaseConfig -RepoRoot $ConfigRoot).BaseName
    return Get-WorktreeDatabaseNameForBranch -BaseName $base -Branch $branch
}

function Set-ManifestValue {
    param([string] $ManifestPath, [string] $Key, [string] $Value)

    $lines = @()
    $found = $false
    if (Test-Path -LiteralPath $ManifestPath) {
        foreach ($line in Get-Content -LiteralPath $ManifestPath) {
            if ($line -match "^\s*$([regex]::Escape($Key))\s*=") {
                $lines += "$Key=$Value"; $found = $true
            } else {
                $lines += $line
            }
        }
    }
    if (-not $found) { $lines += "$Key=$Value" }
    [System.IO.File]::WriteAllText($ManifestPath, ($lines -join [Environment]::NewLine) + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
}

# Single source of truth: reuse the recorded name; otherwise derive and backfill.
function Resolve-WorktreeDatabaseName {
    param([string] $Root, [string] $ManifestPath, [string] $ConfigRoot)

    $recorded = (Read-ManifestValues $ManifestPath)[$DbNameKey]
    if ($recorded) { return $recorded }

    $name = Get-WorktreeDatabaseName $Root $ConfigRoot
    Set-ManifestValue $ManifestPath $DbNameKey $name
    return $name
}

function Set-NoteProperty {
    param([object] $Object, [string] $Name, [object] $Value)

    if (($Object.PSObject.Properties.Name) -notcontains $Name) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    } else {
        $Object.$Name = $Value
    }
}

function Write-BackendWorktreeDockerProfile {
    param([string] $Root, [int] $SqlPort, [string] $ComposeProject)

    # Only relevant when the repo actually ships a root compose file; otherwise this adopter
    # isn't using Docker SQL and a missing profile is expected (stay silent).
    $composeIntended = Test-Path -LiteralPath (Join-Path $Root 'docker-compose.yml')

    Update-TrackedWorktreeJsonOverride $Root $BackendLaunchSettingsRelativePath {
        param([object] $LaunchSettings)

        $profiles = $LaunchSettings.profiles
        $patched = 0

        foreach ($profileName in $profiles.PSObject.Properties.Name) {
            $launchProfile = $profiles.$profileName
            if (($launchProfile.PSObject.Properties.Name) -notcontains 'environmentVariables') {
                continue
            }

            $env = $launchProfile.environmentVariables
            if (($env.PSObject.Properties.Name) -notcontains $DockerSqlStartFlag -or
                [string] $env.$DockerSqlStartFlag -ne 'true') {
                continue
            }

            Set-NoteProperty $env 'COMPOSE_PROJECT_NAME' $ComposeProject
            Set-NoteProperty $env 'AHKFLOW_SQL_PORT' ([string] $SqlPort)

            if (($env.PSObject.Properties.Name) -contains 'ConnectionStrings__DefaultConnection') {
                $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder([string] $env.'ConnectionStrings__DefaultConnection')
                $builder['Data Source'] = "localhost,$SqlPort"
                $env.'ConnectionStrings__DefaultConnection' = $builder.ConnectionString
            }
            $patched++
        }

        if ($patched -eq 0 -and $composeIntended) {
            Write-Host "WARNING: found docker-compose.yml but no launch profile with $DockerSqlStartFlag=true; Docker SQL per-worktree isolation (compose project + SQL port) was not applied."
        }
    }
}

function Write-WorktreeConfig {
    param(
        [string] $Root,
        [int] $ApiPort,
        [int] $UiPort,
        [string] $DbName,
        [string] $ConfigRoot,
        [int] $SqlPort,
        [string] $ComposeProject
    )

    $apiUrl = "http://localhost:$ApiPort"
    $uiUrl = "http://localhost:$UiPort"

    $connectionString = New-WorktreeConnectionString -ConnectionString (Get-WorktreeDatabaseConfig -RepoRoot $ConfigRoot).ConnectionString -DbName $DbName

    # Override the tracked files the app actually loads (skip-worktree), so the worktree
    # binds and talks to its own ports/DB without any Program.cs wiring in the target.
    Write-BackendWorktreeLaunchSettings $Root $apiUrl
    Write-BackendWorktreeAppSettings $Root $uiUrl $connectionString
    Write-BackendWorktreeDevelopmentConfig $Root
    Write-FrontendWorktreeAppSettings $Root $apiUrl
    Write-FrontendWorktreeDevelopmentConfig $Root $apiUrl
    Write-FrontendWorktreeLaunchSettings $Root $uiUrl
    Write-VsCodeWorktreeLaunchConfig $Root $apiUrl $uiUrl
    Write-BackendWorktreeDockerProfile $Root $SqlPort $ComposeProject
}

function Write-Manifest {
    param(
        [string] $Path,
        [string] $Root,
        [int] $ApiPort,
        [int] $UiPort,
        [string] $DbName,
        [int] $SqlPort,
        [string] $ComposeProject
    )

    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null

    $apiUrl = "http://localhost:$ApiPort"
    $uiUrl = "http://localhost:$UiPort"
    $content = @(
        "$ApiPortKey=$ApiPort",
        "$UiPortKey=$UiPort",
        "$ApiUrlKey=$apiUrl",
        "$UiUrlKey=$uiUrl",
        "$DbNameKey=$DbName",
        "$SqlPortKey=$SqlPort",
        "$ComposeProjectKey=$ComposeProject",
        "$RootKey=$Root"
    )

    [System.IO.File]::WriteAllText($Path, ($content -join [Environment]::NewLine) + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
}

$resolvedRepoRoot = Resolve-RepoRoot $RepoRoot
if (-not (Test-LinkedWorktree $resolvedRepoRoot)) {
    throw "Run setup-worktree-local-dev.ps1 from a linked git worktree. The main checkout keeps reserved ports $ReservedApiPort/$ReservedUiPort."
}

$manifestPath = Join-Path $resolvedRepoRoot 'scripts\.env.worktree'
$existingPair = Get-ManifestPortPair $manifestPath

# The main checkout owns the base database name/server (see Get-WorktreeDatabaseName);
# resolve it once so both the reuse path and the allocation path derive consistently.
$mainCheckoutRoot = Get-MainCheckoutRoot $resolvedRepoRoot
Assert-NotNestedLinkedWorktree $resolvedRepoRoot $mainCheckoutRoot

if ($existingPair) {
    $lockPath = Join-Path $mainCheckoutRoot '.claude\worktrees\.port-allocation.lock'
    $dbName = Resolve-WorktreeDatabaseName $resolvedRepoRoot $manifestPath $mainCheckoutRoot
    $sqlPort = Resolve-WorktreeSqlPort $resolvedRepoRoot $manifestPath $lockPath
    $composeProject = Resolve-WorktreeComposeProject $resolvedRepoRoot $manifestPath
    Write-WorktreeConfig $resolvedRepoRoot ([int] $existingPair.ApiPort) ([int] $existingPair.UiPort) $dbName $mainCheckoutRoot $sqlPort $composeProject
    if (-not $Quiet) {
        Write-Host "Reused worktree ports: API $($existingPair.ApiPort), UI $($existingPair.UiPort)"
    }
    exit 0
}

$lockPath = Join-Path $mainCheckoutRoot '.claude\worktrees\.port-allocation.lock'

Invoke-WithFileLock $lockPath {
    $pair = Get-ManifestPortPair $manifestPath
    if (-not $pair) {
        $usedPorts = Get-UsedPorts $resolvedRepoRoot
        $pair = Get-AvailablePortPair $usedPorts
        $dbName = Get-WorktreeDatabaseName $resolvedRepoRoot $mainCheckoutRoot
        $sqlPort = Get-AvailableSqlPort (Get-UsedSqlPorts $resolvedRepoRoot)
        $composeProject = Get-WorktreeComposeProject $resolvedRepoRoot
        Write-Manifest $manifestPath $resolvedRepoRoot ([int] $pair.ApiPort) ([int] $pair.UiPort) $dbName $sqlPort $composeProject
    } else {
        $dbName = Resolve-WorktreeDatabaseName $resolvedRepoRoot $manifestPath $mainCheckoutRoot
        $composeProject = Resolve-WorktreeComposeProject $resolvedRepoRoot $manifestPath
        $recordedSqlPort = Get-ManifestPort (Read-ManifestValues $manifestPath) $SqlPortKey
        if ($recordedSqlPort) {
            $sqlPort = [int] $recordedSqlPort
        } else {
            $sqlPort = Get-AvailableSqlPort (Get-UsedSqlPorts $resolvedRepoRoot)
            Set-ManifestValue $manifestPath $SqlPortKey ([string] $sqlPort)
        }
    }

    Write-WorktreeConfig $resolvedRepoRoot ([int] $pair.ApiPort) ([int] $pair.UiPort) $dbName $mainCheckoutRoot $sqlPort $composeProject

    if (-not $Quiet) {
        Write-Host "Assigned worktree ports: API $($pair.ApiPort), UI $($pair.UiPort)"
    }
}
