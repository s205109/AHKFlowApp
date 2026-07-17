#Requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$suiteRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$realHookScript = Join-Path $suiteRoot '.githooks\pre-push.ps1'

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

# Fresh throwaway git repo standing in for "the working tree being pushed". Each repo gets its
# own stub scripts/pre-push-quick-checks.ps1 and scripts/run-coverage.ps1, distinct from the real
# repo's scripts, so invocation of the real hook script (by path) against this repo's working
# directory proves root resolution follows `git rev-parse --show-toplevel`, not $PSScriptRoot.
function New-TempGitRepo {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('prepush-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root 'scripts') -Force | Out-Null

    & git -C $root init *> $null
    & git -C $root config user.email 'test@example.com' *> $null
    & git -C $root config user.name 'Pre-Push Hook Test' *> $null
    Set-Content -LiteralPath (Join-Path $root 'README.md') -Value 'seed' -Encoding utf8
    & git -C $root add -A *> $null
    & git -C $root commit -m 'seed' *> $null

    return (Resolve-Path -LiteralPath $root).Path
}

function Write-StubQuickChecksScript {
    param(
        [string] $RepoDir,
        [string] $MarkerPath,
        [int] $ExitCode = 0
    )

    $content = @"
`$repoRoot = (Resolve-Path -LiteralPath (Join-Path `$PSScriptRoot '..')).Path
Set-Content -LiteralPath '$MarkerPath' -Value `$repoRoot -Encoding utf8
exit $ExitCode
"@
    Set-Content -LiteralPath (Join-Path $RepoDir 'scripts\pre-push-quick-checks.ps1') -Value $content -Encoding utf8
}

function Write-StubRunCoverageScript {
    param(
        [string] $RepoDir,
        [string] $MarkerPath
    )

    $content = @"
Set-Content -LiteralPath '$MarkerPath' -Value 'invoked' -Encoding utf8
exit 0
"@
    Set-Content -LiteralPath (Join-Path $RepoDir 'scripts\run-coverage.ps1') -Value $content -Encoding utf8
}

function Remove-TempTree {
    param([string] $RepoDir)
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Remove-Item -LiteralPath $RepoDir -Recurse -Force -ErrorAction Stop
            return
        } catch {
            if ($attempt -eq 3) { return }
            Start-Sleep -Milliseconds 200
        }
    }
}

# Invokes the real .githooks/pre-push.ps1 (by path, from the real repo) with the working
# directory set to $RepoDir, exactly as git does when core.hooksPath points elsewhere.
function Invoke-PrePushHook {
    param(
        [string] $RepoDir,
        [hashtable] $EnvOverrides
    )

    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    try {
        $previousValues = @{}
        if ($EnvOverrides) {
            foreach ($key in $EnvOverrides.Keys) {
                $previousValues[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
                [Environment]::SetEnvironmentVariable($key, [string] $EnvOverrides[$key], 'Process')
            }
        }

        try {
            $psExe = [System.Diagnostics.Process]::GetCurrentProcess().Path
            $proc = Start-Process -FilePath $psExe `
                -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $realHookScript) `
                -WorkingDirectory $RepoDir `
                -RedirectStandardOutput $stdoutFile `
                -RedirectStandardError $stderrFile `
                -NoNewWindow -PassThru -Wait
        } finally {
            foreach ($key in $previousValues.Keys) {
                [Environment]::SetEnvironmentVariable($key, $previousValues[$key], 'Process')
            }
        }

        return [pscustomobject]@{
            ExitCode = $proc.ExitCode
            Stdout   = Get-Content -Raw -LiteralPath $stdoutFile -ErrorAction SilentlyContinue
            Stderr   = Get-Content -Raw -LiteralPath $stderrFile -ErrorAction SilentlyContinue
        }
    } finally {
        Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
    }
}

# --- Test: SKIP_PUSH_HOOK=1 short-circuits, stub never invoked -----------------
$repo = New-TempGitRepo
try {
    $marker = Join-Path $repo 'quick-checks-invoked.txt'
    $coverageMarker = Join-Path $repo 'run-coverage-invoked.txt'
    Write-StubQuickChecksScript -RepoDir $repo -MarkerPath $marker
    Write-StubRunCoverageScript -RepoDir $repo -MarkerPath $coverageMarker

    $result = Invoke-PrePushHook -RepoDir $repo -EnvOverrides @{ SKIP_PUSH_HOOK = '1' }
    Assert-Equal 0 $result.ExitCode "SKIP_PUSH_HOOK should short-circuit with exit 0. Stderr: $($result.Stderr)"
    Assert-True (-not (Test-Path -LiteralPath $marker)) 'Quick-checks stub must not run when SKIP_PUSH_HOOK is set.'
    Assert-True (-not (Test-Path -LiteralPath $coverageMarker)) 'run-coverage.ps1 must never be invoked.'
} finally {
    Remove-TempTree $repo
}

# --- Test: legacy SKIP_COVERAGE_HOOK=1 still short-circuits --------------------
$repo = New-TempGitRepo
try {
    $marker = Join-Path $repo 'quick-checks-invoked.txt'
    $coverageMarker = Join-Path $repo 'run-coverage-invoked.txt'
    Write-StubQuickChecksScript -RepoDir $repo -MarkerPath $marker
    Write-StubRunCoverageScript -RepoDir $repo -MarkerPath $coverageMarker

    $result = Invoke-PrePushHook -RepoDir $repo -EnvOverrides @{ SKIP_COVERAGE_HOOK = '1' }
    Assert-Equal 0 $result.ExitCode "Legacy SKIP_COVERAGE_HOOK should still short-circuit with exit 0. Stderr: $($result.Stderr)"
    Assert-True (-not (Test-Path -LiteralPath $marker)) 'Quick-checks stub must not run when SKIP_COVERAGE_HOOK is set.'
    Assert-True (-not (Test-Path -LiteralPath $coverageMarker)) 'run-coverage.ps1 must never be invoked.'
} finally {
    Remove-TempTree $repo
}

# --- Test: repo root resolved from the working tree being pushed ---------------
$repo = New-TempGitRepo
try {
    $marker = Join-Path $repo 'quick-checks-invoked.txt'
    $coverageMarker = Join-Path $repo 'run-coverage-invoked.txt'
    Write-StubQuickChecksScript -RepoDir $repo -MarkerPath $marker -ExitCode 0
    Write-StubRunCoverageScript -RepoDir $repo -MarkerPath $coverageMarker

    $result = Invoke-PrePushHook -RepoDir $repo
    Assert-Equal 0 $result.ExitCode "Hook should succeed when the stub exits 0. Stderr: $($result.Stderr)"
    Assert-True (Test-Path -LiteralPath $marker) "Expected the temp repo's stub to run (proves root resolution follows the working tree, not the hook's own location). Stdout: $($result.Stdout)"

    $recordedRoot = (Get-Content -Raw -LiteralPath $marker).Trim()
    Assert-Equal $repo $recordedRoot 'The quick-checks script should have been invoked with the temp repo as its working directory.'
    Assert-True (-not (Test-Path -LiteralPath $coverageMarker)) 'run-coverage.ps1 must never be invoked.'
} finally {
    Remove-TempTree $repo
}

# --- Test: nonzero stub exit code propagates as hook failure -------------------
$repo = New-TempGitRepo
try {
    $marker = Join-Path $repo 'quick-checks-invoked.txt'
    $coverageMarker = Join-Path $repo 'run-coverage-invoked.txt'
    Write-StubQuickChecksScript -RepoDir $repo -MarkerPath $marker -ExitCode 1
    Write-StubRunCoverageScript -RepoDir $repo -MarkerPath $coverageMarker

    $result = Invoke-PrePushHook -RepoDir $repo
    Assert-True ($result.ExitCode -ne 0) "Hook should fail when the quick-checks stub exits nonzero. Stdout: $($result.Stdout)"
    Assert-True (Test-Path -LiteralPath $marker) 'Stub should still have run before failing.'
    Assert-True (-not (Test-Path -LiteralPath $coverageMarker)) 'run-coverage.ps1 must never be invoked.'
} finally {
    Remove-TempTree $repo
}

Write-Host 'Pre-push hook tests passed.'
