#Requires -Version 5.1
<#
.SYNOPSIS
  Decide whether a branch changed any path the shared code filter does not exclude.
.DESCRIPTION
  The Gate's coverage slice starts a SQL Server container and instruments every assembly. On a
  branch that compiled no C# it costs minutes and can say nothing. This module answers the one
  question that decides whether to run it.

  State that question the way the code actually asks it: does any changed path survive the
  exclusions? Not "does anything compile?". The two differ, and the difference is not an edge
  case - ci.yml, Directory.Packages.props, and coverlet.runsettings all require the slice and
  none of them compiles.

  The patterns live in .github/code-paths-filter.yml, which ci.yml reads through
  dorny/paths-filter. One file, two readers, applying the same exclusions to the same diff.

  The answer is CoverageRequired, not CodeChanged, and the difference is real. The file's
  coverage-tooling key names seven scripts the local coverage run executes. Changing one of
  them compiles nothing and still requires the slice, because the slice is the only local
  check that runs them. CI does not read that key and does not need to: it never runs those
  scripts. So this module can be stricter than CI on seven paths, and never looser anywhere.

  The list is a deny-list. A changed path that matches no pattern requires coverage and the
  slice runs. A pattern nobody wrote costs a few minutes; an allow-list with a hole would cost
  real coverage instead.

  Every failure here - a git command that fails, a missing file, a pattern this matcher cannot
  read - throws. The caller runs the slice when it cannot decide.

  The YAML is read by hand rather than with a parser. PowerShell 5.1 ships none, and the file's
  shape is fixed: one 'code:' key and a list of single-quoted negative globs. Anything else is
  rejected loudly.
  Two functions here run git and gh and read $LASTEXITCODE. Both open with

      $PSNativeCommandUseErrorActionPreference = $false

  PowerShell 7.3 and later turn a non-zero native exit code into a terminating error while
  $ErrorActionPreference is 'Stop', and test-fast.ps1 sets exactly that. Without the opt-out
  'git rev-parse' on a ref that does not exist throws instead of returning 1, so the base-ref
  fallback loop can never reach its second candidate. The variable is set inside each function
  rather than at file scope, because this file is dot-sourced and a file-scope assignment would
  change the caller's behaviour too. The variable does not exist in PowerShell 5.1, where
  assigning it is harmless.
#>

function Get-AhkFlowCodePathFilterPath {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)
    return (Join-Path $RepoRoot '.github/code-paths-filter.yml')
}

function Read-AhkFlowFilterEntry {
    param(
        [Parameter(Mandatory = $true)][string]$FilterPath,
        [Parameter(Mandatory = $true)][string]$Key,
        # 'negative' for the code: list, whose entries all start with '!'.
        # 'plain' for coverage-tooling:, whose entries are literal repo-relative paths.
        [Parameter(Mandatory = $true)][ValidateSet('negative', 'plain')][string]$Shape
    )

    if (-not (Test-Path -LiteralPath $FilterPath -PathType Leaf)) {
        throw "Path filter file not found: $FilterPath"
    }

    $entryPattern = if ($Shape -eq 'negative') { "^\s+-\s+'!(.+)'\s*$" } else { "^\s+-\s+'([^!].*)'\s*$" }
    $lines = Get-Content -LiteralPath $FilterPath
    $inKey = $false
    $entries = New-Object System.Collections.Generic.List[string]

    foreach ($line in $lines) {
        if ($line -match '^\s*#') { continue }
        if ($line -match '^\s*$') { continue }

        if ($line -match '^([A-Za-z0-9_-]+):\s*$') {
            $inKey = ($Matches[1] -eq $Key)
            continue
        }

        if (-not $inKey) { continue }

        # Written as a positive match on purpose. -notmatch only populates $Matches when it
        # returns false, which is the branch this code would not be in.
        if ($line -match $entryPattern) {
            $entries.Add($Matches[1])
            continue
        }

        throw "Cannot read line in ${FilterPath} under '${Key}:': '$line'. Every entry must be single-quoted, and a '$Key' entry must be $Shape."
    }

    if ($entries.Count -eq 0) {
        throw "No '${Key}:' entries found in $FilterPath. An empty list here would silently change what the Gate measures."
    }

    return @($entries)
}

function Read-AhkFlowCodePathExclusion {
    param([Parameter(Mandatory = $true)][string]$FilterPath)
    return (Read-AhkFlowFilterEntry -FilterPath $FilterPath -Key 'code' -Shape 'negative')
}

function Read-AhkFlowCoverageToolingPath {
    param([Parameter(Mandatory = $true)][string]$FilterPath)
    return (Read-AhkFlowFilterEntry -FilterPath $FilterPath -Key 'coverage-tooling' -Shape 'plain')
}

function ConvertTo-AhkFlowPathRegex {
    param([Parameter(Mandatory = $true)][string]$Pattern)

    # Only these four shapes are supported, and an unsupported one throws. The alternative -
    # a full glob engine - would be a second implementation of the action's matcher, and any
    # difference between the two is exactly the disagreement this design exists to prevent.
    $segment = '[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)*'

    # **/*.ext  - any file with that extension, at any depth
    if ($Pattern -match '^\*\*/\*(\.[A-Za-z0-9]+)$') {
        return "^.*$([regex]::Escape($Matches[1]))$"
    }
    # prefix/**/*.ext - that extension anywhere under the prefix, including directly in it
    if ($Pattern -match "^($segment)/\*\*/\*(\.[A-Za-z0-9]+)`$") {
        return "^$([regex]::Escape($Matches[1]))/(?:.+/)?[^/]+$([regex]::Escape($Matches[2]))$"
    }
    # prefix/*.ext - that extension directly in the prefix, one level only
    if ($Pattern -match "^($segment)/\*(\.[A-Za-z0-9]+)`$") {
        return "^$([regex]::Escape($Matches[1]))/[^/]+$([regex]::Escape($Matches[2]))$"
    }
    # prefix/** - everything under the prefix
    if ($Pattern -match "^($segment)/\*\*`$") {
        return "^$([regex]::Escape($Matches[1]))/.+$"
    }

    throw "Unsupported path pattern: '$Pattern'. Supported shapes are '**/*.ext', 'prefix/**', 'prefix/*.ext', and 'prefix/**/*.ext'. Add the shape to ConvertTo-AhkFlowPathRegex before using it in .github/code-paths-filter.yml."
}

function Get-AhkFlowPathExclusionMatch {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Exclusion
    )

    $normalised = $Path -replace '\\', '/'
    foreach ($pattern in $Exclusion) {
        $regex = ConvertTo-AhkFlowPathRegex -Pattern $pattern
        # -cmatch, not -match. PowerShell's -match is case-insensitive and picomatch, which the
        # action uses, is case-sensitive. With -match, scripts/Thing.PS1 would be excluded here
        # and counted as code in CI - the exact disagreement this design exists to prevent.
        if ($normalised -cmatch $regex) { return $pattern }
    }

    return $null
}

function Resolve-AhkFlowGateBaseRef {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [string]$BaseRef
    )

    # See the file header. This function reads $LASTEXITCODE from git and gh.
    $PSNativeCommandUseErrorActionPreference = $false

    if (-not [string]::IsNullOrWhiteSpace($BaseRef)) { return $BaseRef }

    # Stacked work branches from another open branch, so main is the wrong base there. The pull
    # request knows the real one. This mirrors what the Gate already tells a reader to do for
    # git diff --check.
    #
    # gh reads the current directory, not a -C argument, so the location is pushed first. A
    # worktree with no pull request, no gh, or no network falls through to the loop below.
    #
    # The 'origin' check is not an optimisation. A repository with no remote can have no pull
    # request, so asking gh is pointless there - and it is what makes this function testable
    # against a throwaway repository without gh reaching the network or reading whatever
    # repository the temp folder happens to sit inside.
    & git -C $RepoRoot remote get-url origin *> $null
    $hasOrigin = ($LASTEXITCODE -eq 0)

    if ($hasOrigin -and (Get-Command gh -ErrorAction SilentlyContinue)) {
        Push-Location $RepoRoot
        try {
            $branch = & gh pr view --json baseRefName -q .baseRefName 2>$null
        }
        finally { Pop-Location }

        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($branch)) {
            $candidate = "origin/$("$branch".Trim())"
            & git -C $RepoRoot rev-parse --verify --quiet "$candidate^{commit}" *> $null
            if ($LASTEXITCODE -eq 0) { return $candidate }
        }
    }

    foreach ($candidate in @('origin/main', 'main')) {
        & git -C $RepoRoot rev-parse --verify --quiet "$candidate^{commit}" *> $null
        if ($LASTEXITCODE -eq 0) { return $candidate }
    }

    throw 'Cannot resolve a base ref. Tried the pull request base, origin/main, and main.'
}

function Get-AhkFlowChangedPath {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$BaseRef
    )

    # See the file header. This function reads $LASTEXITCODE from git.
    $PSNativeCommandUseErrorActionPreference = $false

    $paths = New-Object System.Collections.Generic.List[string]

    # --no-renames is load-bearing, not tidiness. Git detects renames by default and then prints
    # only the new path, so moving src/Foo.cs to docs/Foo.md reports one excluded .md file and
    # nothing else. The solution just lost a class and the slice would skip. Measured on git
    # 2.55.0: the default prints 'docs/Foo.md' alone, --no-renames prints both paths.
    #
    # Three dots, so the diff is against the merge base. A stale local base ref only widens the
    # result, and a wider result can only make the slice run. That direction is safe.
    $committed = & git -C $RepoRoot -c core.quotePath=false diff --no-renames --name-only "$BaseRef...HEAD"
    if ($LASTEXITCODE -ne 0) { throw "git diff against $BaseRef failed in $RepoRoot." }
    foreach ($line in $committed) {
        $value = "$line".Trim()
        if ($value) { $paths.Add($value) }
    }

    # Work still in flight counts. Someone who edited a .cs file and has not committed it yet
    # must not get a skip. --no-renames here for the same reason as above: a staged rename would
    # otherwise print 'R old -> new' and hide the old path.
    $working = & git -C $RepoRoot -c core.quotePath=false status --porcelain --no-renames --untracked-files=all
    if ($LASTEXITCODE -ne 0) { throw "git status failed in $RepoRoot." }
    foreach ($line in $working) {
        $value = "$line"
        if ($value.Length -le 3) { continue }
        $entry = $value.Substring(3).Trim()
        if ($entry) { $paths.Add($entry.Trim('"')) }
    }

    return @($paths | Sort-Object -Unique)
}

function Get-AhkFlowCoverageDecision {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [string]$BaseRef
    )

    $filterPath = Get-AhkFlowCodePathFilterPath -RepoRoot $RepoRoot
    $exclusion = Read-AhkFlowCodePathExclusion -FilterPath $filterPath
    $coverageTooling = Read-AhkFlowCoverageToolingPath -FilterPath $filterPath
    $resolvedBase = Resolve-AhkFlowGateBaseRef -RepoRoot $RepoRoot -BaseRef $BaseRef
    $changed = Get-AhkFlowChangedPath -RepoRoot $RepoRoot -BaseRef $resolvedBase

    # Ordinal and case-sensitive, to match Get-AhkFlowPathExclusionMatch.
    $toolingSet = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]$coverageTooling, [System.StringComparer]::Ordinal)

    $exclusionByPath = @{}
    $coverageRequired = $false
    foreach ($path in $changed) {
        $normalised = $path -replace '\\', '/'

        # The coverage tooling wins over the exclusions. run-coverage.ps1 is a .ps1 under
        # scripts/, so the code patterns exclude it, and it is the one file whose defect the
        # coverage slice is the only local check for.
        if ($toolingSet.Contains($normalised)) {
            $exclusionByPath[$path] = $null
            $coverageRequired = $true
            continue
        }

        $match = Get-AhkFlowPathExclusionMatch -Path $path -Exclusion $exclusion
        $exclusionByPath[$path] = $match
        if ($null -eq $match) { $coverageRequired = $true }
    }

    return [pscustomobject]@{
        # CoverageRequired, not CodeChanged. A coverage-tooling path compiles nothing and still
        # sets this true, so the old name was wrong in the one case that matters.
        CoverageRequired = $coverageRequired
        BaseRef          = $resolvedBase
        ChangedPath      = $changed
        ExclusionByPath  = $exclusionByPath
        FilterPath       = $filterPath
    }
}

function Write-AhkFlowCoverageSkipReport {
    param([Parameter(Mandatory = $true)][object]$Decision)

    Write-Host ''
    Write-Host '==> Coverage slice skipped' -ForegroundColor Cyan
    Write-Host "    Every changed file matched an exclusion, so a coverage run would measure nothing new."
    Write-Host "    Base ref      : $($Decision.BaseRef)"
    Write-Host "    Changed files : $($Decision.ChangedPath.Count)"
    foreach ($path in $Decision.ChangedPath) {
        Write-Host ("      {0,-60} excluded by {1}" -f $path, $Decision.ExclusionByPath[$path])
    }
    Write-Host "    Patterns      : $($Decision.FilterPath) - ci.yml reads the same file."
    Write-Host '    Run the slice anyway with: -Force'
    Write-Host ''
}
