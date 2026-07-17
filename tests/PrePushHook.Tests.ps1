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
# $HostExe selects the PowerShell host (pwsh or Windows PowerShell 5.1) the hook runs under,
# so the suite can prove the hook works on both - the sh shim falls back to 5.1 when pwsh is absent.
function Invoke-PrePushHook {
    param(
        [string] $RepoDir,
        [hashtable] $EnvOverrides,
        [string] $HostExe
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
            $psExe = if ($HostExe) { $HostExe } else { [System.Diagnostics.Process]::GetCurrentProcess().Path }
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

# All scenarios run against each available PowerShell host so we prove the hook works under both
# pwsh (PowerShell 7+) and Windows PowerShell 5.1 - the sh shim uses whichever is present, and a
# 3-argument Join-Path (PS 6+ only) previously broke the hook under 5.1.
function Invoke-AllScenarios {
    param([string] $HostExe, [string] $HostLabel)

    # --- Test: SKIP_PUSH_HOOK=1 short-circuits, stub never invoked -----------------
    $repo = New-TempGitRepo
    try {
        $marker = Join-Path $repo 'quick-checks-invoked.txt'
        $coverageMarker = Join-Path $repo 'run-coverage-invoked.txt'
        Write-StubQuickChecksScript -RepoDir $repo -MarkerPath $marker
        Write-StubRunCoverageScript -RepoDir $repo -MarkerPath $coverageMarker

        $result = Invoke-PrePushHook -RepoDir $repo -HostExe $HostExe -EnvOverrides @{ SKIP_PUSH_HOOK = '1' }
        Assert-Equal 0 $result.ExitCode "[$HostLabel] SKIP_PUSH_HOOK should short-circuit with exit 0. Stderr: $($result.Stderr)"
        Assert-True (-not (Test-Path -LiteralPath $marker)) "[$HostLabel] Quick-checks stub must not run when SKIP_PUSH_HOOK is set."
        Assert-True (-not (Test-Path -LiteralPath $coverageMarker)) "[$HostLabel] run-coverage.ps1 must not be invoked when the quick-checks helper is present."
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

        $result = Invoke-PrePushHook -RepoDir $repo -HostExe $HostExe -EnvOverrides @{ SKIP_COVERAGE_HOOK = '1' }
        Assert-Equal 0 $result.ExitCode "[$HostLabel] Legacy SKIP_COVERAGE_HOOK should still short-circuit with exit 0. Stderr: $($result.Stderr)"
        Assert-True (-not (Test-Path -LiteralPath $marker)) "[$HostLabel] Quick-checks stub must not run when SKIP_COVERAGE_HOOK is set."
        Assert-True (-not (Test-Path -LiteralPath $coverageMarker)) "[$HostLabel] run-coverage.ps1 must not be invoked when the quick-checks helper is present."
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

        $result = Invoke-PrePushHook -RepoDir $repo -HostExe $HostExe
        Assert-Equal 0 $result.ExitCode "[$HostLabel] Hook should succeed when the stub exits 0. Stderr: $($result.Stderr)"
        Assert-True (Test-Path -LiteralPath $marker) "[$HostLabel] Expected the temp repo's stub to run (proves root resolution follows the working tree, not the hook's own location). Stdout: $($result.Stdout)"

        $recordedRoot = (Get-Content -Raw -LiteralPath $marker).Trim()
        Assert-Equal $repo $recordedRoot "[$HostLabel] The quick-checks script should have been invoked with the temp repo as its working directory."
        Assert-True (-not (Test-Path -LiteralPath $coverageMarker)) "[$HostLabel] run-coverage.ps1 must not be invoked when the quick-checks helper is present."
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

        $result = Invoke-PrePushHook -RepoDir $repo -HostExe $HostExe
        Assert-True ($result.ExitCode -ne 0) "[$HostLabel] Hook should fail when the quick-checks stub exits nonzero. Stdout: $($result.Stdout)"
        Assert-True (Test-Path -LiteralPath $marker) "[$HostLabel] Stub should still have run before failing."
        Assert-True (-not (Test-Path -LiteralPath $coverageMarker)) "[$HostLabel] run-coverage.ps1 must not be invoked when the quick-checks helper is present."
    } finally {
        Remove-TempTree $repo
    }

    # --- Test: version skew - missing quick-checks helper falls back to run-coverage ---
    # Simulates a branch created before pre-push-quick-checks.ps1 existed being pushed under the
    # new hook (core.hooksPath points at the main checkout). The push must not be hard-blocked.
    $repo = New-TempGitRepo
    try {
        $marker = Join-Path $repo 'quick-checks-invoked.txt'
        $coverageMarker = Join-Path $repo 'run-coverage-invoked.txt'
        # Deliberately do NOT write the quick-checks stub - only the legacy run-coverage.ps1 exists.
        Write-StubRunCoverageScript -RepoDir $repo -MarkerPath $coverageMarker

        $result = Invoke-PrePushHook -RepoDir $repo -HostExe $HostExe
        Assert-Equal 0 $result.ExitCode "[$HostLabel] Hook should fall back to run-coverage.ps1 when the quick-checks helper is absent. Stderr: $($result.Stderr)"
        Assert-True (Test-Path -LiteralPath $coverageMarker) "[$HostLabel] run-coverage.ps1 must be invoked as the version-skew fallback. Stdout: $($result.Stdout)"
        Assert-True (-not (Test-Path -LiteralPath $marker)) "[$HostLabel] Quick-checks stub is absent, so its marker must not exist."
    } finally {
        Remove-TempTree $repo
    }

    # --- Test: neither check script present -> hook fails clearly ------------------
    $repo = New-TempGitRepo
    try {
        # No quick-checks stub, no run-coverage stub - the scripts/ dir is empty.
        $result = Invoke-PrePushHook -RepoDir $repo -HostExe $HostExe
        Assert-True ($result.ExitCode -ne 0) "[$HostLabel] Hook should fail when no check script is found. Stdout: $($result.Stdout)"
    } finally {
        Remove-TempTree $repo
    }
}

# Discover every PowerShell host on this machine, de-duplicated case-insensitively, so CI (which
# has both pwsh and Windows PowerShell) exercises the hook under each.
$hostExes = [System.Collections.Generic.List[string]]::new()
$seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($candidate in @(
    [System.Diagnostics.Process]::GetCurrentProcess().Path,
    (Get-Command 'pwsh' -ErrorAction SilentlyContinue).Source,
    (Get-Command 'powershell.exe' -ErrorAction SilentlyContinue).Source
)) {
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and $seen.Add($candidate)) {
        $hostExes.Add($candidate)
    }
}

foreach ($hostExe in $hostExes) {
    $hostLabel = Split-Path -Leaf $hostExe
    Write-Host "Running pre-push hook scenarios under $hostLabel ($hostExe)..."
    Invoke-AllScenarios -HostExe $hostExe -HostLabel $hostLabel
}

Write-Host 'Pre-push hook tests passed.'
