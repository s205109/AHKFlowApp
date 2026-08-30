#Requires -Version 5.1
<#
.SYNOPSIS
Tests for the coverage-slice skip decision shared by the local Gate and ci.yml.

.DESCRIPTION
Three layers are covered here.

  1. Reading .github/code-paths-filter.yml and turning each pattern into a regex.
  2. Deciding from a real branch diff, in a throwaway git repository under the temp folder.
  3. The wiring in scripts/test-fast.ps1, driven in a synthetic repository whose
     run-coverage.ps1 is a stub that writes a marker file. The marker is what proves the
     slice ran; no SQL Server container is ever started by this suite.

No case runs against the real repository's own diff. That diff changes with every commit, so a
case reading it would pass or fail depending on what the developer had edited.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# PowerShell 7.4 turns a non-zero native exit code into a terminating error while
# $ErrorActionPreference is 'Stop'. Several cases here run git and a child pwsh and read the
# exit code themselves, so opt out.
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts\code-change-filter.common.ps1')

$script:Failures = New-Object System.Collections.Generic.List[string]

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-TestCase {
    param([string] $Name, [scriptblock] $Body)
    try {
        & $Body
        Write-Host "  PASS  $Name" -ForegroundColor Green
    }
    catch {
        $script:Failures.Add("$Name :: $($_.Exception.Message)")
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        Write-Host "        $($_.Exception.Message)" -ForegroundColor DarkRed
    }
}

Invoke-TestCase 'The real filter file parses into a non-empty pattern list' {
    $path = Get-AhkFlowCodePathFilterPath -RepoRoot $repoRoot
    Assert-True (Test-Path -LiteralPath $path) "Filter file not found at $path."

    $exclusion = Read-AhkFlowCodePathExclusion -FilterPath $path
    Assert-True ($exclusion.Count -ge 6) "Expected at least 6 patterns, got $($exclusion.Count)."
    Assert-True ($exclusion -contains '**/*.md') 'Expected the markdown pattern.'
    Assert-True ($exclusion -contains 'scripts/*.ps1') 'Expected the top-level scripts pattern.'
    Assert-True ($exclusion -contains 'scripts/**/*.ps1') 'Expected the nested scripts pattern.'
    Assert-True ($exclusion -contains 'tests/*.ps1') 'Expected the PowerShell suites pattern.'
}

Invoke-TestCase 'Each supported pattern shape matches the right paths' {
    $exclusion = Read-AhkFlowCodePathExclusion -FilterPath (Get-AhkFlowCodePathFilterPath -RepoRoot $repoRoot)

    $excluded = @(
        'backlog/119-thing.md'
        'README.md'
        'docs/development/testing-workflow.md'
        '.claude/rules/agents.md'
        'scripts/test-fast.ps1'
        'scripts/agents/check-symlinks.ps1'
        'scripts/ci/generate-changelog-json.ps1'
        'tests/CoverageSliceSkip.Tests.ps1'
    )
    foreach ($path in $excluded) {
        $match = Get-AhkFlowPathExclusionMatch -Path $path -Exclusion $exclusion
        Assert-True ($null -ne $match) "Expected '$path' to be excluded, and nothing matched it."
    }

    $code = @(
        'Program.cs'
        'AHKFlowApp.csproj'
        'src/Backend/AHKFlowApp.Domain/Entities/Hotstring.cs'
        'tests/AHKFlowApp.Domain.Tests/HotstringTests.cs'
        'scripts/ci/check-coverage-thresholds.py'
        'Directory.Packages.props'
        'coverlet.runsettings'
    )
    foreach ($path in $code) {
        $match = Get-AhkFlowPathExclusionMatch -Path $path -Exclusion $exclusion
        Assert-True ($null -eq $match) "Expected '$path' to count as code, but pattern '$match' excluded it."
    }
}

Invoke-TestCase 'Under .github, only a lowercase .md file is excluded' {
    # The list carries no '.github/**' pattern, so every file there counts as code - except one
    # ending in lowercase '.md', which '**/*.md' excludes wherever it sits. That split is
    # deliberate and worth pinning: a change to ci.yml or to the filter itself must run the
    # pipeline it changes, while a change to an instructions file under .github compiles nothing.
    #
    # 'Markdown' would be the wrong word for the exclusion. Matching is case-sensitive, so a
    # file named .MD is Markdown to a reader and code to this filter. The third loop pins that.
    #
    # The PowerShell suites that do check .github Markdown - PersonalDefaultsSyncMarker, for
    # one - run in the powershell-suites job, which carries no filter at all.
    $exclusion = Read-AhkFlowCodePathExclusion -FilterPath (Get-AhkFlowCodePathFilterPath -RepoRoot $repoRoot)

    foreach ($path in @('.github/workflows/ci.yml', '.github/code-paths-filter.yml')) {
        $match = Get-AhkFlowPathExclusionMatch -Path $path -Exclusion $exclusion
        Assert-True ($null -eq $match) `
            "'$path' must require coverage - a change to the pipeline must run the pipeline. Pattern '$match' excluded it."
    }

    foreach ($path in @('.github/instructions/personal-defaults.md', '.github/PULL_REQUEST_TEMPLATE.md')) {
        $match = Get-AhkFlowPathExclusionMatch -Path $path -Exclusion $exclusion
        Assert-True ($match -ceq '**/*.md') `
            "'$path' must be excluded by '**/*.md'. Got '$match'."
    }

    foreach ($path in @('.github/instructions/PERSONAL-DEFAULTS.MD', '.github/Readme.Md')) {
        $match = Get-AhkFlowPathExclusionMatch -Path $path -Exclusion $exclusion
        Assert-True ($null -eq $match) `
            "'$path' is Markdown to a reader but not lowercase .md, so it must count as code. Pattern '$match' excluded it."
    }
}

Invoke-TestCase 'Matching is case-sensitive, the way the action matches' {
    # PowerShell's -match is case-insensitive and picomatch is not. With -match, this path is
    # excluded here and counted as code in CI, which is the disagreement the shared file exists
    # to prevent.
    $exclusion = Read-AhkFlowCodePathExclusion -FilterPath (Get-AhkFlowCodePathFilterPath -RepoRoot $repoRoot)

    # DOCS/ carries a .txt extension on purpose. With .md, '**/*.md' excludes it whatever the
    # case of the folder, so the case would pass with a case-insensitive matcher and prove
    # nothing about 'docs/**'.
    foreach ($path in @('scripts/Thing.PS1', 'DOCS/thing.txt', 'README.MD')) {
        $match = Get-AhkFlowPathExclusionMatch -Path $path -Exclusion $exclusion
        Assert-True ($null -eq $match) "Expected '$path' to count as code under case-sensitive matching, but '$match' excluded it."
    }

    # The same names in the case the patterns actually use are still excluded.
    foreach ($path in @('scripts/thing.ps1', 'docs/thing.txt', 'README.md')) {
        $match = Get-AhkFlowPathExclusionMatch -Path $path -Exclusion $exclusion
        Assert-True ($null -ne $match) "Expected '$path' to be excluded."
    }
}

Invoke-TestCase 'The coverage tooling list is exactly the seven files the slice runs' {
    # The exact set, not a couple of spot checks. Asserting only that two entries are present,
    # and that whatever entries remain exist on disk, lets any of the other five be deleted
    # from the YAML with the suite still green - and a deleted entry silently stops protecting
    # that file.
    $path = Get-AhkFlowCodePathFilterPath -RepoRoot $repoRoot
    $tooling = @(Read-AhkFlowCoverageToolingPath -FilterPath $path | Sort-Object)

    $expected = @(
        'scripts/Common.ps1'
        'scripts/code-change-filter.common.ps1'
        'scripts/coverage-inputs.common.ps1'
        'scripts/run-coverage.ps1'
        'scripts/test-fast.ps1'
        'scripts/test-run-lock.common.ps1'
        'scripts/test-sql-container.common.ps1'
    ) | Sort-Object

    Assert-True ($tooling.Count -eq 7) "Expected 7 coverage-tooling entries, got $($tooling.Count): $($tooling -join ', ')"
    Assert-True (($tooling -join '|') -ceq ($expected -join '|')) `
        "Coverage tooling list does not match. Got: $($tooling -join ', ')"

    # An entry naming a file that no longer exists is a rename nobody finished.
    foreach ($entry in $tooling) {
        Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot $entry)) "Coverage tooling entry '$entry' does not exist."
    }

    # The list must stay in step with what run-coverage.ps1 actually loads. A new dot-source
    # there with no entry here is the failure this catches.
    $runCoverage = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts/run-coverage.ps1') -Raw
    foreach ($name in @('test-sql-container.common.ps1', 'Common.ps1', 'test-run-lock.common.ps1', 'coverage-inputs.common.ps1')) {
        Assert-True ($runCoverage -match [regex]::Escape($name)) `
            "run-coverage.ps1 no longer mentions $name. Re-derive the coverage-tooling list."
    }
}

Invoke-TestCase 'A pattern shape the matcher cannot read is rejected, never ignored' {
    $threw = $false
    try { ConvertTo-AhkFlowPathRegex -Pattern 'src/**/@(a|b).cs' | Out-Null }
    catch { $threw = $true; Assert-True ($_.Exception.Message -match 'src/') 'The message must name the pattern.' }
    Assert-True $threw 'An unsupported pattern must throw. Silently ignoring one would skip real coverage.'
}

Invoke-TestCase 'A filter file with no code key is rejected' {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-filter-' + [guid]::NewGuid().ToString('N') + '.yml')
    Set-Content -LiteralPath $path -Value "other:`n  - '!**/*.md'" -Encoding utf8
    try {
        $threw = $false
        try { Read-AhkFlowCodePathExclusion -FilterPath $path | Out-Null } catch { $threw = $true }
        Assert-True $threw 'A file with no code: key must throw.'
    }
    finally { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
}

Invoke-TestCase 'A filter entry that is not a negative pattern is rejected' {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-filter-' + [guid]::NewGuid().ToString('N') + '.yml')
    Set-Content -LiteralPath $path -Value "code:`n  - 'src/**'" -Encoding utf8
    try {
        $threw = $false
        try { Read-AhkFlowCodePathExclusion -FilterPath $path | Out-Null } catch { $threw = $true }
        Assert-True $threw 'A positive entry must throw. The whole design assumes every entry excludes.'
    }
    finally { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
}

# A throwaway repository with the real filter file copied in. Git is configured locally so the
# case never depends on the developer's global user.name or commit signing settings.
function New-DiffFixture {
    # -BaseSetup runs against the new root BEFORE the base commit, so whatever it writes lands
    # on main and does not show up in the branch diff. New-WrapperFixture needs that: the
    # scripts it copies in include run-coverage.ps1, which the coverage-tooling list treats as
    # a code change. Committed on the branch they would make every skip case fail.
    param([scriptblock] $BaseSetup)

    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-diff-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root '.github') -Force | Out-Null
    Copy-Item -LiteralPath (Get-AhkFlowCodePathFilterPath -RepoRoot $repoRoot) `
        -Destination (Join-Path $root '.github/code-paths-filter.yml')

    & git -C $root init --quiet --initial-branch=main *> $null
    & git -C $root config user.email 'test@example.com' *> $null
    & git -C $root config user.name 'Test' *> $null
    & git -C $root config commit.gpgsign false *> $null

    Set-Content -LiteralPath (Join-Path $root 'README.md') -Value 'base' -Encoding utf8
    if ($BaseSetup) { & $BaseSetup $root }

    & git -C $root add -A *> $null
    & git -C $root commit --quiet -m 'base' *> $null
    & git -C $root checkout --quiet -b work *> $null

    return (Resolve-Path -LiteralPath $root).Path
}

function Add-FixtureFile {
    param([string] $Root, [string] $RelativePath, [string] $Content = 'x')
    $target = Join-Path $Root $RelativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Set-Content -LiteralPath $target -Value $Content -Encoding utf8
}

function Save-Fixture {
    param([string] $Root, [string] $Message)
    & git -C $Root add -A *> $null
    & git -C $Root commit --quiet -m $Message *> $null
}

function Remove-Fixture {
    param([string] $Root)
    if (Test-Path -LiteralPath $Root) {
        Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-TestCase 'A branch of docs, backlog, and PowerShell changes is not a code change' {
    $root = New-DiffFixture
    try {
        # Not test-fast.ps1 or run-coverage.ps1. Those are on the coverage-tooling list, so they
        # are code changes by design and would contradict this case.
        Add-FixtureFile -Root $root -RelativePath 'backlog/119-thing.md'
        Add-FixtureFile -Root $root -RelativePath 'docs/development/testing-workflow.md'
        Add-FixtureFile -Root $root -RelativePath 'scripts/deploy.ps1'
        Add-FixtureFile -Root $root -RelativePath 'scripts/agents/check-symlinks.ps1'
        Add-FixtureFile -Root $root -RelativePath 'tests/Thing.Tests.ps1'
        Save-Fixture -Root $root -Message 'tooling only'

        $decision = Get-AhkFlowCoverageDecision -RepoRoot $root -BaseRef 'main'
        Assert-True (-not $decision.CoverageRequired) "Expected no code change. Changed: $($decision.ChangedPath -join ', ')"
        Assert-True ($decision.ChangedPath.Count -eq 5) "Expected 5 changed paths, got $($decision.ChangedPath.Count)."
    }
    finally { Remove-Fixture -Root $root }
}

Invoke-TestCase 'One committed .cs file makes it a code change' {
    $root = New-DiffFixture
    try {
        Add-FixtureFile -Root $root -RelativePath 'backlog/119-thing.md'
        Add-FixtureFile -Root $root -RelativePath 'src/Backend/AHKFlowApp.Domain/Hotstring.cs'
        Save-Fixture -Root $root -Message 'one cs file'

        $decision = Get-AhkFlowCoverageDecision -RepoRoot $root -BaseRef 'main'
        Assert-True $decision.CoverageRequired 'One .cs file must make this a code change.'
    }
    finally { Remove-Fixture -Root $root }
}

Invoke-TestCase 'An uncommitted .cs file makes it a code change' {
    $root = New-DiffFixture
    try {
        Add-FixtureFile -Root $root -RelativePath 'docs/thing.md'
        Save-Fixture -Root $root -Message 'docs only'
        # Never committed. A developer mid-edit must not get a skip.
        Add-FixtureFile -Root $root -RelativePath 'src/Backend/AHKFlowApp.Domain/Hotkey.cs'

        $decision = Get-AhkFlowCoverageDecision -RepoRoot $root -BaseRef 'main'
        Assert-True $decision.CoverageRequired 'An untracked .cs file must make this a code change.'
    }
    finally { Remove-Fixture -Root $root }
}

Invoke-TestCase 'A rename out of src/ is a code change, not a docs change' {
    # The source file must exist on main, or there is no deletion in the branch diff and this
    # case proves nothing. Creating it on the branch and renaming it there nets out to one
    # added .md file, which --no-renames would not change.
    #
    # With the file on main, git's default rename detection collapses the branch to a single
    # new path, docs/Foo.md, and the class silently leaves the build. --no-renames is what
    # keeps the deletion visible.
    $root = New-DiffFixture -BaseSetup {
        param($root)
        New-Item -ItemType Directory -Path (Join-Path $root 'src/Backend/AHKFlowApp.Domain') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'src/Backend/AHKFlowApp.Domain/Foo.cs') -Value 'class Foo { }' -Encoding utf8
    }
    try {
        New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force | Out-Null
        & git -C $root mv 'src/Backend/AHKFlowApp.Domain/Foo.cs' 'docs/Foo.md' *> $null
        Save-Fixture -Root $root -Message 'move it to docs'

        $decision = Get-AhkFlowCoverageDecision -RepoRoot $root -BaseRef 'main'
        Assert-True ($decision.ChangedPath -contains 'src/Backend/AHKFlowApp.Domain/Foo.cs') `
            "The old path must survive the diff. Got: $($decision.ChangedPath -join ', ')"
        Assert-True $decision.CoverageRequired 'Deleting a .cs file by renaming it must require coverage.'
    }
    finally { Remove-Fixture -Root $root }
}

Invoke-TestCase 'A staged, uncommitted rename out of src/ is a code change' {
    # Same reason as above: the source file goes on main. Nothing is committed on the branch,
    # so the committed diff is empty and git status is the only thing under test here. Get
    # this wrong and the case passes off the committed diff while --no-renames is broken.
    $root = New-DiffFixture -BaseSetup {
        param($root)
        New-Item -ItemType Directory -Path (Join-Path $root 'src/Backend/AHKFlowApp.Domain') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'src/Backend/AHKFlowApp.Domain/Bar.cs') -Value 'class Bar { }' -Encoding utf8
    }
    try {
        # Staged, never committed. git status prints 'R old -> new' without --no-renames.
        New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force | Out-Null
        & git -C $root mv 'src/Backend/AHKFlowApp.Domain/Bar.cs' 'docs/Bar.md' *> $null

        $decision = Get-AhkFlowCoverageDecision -RepoRoot $root -BaseRef 'main'
        Assert-True ($decision.ChangedPath -contains 'src/Backend/AHKFlowApp.Domain/Bar.cs') `
            "The old path must survive git status. Got: $($decision.ChangedPath -join ', ')"
        # Without --no-renames the parser yields one mangled 'old -> new' string. That string
        # matches no exclusion, so the verdict would be right by accident. Assert the shape.
        Assert-True (-not ($decision.ChangedPath | Where-Object { $_ -like '* -> *' })) `
            "No path may carry git's rename arrow. Got: $($decision.ChangedPath -join ', ')"
        Assert-True $decision.CoverageRequired 'A staged rename out of src/ must require coverage.'
    }
    finally { Remove-Fixture -Root $root }
}

Invoke-TestCase 'Changing the coverage runner is a code change even though it is a script' {
    $root = New-DiffFixture
    try {
        Add-FixtureFile -Root $root -RelativePath 'scripts/run-coverage.ps1' -Content '# changed'
        Save-Fixture -Root $root -Message 'edit the coverage runner'

        $decision = Get-AhkFlowCoverageDecision -RepoRoot $root -BaseRef 'main'
        Assert-True $decision.CoverageRequired `
            'run-coverage.ps1 is the one script the coverage slice is the only local check for.'
    }
    finally { Remove-Fixture -Root $root }
}

Invoke-TestCase 'An ordinary script is still not a code change' {
    # The guard above must protect seven named files, not re-admit every .ps1 under scripts/.
    $root = New-DiffFixture
    try {
        Add-FixtureFile -Root $root -RelativePath 'scripts/deploy.ps1' -Content '# changed'
        Save-Fixture -Root $root -Message 'edit an unrelated script'

        $decision = Get-AhkFlowCoverageDecision -RepoRoot $root -BaseRef 'main'
        Assert-True (-not $decision.CoverageRequired) `
            "deploy.ps1 must stay excluded. Changed: $($decision.ChangedPath -join ', ')"
    }
    finally { Remove-Fixture -Root $root }
}

Invoke-TestCase 'With no base ref given, the resolver falls back to main' {
    # Every other decision case passes -BaseRef, so without this one Resolve-AhkFlowGateBaseRef
    # could throw on every call and the suite would still be green.
    $root = New-DiffFixture
    try {
        Add-FixtureFile -Root $root -RelativePath 'src/Backend/AHKFlowApp.Domain/Hotkey.cs'
        Save-Fixture -Root $root -Message 'one cs file'

        # No remote, so the gh branch is skipped and origin/main does not resolve.
        $resolved = Resolve-AhkFlowGateBaseRef -RepoRoot $root
        Assert-True ($resolved -eq 'main') "Expected 'main', got '$resolved'."

        $decision = Get-AhkFlowCoverageDecision -RepoRoot $root
        Assert-True ($decision.BaseRef -eq 'main') "The decision must report the ref it used. Got '$($decision.BaseRef)'."
        Assert-True $decision.CoverageRequired 'The resolved base must produce the same verdict as an explicit one.'
    }
    finally { Remove-Fixture -Root $root }
}

Invoke-TestCase 'origin/main wins over main when it exists' {
    $root = New-DiffFixture
    try {
        # A remote-tracking ref without a remote: enough to prove which candidate is preferred,
        # and it keeps the case offline.
        & git -C $root update-ref refs/remotes/origin/main HEAD *> $null

        $resolved = Resolve-AhkFlowGateBaseRef -RepoRoot $root
        Assert-True ($resolved -eq 'origin/main') "Expected 'origin/main', got '$resolved'."
    }
    finally { Remove-Fixture -Root $root }
}

Invoke-TestCase 'A stacked branch takes its base from the pull request' {
    # The gh lookup is the one branch of the resolver that needs an external command, and it is
    # the branch stacked work depends on. A fake gh earlier on PATH covers it: a test fixture,
    # not a backdoor in the module.
    #
    # The fake also records the directory it ran in. gh reads the current directory rather than
    # a -C argument, so a resolver that forgot to push the location would silently answer from
    # whatever repository the temp folder sits inside.
    $root = New-DiffFixture
    $fakeBin = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-fake-gh-' + [guid]::NewGuid().ToString('N'))
    $previousPath = $env:PATH
    try {
        New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null
        $cwdRecord = Join-Path $fakeBin 'cwd.txt'

        # A .cmd, because Get-Command resolves it through PATHEXT the same way it finds the
        # real gh.exe. It ignores its arguments and always answers with the stacked base.
        Set-Content -LiteralPath (Join-Path $fakeBin 'gh.cmd') -Encoding ascii -Value @"
@echo off
cd > "$cwdRecord"
echo feature/wt-prerequisite
exit /b 0
"@

        # The resolver only asks gh when the repository has an origin remote, so give it one.
        # The URL is never contacted.
        & git -C $root remote add origin 'https://example.invalid/ahkflow.git' *> $null
        & git -C $root update-ref refs/remotes/origin/feature/wt-prerequisite HEAD *> $null
        & git -C $root update-ref refs/remotes/origin/main HEAD *> $null

        $env:PATH = $fakeBin + [System.IO.Path]::PathSeparator + $previousPath
        $resolved = Resolve-AhkFlowGateBaseRef -RepoRoot $root

        Assert-True ($resolved -eq 'origin/feature/wt-prerequisite') `
            "The pull request base must win over origin/main. Got '$resolved'."
        Assert-True (Test-Path -LiteralPath $cwdRecord) 'The fake gh was never called.'
        $ranIn = (Get-Content -LiteralPath $cwdRecord -Raw).Trim()
        Assert-True ($ranIn -eq $root) "gh must run inside the repository. Ran in '$ranIn', expected '$root'."
    }
    finally {
        $env:PATH = $previousPath
        Remove-Item -LiteralPath $fakeBin -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Fixture -Root $root
    }
}

Invoke-TestCase 'A pull request base that has no remote-tracking ref falls back' {
    # gh answers, but origin/<that branch> does not exist locally - a base branch nobody has
    # fetched. Falling through to origin/main is right; using an unresolvable ref would make
    # git diff fail and turn every run into an error.
    $root = New-DiffFixture
    $fakeBin = Join-Path ([System.IO.Path]::GetTempPath()) ('ahkflow-fake-gh-' + [guid]::NewGuid().ToString('N'))
    $previousPath = $env:PATH
    try {
        New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $fakeBin 'gh.cmd') -Encoding ascii -Value @"
@echo off
echo feature/never-fetched
exit /b 0
"@
        & git -C $root remote add origin 'https://example.invalid/ahkflow.git' *> $null
        & git -C $root update-ref refs/remotes/origin/main HEAD *> $null

        $env:PATH = $fakeBin + [System.IO.Path]::PathSeparator + $previousPath
        $resolved = Resolve-AhkFlowGateBaseRef -RepoRoot $root
        Assert-True ($resolved -eq 'origin/main') "Expected the origin/main fallback, got '$resolved'."
    }
    finally {
        $env:PATH = $previousPath
        Remove-Item -LiteralPath $fakeBin -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Fixture -Root $root
    }
}

Invoke-TestCase 'A repository with neither candidate throws' {
    $root = New-DiffFixture
    try {
        & git -C $root branch -m main trunk *> $null

        $threw = $false
        try { Resolve-AhkFlowGateBaseRef -RepoRoot $root | Out-Null } catch { $threw = $true }
        Assert-True $threw 'An unresolvable base must throw, so the caller runs the slice.'
    }
    finally { Remove-Fixture -Root $root }
}

Invoke-TestCase 'A base ref that does not exist throws rather than reporting no change' {
    $root = New-DiffFixture
    try {
        Add-FixtureFile -Root $root -RelativePath 'src/Backend/AHKFlowApp.Domain/Hotkey.cs'
        Save-Fixture -Root $root -Message 'one cs file'

        $threw = $false
        try { Get-AhkFlowCoverageDecision -RepoRoot $root -BaseRef 'no-such-branch' | Out-Null }
        catch { $threw = $true }
        Assert-True $threw 'A failed diff must throw. Reporting an empty diff would skip real coverage.'
    }
    finally { Remove-Fixture -Root $root }
}

$script:HostExe = [System.Diagnostics.Process]::GetCurrentProcess().Path

# test-fast.ps1 resolves its repository root from $PSScriptRoot, so the only way to drive it
# against a controlled diff is to give it a repository of its own. Everything it dot-sources is
# copied in. run-coverage.ps1 is replaced by a stub, so 'the slice ran' is a file on disk rather
# than several minutes and a SQL Server container.
function New-WrapperFixture {
    # The scripts go in through -BaseSetup so they are committed on main. Several of them are on
    # the coverage-tooling list, so committing them on the branch would make every skip case
    # report a code change.
    return (New-DiffFixture -BaseSetup {
            param($root)

            New-Item -ItemType Directory -Path (Join-Path $root 'scripts') -Force | Out-Null

            foreach ($name in @(
                    'test-fast.ps1'
                    'Common.ps1'
                    'test-sql-container.common.ps1'
                    'test-run-lock.common.ps1'
                    'coverage-inputs.common.ps1'
                    'code-change-filter.common.ps1'
                    'progress.common.ps1'
                )) {
                Copy-Item -LiteralPath (Join-Path $repoRoot "scripts/$name") -Destination (Join-Path $root "scripts/$name")
            }

            Set-Content -LiteralPath (Join-Path $root 'scripts/run-coverage.ps1') -Encoding utf8 -Value @'
[CmdletBinding()]
param([string]$Configuration = 'Release', [switch]$SkipThresholdCheck)
Set-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'coverage-ran.marker') -Value $Configuration
exit 0
'@
        })
}

function Invoke-CoverageMode {
    # -BaseRef is passed by default and omitted when $UseDefaultBaseRef is set, so at least one
    # case drives Resolve-AhkFlowGateBaseRef through the wrapper instead of around it.
    param([string] $Root, [string[]] $ExtraArgument = @(), [switch] $UseDefaultBaseRef)

    $arguments = @('-NoProfile', '-File', (Join-Path $Root 'scripts/test-fast.ps1'), '-Mode', 'Coverage')
    if (-not $UseDefaultBaseRef) { $arguments += @('-BaseRef', 'main') }
    $arguments += $ExtraArgument

    $output = & $script:HostExe @arguments 2>&1 | Out-String
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output   = $output
        SliceRan = (Test-Path -LiteralPath (Join-Path $Root 'coverage-ran.marker'))
    }
}

Invoke-TestCase 'Coverage mode skips, and says why, when no compiled file changed' {
    $root = New-WrapperFixture
    try {
        Add-FixtureFile -Root $root -RelativePath 'docs/thing.md'
        Add-FixtureFile -Root $root -RelativePath 'tests/Thing.Tests.ps1'
        Save-Fixture -Root $root -Message 'docs and a suite'

        $result = Invoke-CoverageMode -Root $root
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True (-not $result.SliceRan) "The slice must not run. Output: $($result.Output)"

        # The acceptance criterion is that the skip is reported, not silent. Each of the four
        # things the report promises gets its own assertion, or 'reported' quietly degrades to
        # 'printed the word skipped'.
        Assert-True ($result.Output -match 'Coverage slice skipped') "The skip must be reported. Output: $($result.Output)"
        Assert-True ($result.Output -match 'Base ref\s*:\s*main') "The report must name the base ref it used. Output: $($result.Output)"
        Assert-True ($result.Output -match 'docs/thing\.md\s+excluded by \*\*/\*\.md') `
            "The report must name each file and the exact pattern that excluded it. Output: $($result.Output)"
        Assert-True ($result.Output -match 'tests/Thing\.Tests\.ps1\s+excluded by tests/\*\.ps1') `
            "The pattern shown must be the one that matched, not the first in the list. Output: $($result.Output)"
        Assert-True ($result.Output -match 'code-paths-filter\.yml') "The report must name the pattern file. Output: $($result.Output)"
    }
    finally { Remove-Fixture -Root $root }
}

Invoke-TestCase 'Coverage mode skips with no -BaseRef, resolving the base itself' {
    $root = New-WrapperFixture
    try {
        Add-FixtureFile -Root $root -RelativePath 'docs/thing.md'
        Save-Fixture -Root $root -Message 'docs only'

        $result = Invoke-CoverageMode -Root $root -UseDefaultBaseRef
        Assert-True ($result.ExitCode -eq 0) "Expected exit code 0, got $($result.ExitCode). Output: $($result.Output)"
        Assert-True (-not $result.SliceRan) "The slice must not run. Output: $($result.Output)"
        Assert-True ($result.Output -match 'Base ref\s*:\s*main') `
            "The resolver must have chosen main and said so. Output: $($result.Output)"
    }
    finally { Remove-Fixture -Root $root }
}

Invoke-TestCase 'Coverage mode runs the slice when one .cs file changed' {
    $root = New-WrapperFixture
    try {
        Add-FixtureFile -Root $root -RelativePath 'src/Backend/AHKFlowApp.Domain/Hotstring.cs'
        Save-Fixture -Root $root -Message 'one cs file'

        $result = Invoke-CoverageMode -Root $root
        Assert-True $result.SliceRan "The slice must run for a .cs change. Output: $($result.Output)"
        Assert-True ($result.Output -notmatch 'Coverage slice skipped') "It must not report a skip. Output: $($result.Output)"
    }
    finally { Remove-Fixture -Root $root }
}

Invoke-TestCase '-Force runs the slice even with nothing compiled changed' {
    $root = New-WrapperFixture
    try {
        Add-FixtureFile -Root $root -RelativePath 'docs/thing.md'
        Save-Fixture -Root $root -Message 'docs only'

        $result = Invoke-CoverageMode -Root $root -ExtraArgument @('-Force')
        Assert-True $result.SliceRan "-Force must run the slice. Output: $($result.Output)"
    }
    finally { Remove-Fixture -Root $root }
}

Invoke-TestCase 'A decision that cannot be made runs the slice and says so' {
    $root = New-WrapperFixture
    try {
        Add-FixtureFile -Root $root -RelativePath 'docs/thing.md'
        Save-Fixture -Root $root -Message 'docs only'
        Remove-Item -LiteralPath (Join-Path $root '.github/code-paths-filter.yml') -Force

        $result = Invoke-CoverageMode -Root $root
        Assert-True $result.SliceRan "A broken decision must fall back to running the slice. Output: $($result.Output)"
        Assert-True ($result.Output -match 'code-paths-filter') "It must name what it could not read. Output: $($result.Output)"
    }
    finally { Remove-Fixture -Root $root }
}

Invoke-TestCase 'ci.yml reads the shared filter file and holds no second copy' {
    $ci = Get-Content -LiteralPath (Join-Path $repoRoot '.github/workflows/ci.yml') -Raw

    Assert-True ($ci -match 'filters:\s*\.github/code-paths-filter\.yml') `
        'ci.yml must point dorny/paths-filter at .github/code-paths-filter.yml.'
    Assert-True ($ci -match "predicate-quantifier:\s*'every'") `
        "The 'every' quantifier must stay. Without it the negative patterns do not exclude."
    Assert-True ($ci -notmatch "-\s*'!\*\*/\*\.md'") `
        'ci.yml must not keep an inline copy of the patterns. One source of truth, or the Gate and CI can disagree.'
}

Write-Host ''
if ($script:Failures.Count -gt 0) {
    Write-Host "FAILED: $($script:Failures.Count) test(s)" -ForegroundColor Red
    foreach ($failure in $script:Failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'Coverage slice skip tests passed.' -ForegroundColor Green
exit 0
