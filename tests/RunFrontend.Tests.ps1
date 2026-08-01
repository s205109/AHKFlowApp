#Requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True {
    param([bool] $Condition, [string] $Message)

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Throws {
    param([scriptblock] $Action, [string] $ExpectedSubstring, [string] $Message)

    try {
        & $Action
    } catch {
        Assert-True ($_.Exception.Message -like "*$ExpectedSubstring*") "$Message (message was '$($_.Exception.Message)')"
        return
    }

    throw "$Message (no exception was thrown)"
}

. (Join-Path $repoRoot 'scripts\run-frontend.common.ps1')

# A builder stub that records the build argument array it received, instead of running dotnet.
$script:capturedBuildArguments = $null
$recordingBuilder = {
    param($BuildArguments)
    $script:capturedBuildArguments = $BuildArguments
    return 0
}
$doNothingRunner = { }

# Case 1: -NoAuth resolves to the 'NoAuth' environment, and that name reaches the build
# arguments as '-p:WasmApplicationEnvironmentName=NoAuth'.
$noAuthEnvironmentName = Get-FrontendEnvironmentName -NoAuth $true
Assert-True ($noAuthEnvironmentName -ceq 'NoAuth') "Get-FrontendEnvironmentName(NoAuth=`$true): expected 'NoAuth', got '$noAuthEnvironmentName'."

$script:capturedBuildArguments = $null
Invoke-FrontendLaunch -EnvironmentName $noAuthEnvironmentName -Builder $recordingBuilder -Runner $doNothingRunner | Out-Null
Assert-True ($script:capturedBuildArguments -contains '-p:WasmApplicationEnvironmentName=NoAuth') "Build arguments for NoAuth must carry '-p:WasmApplicationEnvironmentName=NoAuth'. Got: $($script:capturedBuildArguments -join ' ')"

# Case 2: no switch resolves to 'Development', carried the same way.
$developmentEnvironmentName = Get-FrontendEnvironmentName -NoAuth $false
Assert-True ($developmentEnvironmentName -ceq 'Development') "Get-FrontendEnvironmentName(NoAuth=`$false): expected 'Development', got '$developmentEnvironmentName'."

$script:capturedBuildArguments = $null
Invoke-FrontendLaunch -EnvironmentName $developmentEnvironmentName -Builder $recordingBuilder -Runner $doNothingRunner | Out-Null
Assert-True ($script:capturedBuildArguments -contains '-p:WasmApplicationEnvironmentName=Development') "Build arguments for Development must carry '-p:WasmApplicationEnvironmentName=Development'. Got: $($script:capturedBuildArguments -join ' ')"

# Case 3: a builder that reports success (exit code 0) is followed by exactly one runner call.
$script:runnerCallCount = 0
$successBuilder = { param($BuildArguments) return 0 }
$countingRunner = { $script:runnerCallCount++ }

Invoke-FrontendLaunch -EnvironmentName 'Development' -Builder $successBuilder -Runner $countingRunner | Out-Null
Assert-True ($script:runnerCallCount -eq 1) "Runner must be called exactly once after a successful build. Called $script:runnerCallCount times."

# Case 4: a builder that reports failure (non-zero exit code) throws, and the runner is never
# called. This is the regression test for the stale-build trap: $ErrorActionPreference = 'Stop'
# does not stop a failed native command on its own, so without an explicit exit-code check the
# runner would serve the previous, stale build.
$script:runnerCallCount = 0
$failingBuilder = { param($BuildArguments) return 1 }

Assert-Throws {
    Invoke-FrontendLaunch -EnvironmentName 'Development' -Builder $failingBuilder -Runner $countingRunner
} 'build failed' 'A failed build must throw.'
Assert-True ($script:runnerCallCount -eq 0) "Runner must never be called after a failed build. Called $script:runnerCallCount times."

Write-Host 'Run-frontend launcher tests passed.'
