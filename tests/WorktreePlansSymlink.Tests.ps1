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

# Mirrors the production wiring: new-worktree.ps1 dot-sources the PowerShell common file (for
# Write-Stderr) before the plans common file that depends on it.
. (Join-Path $repoRoot 'scripts\worktree-powershell.common.ps1')
. (Join-Path $repoRoot 'scripts\worktree-plans.common.ps1')

function New-PlansFixture {
    param([string] $Slug = 'plans')

    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("wtplans-$Slug-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path (Join-Path $root 'main\docs\superpowers') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $root 'main\docs\superpowers\marker.md') -Value 'seed' -Encoding utf8
    return $root
}

function Remove-Fixture {
    param([string] $Path)

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            return
        } catch {
            if ($attempt -eq 3) { return }
            Start-Sleep -Milliseconds 200
        }
    }
}

function Get-LinkTarget {
    param([string] $Path)

    $item = Get-Item -LiteralPath $Path -Force
    $target = $item.Target
    if ($target -is [array]) { $target = $target[0] }
    return $target
}

# --- Case 1: a fresh worktree gets a symlink, and reads the main checkout's content ---------
$fixture = New-PlansFixture 'fresh'
try {
    $main = Join-Path $fixture 'main'
    $wt = Join-Path $fixture 'wt'
    New-Item -ItemType Directory -Path $wt -Force | Out-Null

    Add-PlansSymlink -RepoRoot $main -WorktreePath $wt

    $link = Join-Path $wt 'docs\superpowers'
    Assert-True (Test-Path -LiteralPath $link) 'A fresh worktree must receive docs\superpowers.'
    Assert-True ((Get-Item -LiteralPath $link -Force).LinkType -eq 'SymbolicLink') 'docs\superpowers must be a symlink, not a copied directory.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $link 'marker.md')) -ceq 'seed') "The worktree must read the main checkout's plan content through the link."

    # Case 3 (live sync): the link is not a snapshot. A plan revised in the main checkout after
    # the worktree exists must be visible immediately -- this is the whole reason it is not a copy.
    Set-Content -LiteralPath (Join-Path $main 'docs\superpowers\later-plan.md') -Value 'revised' -Encoding utf8
    Assert-True ((Get-Content -LiteralPath (Join-Path $link 'later-plan.md')) -ceq 'revised') 'A plan written after linking must be visible through the worktree path.'

    # Case 2 (idempotent): re-running against an existing, correct link is a no-op. new-worktree.ps1
    # calls this on every run, including when reusing a worktree.
    Add-PlansSymlink -RepoRoot $main -WorktreePath $wt
    Assert-True ((Get-Item -LiteralPath $link -Force).LinkType -eq 'SymbolicLink') 'Re-running must leave the symlink in place.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $link 'marker.md')) -ceq 'seed') 'Re-running must not disturb linked content.'
} finally {
    Remove-Fixture $fixture
}

# --- Case 4: no plans repo cloned -> skip silently, create nothing --------------------------
# A contributor who never cloned the private repo must still get a working worktree.
$fixture = New-PlansFixture 'missing'
try {
    $wt = Join-Path $fixture 'wt'
    New-Item -ItemType Directory -Path $wt -Force | Out-Null

    Add-PlansSymlink -RepoRoot (Join-Path $fixture 'no-such-repo') -WorktreePath $wt

    Assert-True (-not (Test-Path -LiteralPath (Join-Path $wt 'docs\superpowers'))) 'With no plans repo to link, nothing may be created.'
} finally {
    Remove-Fixture $fixture
}

# --- Case 5: a real directory already present -> leave it alone ------------------------------
# Never delete data. The path is gitignored, so anything real there was put there by a human.
$fixture = New-PlansFixture 'realdir'
try {
    $main = Join-Path $fixture 'main'
    $wt = Join-Path $fixture 'wt'
    New-Item -ItemType Directory -Path (Join-Path $wt 'docs\superpowers') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $wt 'docs\superpowers\handwritten.txt') -Value 'do not delete' -Encoding utf8

    Add-PlansSymlink -RepoRoot $main -WorktreePath $wt

    $existing = Get-Item -LiteralPath (Join-Path $wt 'docs\superpowers') -Force
    Assert-True ($existing.LinkType -ne 'SymbolicLink') 'A real directory must not be replaced by a symlink.'
    Assert-True (Test-Path -LiteralPath (Join-Path $wt 'docs\superpowers\handwritten.txt')) 'Content in a real directory must survive untouched.'
} finally {
    Remove-Fixture $fixture
}

# --- Case 6: a symlink aimed at the wrong target is repointed --------------------------------
# Happens when the main checkout moves. A stale link silently serves the wrong repo's plans.
$fixture = New-PlansFixture 'wrongtarget'
try {
    $main = Join-Path $fixture 'main'
    $wt = Join-Path $fixture 'wt'
    New-Item -ItemType Directory -Path (Join-Path $fixture 'elsewhere\docs\superpowers') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $fixture 'elsewhere\docs\superpowers\other.md') -Value 'wrong repo' -Encoding utf8
    New-Item -ItemType Directory -Path (Join-Path $wt 'docs') -Force | Out-Null

    Push-Location (Join-Path $wt 'docs')
    try {
        cmd /c mklink /D 'superpowers' (Join-Path $fixture 'elsewhere\docs\superpowers') > $null 2>&1
    } finally {
        Pop-Location
    }

    Add-PlansSymlink -RepoRoot $main -WorktreePath $wt

    $link = Join-Path $wt 'docs\superpowers'
    $target = Get-LinkTarget $link
    $expected = (Resolve-Path -LiteralPath (Join-Path $main 'docs\superpowers')).Path
    Assert-True ((Resolve-Path -LiteralPath $target).Path.TrimEnd('\') -ieq $expected.TrimEnd('\')) "A wrong-target symlink must be repointed at the main checkout (target was '$target')."
    Assert-True (Test-Path -LiteralPath (Join-Path $link 'marker.md')) 'After repointing, the main checkout content must be reachable.'
} finally {
    Remove-Fixture $fixture
}

# --- Case 7: removing the worktree must not touch the main checkout's plans ------------------
# remove-worktree-local-dev.ps1 tears worktrees down with Remove-Item -Recurse -Force. If that
# followed the link, a worktree cleanup would delete the real plans repo.
$fixture = New-PlansFixture 'removal'
try {
    $main = Join-Path $fixture 'main'
    $wt = Join-Path $fixture 'wt'
    New-Item -ItemType Directory -Path $wt -Force | Out-Null

    Add-PlansSymlink -RepoRoot $main -WorktreePath $wt
    Remove-Item -LiteralPath $wt -Recurse -Force

    Assert-True (Test-Path -LiteralPath (Join-Path $main 'docs\superpowers\marker.md')) 'Removing a worktree must never delete the main checkout plans.'
} finally {
    Remove-Fixture $fixture
}

# --- Case 8: paths containing spaces ---------------------------------------------------------
# mklink is invoked through cmd, so an unquoted space would silently produce a broken link.
$fixture = New-PlansFixture 'spaces'
try {
    $main = Join-Path $fixture 'main repo'
    $wt = Join-Path $fixture 'work tree'
    New-Item -ItemType Directory -Path (Join-Path $main 'docs\superpowers') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $main 'docs\superpowers\marker.md') -Value 'spaced' -Encoding utf8
    New-Item -ItemType Directory -Path $wt -Force | Out-Null

    Add-PlansSymlink -RepoRoot $main -WorktreePath $wt

    $link = Join-Path $wt 'docs\superpowers'
    Assert-True (Test-Path -LiteralPath $link) 'A path containing spaces must still produce a link.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $link 'marker.md')) -ceq 'spaced') 'Content must be readable through a link whose path contains spaces.'
} finally {
    Remove-Fixture $fixture
}

# --- The .gitignore pattern must hide the symlink, not just a real directory -----------------
# A pattern ending in '/' matches directories only. Every worktree's docs\superpowers is now a
# symlink, so a trailing slash would leave it showing as untracked in git status.
$gitignorePath = Join-Path $repoRoot '.gitignore'
$plansRules = @(Get-Content -LiteralPath $gitignorePath | Where-Object { $_.Trim() -eq 'docs/superpowers' -or $_.Trim() -eq 'docs/superpowers/' })
Assert-True ($plansRules.Count -ge 1) '.gitignore must carry a docs/superpowers rule.'
Assert-True (-not ($plansRules -contains 'docs/superpowers/')) '.gitignore must use "docs/superpowers" without a trailing slash, or the worktree symlink is not ignored.'

# --- The @-picker script must follow symlinks and suppress the mirror duplicates -------------
# Without --follow, rg does not descend into the docs\superpowers link and the picker shows no
# plans at all inside a worktree -- the bug this change exists to fix.
$suggestionPath = Join-Path $repoRoot '.claude\file-suggestion.sh'
$suggestion = Get-Content -LiteralPath $suggestionPath -Raw
Assert-True ($suggestion -match '(?m)^\s*rg --files[^\r\n]*--follow') '.claude/file-suggestion.sh must pass --follow, or worktree plans stay invisible to the @ picker.'

# --follow also walks the pre-existing skill-mirror symlinks, so .ignore must deny them or every
# skill file and AGENTS.md is listed two or three times.
$ignoreLines = @(Get-Content -LiteralPath (Join-Path $repoRoot '.ignore') | ForEach-Object { $_.Trim() })
foreach ($rule in @('.claude/skills/', '.github/skills/', '.github/AGENTS.md')) {
    Assert-True ($ignoreLines -contains $rule) ".ignore must deny '$rule' so --follow does not duplicate it in the @ picker."
}

# End-to-end picker behavior, when a usable bash host is present. rg is required by the script
# itself. Asking PowerShell whether rg exists answers for the Windows PATH, but the script runs
# inside bash -- and on Windows a bare 'bash' can be the WSL launcher at
# C:\Windows\system32\bash.exe, whose Linux PATH has no Windows rg. So ask each candidate host
# for rg itself, with the same non-login invocation the real run uses, and run the script with
# the first host that answers.
function Get-BashOnPath {
    return @(@(Get-Command bash -All -ErrorAction SilentlyContinue) | ForEach-Object { [string] $_.Source })
}

function Get-GitExePath {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $git) { return '' }
    return [string] $git.Source
}

function Get-BashHostCandidate {
    param(
        # The three inputs are injected so the suite can assert the order, the git layouts, and
        # the de-duplication with paths that need not exist on the machine running the test.
        [string[]] $PathBash = (Get-BashOnPath),
        [string] $GitExe = (Get-GitExePath),
        [scriptblock] $Exists = { param([string] $Path) Test-Path -LiteralPath $Path -PathType Leaf }
    )

    $candidates = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    function Add-Candidate {
        param([string] $Path)

        if ([string]::IsNullOrWhiteSpace($Path)) { return }
        if (-not (& $Exists $Path)) { return }
        # GetFullPath normalizes the separators without asking the filesystem, so a fake path
        # de-duplicates the same way a real one does.
        $full = [System.IO.Path]::GetFullPath($Path)
        if ($seen.Add($full)) { $candidates.Add($full) }
    }

    # PATH order first: that is what the picker command in .claude/settings.json resolves to.
    foreach ($path in @($PathBash)) {
        Add-Candidate $path
    }

    # Then the bash that ships beside git, under both layouts git.exe is installed with:
    # <root>\cmd\git.exe and <root>\mingw64\bin\git.exe.
    if (-not [string]::IsNullOrWhiteSpace($GitExe)) {
        $gitDir = Split-Path -Parent $GitExe
        foreach ($root in @((Split-Path -Parent $gitDir), (Split-Path -Parent (Split-Path -Parent $gitDir)))) {
            if ([string]::IsNullOrWhiteSpace($root)) { continue }
            # Combine, not Join-Path: Join-Path asks the PowerShell provider to resolve the
            # drive letter and throws when that drive does not exist, which makes the function
            # depend on the machine it runs on. Combine is string work only.
            Add-Candidate ([System.IO.Path]::Combine($root, 'bin\bash.exe'))
            Add-Candidate ([System.IO.Path]::Combine($root, 'usr\bin\bash.exe'))
        }
    }

    return $candidates.ToArray()
}

function Invoke-BashProbe {
    param([string] $BashExe)

    # Starts one host and reports what it did. Keeping the launch here, and away from the rule
    # that reads the result, lets the suite assert every outcome without starting a process.
    $errorFile = [System.IO.Path]::GetTempFileName()
    try {
        try {
            $output = (& $BashExe -c 'command -v rg' 2> $errorFile | Out-String).Trim()
            $code = $LASTEXITCODE
        } catch {
            return [pscustomobject] @{ Output = ''; ExitCode = -1; StdErr = ''; Failed = $true; Message = $_.Exception.Message }
        }

        $stdErr = ''
        if (Test-Path -LiteralPath $errorFile) {
            $stdErr = ((Get-Content -LiteralPath $errorFile -Raw -ErrorAction SilentlyContinue) | Out-String).Trim()
        }

        return [pscustomobject] @{ Output = $output; ExitCode = $code; StdErr = $stdErr; Failed = $false; Message = '' }
    } finally {
        Remove-Item -LiteralPath $errorFile -Force -ErrorAction SilentlyContinue
    }
}

function Test-BashHostSeesRg {
    param(
        [string] $BashExe,
        [scriptblock] $Invoke = ${function:Invoke-BashProbe}
    )

    # Returns '' when the host can run the script, otherwise the reason it was rejected.
    $result = & $Invoke $BashExe

    if ($result.Failed) {
        return "cannot start ($($result.Message))"
    }

    # A host can fail for a reason that has nothing to do with rg. The WSL launcher with no
    # installed distribution is the common one: it exits non-zero and explains itself on stderr.
    # Repeat that explanation instead of blaming rg, and keep it to one line so the skip message
    # stays readable.
    if ($result.ExitCode -ne 0 -and -not [string]::IsNullOrWhiteSpace($result.StdErr)) {
        $firstLine = @($result.StdErr -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })[0]
        return "exited $($result.ExitCode) with an error: $($firstLine.Trim())"
    }

    if ($result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($result.Output)) {
        return "runs, but 'command -v rg' finds no rg on its PATH"
    }

    return ''
}

function Select-BashHost {
    param(
        [string[]] $Candidate,
        [scriptblock] $Probe
    )

    # Pure: no filesystem, no processes. The probe decides, so the suite can assert this with
    # fake paths. Returns the chosen host, or $null plus the exact lines the skip message prints.
    $rejected = [System.Collections.Generic.List[string]]::new()

    # A function that returns an empty array hands back nothing at all, and a literal $null binds
    # to [string[]] as one null element. Filter, or the probe is called with an empty path.
    foreach ($path in @($Candidate | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $reason = & $Probe $path
        if ([string]::IsNullOrEmpty($reason)) {
            return [pscustomobject] @{ BashExe = $path; SkipLine = @() }
        }

        $rejected.Add("  $path - $reason")
    }

    if ($rejected.Count -eq 0) {
        return [pscustomobject] @{
            BashExe  = $null
            SkipLine = @('Skipped the live @-picker checks: no bash executable was found on this host.')
        }
    }

    return [pscustomobject] @{
        BashExe  = $null
        SkipLine = @('Skipped the live @-picker checks: no bash host on this machine can see rg.') + $rejected.ToArray()
    }
}

# --- Bash host selection: assert the choice and the diagnostics without launching anything ------
# The live check below needs a bash that can see rg. Selecting one is the part that broke on a
# machine where the WSL launcher comes first on PATH, so the selection is asserted here with fake
# candidates and a fake probe. These cases run on every machine, including a CI runner with no rg.
$fakeProbe = {
    param([string] $BashExe)

    if ($BashExe -like '*good*') { return '' }
    return "runs, but 'command -v rg' finds no rg on its PATH"
}

$selected = Select-BashHost -Candidate @('Q:\wsl\bash.exe', 'Q:\good\bash.exe') -Probe $fakeProbe
Assert-True ($selected.BashExe -eq 'Q:\good\bash.exe') "Selection must skip a rejected host and take the next one (chose '$($selected.BashExe)')."
Assert-True ($selected.SkipLine.Count -eq 0) 'A chosen host must produce no skip lines.'

$firstGood = Select-BashHost -Candidate @('Q:\good-one\bash.exe', 'Q:\good-two\bash.exe') -Probe $fakeProbe
Assert-True ($firstGood.BashExe -eq 'Q:\good-one\bash.exe') 'Selection must take the first host that answers, not a later one.'

$noneGood = Select-BashHost -Candidate @('Q:\wsl\bash.exe', 'Q:\store\bash.exe') -Probe $fakeProbe
Assert-True ($null -eq $noneGood.BashExe) 'No host that sees rg means no host is chosen.'
Assert-True ($noneGood.SkipLine.Count -eq 3) "The skip message must carry a header plus one line per rejected host (got $($noneGood.SkipLine.Count))."
Assert-True ($noneGood.SkipLine[0] -eq 'Skipped the live @-picker checks: no bash host on this machine can see rg.') "Unexpected skip header: '$($noneGood.SkipLine[0])'."
foreach ($rejectedHost in @('Q:\wsl\bash.exe', 'Q:\store\bash.exe')) {
    $line = @($noneGood.SkipLine | Where-Object { $_ -like "*$rejectedHost*" })
    Assert-True ($line.Count -eq 1) "The skip message must name '$rejectedHost' exactly once."
    Assert-True ($line[0] -like "*finds no rg on its PATH*") "The skip line for '$rejectedHost' must say why it was rejected: '$($line[0])'."
}

$noHost = Select-BashHost -Candidate @() -Probe $fakeProbe
Assert-True ($null -eq $noHost.BashExe) 'With no candidates there is no host to choose.'
Assert-True ($noHost.SkipLine.Count -eq 1) 'The no-bash case must be one line, not a header with an empty list.'
Assert-True ($noHost.SkipLine[0] -eq 'Skipped the live @-picker checks: no bash executable was found on this host.') "The no-bash case needs its own message: '$($noHost.SkipLine[0])'."

# --- Candidate discovery: assert it with fake PATH and git locations ----------------------------
# Discovery decides which hosts the probe ever sees. If it silently returns nothing, the live
# check below takes the skip path and the suite still passes, so the discovery order, the
# git-adjacent layouts, and the de-duplication all need assertions of their own.
$existsAlways = { param([string] $Path) return $true }

$underWindowsOrGit = {
    param([string] $Path)

    return ($Path -like 'Q:\Windows\*' -or $Path -like 'Q:\Git\*')
}
$ordered = @(Get-BashHostCandidate -PathBash @('Q:\Windows\system32\bash.exe') -GitExe 'Q:\Git\cmd\git.exe' -Exists $underWindowsOrGit)
Assert-True ($ordered.Count -eq 3) "Discovery must find the PATH host plus both git-adjacent hosts (got $($ordered.Count): $($ordered -join ', '))."
Assert-True ($ordered[0] -eq 'Q:\Windows\system32\bash.exe') "A host on PATH must come first, because that is what a bare 'bash' resolves to (got '$($ordered[0])')."
Assert-True ($ordered[1] -eq 'Q:\Git\bin\bash.exe') "The git-adjacent hosts must follow the PATH hosts (got '$($ordered[1])')."
Assert-True ($ordered[2] -eq 'Q:\Git\usr\bin\bash.exe') "Discovery must cover both bin and usr\bin under the git root (got '$($ordered[2])')."

$onlyGitUsrBin = { param([string] $Path) return ($Path -eq 'Q:\Git\usr\bin\bash.exe') }
$mingw = @(Get-BashHostCandidate -PathBash @() -GitExe 'Q:\Git\mingw64\bin\git.exe' -Exists $onlyGitUsrBin)
Assert-True ($mingw.Count -eq 1 -and $mingw[0] -eq 'Q:\Git\usr\bin\bash.exe') "Discovery must walk up two levels for the mingw64 git layout (got: $($mingw -join ', '))."

$anyUsrBin = { param([string] $Path) return ($Path -like 'Q:\Git\usr\bin\bash.exe') }
$deduped = @(Get-BashHostCandidate -PathBash @('Q:\Git\usr\bin\bash.exe', 'q:\git\usr\bin\BASH.EXE') -GitExe 'Q:\Git\cmd\git.exe' -Exists $anyUsrBin)
Assert-True ($deduped.Count -eq 1) "One host reached by several spellings must be listed once (got: $($deduped -join ', '))."

$existsNever = { param([string] $Path) return $false }
$missing = @(Get-BashHostCandidate -PathBash @('Q:\Windows\system32\bash.exe') -GitExe 'Q:\Git\cmd\git.exe' -Exists $existsNever)
Assert-True ($missing.Count -eq 0) "Discovery must drop a path that does not exist (got: $($missing -join ', '))."

$blanks = @(Get-BashHostCandidate -PathBash @('', '   ') -GitExe '' -Exists $existsAlways)
Assert-True ($blanks.Count -eq 0) "Discovery must ignore empty and whitespace entries (got: $($blanks -join ', '))."

# Discovery and selection together: the exact machine shape that broke, with the WSL launcher
# first on PATH and Git Bash behind it.
$wslOrGitBin = {
    param([string] $Path)

    return ($Path -eq 'Q:\Windows\system32\bash.exe' -or $Path -eq 'Q:\Git\bin\bash.exe')
}
$wslFirst = @(Get-BashHostCandidate -PathBash @('Q:\Windows\system32\bash.exe') -GitExe 'Q:\Git\cmd\git.exe' -Exists $wslOrGitBin)
$wslProbe = {
    param([string] $BashExe)

    if ($BashExe -eq 'Q:\Windows\system32\bash.exe') { return "runs, but 'command -v rg' finds no rg on its PATH" }
    return ''
}
$wslChoice = Select-BashHost -Candidate $wslFirst -Probe $wslProbe
Assert-True ($wslChoice.BashExe -eq 'Q:\Git\bin\bash.exe') "With the WSL launcher first on PATH the run must still choose Git Bash (chose '$($wslChoice.BashExe)')."

# --- The real probe: assert how it reads each outcome the launcher can report -------------------
# The launcher is injected, so every branch runs on every machine, including one with no bash.
$seesRg = Test-BashHostSeesRg -BashExe 'Q:\Git\bin\bash.exe' -Invoke {
    param([string] $BashExe)

    return [pscustomobject] @{ Output = '/c/tools/rg'; ExitCode = 0; StdErr = ''; Failed = $false; Message = '' }
}
Assert-True ($seesRg -eq '') "A host that prints an rg path and exits 0 must be accepted (got '$seesRg')."

$noRg = Test-BashHostSeesRg -BashExe 'Q:\Windows\system32\bash.exe' -Invoke {
    param([string] $BashExe)

    return [pscustomobject] @{ Output = ''; ExitCode = 1; StdErr = ''; Failed = $false; Message = '' }
}
Assert-True ($noRg -eq "runs, but 'command -v rg' finds no rg on its PATH") "A host that runs but finds no rg must say so (got '$noRg')."

$cannotStart = Test-BashHostSeesRg -BashExe 'Q:\nope\bash.exe' -Invoke {
    param([string] $BashExe)

    return [pscustomobject] @{ Output = ''; ExitCode = -1; StdErr = ''; Failed = $true; Message = 'The system cannot find the file specified.' }
}
Assert-True ($cannotStart -like 'cannot start (*') "A host that will not start must be reported as such (got '$cannotStart')."

$brokeOnStderr = Test-BashHostSeesRg -BashExe 'Q:\Windows\system32\bash.exe' -Invoke {
    param([string] $BashExe)

    return [pscustomobject] @{ Output = ''; ExitCode = 1; StdErr = "Windows Subsystem for Linux has no installed distributions.`nInstall one."; Failed = $false; Message = '' }
}
Assert-True ($brokeOnStderr -like '*Windows Subsystem for Linux has no installed distributions.*') "A host that fails with an error must repeat that error, not claim rg is missing (got '$brokeOnStderr')."
Assert-True (-not ($brokeOnStderr -like '*finds no rg*')) "A startup error must not be reported as a missing rg (got '$brokeOnStderr')."
Assert-True (-not ($brokeOnStderr -like "*`n*")) "A rejection reason must stay on one line, or the skip message breaks apart (got '$brokeOnStderr')."

# The real launcher on a path that cannot run: deterministic on every machine.
$deadPath = Test-BashHostSeesRg -BashExe (Join-Path $repoRoot 'no-such-bash.exe')
Assert-True (-not [string]::IsNullOrWhiteSpace($deadPath)) 'The real launcher must reject a bash path that cannot run.'

$host_ = Select-BashHost -Candidate @(Get-BashHostCandidate) -Probe ${function:Test-BashHostSeesRg}
if ($host_.BashExe) {
    $bashExe = $host_.BashExe
    $suggestionUnixPath = './.claude/file-suggestion.sh'
    Push-Location $repoRoot
    try {
        $env:CLAUDE_PROJECT_DIR = $repoRoot
        # Assert the exit code as well as the output. The script runs under 'set -uo pipefail', so
        # a broken pipeline can still print an acceptable-looking partial list and then exit
        # non-zero. Both queries match files in this repository, so the only correct code is 0.
        $picked = '{"query":"AGENTS.md"}' | & $bashExe $suggestionUnixPath 2>$null
        $agentsExit = $LASTEXITCODE
        Assert-True ($agentsExit -eq 0) "The @ picker must exit 0 for the AGENTS.md query (host: $bashExe, exit: $agentsExit)."
        $agentsHits = @($picked | Where-Object { $_.Trim() -eq 'AGENTS.md' -or $_.Trim() -eq '.github/AGENTS.md' })
        Assert-True (-not ($agentsHits -contains '.github/AGENTS.md')) 'The @ picker must not list the .github/AGENTS.md symlink mirror.'
        Assert-True ($agentsHits -contains 'AGENTS.md') "The @ picker must still list the real root AGENTS.md (host: $bashExe)."

        $skillPicked = '{"query":"dck-build-fix"}' | & $bashExe $suggestionUnixPath 2>$null
        $skillExit = $LASTEXITCODE
        Assert-True ($skillExit -eq 0) "The @ picker must exit 0 for the dck-build-fix query (host: $bashExe, exit: $skillExit)."
        $mirrorHits = @($skillPicked | Where-Object { $_ -like '.claude/skills/*' -or $_ -like '.github/skills/*' })
        Assert-True ($mirrorHits.Count -eq 0) "The @ picker must not list .claude/skills or .github/skills mirrors (got: $($mirrorHits -join ', '))."
    } finally {
        Remove-Item Env:\CLAUDE_PROJECT_DIR -ErrorAction SilentlyContinue
        Pop-Location
    }
} else {
    foreach ($line in $host_.SkipLine) { Write-Host $line }
}

Write-Host 'Worktree plans symlink tests passed.'
