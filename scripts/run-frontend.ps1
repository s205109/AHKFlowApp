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
$frontendProject = 'src/Frontend/AHKFlowApp.UI.Blazor'

. "$PSScriptRoot\run-frontend.common.ps1"
. "$PSScriptRoot\Common.ps1"

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

# Both scriptblocks run their real command through Invoke-NativeCommand. That keeps the build's
# reported exit code a clean scalar (see the comment on Invoke-NativeCommand for why a bare
# native call cannot be trusted for that), and it keeps dotnet's own console output visible to
# the developer even though the call to Invoke-FrontendLaunch below is piped to Out-Null.
$builder = {
    param($BuildArguments)
    return Invoke-NativeCommand -FilePath 'dotnet' -ArgumentList $BuildArguments
}

$runner = {
    Write-Success "Starting the frontend with $modeLabel."
    Write-Success "Frontend URL: $frontendUrl"
    Invoke-NativeCommand -FilePath 'dotnet' -ArgumentList @('run', '--project', $frontendProject, '--no-build') | Out-Null
}

Push-Location $repoRoot
try {
    Write-Step "Building the frontend for the '$environmentName' environment"
    Invoke-FrontendLaunch -EnvironmentName $environmentName -Builder $builder -Runner $runner | Out-Null
}
finally {
    Pop-Location
}
