#Requires -Version 7.0

# Backlog 193. scripts/measure-architecture-pilot.ps1 runs the pilot's control runs and defect runs
# against local clones. A mistake in it can make a trial look clean when it is not, and no other
# test would fail. So its rules are durable cases here, not a one-time dry run.
#
# Every case builds a temporary git repository with the script and fake Suites, and clones it into
# that repository's own .superpowers\193-pilot folder. The script finds the pilot folder from its
# own location, so it never touches this worktree. Each case ends any process a fake Suite started.
#
# Run it by hand with:  pwsh ./tests/MeasureArchitecturePilot.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$script:PilotScript = Join-Path $repoRoot 'scripts\measure-architecture-pilot.ps1'
$script:LaneVariables = @('AHKFLOW_TEST_LANES', 'AHKFLOW_TEST_LANES_HOLDER', 'AHKFLOW_TEST_LANES_ROOT')

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

function Invoke-Git {
    param([string] $Path, [string[]] $Arguments)
    $output = & git -C $Path -c user.name=pilot -c user.email=pilot@example.invalid @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed: $output" }
    $output
}

# One fake Suite per name. Each prints the case lines of the real helpers. The state folder sits
# outside the repository, so neither the clone reset nor the trial folder removes its files.
function Get-FakeSuiteText {
    param([string] $Name, [string] $State)
    $case = @'
function Write-Start([string] $n) { if ($env:AHKFLOW_SUITE_CASE_START -eq '1') { Write-Host "  START  $n" } }
function Write-Pass([string] $n) { Write-Start $n; Write-Host "  PASS  $n" }
'@
    $sleeper = "Start-Process -FilePath ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) -ArgumentList '-NoProfile', '-Command', 'Start-Sleep 600' -WindowStyle Hidden -PassThru"
    $body = switch ($Name) {
        'Pass' { "Add-Content -LiteralPath '$State\pass-ran.txt' ran`nWrite-Pass 'pass one'`nWrite-Pass 'pass two'" }
        'FailZero' { "Write-Start 'fail zero'`nWrite-Host '  FAIL  fail zero'`nWrite-Host '        the fail zero message'`nexit 0" }
        'ExitOne' { "Write-Pass 'exit one'`nexit 1" }
        'Unfinished' { "Write-Start 'never ends'`nexit 0" }
        'Silent' { 'exit 0' }
        'Hang' { "`$child = $sleeper`nSet-Content -LiteralPath '$State\hang-child.txt' `$child.Id`nWrite-Start 'hang case'`nStart-Sleep 600" }
        'Leak' { "`$child = $sleeper`nSet-Content -LiteralPath '$State\leak-child.txt' `$child.Id`nWrite-Pass 'leak case'`nexit 0" }
        'NoLeftover' {
            @"
Write-Start 'no leftover'
`$id = [int](Get-Content -LiteralPath '$State\leak-child.txt' -Raw)
if (Get-Process -Id `$id -ErrorAction SilentlyContinue) { Write-Host '  FAIL  no leftover'; Write-Host "        process `$id is still running"; exit 1 }
Write-Host '  PASS  no leftover'
"@
        }
        'Patched' {
            @"
Write-Start 'patched case'
if ((Get-Content -LiteralPath (Join-Path `$PSScriptRoot '..\fake.txt') -Raw).Trim() -eq 'bad') {
    Write-Host '  FAIL  patched case'
    Write-Host '        fake.txt holds bad'
    Start-Sleep -Seconds 1
    Set-Content -LiteralPath '$State\flaky.flag' set
    exit 1
}
Write-Host '  PASS  patched case'
"@
        }
        'Flaky' {
            @"
Write-Pass 'flaky one'
if (Test-Path -LiteralPath '$State\flaky.flag') { Remove-Item -LiteralPath '$State\flaky.flag'; exit 0 }
Write-Pass 'flaky two'
"@
        }
        default { throw "No fake Suite named $Name." }
    }
    $case + "`n" + $body + "`n"
}

function New-PilotFixture {
    param([string[]] $Suite, [object[]] $Defect = @(), [switch] $NoClone)
    $root = Join-Path ([IO.Path]::GetTempPath()) ('map-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $repo = Join-Path $root 'repo'
    $state = Join-Path $root 'state'
    New-Item -ItemType Directory -Force (Join-Path $repo 'scripts'), (Join-Path $repo 'tests'), $state | Out-Null
    Copy-Item -LiteralPath $script:PilotScript -Destination (Join-Path $repo 'scripts\measure-architecture-pilot.ps1') -ErrorAction SilentlyContinue
    foreach ($name in @('Pass', 'FailZero', 'ExitOne', 'Unfinished', 'Silent', 'Hang', 'Leak', 'NoLeftover', 'Patched', 'Flaky')) {
        Set-Content -LiteralPath (Join-Path $repo "tests\$name.Tests.ps1") -Value (Get-FakeSuiteText $name $state)
    }
    Set-Content -LiteralPath (Join-Path $repo 'fake.txt') -Value 'good'
    Set-Content -LiteralPath (Join-Path $repo 'twice.txt') -Value 'x and x'
    Set-Content -LiteralPath (Join-Path $repo '.gitignore') -Value '.superpowers/'
    Set-Content -LiteralPath (Join-Path $repo 'keep.txt') -Value 'untracked work that no reset may touch'
    [void](Invoke-Git $repo @('init', '--quiet'))
    [void](Invoke-Git $repo @('add', '--', 'tests', 'fake.txt', 'twice.txt', '.gitignore'))
    [void](Invoke-Git $repo @('commit', '--quiet', '-m', 'fixture'))
    $sha = (Invoke-Git $repo @('rev-parse', 'HEAD')).Trim()
    $inputs = Join-Path $root 'inputs.json'
    $suites = @($Suite | ForEach-Object { @{ name = "$_.Tests.ps1"; budgetSeconds = 2 } })
    @{ suites = $suites; defects = @($Defect) } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $inputs
    $pilot = Join-Path $repo '.superpowers\193-pilot'
    New-Item -ItemType Directory -Force $pilot | Out-Null
    $clone = Join-Path $pilot 'dry'
    if (-not $NoClone) { New-PilotClone -Repo $repo -Path $clone -Sha $sha }
    [pscustomobject]@{ Root = $root; Repo = $repo; State = $state; Sha = $sha; Inputs = $inputs; Pilot = $pilot; Clone = $clone; Script = (Join-Path $repo 'scripts\measure-architecture-pilot.ps1') }
}

function New-PilotClone {
    param([string] $Repo, [string] $Path, [string] $Sha, [switch] $NoMark)
    $output = & git clone --quiet --no-checkout --shared (Join-Path $Repo '.git') $Path 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "clone failed: $output" }
    [void](Invoke-Git $Path @('checkout', '--quiet', '--detach', $Sha))
    if (-not $NoMark) { [void](Invoke-Git $Path @('config', '--local', 'ahkflow.pilot', '193')) }
}

function Stop-FixtureChildren {
    param($Fixture)
    foreach ($file in @('hang-child.txt', 'leak-child.txt')) {
        $path = Join-Path $Fixture.State $file
        if (Test-Path -LiteralPath $path) {
            $id = [int](Get-Content -LiteralPath $path -Raw)
            $process = Get-Process -Id $id -ErrorAction SilentlyContinue
            if ($process) { $process.Kill($true); [void]$process.WaitForExit(5000) }
        }
    }
}

function Remove-PilotFixture {
    param($Fixture)
    if ($null -eq $Fixture) { return }
    Stop-FixtureChildren $Fixture
    foreach ($junction in @(Get-ChildItem -LiteralPath $Fixture.Pilot -Force -ErrorAction SilentlyContinue | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })) {
        [IO.Directory]::Delete($junction.FullName)
    }
    Remove-Item -LiteralPath $Fixture.Root -Recurse -Force -ErrorAction SilentlyContinue
}

# Runs the script in a child pwsh with the Lane variables removed, unless a case sets one.
function Invoke-Pilot {
    param($Fixture, [string[]] $Arguments, [hashtable] $Environment = @{})
    $saved = @{}
    foreach ($name in $script:LaneVariables) { $saved[$name] = [Environment]::GetEnvironmentVariable($name); [Environment]::SetEnvironmentVariable($name, $null) }
    foreach ($name in $Environment.Keys) { [Environment]::SetEnvironmentVariable($name, $Environment[$name]) }
    try {
        $pwsh = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $output = & $pwsh -NoProfile -File $Fixture.Script @Arguments 2>&1 | Out-String
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }
    finally {
        foreach ($name in $Environment.Keys) { [Environment]::SetEnvironmentVariable($name, $null) }
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    }
}

function Get-TrialResult {
    param([string] $OutDir, [string] $Pattern)
    $file = @(Get-ChildItem -LiteralPath $OutDir -Filter "*$Pattern*.json" -ErrorAction SilentlyContinue)
    Assert-True ($file.Count -eq 1) "Expected one trial file matching '$Pattern' in $OutDir, found $($file.Count)."
    Get-Content -LiteralPath $file[0].FullName -Raw | ConvertFrom-Json
}

function Get-SuiteResult {
    param($Trial, [string] $Suite)
    $result = @($Trial.Suites | Where-Object { $_.Name -eq "$Suite.Tests.ps1" })
    Assert-True ($result.Count -eq 1) "Expected one result for $Suite."
    $result[0]
}

$fakeDefect = @{
    id = 'D1'; owner = 'fixture'; sentence = 'fake.txt holds bad.'
    before = @(@{ file = 'fake.txt'; find = 'good'; replace = 'bad' })
    after = @(@{ file = 'fake.txt'; find = 'good'; replace = 'bad' })
}

foreach ($row in @('FailZero', 'ExitOne', 'Unfinished', 'Silent')) {
    Invoke-TestCase "An opening control that is not clean stops the attempt: $row" {
        $fixture = New-PilotFixture -Suite $row -Defect $fakeDefect
        try {
            $out = Join-Path $fixture.Root 'out'
            $run = Invoke-Pilot $fixture @('-Mode', 'Attempt', '-Inputs', $fixture.Inputs, '-OutDir', $out, '-Checkout', $fixture.Clone, '-Commit', $fixture.Sha, '-Side', 'Before')
            $attempt = Get-Content -LiteralPath (Join-Path $out 'attempt.json') -Raw | ConvertFrom-Json
            Assert-True ($attempt.Status -eq 'opening control failed') "Expected 'opening control failed', got '$($attempt.Status)'. $($run.Output)"
            Assert-True ($run.ExitCode -ne 0) 'A failed opening control must exit nonzero.'
            Assert-True (@(Get-ChildItem -LiteralPath $out -Filter '*defect*').Count -eq 0) 'No defect may run after a failed opening control.'
            $suite = Get-SuiteResult (Get-TrialResult $out 'opening-control') $row
            Assert-True (-not $suite.Clean) "$row must not be clean."
            if ($row -eq 'FailZero') {
                $fail = @($suite.Fails | Where-Object { $_.Name -eq 'fail zero' })
                Assert-True ($fail.Count -eq 1 -and $fail[0].Message -eq 'the fail zero message') 'The FAIL line must keep its message.'
            }
        }
        finally { Remove-PilotFixture $fixture }
    }
}

Invoke-TestCase 'A hung Suite times out at three times its budget, and its first child is in the job and ended' {
    $fixture = New-PilotFixture -Suite 'Hang'
    try {
        $out = Join-Path $fixture.Root 'out'
        $run = Invoke-Pilot $fixture @('-Mode', 'SuiteSet', '-Inputs', $fixture.Inputs, '-OutDir', $out, '-Checkout', $fixture.Clone, '-Commit', $fixture.Sha)
        $suite = Get-SuiteResult (Get-TrialResult $out 'suiteset') 'Hang'
        $childId = [int](Get-Content -LiteralPath (Join-Path $fixture.State 'hang-child.txt') -Raw)
        Assert-True ($suite.TimedOut) "The hung Suite must time out. $($run.Output)"
        Assert-True (-not $suite.Clean) 'A timed-out Suite is not clean.'
        Assert-True ($suite.WaitedSeconds -ge 6 -and $suite.WaitedSeconds -lt 20) "The timeout must be three times the budget, got $($suite.WaitedSeconds) seconds."
        Assert-True (@($suite.LeftProcesses | Where-Object { $_.Id -eq $childId }).Count -eq 1) "The first child $childId must be in the job list."
        Assert-True (@($suite.Unfinished) -contains 'hang case') 'The start line must name the hung case.'
        Assert-True ($null -eq (Get-Process -Id $childId -ErrorAction SilentlyContinue)) 'The hung child must have ended.'
    }
    finally { Remove-PilotFixture $fixture }
}

Invoke-TestCase 'A Suite that leaves a child behind is not clean, and the child has ended before the next trial' {
    $fixture = New-PilotFixture -Suite 'Leak'
    try {
        $first = Join-Path $fixture.Root 'out-leak'
        [void](Invoke-Pilot $fixture @('-Mode', 'SuiteSet', '-Inputs', $fixture.Inputs, '-OutDir', $first, '-Checkout', $fixture.Clone, '-Commit', $fixture.Sha))
        $suite = Get-SuiteResult (Get-TrialResult $first 'suiteset') 'Leak'
        $childId = [int](Get-Content -LiteralPath (Join-Path $fixture.State 'leak-child.txt') -Raw)
        Assert-True (-not $suite.Clean) 'A Suite that leaves a child behind is not clean.'
        Assert-True (@($suite.LeftProcesses | Where-Object { $_.Id -eq $childId }).Count -eq 1) "The left child $childId must be recorded."
        @{ suites = @(@{ name = 'NoLeftover.Tests.ps1'; budgetSeconds = 2 }); defects = @() } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $fixture.Inputs
        $second = Join-Path $fixture.Root 'out-next'
        $run = Invoke-Pilot $fixture @('-Mode', 'SuiteSet', '-Inputs', $fixture.Inputs, '-OutDir', $second, '-Checkout', $fixture.Clone, '-Commit', $fixture.Sha)
        $next = Get-SuiteResult (Get-TrialResult $second 'suiteset') 'NoLeftover'
        Assert-True ($next.Clean) "The next trial must find no leftover child. $($run.Output)"
    }
    finally { Remove-PilotFixture $fixture }
}

Invoke-TestCase 'A defect run restores the patched file to its saved hash' {
    $fixture = New-PilotFixture -Suite 'Patched' -Defect $fakeDefect
    try {
        $out = Join-Path $fixture.Root 'out'
        $run = Invoke-Pilot $fixture @('-Mode', 'Attempt', '-Inputs', $fixture.Inputs, '-OutDir', $out, '-Checkout', $fixture.Clone, '-Commit', $fixture.Sha, '-Side', 'Before')
        $attempt = Get-Content -LiteralPath (Join-Path $out 'attempt.json') -Raw | ConvertFrom-Json
        Assert-True ($attempt.Status -eq 'clean') "Expected a clean attempt, got '$($attempt.Status)'. $($run.Output)"
        $defect = Get-SuiteResult (Get-TrialResult $out 'defect-D1') 'Patched'
        Assert-True (-not $defect.Clean -and @($defect.Fails).Count -eq 1) 'The defect run must fail the patched case.'
        $record = @($attempt.Defects | Where-Object { $_.Id -eq 'D1' })
        Assert-True ($record.Count -eq 1 -and $record[0].Restored) 'The attempt must record the restored hash.'
        $text = (Get-Content -LiteralPath (Join-Path $fixture.Clone 'fake.txt') -Raw).Trim()
        Assert-True ($text -eq 'good') "The patched file must be restored, got '$text'."
    }
    finally { Remove-PilotFixture $fixture }
}

Invoke-TestCase 'A closing control with a missing case fails the attempt' {
    $fixture = New-PilotFixture -Suite 'Patched', 'Flaky' -Defect $fakeDefect
    try {
        $out = Join-Path $fixture.Root 'out'
        $run = Invoke-Pilot $fixture @('-Mode', 'Attempt', '-Inputs', $fixture.Inputs, '-OutDir', $out, '-Checkout', $fixture.Clone, '-Commit', $fixture.Sha, '-Side', 'Before')
        $attempt = Get-Content -LiteralPath (Join-Path $out 'attempt.json') -Raw | ConvertFrom-Json
        Assert-True ($attempt.Status -eq 'closing control failed') "Expected 'closing control failed', got '$($attempt.Status)'. $($run.Output)"
        Assert-True ($run.ExitCode -ne 0) 'A failed closing control must exit nonzero.'
    }
    finally { Remove-PilotFixture $fixture }
}

foreach ($row in @(
        @{ Name = 'zero times'; Edit = @{ file = 'fake.txt'; find = 'absent'; replace = 'bad' }; Count = 0 }
        @{ Name = 'twice'; Edit = @{ file = 'twice.txt'; find = 'x'; replace = 'y' }; Count = 2 }
    )) {
    Invoke-TestCase "Verify refuses an edit whose text occurs zero times or twice: $($row.Name)" {
        $defect = @{ id = 'D2'; owner = 'fixture'; sentence = 'unused'; before = @($row.Edit); after = @($row.Edit) }
        $fixture = New-PilotFixture -Suite 'Pass' -Defect $defect
        try {
            $run = Invoke-Pilot $fixture @('-Mode', 'Verify', '-Inputs', $fixture.Inputs, '-Checkout', $fixture.Clone, '-Commit', $fixture.Sha, '-Side', 'Before')
            Assert-True ($run.ExitCode -ne 0) "Verify must refuse an edit found $($row.Count) times. $($run.Output)"
            Assert-True ($run.Output -match "D2.*occurs $($row.Count) times") "The refusal must name the defect and the count. $($run.Output)"
        }
        finally { Remove-PilotFixture $fixture }
    }
}

Invoke-TestCase 'A failed job assignment stops the run before the Suite starts' {
    $fixture = New-PilotFixture -Suite 'Pass'
    try {
        $out = Join-Path $fixture.Root 'out'
        $run = Invoke-Pilot $fixture @('-Mode', 'SuiteSet', '-Inputs', $fixture.Inputs, '-OutDir', $out, '-Checkout', $fixture.Clone, '-Commit', $fixture.Sha, '-FailJobAssignment')
        Assert-True ($run.ExitCode -ne 0) "A failed job assignment must stop the run. $($run.Output)"
        Assert-True ($run.Output -match 'AssignProcessToJobObject failed with Win32 error \d+') "The error must name the call and its code. $($run.Output)"
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $fixture.State 'pass-ran.txt'))) 'The Suite must never start outside a job.'
    }
    finally { Remove-PilotFixture $fixture }
}

$refusals = @(
    @{ Name = 'a folder outside the pilot folder'; Kind = 'outside' }
    @{ Name = 'a junction in the pilot folder that points outside it'; Kind = 'junction' }
    @{ Name = 'a direct child with an empty .git folder'; Kind = 'empty-git' }
    @{ Name = 'a valid repository in the pilot folder without the ownership mark'; Kind = 'no-mark' }
)
foreach ($variable in $script:LaneVariables) { $refusals += @{ Name = "$variable set"; Kind = 'variable'; Variable = $variable } }
foreach ($row in $refusals) {
    Invoke-TestCase "A checkout the script does not own, or a set Lane variable, is refused: $($row.Name)" {
        $fixture = New-PilotFixture -Suite 'Pass'
        try {
            $checkout = $fixture.Clone
            $environment = @{}
            switch ($row.Kind) {
                'outside' { $checkout = Join-Path $fixture.Root 'outside'; New-PilotClone -Repo $fixture.Repo -Path $checkout -Sha $fixture.Sha }
                'junction' {
                    $target = Join-Path $fixture.Root 'target'
                    New-PilotClone -Repo $fixture.Repo -Path $target -Sha $fixture.Sha
                    $checkout = Join-Path $fixture.Pilot 'junction'
                    New-Item -ItemType Junction -Path $checkout -Target $target | Out-Null
                }
                'empty-git' { $checkout = Join-Path $fixture.Pilot 'empty'; New-Item -ItemType Directory -Force (Join-Path $checkout '.git') | Out-Null }
                'no-mark' { $checkout = Join-Path $fixture.Pilot 'nomark'; New-PilotClone -Repo $fixture.Repo -Path $checkout -Sha $fixture.Sha -NoMark }
                'variable' { $environment[$row.Variable] = 'set-by-case' }
            }
            Set-Content -LiteralPath (Join-Path $checkout 'scratch.txt') -Value 'must survive' -ErrorAction SilentlyContinue
            $out = Join-Path $fixture.Root 'out'
            $run = Invoke-Pilot $fixture @('-Mode', 'SuiteSet', '-Inputs', $fixture.Inputs, '-OutDir', $out, '-Checkout', $checkout, '-Commit', $fixture.Sha) -Environment $environment
            Assert-True ($run.ExitCode -ne 0) "The script must refuse $($row.Name). $($run.Output)"
            Assert-True ($run.Output -match 'Refused') "The refusal must say so. $($run.Output)"
            Assert-True (-not (Test-Path -LiteralPath (Join-Path $fixture.State 'pass-ran.txt'))) 'No Suite may run after a refusal.'
            Assert-True (Test-Path -LiteralPath (Join-Path $fixture.Repo 'keep.txt')) 'No reset or clean may reach the repository above.'
            if ($row.Kind -ne 'empty-git') { Assert-True (Test-Path -LiteralPath (Join-Path $checkout 'scratch.txt')) 'No reset or clean may reach the refused checkout.' }
        }
        finally { Remove-PilotFixture $fixture }
    }
}

# Timing cases. The fixture's module is a stub that names only public functions. Its run start
# prints the sharing line while contention.flag exists, or once while contention-once.flag exists.
function Add-TimingFixture {
    param($Fixture, [string[]] $Passes)
    $flag = Join-Path $Fixture.State 'contention.flag'
    $once = Join-Path $Fixture.State 'contention-once.flag'
    Set-Content -LiteralPath (Join-Path $Fixture.Repo 'scripts\test-lanes.common.ps1') -Value @"
function Enter-AhkFlowLaneRun {
    param([string] `$Mode, [string] `$Checkout, [string] `$Share)
    if (Test-Path -LiteralPath '$once') { Remove-Item -LiteralPath '$once'; Write-Host 'Sharing the test Lane pool with: pid 1 Fake' }
    elseif (Test-Path -LiteralPath '$flag') { Write-Host 'Sharing the test Lane pool with: pid 1 Fake' }
    [pscustomobject]@{ Role = 'owner' }
}
function Exit-AhkFlowLaneRun { param(`$State) }
"@
    $cases = Join-Path $Fixture.Root 'cases.json'
    $suiteName = (Get-Content -LiteralPath $Fixture.Inputs -Raw | ConvertFrom-Json).suites[0].name
    @{ Clean = $true; Suites = @(@{ Name = $suiteName; Passes = $Passes }) } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $cases
    $cases
}

function Invoke-Timing {
    param($Fixture, [string] $Cases, [string] $OutDir)
    Invoke-Pilot $Fixture @('-Mode', 'Timing', '-Inputs', $Fixture.Inputs, '-OutDir', $OutDir,
        '-BeforeCheckout', $Fixture.Clone, '-BeforeCommit', $Fixture.Sha, '-AfterCheckout', $Fixture.Clone, '-AfterCommit', $Fixture.Sha,
        '-BeforeCases', $Cases, '-AfterCases', $Cases)
}

$script:TimingOrder = @('warm-A', 'warm-B', '1-A', '2-B', '3-B', '4-A', '5-B', '6-A', '7-A', '8-B')

Invoke-TestCase 'Timing runs the passes in the order warm A, warm B, then A B B A B A A B' {
    $fixture = New-PilotFixture -Suite 'Pass'
    try {
        $cases = Add-TimingFixture $fixture @('pass one', 'pass two')
        $out = Join-Path $fixture.Root 'out'
        $run = Invoke-Timing $fixture $cases $out
        Assert-True ($run.ExitCode -eq 0) "A clean timing must exit 0. $($run.Output)"
        $timing = Get-Content -LiteralPath (Join-Path $out 'timing.json') -Raw | ConvertFrom-Json
        Assert-True ($timing.Status -eq 'clean') "Expected a clean timing, got '$($timing.Status)'."
        Assert-True ((@($timing.Passes | ForEach-Object { $_.Position }) -join ',') -eq ($script:TimingOrder -join ',')) "Wrong pass order: $(@($timing.Passes | ForEach-Object { $_.Position }) -join ',')"
        Assert-True (@($timing.Rejected).Count -eq 0) 'A clean timing rejects no pass.'
        foreach ($pass in $timing.Passes) {
            $sum = (@($pass.Suites | ForEach-Object { [double]$_.Seconds }) | Measure-Object -Sum).Sum
            Assert-True ($pass.Seconds -gt 0 -and [Math]::Abs($pass.Seconds - $sum) -lt 0.02) "The pass time must be the sum of its Suite times: $($pass.Position)."
        }
    }
    finally { Remove-PilotFixture $fixture }
}

Invoke-TestCase 'A pass with a missing case is rejected and runs again in the same position' {
    $fixture = New-PilotFixture -Suite 'Flaky'
    try {
        $cases = Add-TimingFixture $fixture @('flaky one', 'flaky two')
        Set-Content -LiteralPath (Join-Path $fixture.State 'flaky.flag') -Value set
        $out = Join-Path $fixture.Root 'out'
        $run = Invoke-Timing $fixture $cases $out
        $timing = Get-Content -LiteralPath (Join-Path $out 'timing.json') -Raw | ConvertFrom-Json
        Assert-True ($timing.Status -eq 'clean') "One rejection must leave the timing clean, got '$($timing.Status)'. $($run.Output)"
        Assert-True (@($timing.Rejected).Count -eq 1 -and $timing.Rejected[0].Position -eq 'warm-A') 'The first pass must be rejected once.'
        Assert-True (($timing.Rejected[0].Reasons -join ' ') -match 'expected cases') "The reason must name the expected cases: $($timing.Rejected[0].Reasons -join '; ')"
        Assert-True ((@($timing.Passes | ForEach-Object { $_.Position }) -join ',') -eq ($script:TimingOrder -join ',')) 'The rejected pass must run again in the same position.'
    }
    finally { Remove-PilotFixture $fixture }
}

Invoke-TestCase 'A pass that meets another registered run is rejected' {
    $fixture = New-PilotFixture -Suite 'Pass'
    try {
        $cases = Add-TimingFixture $fixture @('pass one', 'pass two')
        Set-Content -LiteralPath (Join-Path $fixture.State 'contention-once.flag') -Value set
        $out = Join-Path $fixture.Root 'out'
        $run = Invoke-Timing $fixture $cases $out
        $timing = Get-Content -LiteralPath (Join-Path $out 'timing.json') -Raw | ConvertFrom-Json
        Assert-True ($timing.Status -eq 'clean') "One rejection must leave the timing clean, got '$($timing.Status)'. $($run.Output)"
        Assert-True (@($timing.Rejected).Count -eq 1 -and $timing.Rejected[0].Position -eq 'warm-A') 'The pass that met another run must be rejected.'
        Assert-True (($timing.Rejected[0].Reasons -join ' ') -match 'another registered test run') "The reason must name the other run: $($timing.Rejected[0].Reasons -join '; ')"
        Assert-True (@($timing.Passes).Count -eq 10) 'The timing must still run all ten passes.'
    }
    finally { Remove-PilotFixture $fixture }
}

Invoke-TestCase 'A fourth rejected pass ends the timing as inconclusive' {
    $fixture = New-PilotFixture -Suite 'Pass'
    try {
        $cases = Add-TimingFixture $fixture @('pass one', 'pass two')
        Set-Content -LiteralPath (Join-Path $fixture.State 'contention.flag') -Value set
        $out = Join-Path $fixture.Root 'out'
        $run = Invoke-Timing $fixture $cases $out
        $timing = Get-Content -LiteralPath (Join-Path $out 'timing.json') -Raw | ConvertFrom-Json
        Assert-True ($run.ExitCode -ne 0) "An inconclusive timing must exit nonzero. $($run.Output)"
        Assert-True ($timing.Status -eq 'inconclusive') "Expected 'inconclusive', got '$($timing.Status)'."
        Assert-True (@($timing.Rejected).Count -eq 4) "The timing must stop at the fourth rejection, got $(@($timing.Rejected).Count)."
        Assert-True (@($timing.Passes).Count -eq 0) 'No pass may count after the timing ends.'
    }
    finally { Remove-PilotFixture $fixture }
}

if ($script:Failures.Count -gt 0) {
    Write-Host ''
    Write-Host "FAILED: $($script:Failures.Count) test(s)" -ForegroundColor Red
    foreach ($failure in $script:Failures) {
        Write-Host "  - $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host ''
Write-Host 'Architecture pilot measurement tests passed.' -ForegroundColor Green
