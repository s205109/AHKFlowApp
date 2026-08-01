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

# Runs a native command and returns its exit code as a plain scalar integer.
#
# A bare, unredirected native call inside a scriptblock lets PowerShell merge the command's own
# stdout lines into whatever the scriptblock returns. '& dotnet build ...; return $LASTEXITCODE'
# looks safe, but if the command prints anything, the caller receives an array of
# [...output lines..., exit code], not the exit code alone -- and '-ne 0' against that array is
# truthy for every real build, even one that succeeded.
#
# This function avoids that trap: '2>&1 | ForEach-Object { Write-Host $_ }' drains the command's
# stdout and stderr through Write-Host, which writes straight to the console host and never joins
# the success stream. That keeps two things true at once: the caller gets a clean scalar exit
# code, and the command's own output still reaches the developer even if the caller later pipes
# this function's result to Out-Null.
function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string] $FilePath,

        [Parameter(Mandatory = $true)]
        [string[]] $ArgumentList
    )

    & $FilePath @ArgumentList 2>&1 | ForEach-Object { Write-Host $_ }
    return $LASTEXITCODE
}

# The frontend project path, relative to the repo root. Read by both the builder factory below and
# scripts/run-frontend.ps1, so it lives in exactly one place.
$script:FrontendProjectPath = 'src/Frontend/AHKFlowApp.UI.Blazor'

# Builds a $Builder scriptblock for Invoke-FrontendLaunch: it runs $FilePath through
# Invoke-NativeCommand and returns the exit code as a plain scalar. scripts/run-frontend.ps1 calls
# this with 'dotnet' for its real build; RunFrontend.Tests.ps1 calls it with 'cmd' so the shipped
# wiring can be tested without ever shelling out to dotnet.
#
# The closure captures Invoke-NativeCommand as a scriptblock in $invokeNativeCommand, and calls
# that variable instead of the function name. GetNewClosure() binds the returned scriptblock to a
# new dynamic module, and a module resolves an unqualified command name against the global scope,
# not against the scope that dot-sourced this file. When a script dot-sources this file, the
# function lands in that script's own scope, so the closure could not see it by name and failed
# with "The term 'Invoke-NativeCommand' is not recognized". A captured variable has no such
# problem: GetNewClosure() copies it into the closure itself.
function New-FrontendBuilder {
    param(
        [Parameter(Mandatory = $true)]
        [string] $FilePath
    )

    $invokeNativeCommand = ${function:Invoke-NativeCommand}

    return {
        param($BuildArguments)
        return & $invokeNativeCommand -FilePath $FilePath -ArgumentList $BuildArguments
    }.GetNewClosure()
}

# Builds a $Runner scriptblock for Invoke-FrontendLaunch, the same way New-FrontendBuilder builds a
# $Builder. It runs $FilePath with $ArgumentList through Invoke-NativeCommand and returns the exit
# code as a plain scalar, so Invoke-FrontendLaunch can check it. scripts/run-frontend.ps1 calls this
# with 'dotnet' for the real run; RunFrontend.Tests.ps1 calls it with 'cmd'.
#
# The closure captures Invoke-NativeCommand in a variable for the same scope reason spelled out on
# New-FrontendBuilder above.
function New-FrontendRunner {
    param(
        [Parameter(Mandatory = $true)]
        [string] $FilePath,

        [Parameter(Mandatory = $true)]
        [string[]] $ArgumentList
    )

    $invokeNativeCommand = ${function:Invoke-NativeCommand}

    return {
        return & $invokeNativeCommand -FilePath $FilePath -ArgumentList $ArgumentList
    }.GetNewClosure()
}

# Builds the frontend for the given environment, then runs it, but only when the build succeeds.
# $Builder receives the build argument array and must return the process exit code. $Runner takes
# no arguments and returns the run's exit code, or nothing when it has no process to report on.
# Both are scriptblocks so a test can drive this without ever shelling out to dotnet.
#
# $ErrorActionPreference = 'Stop' does not stop a failed native command on its own, so both exit
# code checks below are explicit. Without the build check, a failed build would still fall through
# to $Runner and serve the previous, stale build. Without the run check, a frontend that never
# started -- a port already in use, for example -- would still let the whole command exit
# successfully.
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
        $script:FrontendProjectPath,
        "-p:WasmApplicationEnvironmentName=$EnvironmentName"
    )

    $buildExitCode = & $Builder $buildArguments
    if ($buildExitCode -ne 0) {
        throw "Frontend build failed for environment '$EnvironmentName'."
    }

    # A runner that returns nothing counts as success: it had no process exit code to report.
    $runExitCode = & $Runner
    if ($null -ne $runExitCode -and $runExitCode -ne 0) {
        throw "Frontend run failed for environment '$EnvironmentName' (exit code $runExitCode)."
    }

    return [pscustomobject]@{
        EnvironmentName = $EnvironmentName
        BuildArguments  = $buildArguments
    }
}
