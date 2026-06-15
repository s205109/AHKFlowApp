#Requires -Version 5.1
<#
.SYNOPSIS
    Shared worktree-Docker helpers: the canonical per-worktree Compose project name
    rule (mirroring src/Backend/AHKFlowApp.API/Worktrees/WorktreeComposeProject.cs),
    a guard, a guarded teardown, and a host project enumerator. Dot-sourced by setup-,
    remove-, and prune-worktree-docker.ps1 so the rule lives in one place. The single
    docker-CLI dependency point (mirrors worktree-database.common.ps1's SQL-client role).
    Do not call Set-StrictMode here: dot-sourcing runs in the caller scope.
#>

# Lowercase base; Docker Compose requires lowercase project names.
$script:WorktreeComposeBaseName = 'ahkflowapp'

# Canonical rule: <base>_<slug>_<hash8>. Null/whitespace branch -> base.
# Hash over the trimmed raw branch; slug lowercased. Matches the C# helper exactly.
function Get-WorktreeComposeProjectForBranch {
    param([string] $Branch)

    $base = $script:WorktreeComposeBaseName
    if ([string]::IsNullOrWhiteSpace($Branch)) { return $base }
    $trimmed = $Branch.Trim()

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($trimmed)
        $hash = ([System.BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant().Substring(0, 8)
    } finally {
        $sha.Dispose()
    }

    $slug = ($trimmed.ToLowerInvariant() -replace '[^a-z0-9]', '_')
    while ($slug -match '__') { $slug = $slug -replace '__', '_' }
    $slug = $slug.Trim('_')

    $prefix = "${base}_"
    $suffix = "_$hash"
    $slugBudget = 63 - $prefix.Length - $suffix.Length
    if ($slug.Length -gt $slugBudget) { $slug = $slug.Substring(0, [Math]::Max(0, $slugBudget)).Trim('_') }

    if (-not $slug) { return "${base}_$hash" }
    return "$prefix$slug$suffix"
}

# True when a name is a canonical per-worktree project: <base>_<slug>_<hash8> or
# <base>_<hash8>. The trailing 8-hex hash refuses the main <base> and unrelated names.
function Test-WorktreeComposeProject {
    param([string] $Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    return [bool]($Name -match ('^' + [regex]::Escape($script:WorktreeComposeBaseName) + '_(?:[a-z0-9_]+_)?[0-9a-f]{8}$'))
}

# Every Compose project on the host (running and stopped). Returns names only.
# Returns an empty list when docker is missing/unreachable, so callers under
# $ErrorActionPreference='Stop' (the prune script) degrade instead of aborting:
# a missing 'docker' command would otherwise raise a terminating CommandNotFound.
function Get-WorktreeComposeProjectsOnHost {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { return @() }
    try {
        $json = & docker compose ls --all --format json 2>$null
    } catch {
        return @()
    }
    if (-not $json) { return @() }
    try { $parsed = ($json | Out-String) | ConvertFrom-Json } catch { return @() }
    # PS 5.1: ConvertFrom-Json returns $null for '[]', and piping $null through
    # ForEach-Object iterates once (yielding ''), so guard before projecting names.
    if ($null -eq $parsed) { return @() }
    return @($parsed | ForEach-Object { [string] $_.Name })
}

# Guarded teardown. Returns { Removed; Skipped; Error } and never throws. Runs
# 'docker compose -f <file> -p <name> down -v', removing the project's container,
# network, and named data volume. The compose file is required so 'down' can resolve
# the volume to delete.
function Remove-WorktreeDockerProject {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $ComposeFilePath
    )

    if (-not (Test-WorktreeComposeProject -Name $Name)) {
        return [pscustomobject]@{ Removed = $false; Skipped = $true; Error = $null }
    }
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ Removed = $false; Skipped = $false; Error = 'docker not found' }
    }
    if (-not (Test-Path -LiteralPath $ComposeFilePath)) {
        return [pscustomobject]@{ Removed = $false; Skipped = $false; Error = "compose file not found: $ComposeFilePath" }
    }

    try {
        & docker compose -f $ComposeFilePath -p $Name down -v 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            return [pscustomobject]@{ Removed = $true; Skipped = $false; Error = $null }
        }
        return [pscustomobject]@{ Removed = $false; Skipped = $false; Error = "docker compose down exited $LASTEXITCODE" }
    } catch {
        return [pscustomobject]@{ Removed = $false; Skipped = $false; Error = $_.Exception.Message }
    }
}
