#Requires -Version 5.1
# Shared logic for scripts/run-frontend.ps1. Kept separate so a test can drive the build and run
# steps through injected scriptblocks, without ever shelling out to dotnet.
# Dot-source from a script: . "$PSScriptRoot\run-frontend.common.ps1"

# Which environment name to bake into the frontend build. NoAuth signs in as the test user.
# Development is the default and uses real MSAL sign-in. Pure, so a test can call it directly.
function Get-FrontendEnvironmentName {
    param([bool] $NoAuth)

    if ($NoAuth) {
        return 'NoAuth'
    }

    return 'Development'
}

# Builds the frontend for the given environment, then runs it, but only when the build succeeds.
# $Builder receives the build argument array and must return the process exit code. $Runner takes
# no arguments. Both are scriptblocks so a test can drive this without ever shelling out to dotnet.
#
# $ErrorActionPreference = 'Stop' does not stop a failed native command on its own, so the exit
# code check below is explicit. Without it, a failed build would still fall through to $Runner and
# serve the previous, stale build.
function Invoke-FrontendLaunch {
    param(
        [Parameter(Mandatory = $true)]
        [string] $EnvironmentName,

        [Parameter(Mandatory = $true)]
        [scriptblock] $Builder,

        [Parameter(Mandatory = $true)]
        [scriptblock] $Runner
    )

    $buildArguments = @(
        'build',
        'src/Frontend/AHKFlowApp.UI.Blazor',
        "-p:WasmApplicationEnvironmentName=$EnvironmentName"
    )

    $buildExitCode = & $Builder $buildArguments
    if ($buildExitCode -ne 0) {
        throw "Frontend build failed for environment '$EnvironmentName'."
    }

    & $Runner

    return [pscustomobject]@{
        EnvironmentName = $EnvironmentName
        BuildArguments  = $buildArguments
    }
}
