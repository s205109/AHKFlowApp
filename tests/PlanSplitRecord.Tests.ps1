#Requires -Version 7.0

# CI cannot see the plans repository (.gitignore keeps docs/superpowers out), so this suite tests
# the Split record rule against fixture text and fixture folders. Pre-push applies the rule to the
# real plans, through scripts/check-plan-split-record.ps1.
#
# Never point a case at the real docs/superpowers. Every worktree links to that one folder, and it
# is shared live.
#
# Run it by hand with:  pwsh ./tests/PlanSplitRecord.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$suiteRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $suiteRoot 'scripts/check-plan-split-record.ps1') -AsModule

$failures = @()
$roots = @()

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { $script:failures += $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [string] $Message)
    if (-not [string]::Equals([string] $Expected, [string] $Actual, [System.StringComparison]::OrdinalIgnoreCase)) {
        $script:failures += "$Message (expected '$Expected', got '$Actual')"
    }
}

function New-Root {
    param([string] $Prefix)

    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("$Prefix-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $script:roots += $root
    return $root
}

# One plan line that names a test-run command. The split trigger counts lines like this one.
$testRunLine = 'Run: `pwsh ./scripts/test-fast.ps1 -Mode Fast`'

# A plan's text, built from parts. The defaults make a complete record below the trigger: one
# session, the user story closing at Task 2 of 3, and no verdict.
function New-PlanText {
    param(
        [AllowEmptyString()][string] $Estimate = '1 session',
        [AllowEmptyString()][string] $ClosesAt = 'Task 2',
        [AllowEmptyString()][string] $Verdict = '',
        [int] $TaskCount = 3,
        [int] $TestRunLines = 0,
        [switch] $NoSection
    )

    $lines = @('# 900 probe plan', '')
    if (-not $NoSection) {
        $lines += @('## Split', '')
        if ($Estimate) { $lines += "- **Estimate**: $Estimate" }
        if ($ClosesAt) { $lines += "- **User story closes at**: $ClosesAt" }
        if ($Verdict) { $lines += "- **Verdict**: $Verdict" }
        $lines += ''
    }
    for ($n = 1; $n -le $TaskCount; $n++) { $lines += @("### Task ${n}: probe", '') }
    for ($n = 1; $n -le $TestRunLines; $n++) { $lines += $testRunLine }
    return ($lines -join "`n")
}

function Get-ProblemText {
    param([string] $PlanText)
    return (@(Get-PlanSplitProblem -Record (Get-PlanSplitRecord -PlanText $PlanText)) -join ' ')
}

# A scratch root holding a plans folder, so no case reads the real one. No git here: this section
# hands the check the item's lines directly, the way the branch scope does in Task 3's code.
function New-PlanFolder {
    param([AllowEmptyString()][string] $PlanBody = '')

    $root = New-Root -Prefix 'split-record'
    New-Item -ItemType Directory -Path (Join-Path $root 'docs/superpowers/plans') -Force | Out-Null
    if ($PlanBody) {
        Set-Content -LiteralPath (Join-Path $root 'docs/superpowers/plans/probe-plan-900.md') -Value $PlanBody -Encoding utf8
    }
    return (Resolve-Path -LiteralPath $root).Path
}

# An item record as the branch scope returns it: number, path, and the lines of the pushed commit.
function New-EnteringItem {
    param([AllowEmptyString()][string] $PlanBullet = '- Plan: `docs/superpowers/plans/probe-plan-900.md`')

    $lines = @('# 900 - probe', '', '- **Stage**: 4-execute', '')
    if ($PlanBullet) { $lines += $PlanBullet }
    return [pscustomobject]@{ Number = '900'; RelativePath = 'backlog/900-probe.md'; Stage = '4-execute'; Lines = $lines }
}

# A throwaway git repository, built the way tests/ShippedPlanTicked.Tests.ps1 builds one.
function New-TempGitRepo {
    param([string] $Prefix = 'split-record-git')

    $root = New-Root -Prefix $Prefix
    New-Item -ItemType Directory -Path (Join-Path $root 'backlog') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root 'docs/superpowers/plans') -Force | Out-Null

    & git -C $root init *> $null
    & git -C $root config user.email 'test@example.com' *> $null
    & git -C $root config user.name 'Split Record Test' *> $null
    Set-Content -LiteralPath (Join-Path $root 'README.md') -Value 'seed' -Encoding utf8
    & git -C $root add -A *> $null
    & git -C $root commit -m 'seed' *> $null

    return (Resolve-Path -LiteralPath $root).Path
}

function Write-Item {
    param(
        [string] $Root,
        [string] $Stage,
        [string] $Extra = '',
        [string] $PlanBullet = '- Plan: none - trivial'
    )

    $body = @('# 900 - probe', '', "- **Stage**: $Stage", '', $PlanBullet)
    if ($Extra) { $body += $Extra }
    Set-Content -LiteralPath (Join-Path $Root 'backlog/900-probe.md') -Value ($body -join "`n") -Encoding utf8
}

# Commits the backlog folder only. The plan stays untracked on purpose: no commit in this
# repository ever carries a plan, and the check must read it from disk.
function Save-Repo {
    param([string] $Root, [string] $Message)
    & git -C $Root add -A -- backlog *> $null
    & git -C $Root commit -m $Message *> $null
}

function Get-HeadSha {
    param([string] $Root)
    return ((& git -C $Root rev-parse HEAD) | Out-String).Trim()
}

try {
    # === Get-PlanSplitRecord and Get-PlanSplitProblem: plain text, no files ===

    # 1. No Split section. Exactly one problem, because every other problem would only repeat that
    #    the section is missing.
    $problems = @(Get-PlanSplitProblem -Record (Get-PlanSplitRecord -PlanText (New-PlanText -NoSection)))
    Assert-Equal 1 $problems.Count 'A plan with no Split section reports one problem'
    Assert-True (($problems -join ' ') -match '## Split') "The problem must name the section, got: $problems"

    # 2. A complete record below the trigger. No verdict is needed there.
    $record = Get-PlanSplitRecord -PlanText (New-PlanText)
    Assert-Equal 0 @(Get-PlanSplitProblem -Record $record).Count 'A complete record below the trigger passes'
    Assert-Equal 1 $record.Estimate 'The estimate is read as a number'
    Assert-Equal 2 $record.UserStoryTask 'The user story task is read as a number'
    Assert-Equal '1 2 3' ($record.TaskNumbers -join ' ') 'Every task heading is found'

    # 3. No estimate line.
    $text = Get-ProblemText (New-PlanText -Estimate '')
    Assert-True ($text -match 'no estimate') "A missing estimate is reported, got: $text"

    # 4. An estimate in words. The check needs a number to compare with the limit.
    $text = Get-ProblemText (New-PlanText -Estimate 'two sessions')
    Assert-True ($text -match 'no estimate') "An estimate with no number is reported, got: $text"

    # 5. No line that names where the user story closes.
    $text = Get-ProblemText (New-PlanText -ClosesAt '')
    Assert-True ($text -match 'user story closes') "A missing user story close is reported, got: $text"

    # 6. The named task does not exist, so a reader cannot find where the Extension starts.
    $text = Get-ProblemText (New-PlanText -ClosesAt 'Task 9')
    Assert-True ($text -match 'no Task 9') "A user story task the plan lacks is reported, got: $text"

    # 7. Over the session limit, with no verdict.
    $problems = @(Get-PlanSplitProblem -Record (Get-PlanSplitRecord -PlanText (New-PlanText -Estimate '3 sessions')))
    Assert-Equal 1 $problems.Count 'An estimate over two sessions with no verdict reports one problem'
    Assert-True (($problems -join ' ') -match 'split trigger') "The problem must name the split trigger, got: $problems"

    # 8. Both limits at their edge. Two sessions is not more than two, and 14 lines is under 15.
    $text = Get-ProblemText (New-PlanText -Estimate '2 sessions' -TestRunLines 14)
    Assert-Equal '' $text 'Two sessions and 14 test-run lines stay below the trigger'

    # 9. Fifteen test-run lines meet the trigger when the estimate is low. This half of the trigger
    #    exists to catch a wrong estimate.
    $record = Get-PlanSplitRecord -PlanText (New-PlanText -TestRunLines 15)
    Assert-Equal 15 $record.TestRunLineCount 'Every test-run line is counted'
    $text = @(Get-PlanSplitProblem -Record $record) -join ' '
    Assert-True ($text -match '15 lines name a test-run command') "The count must appear in the problem, got: $text"

    # 10. A fractional estimate over the limit.
    $text = Get-ProblemText (New-PlanText -Estimate '2.5 sessions')
    Assert-True ($text -match 'split trigger') "2.5 sessions meets the trigger, got: $text"

    # 11. At the trigger, a verdict that names only one of the two tests is not an evaluation.
    $text = Get-ProblemText (New-PlanText -Estimate '3 sessions' -Verdict 'No split. The extension test found nothing.')
    Assert-True ($text -match 'disjoint set test') "A verdict that names one test is reported, got: $text"

    # 12. At the trigger, a verdict that names both tests passes, also when it wraps onto an
    #     indented second line. Plans wrap at about 100 characters.
    $verdict = "No split. The extension test found nothing after Task 2.`n  The disjoint set test found no group of tasks with files of its own."
    $text = Get-ProblemText (New-PlanText -Estimate '3 sessions' -Verdict $verdict)
    Assert-Equal '' $text 'A wrapped verdict that names both tests passes'

    # 13. Each of the four commands counts, one line each. A suite started directly with pwsh does
    #     not count: Design calibrated the limit of 15 on these four names only.
    $commands = @('dotnet test tests/X', 'pwsh ./scripts/test-fast.ps1 -Mode Fast', 'pwsh ./scripts/run-powershell-suites.ps1', 'Invoke-Pester ./tests', 'pwsh ./tests/Probe.Tests.ps1')
    Assert-Equal 4 (Get-PlanSplitRecord -PlanText ($commands -join "`n")).TestRunLineCount 'The four commands count, and a direct suite run does not'

    # 14. A Split section inside a fenced block is an example, not the record. A task heading
    #     inside a fence is not a task either.
    $fence = '`' * 3
    $text = @('# probe', '', "${fence}markdown", '## Split', '', '- **Estimate**: 1 session', '- **User story closes at**: Task 1', '### Task 9: example', $fence, '', '### Task 1: real') -join "`n"
    $record = Get-PlanSplitRecord -PlanText $text
    Assert-True (-not $record.HasSection) 'A fenced Split section is not the record'
    Assert-Equal '1' ($record.TaskNumbers -join ' ') 'A fenced task heading is not a task'

    # 15. The section ends at the next level-two heading, so a Verdict bullet under a later section
    #     is not read. Task headings count at levels two to four.
    $text = @('## Split', '', '- **Estimate**: 3 sessions', '- **User story closes at**: Task 1', '', '## Global Constraints', '', '- **Verdict**: the extension test and the disjoint set test found nothing', '', '## Task 1 - two hashes', '#### Task 2: four hashes') -join "`n"
    $record = Get-PlanSplitRecord -PlanText $text
    Assert-Equal '' $record.Verdict 'A bullet after the section ends is not read'
    Assert-Equal '1 2' ($record.TaskNumbers -join ' ') 'Task headings count at levels two to four'

    # === Get-PlanSplitFailure: fixture folders, no git ========================

    # 16. A plan with no Split section. Reported, naming the item, the plan, and the problem.
    $root = New-PlanFolder -PlanBody (New-PlanText -NoSection)
    $result = Get-PlanSplitFailure -RepoRoot $root -Item @(New-EnteringItem)
    Assert-Equal 1 $result.Failures.Count 'A plan with no Split section is reported'
    if ($result.Failures.Count -eq 1) {
        Assert-Equal 'backlog/900-probe.md' $result.Failures[0].ItemPath 'The failure must name the item file'
        Assert-Equal 'docs/superpowers/plans/probe-plan-900.md' $result.Failures[0].PlanPath 'The failure must name the plan file'
        Assert-True ((@($result.Failures[0].Problems) -join ' ') -match '## Split') 'The failure must carry the problem'
    }

    # 17. A complete plan. No failure, and the plan is listed as judged, so the push can print it.
    $root = New-PlanFolder -PlanBody (New-PlanText)
    $result = Get-PlanSplitFailure -RepoRoot $root -Item @(New-EnteringItem)
    Assert-Equal 0 $result.Failures.Count 'A complete plan passes'
    Assert-Equal 1 $result.Judged.Count 'A plan that was read is listed as judged'

    # 18. 'Plan: none' with a reason. The item has no plan, so there is nothing to judge.
    $root = New-PlanFolder
    $result = Get-PlanSplitFailure -RepoRoot $root -Item @(New-EnteringItem -PlanBullet '- Plan: none - trivial wording fix')
    Assert-Equal 0 $result.Failures.Count '"Plan: none" passes'
    Assert-Equal 0 $result.Judged.Count '"Plan: none" judges nothing'

    # 19. No '- Plan:' bullet. tests/BacklogPlanPointer.Tests.ps1 owns that problem, so this check
    #     stays quiet rather than report it a second time.
    $result = Get-PlanSplitFailure -RepoRoot $root -Item @(New-EnteringItem -PlanBullet '')
    Assert-Equal 0 $result.Failures.Count 'An item with no Plan bullet passes here'

    # 20. A pointer to a file that is not on disk. The record cannot be read, so the push stops.
    #     Passing here would let one mistyped pointer switch the rule off for that item.
    $result = Get-PlanSplitFailure -RepoRoot $root -Item @(New-EnteringItem -PlanBullet '- Plan: `docs/superpowers/plans/gone.md`')
    Assert-Equal 1 $result.Failures.Count 'A missing plan file fails'
    if ($result.Failures.Count -eq 1) {
        Assert-True ((@($result.Failures[0].Problems) -join ' ') -match 'not on disk') 'The failure must say the plan is not on disk'
    }

    # 21. A pointer outside the plans folder.
    $result = Get-PlanSplitFailure -RepoRoot $root -Item @(New-EnteringItem -PlanBullet '- Plan: `docs/elsewhere/plan.md`')
    Assert-Equal 1 $result.Failures.Count 'A pointer outside the plans folder fails'

    # 21b. A '- Plan:' bullet whose content is only whitespace. tests/BacklogPlanPointer.Tests.ps1
    #      does not catch this: its Test-BacklogPlanPath and Test-BacklogPlanNone both take a
    #      mandatory string, and PowerShell refuses to bind an empty string to one, so the bullet
    #      is silently read as zero problems there. This check must report it instead.
    $result = Get-PlanSplitFailure -RepoRoot $root -Item @(New-EnteringItem -PlanBullet '- Plan:   ')
    Assert-Equal 1 $result.Failures.Count 'A whitespace-only Plan bullet fails'
    if ($result.Failures.Count -eq 1) {
        Assert-True ((@($result.Failures[0].Problems) -join ' ') -match 'empty') 'The failure must say the bullet is empty'
    }

    # 22. The line a push prints for each judged plan. This line is what makes the size visible.
    $summary = Format-PlanSplitSummary -Number '900' -Record (Get-PlanSplitRecord -PlanText (New-PlanText))
    Assert-Equal 'Backlog item 900: estimate 1 session(s); the user story closes at Task 2 of 3; 0 line(s) name a test-run command; below the split trigger.' $summary 'The summary line reads the record'

    # === Test-BacklogItemEntersExecute: plain data, no git ===================

    # 23. The base does not carry the item, so this branch filed it and carried it into Execute.
    Assert-True (Test-BacklogItemEntersExecute -WorkingStages @('4-execute') -BaseStages @() -BasePath '') `
        'An item filed on this branch enters Execute here'

    # 24. The base holds it at 3-plan.
    Assert-True (Test-BacklogItemEntersExecute -WorkingStages @('4-execute') -BaseStages @('3-plan') -BasePath 'backlog/900-probe.md') `
        'An item the base holds at 3-plan enters Execute here'

    # 25. The base already holds it at 6-verify. This is the case that keeps every plan written
    #     before the rule out of reach.
    Assert-True (-not (Test-BacklogItemEntersExecute -WorkingStages @('7-document') -BaseStages @('6-verify') -BasePath 'backlog/900-probe.md')) `
        'An item already past Plan in the base is not judged'

    # 26. Still at 3-plan on this branch. The record is not required yet.
    Assert-True (-not (Test-BacklogItemEntersExecute -WorkingStages @('3-plan') -BaseStages @() -BasePath '')) `
        'An item at 3-plan has not reached the stage that is judged'

    # 27. Two Stage lines. The backlog numbering check owns that problem.
    Assert-True (-not (Test-BacklogItemEntersExecute -WorkingStages @('4-execute', '4-execute') -BaseStages @() -BasePath '')) `
        'An item with two Stage lines is skipped'

    # 28. One branch can carry an item from 0-intake to 9-ship. Its last push is still judged.
    Assert-True (Test-BacklogItemEntersExecute -WorkingStages @('9-ship') -BaseStages @('0-intake') -BasePath 'backlog/900-probe.md') `
        'An item that reaches 9-ship on this branch enters Execute here'

    # 29. Stage 10 is later than stage 4. A text sort would put 10-cleanup before 4-execute.
    Assert-True (Test-BacklogStageIsExecuteOrLater -Stage '10-cleanup') '10-cleanup counts as Execute or later'
    Assert-True (-not (Test-BacklogStageIsExecuteOrLater -Stage '3-plan')) '3-plan is before Execute'

    # === Get-BranchExecutingItem: throwaway git repositories =================

    # 30. A branch moves an item from 3-plan to 4-execute. One record, carrying the pushed lines.
    $repo = New-TempGitRepo
    Write-Item -Root $repo -Stage '3-plan'
    Save-Repo -Root $repo -Message 'plan 900'
    $base = Get-HeadSha -Root $repo
    Write-Item -Root $repo -Stage '4-execute'
    Save-Repo -Root $repo -Message 'execute 900'
    $entering = @(Get-BranchExecutingItem -RepoRoot $repo -MergeBase $base -TargetCommit (Get-HeadSha -Root $repo))
    Assert-Equal 1 $entering.Count 'An item moved to 4-execute is returned'
    if ($entering.Count -eq 1) {
        Assert-Equal '900' $entering[0].Number 'The record names the item'
        Assert-Equal 'backlog/900-probe.md' $entering[0].RelativePath 'The record names the item file'
        Assert-True ((@($entering[0].Lines) -join "`n") -match '4-execute') 'The record carries the pushed lines'
    }

    # 31. A branch edits an item the base already holds at 6-verify. Its plan predates the rule,
    #     so the check must not read it.
    $repo = New-TempGitRepo
    Write-Item -Root $repo -Stage '6-verify'
    Save-Repo -Root $repo -Message 'verify 900'
    $base = Get-HeadSha -Root $repo
    Write-Item -Root $repo -Stage '6-verify' -Extra '- Typo repaired.'
    Save-Repo -Root $repo -Message 'fix a typo in 900'
    Assert-Equal 0 @(Get-BranchExecutingItem -RepoRoot $repo -MergeBase $base -TargetCommit (Get-HeadSha -Root $repo)).Count `
        'An item already past Plan in the base returns nothing'

    # 32. A branch files a new item at 1-pickup.
    $repo = New-TempGitRepo
    $base = Get-HeadSha -Root $repo
    Write-Item -Root $repo -Stage '1-pickup'
    Save-Repo -Root $repo -Message 'file 900'
    Assert-Equal 0 @(Get-BranchExecutingItem -RepoRoot $repo -MergeBase $base -TargetCommit (Get-HeadSha -Root $repo)).Count `
        'A new item at 1-pickup returns nothing'

    # 33. An unresolvable merge base must throw. An empty list would switch the check off in silence.
    $repo = New-TempGitRepo
    $threw = $false
    try {
        $null = Get-BranchExecutingItem -RepoRoot $repo -MergeBase '0000000000000000000000000000000000000000' `
            -TargetCommit (Get-HeadSha -Root $repo)
    } catch {
        $threw = $true
    }
    Assert-True $threw 'An unresolvable merge base must throw'

    # === the script itself, run as pre-push runs it ==========================
    # Pre-push reads the exit code and nothing else, so the exit code is the contract. The fixture
    # root carries a space, because pre-push passes -MergeBase through 'pwsh -NoProfile -File'.
    $entryRepo = New-TempGitRepo -Prefix 'split record entry'
    $entryBullet = '- Plan: `docs/superpowers/plans/probe-plan-900.md`'
    Write-Item -Root $entryRepo -Stage '3-plan' -PlanBullet $entryBullet
    Save-Repo -Root $entryRepo -Message 'plan 900'
    $entryBase = Get-HeadSha -Root $entryRepo
    Write-Item -Root $entryRepo -Stage '4-execute' -PlanBullet $entryBullet
    Save-Repo -Root $entryRepo -Message 'execute 900'
    $entryPlan = Join-Path $entryRepo 'docs/superpowers/plans/probe-plan-900.md'
    Set-Content -LiteralPath $entryPlan -Value (New-PlanText -NoSection) -Encoding utf8

    $checkScript = Join-Path $suiteRoot 'scripts/check-plan-split-record.ps1'
    $pwshPath = (Get-Process -Id $PID).Path

    function Invoke-CheckScript {
        param([string] $Root, [string] $Base)

        $output = & $pwshPath -NoProfile -File $checkScript -RepoRoot $Root -MergeBase $Base 2>&1
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = (@($output) -join "`n") }
    }

    # 34. An item entering Execute whose plan has no Split section: exit 1. The refusal names the
    #     item, the plan, the problem, and how to skip the check.
    $run = Invoke-CheckScript -Root $entryRepo -Base $entryBase
    Assert-Equal 1 $run.ExitCode "A plan with no Split record must exit 1, got: $($run.Text)"
    Assert-True ($run.Text -match 'Backlog item 900') 'The refusal must name the item'
    Assert-True ($run.Text -match 'backlog/900-probe\.md') 'The refusal must name the item file'
    Assert-True ($run.Text -match 'probe-plan-900\.md') 'The refusal must name the plan file'
    Assert-True ($run.Text -match '## Split') 'The refusal must name the missing section'
    Assert-True ($run.Text -match 'SKIP_PUSH_HOOK=1') 'The refusal must say how to skip the check'

    # 35. A complete record: exit 0, and the push prints the size of the plan.
    Set-Content -LiteralPath $entryPlan -Value (New-PlanText) -Encoding utf8
    $run = Invoke-CheckScript -Root $entryRepo -Base $entryBase
    Assert-Equal 0 $run.ExitCode "A complete record must exit 0, got: $($run.Text)"
    Assert-True ($run.Text -match 'the user story closes at Task 2 of 3') "The push must print the plan's size, got: $($run.Text)"
    Assert-True ($run.Text -match 'RESULT: every plan entering Execute carries a complete Split record') `
        'A clean run must print its result line'

    # 36. The fixture root above carries a space. This asserts the property rather than assuming it.
    Assert-True ($entryRepo -match ' ') 'The entry-point fixture root must carry a space'

    # === the pre-push wiring, as written down ================================
    # A source assertion. It does not prove the step runs, because pre-push builds the solution
    # first and no unit test can afford that. Backlog 157 ran pre-push by hand once for that proof.
    # It does stop a later edit from deleting the step while this suite stays green.
    $prePushSource = Get-Content -Raw -LiteralPath (Join-Path $suiteRoot 'scripts/pre-push-quick-checks.ps1')
    Assert-True ($prePushSource -match 'check-plan-split-record\.ps1') `
        'pre-push-quick-checks.ps1 must run check-plan-split-record.ps1'
    Assert-True ($prePushSource -match '(?s)check-plan-split-record\.ps1.{0,200}-TargetCommit \$target') `
        'pre-push must judge each pushed commit, not the working tree'
    Assert-True ($prePushSource -match '(?s)check-plan-split-record\.ps1.*?\$LASTEXITCODE -ne 0.*?throw ') `
        'pre-push must throw when the check exits non-zero'

    if ($failures.Count -gt 0) {
        foreach ($failure in $failures) { Write-Host "FAIL: $failure" }
        throw "$($failures.Count) Split record check test(s) failed."
    }

    Write-Host 'Split record check tests passed.'
} finally {
    foreach ($root in $roots) {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}
