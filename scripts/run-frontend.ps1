#Requires -Version 5.1
<#
.SYNOPSIS
  Build and start the Blazor frontend, signed in with MSAL or the no-auth test user.
.DESCRIPTION
  .NET 10 bakes the WebAssembly boot environment into the build output. Switching between
  Development and NoAuth needs a rebuild every time, so this script always builds first with
  the right environment name, then runs the build with --no-build.
.PARAMETER NoAuth
  Build and run with the NoAuth environment, so the app signs in as the test user.
  Without this switch, the app builds for Development and uses real MSAL sign-in.
#>
[CmdletBinding()]
param(
    [switch]$NoAuth
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

. "$PSScriptRoot\run-frontend.common.ps1"
. "$PSScriptRoot\Common.ps1"

$frontendProject = $script:FrontendProjectPath

$environmentName = Get-FrontendEnvironmentName -NoAuth $NoAuth.IsPresent
$modeLabel = if ($NoAuth) { 'the no-auth test user' } else { 'MSAL sign-in' }

# Read the URL from launchSettings.json instead of guessing it. Agent worktrees run on offset
# ports, so a hardcoded port would be wrong there.
$launchSettingsPath = Join-Path $repoRoot "$frontendProject/Properties/launchSettings.json"
$frontendUrl = $null
if (Test-Path -LiteralPath $launchSettingsPath) {
    $launchSettings = Get-Content -LiteralPath $launchSettingsPath -Raw | ConvertFrom-Json
    $frontendUrl = $launchSettings.profiles.http.applicationUrl
}
if (-not $frontendUrl) {
    $frontendUrl = 'check the console output below'
}

# $builder and $runCommand both go through Invoke-NativeCommand (see New-FrontendBuilder and the
# comment on Invoke-NativeCommand for why a bare native call cannot be trusted for a clean exit
# code). That keeps dotnet's own console output visible to the developer even though the call to
# Invoke-FrontendLaunch below is piped to Out-Null, and it still returns a scalar exit code that
# Invoke-FrontendLaunch can check. Write-Success writes through Write-Host, so the two lines below
# do not join the scriptblock's return value.
$builder = New-FrontendBuilder -FilePath 'dotnet'
$runCommand = New-FrontendRunner -FilePath 'dotnet' -ArgumentList @('run', '--project', $frontendProject, '--no-build')

$runner = {
    Write-Success "Starting the frontend with $modeLabel."
    Write-Success "Frontend URL: $frontendUrl"
    return & $runCommand
}

Push-Location $repoRoot
try {
    Write-Step "Building the frontend for the '$environmentName' environment"
    Invoke-FrontendLaunch -EnvironmentName $environmentName -Builder $builder -Runner $runner | Out-Null
}
finally {
    Pop-Location
}
