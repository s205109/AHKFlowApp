#Requires -Version 5.1
<#
.SYNOPSIS
    Shared worktree-database helpers: resolve the base database name and server
    from the tracked connection string, apply the canonical per-worktree naming
    rule, quote SQL identifiers, and drop a worktree database safely. Dot-sourced
    by setup-, remove-, and prune-worktree-databases.ps1 so the rule lives in one
    place. Do not call Set-StrictMode here: dot-sourcing runs in the caller scope.
.NOTES
    Uses System.Data.SqlClient (ships with Windows PowerShell 5.1; no extra
    assembly to load) and standard connection-string keywords. An open-source
    port whose connection string uses Microsoft.Data.SqlClient-only keywords
    (e.g. 'Authentication=Active Directory Default' for Azure SQL) must load
    Microsoft.Data.SqlClient and swap the SqlConnectionStringBuilder/SqlConnection
    references in THIS one file -- the single SQL-client dependency point.
#>

# Dot-source the JSON helpers so appsettings.json reads tolerate comments/trailing
# commas. remove- and prune- source this file but not the JSON helper directly, so
# declaring the dependency here keeps Get-WorktreeDatabaseConfig self-contained.
. (Join-Path $PSScriptRoot 'worktree-json.common.ps1')

# The single project-specific constant. A port to another solution changes only
# this relative path to the tracked appsettings that holds DefaultConnection.
$script:WorktreeBackendAppSettingsRelativePath =
    'src\Backend\AHKFlowApp.API\appsettings.json'

# Reads the tracked backend appsettings and returns the canonical connection
# string, its base database name (Initial Catalog), and server (Data Source).
function Get-WorktreeDatabaseConfig {
    param([Parameter(Mandatory)][string] $RepoRoot)

    $appsettingsPath = Join-Path $RepoRoot $script:WorktreeBackendAppSettingsRelativePath
    if (-not (Test-Path -LiteralPath $appsettingsPath)) {
        throw "Tracked appsettings.json not found at '$appsettingsPath'."
    }

    $connectionString = (ConvertFrom-Jsonc (Get-Content -LiteralPath $appsettingsPath -Raw)).ConnectionStrings.DefaultConnection
    if (-not $connectionString) {
        throw "appsettings.json has no ConnectionStrings.DefaultConnection at '$appsettingsPath'."
    }

    $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder($connectionString)
    if (-not $builder.InitialCatalog) {
        throw "Base connection string has no 'Database'/'Initial Catalog'; cannot derive the per-worktree database name."
    }

    return [pscustomobject]@{
        ConnectionString = $connectionString
        BaseName         = $builder.InitialCatalog
        DataSource       = $builder.DataSource
    }
}

# Canonical naming rule: <base>_<slug>_<hash8>. Null/whitespace branch -> base.
# The SHA-256 suffix keeps branches that sanitize/truncate to the same slug
# distinct. The slug (only) is truncated to keep the name within 128 chars.
function Get-WorktreeDatabaseNameForBranch {
    param(
        [Parameter(Mandatory)][string] $BaseName,
        [string] $Branch
    )

    if ([string]::IsNullOrWhiteSpace($Branch)) { return $BaseName }
    $trimmed = $Branch.Trim()

    # Even an empty slug yields <base>_<hash8> (base + 1 + 8). A base longer than
    # 119 chars cannot fit SQL Server's 128-char identifier limit, and truncating
    # the base would change which database the teardown guard matches. Fail loud.
    if ($BaseName.Length -gt (128 - 9)) {
        throw "Base database name '$BaseName' is too long ($($BaseName.Length) chars) to derive a per-worktree database name within SQL Server's 128-character limit."
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($trimmed)
        $hash = ([System.BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant().Substring(0, 8)
    } finally {
        $sha.Dispose()
    }

    $slug = ($trimmed -replace '[^A-Za-z0-9]', '_')
    while ($slug -match '__') { $slug = $slug -replace '__', '_' }
    $slug = $slug.Trim('_')

    $prefix = "${BaseName}_"
    $suffix = "_$hash"
    $slugBudget = 128 - $prefix.Length - $suffix.Length
    if ($slug.Length -gt $slugBudget) { $slug = $slug.Substring(0, [Math]::Max(0, $slugBudget)).Trim('_') }

    if (-not $slug) { return "${BaseName}_$hash" }
    return "$prefix$slug$suffix"
}

# Per-worktree connection string: the tracked string with only the database
# swapped. SqlConnectionStringBuilder is robust to Server/Data Source and
# Database/Initial Catalog aliases (the output normalizes those keywords).
function New-WorktreeConnectionString {
    param(
        [Parameter(Mandatory)][string] $ConnectionString,
        [Parameter(Mandatory)][string] $DbName
    )

    $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder($ConnectionString)
    $builder['Initial Catalog'] = $DbName
    return $builder.ConnectionString
}

# master connection string for the same server, preserving auth options.
function Get-WorktreeMasterConnectionString {
    param([Parameter(Mandatory)][string] $ConnectionString)

    $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder($ConnectionString)
    $builder['Initial Catalog'] = 'master'
    return $builder.ConnectionString
}

# Every database name on the server behind the given master connection string.
# Kept here so this file stays the single SQL-client dependency point: callers
# (prune) enumerate via this helper rather than opening their own connection.
function Get-WorktreeServerDatabaseName {
    param([Parameter(Mandatory)][string] $MasterConnectionString)

    $conn = New-Object System.Data.SqlClient.SqlConnection($MasterConnectionString)
    $conn.Open()
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = 'SELECT name FROM sys.databases'
        $reader = $cmd.ExecuteReader()
        $found = New-Object System.Collections.Generic.List[string]
        while ($reader.Read()) { $found.Add([string] $reader['name']) }
        $reader.Close()
        return $found
    } finally {
        $conn.Dispose()
    }
}

# Doubles ] so a name can be safely embedded in a [bracket-quoted] identifier.
function Get-QuotedSqlIdentifier {
    param([Parameter(Mandatory)][string] $Name)
    return ($Name -replace '\]', ']]')
}

# True when a database name is a canonical per-worktree database for the given
# base: <base>_<slug>_<hash8> or <base>_<hash8> (empty slug). Requiring the
# trailing 8-hex hash refuses the main <base> AND non-worktree databases that
# merely share the prefix (e.g. <base>_reporting).
function Test-WorktreeDatabaseName {
    param(
        [Parameter(Mandatory)][string] $BaseName,
        [string] $DbName
    )

    if ([string]::IsNullOrWhiteSpace($DbName)) { return $false }
    return [bool]($DbName -match ('^' + [regex]::Escape($BaseName) + '_(?:[A-Za-z0-9_]+_)?[0-9a-f]{8}$'))
}

# Guarded drop. Returns { Dropped; Skipped; Error } and never throws, so callers
# can report-and-continue. DDL cannot be parameterized, so the bracketed name is
# quoted; DB_ID is parameterized.
function Remove-WorktreeDatabaseByName {
    param(
        [Parameter(Mandatory)][string] $DbName,
        [Parameter(Mandatory)][string] $BaseName,
        [Parameter(Mandatory)][string] $MasterConnectionString
    )

    if (-not (Test-WorktreeDatabaseName -BaseName $BaseName -DbName $DbName)) {
        return [pscustomobject]@{ Dropped = $false; Skipped = $true; Error = $null }
    }

    $quoted = Get-QuotedSqlIdentifier $DbName
    $conn = New-Object System.Data.SqlClient.SqlConnection($MasterConnectionString)
    try {
        $conn.Open()
        $cmd = $conn.CreateCommand()
        # Report whether a database was actually dropped. A name that passes the
        # guard but does not exist on the server (e.g. the worktree API never
        # connected, so it was never created) must not be logged as "Dropped".
        $cmd.CommandText = "IF DB_ID(@name) IS NOT NULL BEGIN ALTER DATABASE [$quoted] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$quoted]; SELECT 1; END ELSE SELECT 0"
        [void] $cmd.Parameters.AddWithValue('@name', $DbName)
        $dropped = [int] $cmd.ExecuteScalar()
        if ($dropped -eq 1) {
            return [pscustomobject]@{ Dropped = $true; Skipped = $false; Error = $null }
        }
        return [pscustomobject]@{ Dropped = $false; Skipped = $true; Error = $null }
    } catch {
        return [pscustomobject]@{ Dropped = $false; Skipped = $false; Error = $_.Exception.Message }
    } finally {
        $conn.Dispose()
    }
}
