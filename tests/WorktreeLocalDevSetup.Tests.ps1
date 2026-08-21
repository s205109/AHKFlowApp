#Requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$setupScript = Join-Path $repoRoot 'scripts\setup-worktree-local-dev.ps1'

# ConvertTo-JsonStringLiteral builds expected lines; New-WorktreeConnectionString computes the
# expected per-worktree connection string exactly as the setup script does.
. (Join-Path $repoRoot 'scripts\worktree-database.common.ps1')

$SeedConnection = 'Server=localhost,1433;Database=AHKFlowAppDb;User Id=sa;Password=Dev!LocalOnly_2026;TrustServerCertificate=True;MultipleActiveResultSets=true'

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [string] $Message)
    if (-not [string]::Equals([string] $Expected, [string] $Actual, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Message (expected '$Expected', got '$Actual')"
    }
}

function Assert-ExactText {
    param([string] $Expected, [string] $Actual, [string] $Message)
    if (-not [string]::Equals($Expected, $Actual, [System.StringComparison]::Ordinal)) {
        throw "$Message`n--- expected ---`n$Expected`n--- actual ---`n$Actual`n---"
    }
}

function Write-SeedFile {
    param([string] $Path, [string[]] $Lines, [switch] $WithBom)
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    [System.IO.File]::WriteAllText($Path, ($Lines -join "`n"), (New-Object System.Text.UTF8Encoding($WithBom.IsPresent)))
}

function Test-FileHasBom {
    param([string] $Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    return ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
}

function Get-FileTextWithoutBom {
    param([string] $Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $offset = if (Test-FileHasBom $Path) { 3 } else { 0 }
    return (New-Object System.Text.UTF8Encoding($false)).GetString($bytes, $offset, $bytes.Length - $offset)
}

# Idempotence is a claim about bytes, not about decoded text. Comparing BOM-stripped text
# would pass even if a second run flipped the BOM.
function Get-FileByteHash {
    param([string] $Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($sha.ComputeHash([System.IO.File]::ReadAllBytes($Path)))
    } finally {
        $sha.Dispose()
    }
}

function Invoke-TestGit {
    param([string] $RepoDir, [string[]] $GitArgs)
    # Windows PowerShell 5.1 turns native stderr into an ErrorRecord, which $ErrorActionPreference
    # = 'Stop' then treats as terminating. git writes progress to stderr, so the exit code is the
    # only reliable success signal on both hosts.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & git -C $RepoDir @GitArgs 2>&1
    } finally {
        $ErrorActionPreference = $previous
    }
    if ($LASTEXITCODE -ne 0) {
        throw "git $($GitArgs -join ' ') failed: $out"
    }
    return $out
}

# Each seed mirrors the shape of the real committed file closely enough to exercise its
# writer: the launch.json comments, the one-line arrays, and the profiles that carry the
# Docker SQL marker.

function Get-SeedVsCodeLaunch {
    return @(
        '{',
        '  "version": "0.2.0",',
        '  "configurations": [',
        '    {',
        '      "name": "API: Docker SQL (Recommended)",',
        '      "type": "coreclr",',
        '      // internalConsole is required for serverReadyAction: VS Code only scans the Debug',
        '      // Console for the pattern below (never an external/integrated terminal).',
        '      "console": "internalConsole",',
        '      "serverReadyAction": {',
        '        "action": "openExternally",',
        '        "pattern": "\\bNow listening on:",',
        '        "uriFormat": "http://localhost:5600/swagger"',
        '      }',
        '    },',
        '    {',
        '      "name": "Open Swagger (Chrome)",',
        '      "type": "chrome",',
        '      "request": "launch",',
        '      "url": "http://localhost:5600/swagger"',
        '    },',
        '    {',
        '      "name": "UI: http",',
        '      "type": "blazorwasm",',
        '      "url": "http://localhost:5601",',
        '      // Keep the UI debugger on an isolated Chrome profile. Reusing the default profile',
        '      // can hand startup off to an existing Chrome process and reintroduce cold-start crashes.',
        '      "browserConfig": {',
        '        "userDataDir": "${workspaceFolder}/.vscode/chrome-debug-profile"',
        '      }',
        '    }',
        '  ],',
        '  "compounds": [',
        '    {',
        '      "name": "Full Stack: Docker SQL (Recommended)",',
        '      "configurations": ["API: Docker SQL (Recommended)", "UI: http"],',
        '      "stopAll": true',
        '    }',
        '  ]',
        '}'
    )
}

function Get-ExpectedVsCodeLaunch {
    param([string] $ApiUrl, [string] $UiUrl)

    $lines = Get-SeedVsCodeLaunch
    $expected = @()
    foreach ($line in $lines) {
        if ($line -eq '        "uriFormat": "http://localhost:5600/swagger"') {
            $expected += "        `"uriFormat`": `"$ApiUrl/swagger`""
        } elseif ($line -eq '      "url": "http://localhost:5600/swagger"') {
            $expected += "      `"url`": `"$ApiUrl/swagger`""
        } elseif ($line -eq '      "url": "http://localhost:5601",') {
            $expected += "      `"url`": `"$UiUrl`","
        } else {
            $expected += $line
        }
    }
    return $expected
}

function Get-SeedBackendLaunchSettings {
    return @(
        '{',
        '  "$schema": "https://json.schemastore.org/launchsettings.json",',
        '  "profiles": {',
        '    "Docker SQL (Recommended)": {',
        '      "commandName": "Project",',
        '      "environmentVariables": {',
        '        "ASPNETCORE_ENVIRONMENT": "Development",',
        '        "AHKFLOW_START_DOCKER_SQL": "true",',
        '        "COMPOSE_PROJECT_NAME": "ahkflowapp",',
        "        `"ConnectionStrings__DefaultConnection`": `"$SeedConnection`"",
        '      },',
        '      "applicationUrl": "http://localhost:5600"',
        '    },',
        '    "Docker SQL (No Auth)": {',
        '      "commandName": "Project",',
        '      "environmentVariables": {',
        '        "ASPNETCORE_ENVIRONMENT": "Development",',
        '        "AHKFLOW_START_DOCKER_SQL": "true",',
        '        "COMPOSE_PROJECT_NAME": "ahkflowapp",',
        "        `"ConnectionStrings__DefaultConnection`": `"$SeedConnection`",",
        '        "Auth__UseTestProvider": "true"',
        '      },',
        '      "applicationUrl": "http://localhost:5600"',
        '    },',
        '    "LocalDB SQL": {',
        '      "commandName": "Project",',
        '      "environmentVariables": {',
        '        "ASPNETCORE_ENVIRONMENT": "Development",',
        '        "AHKFLOW_START_DOCKER_SQL": "false"',
        '      },',
        '      "applicationUrl": "http://localhost:5600"',
        '    }',
        '  }',
        '}'
    )
}

function Get-ExpectedBackendLaunchSettings {
    param([string] $ApiUrl, [string] $ComposeProject, [string] $SqlPort)

    $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder($SeedConnection)
    $builder['Data Source'] = "localhost,$SqlPort"
    $connectionLiteral = ConvertTo-JsonStringLiteral $builder.ConnectionString
    $portLiteral = ConvertTo-JsonStringLiteral $SqlPort
    $projectLiteral = ConvertTo-JsonStringLiteral $ComposeProject

    return @(
        '{',
        '  "$schema": "https://json.schemastore.org/launchsettings.json",',
        '  "profiles": {',
        '    "Docker SQL (Recommended)": {',
        '      "commandName": "Project",',
        '      "environmentVariables": {',
        '        "ASPNETCORE_ENVIRONMENT": "Development",',
        '        "AHKFLOW_START_DOCKER_SQL": "true",',
        "        `"COMPOSE_PROJECT_NAME`": $projectLiteral,",
        "        `"ConnectionStrings__DefaultConnection`": $connectionLiteral,",
        "        `"AHKFLOW_SQL_PORT`": $portLiteral",
        '      },',
        "      `"applicationUrl`": `"$ApiUrl`"",
        '    },',
        '    "Docker SQL (No Auth)": {',
        '      "commandName": "Project",',
        '      "environmentVariables": {',
        '        "ASPNETCORE_ENVIRONMENT": "Development",',
        '        "AHKFLOW_START_DOCKER_SQL": "true",',
        "        `"COMPOSE_PROJECT_NAME`": $projectLiteral,",
        "        `"ConnectionStrings__DefaultConnection`": $connectionLiteral,",
        '        "Auth__UseTestProvider": "true",',
        "        `"AHKFLOW_SQL_PORT`": $portLiteral",
        '      },',
        "      `"applicationUrl`": `"$ApiUrl`"",
        '    },',
        '    "LocalDB SQL": {',
        '      "commandName": "Project",',
        '      "environmentVariables": {',
        '        "ASPNETCORE_ENVIRONMENT": "Development",',
        '        "AHKFLOW_START_DOCKER_SQL": "false"',
        '      },',
        "      `"applicationUrl`": `"$ApiUrl`"",
        '    }',
        '  }',
        '}'
    )
}

function Get-SeedBackendAppSettings {
    return @(
        '{',
        '  "ConnectionStrings": {',
        "    `"DefaultConnection`": `"$SeedConnection`"",
        '  },',
        '  "Serilog": {',
        '    "Using": [ "Serilog.Sinks.Console", "Serilog.Sinks.File" ]',
        '  },',
        '  "AllowedHosts": "*",',
        '  "Cors": {',
        '    "AllowedOrigins": []',
        '  }',
        '}'
    )
}

function Get-ExpectedBackendAppSettings {
    param([string] $UiUrl, [string] $DbName)

    $connectionLiteral = ConvertTo-JsonStringLiteral (New-WorktreeConnectionString -ConnectionString $SeedConnection -DbName $DbName)

    return @(
        '{',
        '  "ConnectionStrings": {',
        "    `"DefaultConnection`": $connectionLiteral",
        '  },',
        '  "Serilog": {',
        '    "Using": [ "Serilog.Sinks.Console", "Serilog.Sinks.File" ]',
        '  },',
        '  "AllowedHosts": "*",',
        '  "Cors": {',
        "    `"AllowedOrigins`": [`"$UiUrl`"]",
        '  }',
        '}'
    )
}

function Get-SeedFrontendLaunchSettings {
    return @(
        '{',
        '  "$schema": "http://json.schemastore.org/launchsettings.json",',
        '  "profiles": {',
        '    "http": {',
        '      "commandName": "Project",',
        '      "applicationUrl": "http://localhost:5601",',
        '      "environmentVariables": {',
        '        "ASPNETCORE_ENVIRONMENT": "Development"',
        '      }',
        '    }',
        '  }',
        '}'
    )
}

function Get-ExpectedFrontendLaunchSettings {
    param([string] $UiUrl)

    $lines = Get-SeedFrontendLaunchSettings
    $expected = @()
    foreach ($line in $lines) {
        if ($line -eq '      "applicationUrl": "http://localhost:5601",') {
            $expected += "      `"applicationUrl`": `"$UiUrl`","
        } else {
            $expected += $line
        }
    }
    return $expected
}

function Get-SeedFrontendAppSettings {
    return @(
        '{',
        '  "ApiHttpClient": {',
        '    "BaseAddress": "http://localhost:5600"',
        '  },',
        '  "AzureAd": {',
        '    "Instance": "https://login.microsoftonline.com/",',
        '    "ValidateAuthority": true',
        '  }',
        '}'
    )
}

function Get-ExpectedFrontendAppSettings {
    param([string] $ApiUrl)

    $lines = Get-SeedFrontendAppSettings
    $expected = @()
    foreach ($line in $lines) {
        if ($line -eq '    "BaseAddress": "http://localhost:5600"') {
            $expected += "    `"BaseAddress`": `"$ApiUrl`""
        } else {
            $expected += $line
        }
    }
    return $expected
}

# Fresh main-checkout repo seeded with all five tracked files the setup script rewrites, plus
# the backend appsettings it reads to derive the per-worktree database. Worktrees are created
# as siblings, matching the harness in the other Worktree*.Tests.ps1 files.
function New-TempMainCheckout {
    param([switch] $BackendAppSettingsWithBom)

    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('wtsetup-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $repo = Join-Path $root 'repo'
    New-Item -ItemType Directory -Path $repo -Force | Out-Null

    & git -C $repo init *> $null
    & git -C $repo symbolic-ref HEAD refs/heads/main *> $null
    & git -C $repo config user.email 'test@example.com' *> $null
    & git -C $repo config user.name 'Worktree Setup Test' *> $null

    # The seeds are written with LF. A global core.autocrlf=true would rewrite them to CRLF on
    # checkout, so the byte-for-byte expectations below would depend on the developer's git config.
    & git -C $repo config core.autocrlf false *> $null

    Write-SeedFile (Join-Path $repo 'src\Backend\AHKFlowApp.API\appsettings.json') (Get-SeedBackendAppSettings) -WithBom:$BackendAppSettingsWithBom
    Write-SeedFile (Join-Path $repo 'src\Backend\AHKFlowApp.API\Properties\launchSettings.json') (Get-SeedBackendLaunchSettings)
    Write-SeedFile (Join-Path $repo 'src\Frontend\AHKFlowApp.UI.Blazor\Properties\launchSettings.json') (Get-SeedFrontendLaunchSettings)
    Write-SeedFile (Join-Path $repo 'src\Frontend\AHKFlowApp.UI.Blazor\wwwroot\appsettings.json') (Get-SeedFrontendAppSettings)
    Write-SeedFile (Join-Path $repo '.vscode\launch.json') (Get-SeedVsCodeLaunch)

    # Compose file marks the repo as a Docker SQL adopter so profile patching is expected.
    Write-SeedFile (Join-Path $repo 'docker-compose.yml') @('services: {}')

    Invoke-TestGit $repo @('add', '-A') | Out-Null
    Invoke-TestGit $repo @('commit', '-m', 'seed') | Out-Null

    return (Resolve-Path -LiteralPath $repo).Path
}

function Add-TestWorktree {
    param([string] $RepoDir, [string] $BranchName)
    $wtPath = Join-Path (Split-Path -Parent $RepoDir) ('wt-' + $BranchName)
    Invoke-TestGit $RepoDir @('worktree', 'add', '-b', $BranchName, $wtPath, 'main') | Out-Null
    return (Resolve-Path -LiteralPath $wtPath).Path
}

function Remove-TempTree {
    param([string] $RepoDir)
    $root = Split-Path -Parent $RepoDir
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop
            return
        } catch {
            if ($attempt -eq 3) { return }
            Start-Sleep -Milliseconds 200
        }
    }
}

function Get-ManifestPort {
    param([string] $ManifestPath, [string] $Key)
    foreach ($line in Get-Content -LiteralPath $ManifestPath) {
        if ($line -match "^\s*$([regex]::Escape($Key))\s*=\s*(.+?)\s*$") { return $matches[1] }
    }
    throw "Manifest '$ManifestPath' has no key '$Key'."
}

# --- Test: setup writes both no-auth dev configs, frontend points at the allocated API port ---
$repo = New-TempMainCheckout
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-noauth'

    & $setupScript -RepoRoot $wtPath -Quiet
    Assert-True ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) 'Setup script should succeed.'

    $backendDev = Join-Path $wtPath 'src\Backend\AHKFlowApp.API\appsettings.Development.json'
    $frontendDev = Join-Path $wtPath 'src\Frontend\AHKFlowApp.UI.Blazor\wwwroot\appsettings.Development.json'

    Assert-True (Test-Path -LiteralPath $backendDev) "Backend dev config should be written at $backendDev."
    Assert-True (Test-Path -LiteralPath $frontendDev) "Frontend dev config should be written at $frontendDev."

    $backend = Get-Content -Raw -LiteralPath $backendDev | ConvertFrom-Json
    Assert-True ([bool] $backend.Auth.UseTestProvider) 'Backend dev config must enable the test auth provider.'

    $frontend = Get-Content -Raw -LiteralPath $frontendDev | ConvertFrom-Json
    Assert-True ([bool] $frontend.Auth.UseTestProvider) 'Frontend dev config must enable the test auth provider.'

    # Regression guard: the old copy-from-main behavior leaked the main checkout's real Azure AD IDs
    # into worktrees. The deterministic writer must not emit an AzureAd section.
    Assert-True (($frontend.PSObject.Properties.Name) -notcontains 'AzureAd') 'Frontend dev config must not carry Azure AD IDs.'

    $apiPort = Get-ManifestPort (Join-Path $wtPath 'scripts\.env.worktree') 'AHKFLOW_API_PORT'
    Assert-Equal "http://localhost:$apiPort" $frontend.ApiHttpClient.BaseAddress 'Frontend BaseAddress must match the allocated API port.'

    # Regression guard: every Docker SQL profile (marker AHKFLOW_START_DOCKER_SQL=true) must get
    # per-worktree SQL isolation — originally only "Docker SQL (Recommended)" was patched, so
    # "Docker SQL (No Auth)" kept pointing at the main checkout's SQL container on 1433.
    $sqlPort = Get-ManifestPort (Join-Path $wtPath 'scripts\.env.worktree') 'AHKFLOW_SQL_PORT'
    $composeProject = Get-ManifestPort (Join-Path $wtPath 'scripts\.env.worktree') 'AHKFLOW_COMPOSE_PROJECT'
    $launchSettingsPath = Join-Path $wtPath 'src\Backend\AHKFlowApp.API\Properties\launchSettings.json'
    $launch = Get-Content -Raw -LiteralPath $launchSettingsPath | ConvertFrom-Json

    foreach ($profileName in @('Docker SQL (Recommended)', 'Docker SQL (No Auth)')) {
        $profileEnv = $launch.profiles.$profileName.environmentVariables
        Assert-Equal $composeProject $profileEnv.COMPOSE_PROJECT_NAME "'$profileName' must use the worktree compose project."
        Assert-Equal $sqlPort $profileEnv.AHKFLOW_SQL_PORT "'$profileName' must use the worktree SQL port."
        Assert-True ($profileEnv.ConnectionStrings__DefaultConnection -match [regex]::Escape("localhost,$sqlPort")) "'$profileName' connection string must target the worktree SQL port."
    }

    $localDbEnv = $launch.profiles.'LocalDB SQL'.environmentVariables
    Assert-True (($localDbEnv.PSObject.Properties.Name) -notcontains 'COMPOSE_PROJECT_NAME') 'Non-Docker profile must not be patched with a compose project.'

    # --- backlog 048: the rewrite must change only the intended values ---

    $manifestPath = Join-Path $wtPath 'scripts\.env.worktree'
    $uiPort = Get-ManifestPort $manifestPath 'AHKFLOW_UI_PORT'
    $dbName = Get-ManifestPort $manifestPath 'AHKFLOW_DB_NAME'
    $apiUrl = "http://localhost:$apiPort"
    $uiUrl = "http://localhost:$uiPort"

    $rewritten = @(
        @{ Path = '.vscode\launch.json'; Expected = (Get-ExpectedVsCodeLaunch -ApiUrl $apiUrl -UiUrl $uiUrl) },
        @{ Path = 'src\Backend\AHKFlowApp.API\Properties\launchSettings.json'; Expected = (Get-ExpectedBackendLaunchSettings -ApiUrl $apiUrl -ComposeProject $composeProject -SqlPort $sqlPort) },
        @{ Path = 'src\Backend\AHKFlowApp.API\appsettings.json'; Expected = (Get-ExpectedBackendAppSettings -UiUrl $uiUrl -DbName $dbName) },
        @{ Path = 'src\Frontend\AHKFlowApp.UI.Blazor\Properties\launchSettings.json'; Expected = (Get-ExpectedFrontendLaunchSettings -UiUrl $uiUrl) },
        @{ Path = 'src\Frontend\AHKFlowApp.UI.Blazor\wwwroot\appsettings.json'; Expected = (Get-ExpectedFrontendAppSettings -ApiUrl $apiUrl) }
    )

    foreach ($file in $rewritten) {
        $fullPath = Join-Path $wtPath $file.Path
        Assert-True (-not (Test-FileHasBom $fullPath)) "$($file.Path) must not gain a UTF-8 BOM."
        Assert-ExactText (($file.Expected) -join "`n") (Get-FileTextWithoutBom $fullPath) "$($file.Path) must change only the intended values."
    }

    # Named separately because a missing comment fails with a clearer message than a whole-file mismatch.
    $launchText = Get-FileTextWithoutBom (Join-Path $wtPath '.vscode\launch.json')
    foreach ($comment in @(
        '// internalConsole is required for serverReadyAction: VS Code only scans the Debug',
        '// Keep the UI debugger on an isolated Chrome profile. Reusing the default profile'
    )) {
        Assert-True ($launchText.Contains($comment)) "launch.json must keep the comment '$comment'."
    }

    # The two generated dev configs are gitignored and written whole, but must not gain a BOM either.
    Assert-True (-not (Test-FileHasBom $backendDev)) 'The generated backend dev config must not carry a BOM.'
    Assert-True (-not (Test-FileHasBom $frontendDev)) 'The generated frontend dev config must not carry a BOM.'

    # Running setup a second time must produce byte-identical files, BOM state included.
    $before = @{}
    foreach ($file in $rewritten) { $before[$file.Path] = Get-FileByteHash (Join-Path $wtPath $file.Path) }
    & $setupScript -RepoRoot $wtPath -Quiet
    foreach ($file in $rewritten) {
        Assert-ExactText $before[$file.Path] (Get-FileByteHash (Join-Path $wtPath $file.Path)) "$($file.Path) must be byte-identical after a second setup run."
    }
} finally {
    Remove-TempTree $repo
}

# --- backlog 048: a file that already had a BOM keeps it ---
# Without this case, a Read-JsoncFile that strips the BOM and never puts it back would pass
# every other assertion above.
$repo = New-TempMainCheckout -BackendAppSettingsWithBom
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'feat-bom'
    & $setupScript -RepoRoot $wtPath -Quiet

    $manifestPath = Join-Path $wtPath 'scripts\.env.worktree'
    $uiUrl = 'http://localhost:' + (Get-ManifestPort $manifestPath 'AHKFLOW_UI_PORT')
    $dbName = Get-ManifestPort $manifestPath 'AHKFLOW_DB_NAME'
    $appSettingsPath = Join-Path $wtPath 'src\Backend\AHKFlowApp.API\appsettings.json'

    Assert-True (Test-FileHasBom $appSettingsPath) 'A file that already had a BOM must keep it.'
    Assert-ExactText ((Get-ExpectedBackendAppSettings -UiUrl $uiUrl -DbName $dbName) -join "`n") `
        (Get-FileTextWithoutBom $appSettingsPath) 'The BOM file must change only the intended values.'

    # A second run must not drop the BOM either, which only a byte comparison can prove.
    $bomHashBefore = Get-FileByteHash $appSettingsPath
    & $setupScript -RepoRoot $wtPath -Quiet
    Assert-True (Test-FileHasBom $appSettingsPath) 'A second run must not drop an existing BOM.'
    Assert-ExactText $bomHashBefore (Get-FileByteHash $appSettingsPath) 'The BOM file must be byte-identical after a second setup run.'
} finally {
    Remove-TempTree $repo
}

# --- backlog 073: the manifest records which backlog item this worktree serves ---
# The plan guard reads this key at removal time. By then the folder may already be renamed, and
# the slug match already misses for at least one live worktree, so the number is captured once
# here, at creation, while both names still exist.
$repo = New-TempMainCheckout
try {
    # The item number is derived by matching the worktree slug against the backlog file name.
    Write-SeedFile (Join-Path $repo 'backlog\073-planguard-probe.md') @('# 073 - planguard probe')
    Invoke-TestGit $repo @('add', '-A') | Out-Null
    Invoke-TestGit $repo @('commit', '-m', 'seed backlog item') | Out-Null

    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'planguard-probe'
    & $setupScript -RepoRoot $wtPath -Quiet

    $manifestPath = Join-Path $wtPath 'scripts\.env.worktree'
    $manifestText = Get-Content -Raw -LiteralPath $manifestPath
    Assert-True ($manifestText -match '(?m)^AHKFLOW_BACKLOG_ITEM=') 'The manifest must carry AHKFLOW_BACKLOG_ITEM'
    Assert-Equal '073' (Get-ManifestPort $manifestPath 'AHKFLOW_BACKLOG_ITEM') 'The manifest must record the matching item number.'

    # A second run must not change the recorded number.
    & $setupScript -RepoRoot $wtPath -Quiet
    Assert-Equal '073' (Get-ManifestPort $manifestPath 'AHKFLOW_BACKLOG_ITEM') 'A second setup run must keep the recorded item number.'
} finally {
    Remove-TempTree $repo
}

# --- backlog 073: a worktree with no matching backlog item still gets the key, left empty ---
# An absent key and an empty key mean different things to the plan guard: empty says "nothing to
# judge", absent would be a worktree the setup script never touched.
$repo = New-TempMainCheckout
try {
    $wtPath = Add-TestWorktree -RepoDir $repo -BranchName 'no-item-here'
    & $setupScript -RepoRoot $wtPath -Quiet

    $manifestText = Get-Content -Raw -LiteralPath (Join-Path $wtPath 'scripts\.env.worktree')
    Assert-True ($manifestText -match '(?m)^AHKFLOW_BACKLOG_ITEM=\s*$') 'A worktree with no backlog item records an empty value.'
} finally {
    Remove-TempTree $repo
}

Write-Host 'Worktree local-dev setup no-auth tests passed.'
