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

# Cases 5 and 6 drive the real wiring, not a fake exit code.
#
# Cases 1-4 hand Invoke-FrontendLaunch a fake builder that returns a clean scalar. A real builder
# never does that. A native command's own output, when it is neither redirected nor suppressed,
# joins the scriptblock's return value. The caller then receives an array of output lines plus the
# exit code, not the exit code alone. '-ne 0' against an array filters instead of comparing, so it
# returns the non-matching elements, and a non-empty array is truthy. That made every successful
# real build look like a failure. Cases 1-4 cannot see that bug, because their fake builders never
# print anything.
#
# So these two cases build $Builder with New-FrontendBuilder -FilePath 'cmd' -- the exact factory
# scripts/run-frontend.ps1 calls with 'dotnet' for its real $Builder. 'cmd' is always present on
# Windows and costs almost nothing to start, so the suite still never shells out to dotnet, while
# still exercising the shipped object rather than a locally re-declared copy of its shape.
$countingRunner2 = { $script:runnerCallCount++ }
$cmdBuilder = New-FrontendBuilder -FilePath 'cmd'

# Case 5: a build that prints two lines and exits 0 must not throw, and must reach the runner.
$script:runnerCallCount = 0
$noisySuccessBuilder = {
    param($BuildArguments)
    return & $cmdBuilder @('/c', 'echo build-line-one & echo build-line-two & exit 0')
}

$script:caughtMessage = $null
# Write-Host writes to the information stream, so '6>&1' captures the native command's own output
# here instead of letting it clutter the test console. Case 5b asserts on what this captured.
# The catch writes to $script:caughtMessage because '& { }' runs in its own child scope.
$hostOutput = & {
    try {
        Invoke-FrontendLaunch -EnvironmentName 'Development' -Builder $noisySuccessBuilder -Runner $countingRunner2 | Out-Null
    } catch {
        $script:caughtMessage = $_.Exception.Message
    }
} 6>&1

Assert-True ($null -eq $script:caughtMessage) "A noisy build that exits 0 must not throw. It threw: '$($script:caughtMessage)'"
Assert-True ($script:runnerCallCount -eq 1) "Runner must run once after a noisy, successful build. Called $script:runnerCallCount times."

# Case 5b: the build's own console output must still reach the developer, even though the call to
# Invoke-FrontendLaunch above is piped to Out-Null. An earlier version routed that output through
# the success stream, so Out-Null swallowed every line the build printed.
$hostText = (@($hostOutput) | ForEach-Object { $_.ToString() }) -join "`n"
Assert-True ($hostText -like '*build-line-one*') "The build's own output must reach the console. Got: '$hostText'"
Assert-True ($hostText -like '*build-line-two*') "The build's own output must reach the console. Got: '$hostText'"

# Case 6: the same real wiring, but the native command exits 1. It must still throw, and it must
# still never call the runner.
$script:runnerCallCount = 0
$noisyFailureBuilder = {
    param($BuildArguments)
    return & $cmdBuilder @('/c', 'echo build-failed-line & exit 1')
}

Assert-Throws {
    Invoke-FrontendLaunch -EnvironmentName 'Development' -Builder $noisyFailureBuilder -Runner $countingRunner2 6>$null
} 'build failed' 'A noisy failing build must still throw.'
Assert-True ($script:runnerCallCount -eq 0) "Runner must never run after a noisy failing build. Called $script:runnerCallCount times."

# Case 7: the builder must still work when run-frontend.common.ps1 is dot-sourced into a scope
# that is not the global one. This is the regression test for the closure-scope bug: the builder
# used to call Invoke-NativeCommand by name, and GetNewClosure() binds the returned scriptblock to
# a new dynamic module, which resolves an unqualified name against the global scope only.
#
# The check runs in a fresh host process, because the arrangement cannot be built inside this one.
# This file already dot-sourced the shared script at the top, and under 'pwsh -File' that top-level
# scope is the global scope, so a nested dot-source here would still find the earlier global copy
# and hide the bug. The child process dot-sources the script inside '& { }' only, which is exactly
# what scripts/run-frontend.ps1 does not get for free, and prints the exit code it received.
$powerShellHost = (Get-Process -Id $PID).Path
$nestedScopeScript = @"
& {
    . '$(Join-Path $repoRoot 'scripts\run-frontend.common.ps1')'
    `$nestedBuilder = New-FrontendBuilder -FilePath 'cmd'
    Write-Output ('exit-code=' + (& `$nestedBuilder @('/c', 'exit 0')))
}
"@

$nestedScopeOutput = (& $powerShellHost -NoProfile -Command $nestedScopeScript 2>&1 | ForEach-Object { $_.ToString() }) -join "`n"
Assert-True ($nestedScopeOutput -like '*exit-code=0*') "A builder created in a non-global scope must return exit code 0. Got: '$nestedScopeOutput'"

# Cases 8-10 cover the run step's exit code. The build step already had cases 4 and 6; the run step
# had nothing, so a frontend that failed to start -- a port already in use, for example -- exited
# quietly and the whole command still looked successful.

# Case 8: a runner that reports failure must throw, and the message must name the exit code.
Assert-Throws {
    Invoke-FrontendLaunch -EnvironmentName 'Development' -Builder $successBuilder -Runner { return 7 }
} 'run failed' 'A failing run must throw.'

Assert-Throws {
    Invoke-FrontendLaunch -EnvironmentName 'Development' -Builder $successBuilder -Runner { return 7 }
} '7' 'The run failure message must carry the exit code.'

# Case 9: the real runner wiring, not a fake exit code. New-FrontendRunner is the factory
# scripts/run-frontend.ps1 calls with 'dotnet'. A run that prints a line and exits 7 must still
# throw. This is the regression test for the discarded exit code: the run result used to go to
# Out-Null, so a failed start reached no check at all.
$failingRunner = New-FrontendRunner -FilePath 'cmd' -ArgumentList @('/c', 'echo run-failed-line & exit 7')

Assert-Throws {
    Invoke-FrontendLaunch -EnvironmentName 'Development' -Builder $successBuilder -Runner $failingRunner 6>$null
} 'run failed' 'A noisy failing run must still throw.'

# Case 10: the same real wiring, exiting 0. It must not throw, and the run's own console output
# must still reach the developer even though the caller pipes the result to Out-Null.
$script:caughtMessage = $null
$succeedingRunner = New-FrontendRunner -FilePath 'cmd' -ArgumentList @('/c', 'echo run-line-one & exit 0')

$runHostOutput = & {
    try {
        Invoke-FrontendLaunch -EnvironmentName 'Development' -Builder $successBuilder -Runner $succeedingRunner | Out-Null
    } catch {
        $script:caughtMessage = $_.Exception.Message
    }
} 6>&1

Assert-True ($null -eq $script:caughtMessage) "A noisy run that exits 0 must not throw. It threw: '$($script:caughtMessage)'"

$runHostText = (@($runHostOutput) | ForEach-Object { $_.ToString() }) -join "`n"
Assert-True ($runHostText -like '*run-line-one*') "The run's own output must reach the console. Got: '$runHostText'"

# Case 11: New-FrontendRunner must also work when the shared script is dot-sourced into a scope
# that is not the global one -- the same closure-scope trap case 7 covers for the builder.
$nestedRunnerScript = @"
& {
    . '$(Join-Path $repoRoot 'scripts\run-frontend.common.ps1')'
    `$nestedRunner = New-FrontendRunner -FilePath 'cmd' -ArgumentList @('/c', 'exit 0')
    Write-Output ('exit-code=' + (& `$nestedRunner))
}
"@

$nestedRunnerOutput = (& $powerShellHost -NoProfile -Command $nestedRunnerScript 2>&1 | ForEach-Object { $_.ToString() }) -join "`n"
Assert-True ($nestedRunnerOutput -like '*exit-code=0*') "A runner created in a non-global scope must return exit code 0. Got: '$nestedRunnerOutput'"

Write-Host 'Run-frontend launcher tests passed.'
