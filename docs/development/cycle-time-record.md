# Cycle time record (backlog 188)

This file records how fast the development cycle is, before and after backlog 188. It holds five
measures. Each measure is taken the same way before and after the work.

- `## Before` holds the baseline, taken on 2026-10-18 and 2026-10-19.
- `## Targets` holds the target the user approves for each measure.
- `## Audit` holds the test audit results.
- `## After` holds the numbers after the work.

The session folders under `TestResults/` are not tracked, so every number below is copied in.

## Before

### Machine and revision

- Revision: `8e617610f68d56e8a2d1c025906ae94ba7504fe4` on `feature/wt-speed-up-the-development-cycle`.
  Its merge base with `main` is `a00de1e4`, the merge of PR #451, so the two quick fixes from that
  pull request are part of the baseline.
- Machine: the developer's Windows 11 laptop. PowerShell 7.6.6, .NET SDK 10.0.400.
- Load: no other heavy work ran during the three cases. A first attempt on 2026-10-18 was stopped
  and thrown away, because a Windows VM on the same laptop was busy during it.
- The output never printed `Sharing the test Lane pool with:`, so no other run shared the test
  Lane pool.

### 1. Gate time

Method: `scripts/measure-test-modes.ps1` in Gate Mode runs the five Gate steps (build, format,
PowerShell Suites, coverage slice, diff check) as one timed run. Each case gets 1 warm-up and 3
counted runs. The warm-up is discarded, and the median of the counted runs is reported.

Case 1, full Gate with evidence reuse switched off:

```powershell
pwsh .\scripts\measure-test-modes.ps1 -Mode Gate -BaseRef HEAD -NoEvidenceReuse
```

- Preparation: none beyond the warm-up. The working tree was clean.
- Warm-up: 354.79 s (discarded).
- Counted runs: 350.84 s, 347.73 s, 359.72 s.
- **Median: 350.84 s.** Spread: 3.4 percent of the median.
- Step medians: build 6.54 s, format 45.29 s, PowerShell 295.21 s, coverage 0.14 s, diff check
  0.03 s.
- The coverage slice skipped itself in every run, because no file had changed.

Case 3, second Gate with no input changed (evidence reuse on, which today changes nothing):

```powershell
pwsh .\scripts\measure-test-modes.ps1 -Mode Gate -BaseRef HEAD
```

- Preparation: none beyond the warm-up. The working tree was clean.
- Warm-up: 334.98 s (discarded).
- Counted runs: 335.92 s, 336.01 s, 354.04 s.
- **Median: 336.01 s.** Spread: 5.4 percent of the median.
- Step medians: build 4.76 s, format 40.61 s, PowerShell 291.39 s, coverage 0.12 s, diff check
  0.02 s.
- Case 3 is 4.2 percent faster than case 1. That is inside the 15 to 20 percent hourly drift this
  machine shows, so today the two cases are equal within noise.

### 2. Affected-test time

Method: case 2 of the same script. It runs one preparation Gate, then three fixed changes one after
another. Each change gets 1 warm-up and 3 counted runs. Before each run the script puts the Gate
evidence back to the state it had after the preparation run, and applies the change again.

```powershell
pwsh .\scripts\measure-test-modes.ps1 -Mode Gate -BaseRef HEAD -Change Docs,Script,Code
```

- Preparation run: 346.08 s (build 6.13 s, format 45.03 s, PowerShell 294.71 s, coverage 0.17 s,
  diff check 0.03 s).

| Change | File changed | Warm-up | Counted runs | Median | Spread |
|---|---|---|---|---|---|
| Docs | `docs/development/testing-workflow.md` | 345.19 s | 341.26 s, 342.80 s, 343.70 s | **342.80 s** | 0.7 % |
| Script | `scripts/watch-task.ps1` | 341.82 s | 347.21 s, 343.88 s, 346.29 s | **346.29 s** | 1.0 % |
| Code | `src/Backend/AHKFlowApp.Domain/Entities/Category.cs` | 513.18 s | 510.32 s, 522.27 s, 513.63 s | **513.63 s** | 2.3 % |

Step medians per change:

| Change | build | format | PowerShell | coverage | diff check |
|---|---|---|---|---|---|
| Docs | 5.52 s | 44.93 s | 290.43 s | 0.16 s | 0.03 s |
| Script | 5.57 s | 44.98 s | 293.46 s | 0.16 s | 0.03 s |
| Code | 5.42 s | 46.55 s | 281.44 s | 180.80 s | 0.02 s |

- The change is one comment line at the end of the file. The script removes it after the case.
- The coverage slice skipped itself for Docs and Script, and ran for Code.
- Every change still runs all 77 PowerShell Suites, because the Gate cannot reuse a result yet.

### 3. CI critical path

Method: the last 10 runs of `ci.yml` with event `pull_request`, conclusion `success` and attempt 1.
A run's critical path is the latest `completedAt` among its required CI jobs, minus the run's
`startedAt`. The required jobs come from branch protection. On 2026-10-18 they were `build-test`,
`powershell-suites`, `bicep-lint`, `codex-skills-hash-parity` and `repo-invariants`.
`shipping-pr-closes-item` is also required, but it runs in another workflow.

```powershell
gh api repos/s205109/AHKFlowApp/branches/main/protection/required_status_checks --jq .contexts
gh run list --repo s205109/AHKFlowApp --workflow ci.yml --event pull_request --status success --limit 40 --json databaseId,attempt,startedAt
gh run view <id> --repo s205109/AHKFlowApp --json jobs --jq '.jobs[] | {name, completedAt}'
```

| Run | Critical path |
|---|---|
| 39143056466 | 763 s |
| 39142983069 | 780 s |
| 39142844349 | 781 s |
| 39142835600 | 800 s |
| 39136673805 | 725 s |
| 39136477682 | 785 s |
| 39136430795 | 769 s |
| 39136272688 | 773 s |
| 39135497378 | 757 s |
| 39135420630 | 540 s |

**Median: 771 s.**

### 4. Gate-required stage exits per item

Method: the last 10 items moved into `backlog/done/` on `origin/main`. In each item's git history,
read the pairs of removed and added `- **Stage**:` lines. Count a change from `6-verify` to any
higher stage, and a change from `8-review` to any higher stage. A move back to `4-execute` is a
failure edge and does not count.

```powershell
git log origin/main --no-renames --diff-filter=A --name-only --format= -- backlog/done/
git log origin/main --follow -p --format=%H -- backlog/done/<file>
```

The follow-up item repeats these commands with `4-execute` in place of `6-verify`, once the process
item merges.

| Item | Exits from 6-verify | Exits from 8-review | Total |
|---|---|---|---|
| 186 | 1 | 1 | 2 |
| 185 | 1 | 1 | 2 |
| 168 | 1 | 1 | 2 |
| 183 | 1 | 1 | 2 |
| 184 | 1 | 1 | 2 |
| 174 | 1 | 1 | 2 |
| 176 | 1 | 1 | 2 |
| 171 | 1 | 1 | 2 |
| 172 | 1 | 1 | 2 |
| 181 | 1 | 1 | 2 |

**Median: 2 per item.** This is a proxy. It does not see failed Gate attempts or repeated Gates
inside one stage.

### 5. Flaky failures

Method: every run of `ci.yml` and `shipping-pr-closes-item.yml` created from 2026-09-18 to
2026-10-18. A failure is any failed attempt; earlier attempts of a rerun come from
`gh api repos/s205109/AHKFlowApp/actions/runs/<id>/attempts/<n>`. A failure is flaky when a later
attempt of the same run, or a later run of the same workflow on the same `headSha`, succeeded.

```powershell
gh run list --repo s205109/AHKFlowApp --workflow ci.yml --created ">=2026-09-18" --limit 500 --json databaseId,attempt,conclusion,headSha,createdAt
gh run list --repo s205109/AHKFlowApp --workflow shipping-pr-closes-item.yml --created ">=2026-09-18" --limit 500 --json databaseId,attempt,conclusion,headSha,createdAt
```

- `ci.yml`: 300 runs, 304 attempts, 57 failures, 4 flaky.
- `shipping-pr-closes-item.yml`: 330 runs, 330 attempts, 14 failures, 0 flaky.

All four flaky failures were in job `powershell-suites`, step `Run PowerShell suites`:

| Run | Date | Suite | Failing case |
|---|---|---|---|
| 38236860070 | 2026-10-12 | `CoverageRunnerProgress.Tests.ps1` | Cancellation releases Lane and checkout ownership in a surviving host |
| 38779466003 | 2026-10-15 | `CiPowerShellSuiteRunner.Tests.ps1` | Lane one runner admits exactly two of four Workers; off admits all four |
| 38789497998 | 2026-10-15 | `CiPowerShellSuiteRunner.Tests.ps1` | the same case |
| 39002212507 | 2026-10-17 | `LanePool.Tests.ps1` | process crash, exit code -532462766 |

**Count: 4 per 30 days.**

### Suites ranked by time

Each Suite's median over the 3 counted runs of case 1. Together they hold 1,760.2 s of Suite time.
The runner spreads it over its Workers, so the PowerShell step took about 295 s of wall clock.
`baselineSeconds` in `tests/powershell-suites.json` now holds these medians, rounded to one
decimal, with 0.1 s as the lowest value. `CodexSkillsHashParity.Tests.ps1` does not run on Windows,
so it keeps its old value.

Excluded from the audit:

- `WorktreeRemoveHook.Tests.ps1`: backlog 068 is still open (in `backlog/blocked/`), and the audit
  leaves its Suite alone.
- `FrictionRecallSample.Tests.ps1`, `CleanupEventLabels.Tests.ps1`, `CleanupEventScripts.Tests.ps1`,
  `HarnessOverheadReport.Tests.ps1` and `IntervalUnion.Tests.ps1`: Task 4 retires them.

| Rank | Suite | Median | Note |
|---|---|---|---|
| 1 | `CiPowerShellSuiteRunner.Tests.ps1` | 177.4 s | |
| 2 | `StageTransition.Tests.ps1` | 169.9 s | |
| 3 | `AgentWorktreeGuard.Tests.ps1` | 111.5 s | |
| 4 | `WorktreeMergedCleanupEligibility.Tests.ps1` | 102.1 s | |
| 5 | `WatchTask.Tests.ps1` | 85.2 s | |
| 6 | `MeasureTestModes.Tests.ps1` | 84.7 s | |
| 7 | `WorktreeMergedCleanupSweep.Tests.ps1` | 78.8 s | |
| 8 | `WorktreeRemoveHook.Tests.ps1` | 72.6 s | excluded, backlog 068 |
| 9 | `WorktreeMergedCleanup.Tests.ps1` | 71.9 s | |
| 10 | `WorktreeSweepRemoteBase.Tests.ps1` | 65.3 s | |
| 11 | `BacklogStaleOpen.Tests.ps1` | 57.2 s | |
| 12 | `CoverageRunnerProgress.Tests.ps1` | 56.9 s | |
| 13 | `WorktreeLocalDevSetup.Tests.ps1` | 48.3 s | |
| 14 | `CitationFreshness.Tests.ps1` | 48.1 s | |
| 15 | `TestSqlContainerLifecycle.Tests.ps1` | 40.4 s | |
| 16 | `AgentPreCommitHook.Tests.ps1` | 29.9 s | |
| 17 | `TestFastDotnetProgress.Tests.ps1` | 29.0 s | |
| 18 | `LanePool.Tests.ps1` | 27.7 s | |
| 19 | `TestFastPowerShellMode.Tests.ps1` | 27.3 s | |
| 20 | `WorktreeLockHonored.Tests.ps1` | 27.1 s | |
| 21 | `CoverageSliceSkip.Tests.ps1` | 26.3 s | |
| 22 | `ProcessParity.Tests.ps1` | 23.0 s | |
| 23 | `WorktreeCreateHookStdin.Tests.ps1` | 20.2 s | |
| 24 | `ShippedPlanTicked.Tests.ps1` | 20.1 s | |
| 25 | `WorktreeHolderProbe.Tests.ps1` | 18.8 s | |
| 26 | `PrePushHook.Tests.ps1` | 18.7 s | |
| 27 | `WorktreeLeftoverBranch.Tests.ps1` | 17.9 s | |
| 28 | `GateWording.Tests.ps1` | 15.5 s | |
| 29 | `ShippingPrClosesItem.Tests.ps1` | 14.5 s | |
| 30 | `SuiteRunnerLinux.Tests.ps1` | 14.3 s | |
| 31 | `PlanWorkflowParity.Tests.ps1` | 14.0 s | |
| 32 | `BacklogNumbering.Tests.ps1` | 13.8 s | |
| 33 | `StopNextStepHook.Tests.ps1` | 12.0 s | |
| 34 | `WorkflowPdfGenerator.Tests.ps1` | 11.3 s | |
| 35 | `PrePushQuickChecks.Tests.ps1` | 11.1 s | |
| 36 | `ProcessAnchors.Tests.ps1` | 10.1 s | |
| 37 | `PlanSplitRecord.Tests.ps1` | 8.8 s | |
| 38 | `FrictionRecallSample.Tests.ps1` | 8.7 s | excluded, retired in Task 4 |
| 39 | `LaneFileLockPrimitive.Tests.ps1` | 7.0 s | |
| 40 | `WorktreePlanGuard.Tests.ps1` | 5.2 s | |
| 41 | `PreCommitAntiPatternHook.Tests.ps1` | 4.3 s | |
| 42 | `BacklogPlanPointer.Tests.ps1` | 3.8 s | |
| 43 | `CleanupEventScripts.Tests.ps1` | 3.4 s | excluded, retired in Task 4 |
| 44 | `WorktreeWatcherWindow.Tests.ps1` | 2.9 s | |
| 45 | `BlockUpstreamMpForksHook.Tests.ps1` | 2.8 s | |
| 46 | `Progress.Tests.ps1` | 2.8 s | |
| 47 | `WorktreeRemovalLog.Tests.ps1` | 2.6 s | |
| 48 | `RunIndependentSqlTests.Tests.ps1` | 2.4 s | |
| 49 | `ProcessFriction.Tests.ps1` | 2.3 s | |
| 50 | `WorktreePlansSymlink.Tests.ps1` | 2.3 s | |
| 51 | `RunFrontend.Tests.ps1` | 2.2 s | |
| 52 | `WorktreeBaseRef.Tests.ps1` | 2.0 s | |
| 53 | `WorktreeSpawnPruneOptOut.Tests.ps1` | 1.9 s | |
| 54 | `SuiteWorkerCount.Tests.ps1` | 1.8 s | |
| 55 | `CoverageInputCompleteness.Tests.ps1` | 1.5 s | |
| 56 | `SkillParity.Tests.ps1` | 1.4 s | |
| 57 | `WorktreeJsonEdit.Tests.ps1` | 1.3 s | |
| 58 | `ArchivedPlanFrozen.Tests.ps1` | 1.1 s | |
| 59 | `CodexParityCiJob.Tests.ps1` | 1.1 s | |
| 60 | `CiBuildTestSteps.Tests.ps1` | 1.0 s | |
| 61 | `ProcessWorkflow.Tests.ps1` | 1.0 s | |
| 62 | `RepoInvariantsCiJob.Tests.ps1` | 1.0 s | |
| 63 | `CoverageRunLock.Tests.ps1` | 0.9 s | |
| 64 | `HarnessOverheadReport.Tests.ps1` | 0.9 s | excluded, retired in Task 4 |
| 65 | `PersonalDefaultsSyncMarker.Tests.ps1` | 0.9 s | |
| 66 | `BacklogFolderParity.Tests.ps1` | 0.8 s | |
| 67 | `PrAgentConfiguration.Tests.ps1` | 0.8 s | |
| 68 | `TrxIntervals.Tests.ps1` | 0.8 s | |
| 69 | `CleanupEventLabels.Tests.ps1` | 0.7 s | excluded, retired in Task 4 |
| 70 | `HandoverRules.Tests.ps1` | 0.7 s | |
| 71 | `ShippingPrClosesItemWorkflow.Tests.ps1` | 0.7 s | |
| 72 | `AcceptanceBoxes.Tests.ps1` | 0.6 s | |
| 73 | `IntervalUnion.Tests.ps1` | 0.6 s | excluded, retired in Task 4 |
| 74 | `ProgressParallel.Tests.ps1` | 0.6 s | |
| 75 | `SkillLayout.Tests.ps1` | 0.6 s | |
| 76 | `WorktreeBranchName.Tests.ps1` | 0.6 s | |
| 77 | `WorktreePowerShellHost.Tests.ps1` | 0.5 s | |

### Proposed .NET verdict

Proposed: **worth an audit item.** The user confirms or changes this at Task 3.

- With no `.cs` change (case 1), the .NET steps are build and format: 51.8 s of 350.8 s, which is
  14.8 percent. The .NET tests do not run, because the coverage slice skips itself. The PowerShell
  step is 295.2 s, which is 84.1 percent.
- With a `.cs` change (the `Code` change in case 2), the .NET tests run in the coverage slice and
  take 180.8 s, which is 35.2 percent of 513.6 s. All .NET steps together take 232.8 s, which is
  45.3 percent. The PowerShell step is 281.4 s, which is 54.8 percent.
- So every code change pays about 171 s more than a docs change (513.6 s against 342.8 s). The
  .NET tests are the second largest cost of the Gate, and evidence reuse does not help the first
  Gate after a code change.
- Format is a fixed cost of about 45 s on every Gate. It is not a test, so a test audit does not
  cover it.

## Targets

Approved by the user on 2026-10-19.

| # | Measure | Baseline | Target |
|---|---|---|---|
| 1 | Gate time, full Gate with evidence reuse switched off | 350.8 s | 210 s or less (40 percent lower) |
| 2 | Affected-test time, Docs change | 342.8 s | 90 s or less |
| 2 | Affected-test time, Script change | 346.3 s | 150 s or less |
| 2 | Affected-test time, Code change | 513.6 s | 300 s or less |
| 3 | CI critical path | 771 s | 450 s or less |
| 4 | Gate-required stage exits per item | 2 | 2 or less |
| 5 | Flaky failures per 30 days | 4 | 1 or less |

- Measures 1 and 2 are judged at 188's closure, in its after record.
- Measures 3, 4 and 5 move to the follow-up item, with their targets, and are judged there.
- Measure 4 stays at 2 or less. After the process item merges, the counted stages are `4-execute`
  and `8-review`, so two exits per item remain normal.

.NET verdict: **worth an audit item**, confirmed by the user on 2026-10-19. Backlog 194 carries
the .NET test audit.

## Audit

### Candidate set

Picked on 2026-10-19: the ten slowest Suites from the ranking under `## Before`, less the
exclusions.

Batch 1:

1. `CiPowerShellSuiteRunner.Tests.ps1` (177.4 s)
2. `StageTransition.Tests.ps1` (169.9 s)
3. `AgentWorktreeGuard.Tests.ps1` (111.5 s)
4. `WorktreeMergedCleanupEligibility.Tests.ps1` (102.1 s)
5. `WatchTask.Tests.ps1` (85.2 s)

Batch 2:

6. `MeasureTestModes.Tests.ps1` (84.7 s)
7. `WorktreeMergedCleanupSweep.Tests.ps1` (78.8 s)
8. `WorktreeMergedCleanup.Tests.ps1` (71.9 s)
9. `WorktreeSweepRemoteBase.Tests.ps1` (65.3 s)
10. `BacklogStaleOpen.Tests.ps1` (57.2 s)

Exclusions:

- `WorktreeRemoveHook.Tests.ps1` (rank 8, 72.6 s): backlog 068 is still open, in
  `backlog/blocked/`.
- The five Suites Task 4 retired. None of them was in the top ten.
- Unmerged branches: no remote branch changes any candidate. The check ran
  `git log origin/main..<branch> -- tests/<Suite>` over the six remote branches other than
  `main`. This branch changes `MeasureTestModes.Tests.ps1` itself (Task 1), which does not exclude
  it.

### The refuter's method

The refuters use the `test-value-evidence` skill from the `dotnet-test` plugin. The installed
copy lacked it until 2026-10-19. `claude plugin update` reported "already at the latest version
(1.0.0)", because the plugin gained the skill without a new version number. An uninstall and a
fresh install of `dotnet-test@dotnet-agent-skills` brought it in, at source commit `10d85e25`.

### Isolation check

Run on 2026-10-19: one workflow agent with `isolation: 'worktree'`, asked only to print its
working directory and `git branch --show-current`.

- Time: 88.9 s for the whole workflow, from 08:59:52. The agent itself did almost nothing.
- What the copy creates: the `WorktreeCreate` hook runs `scripts/new-worktree.ps1`, so each copy
  is a full managed worktree.
  - A worktree at `.claude/worktrees/wf_f47e00c5-410-1`, on a new local branch
    `fix/wt-wf_f47e00c5-410-1`. The branch was not pushed.
  - A port slot: API 5610, UI 5611, SQL 14334, with its own database name and Compose project.
    That was the only free slot below 5612.
  - A merged-cleanup sweep over all eight other worktrees (09:00:05 to 09:00:08 in
    `worktree-removal.log`). It kept all eight.
  - No backlog item, and no change to `backlog/` in the main checkout.
- What it left behind: the worktree, its branch and its port slot. The workflow did not remove
  the copy, although the agent changed nothing in it.
- Inside the copy, `git branch --show-current` was refused. The worktree guard blocks git there,
  the same way it blocks git in an entered session. A refuter in a copy could not run git.

### Refuter mode

Refuters run one at a time, in this worktree. That is the default from the plan. The isolation
check rules out copies: each copy is slow to make, takes a port slot and a branch, runs a
cleanup sweep, stays behind afterwards, and cannot run git.

### Batch 1

The saved workflow is `.claude/workflows/test-audit.js`, with `meta.name` `'test-audit'`. Run
`wf_de859706-6ad` took 164.5 minutes and 1.72 million subagent tokens, for 5 auditors and 5
refuters. Every refuter left the worktree clean.

The auditors gave 473 verdicts: 320 KEEP, 92 SPEED UP, 38 MERGE, 17 REMOVE and 6 REWORK. The
refuters tested all 55 REMOVE and MERGE claims. They upheld 46 and refuted 9.

The user approved the work by group on 2026-10-19, with a limit of about five hours of runs:

- Apply the 46 upheld claims. Drop the 9 refuted ones.
- Apply the 12 largest SPEED UP proposals that change test code only.
- Defer the other 80 SPEED UP proposals and the 6 REWORK proposals to a backlog item. Two of the
  deferred ones need a production refactor: the StageTransition 15-edge loop and the in-process
  GitHub Actions worker count.

Each Suite ran alone, three times per point. The table gives the median in seconds.

| Suite | Before | After remove and merge | After speed-ups |
|---|---|---|---|
| `CiPowerShellSuiteRunner.Tests.ps1` | 117.9 | 111.6 | 104.2 |
| `StageTransition.Tests.ps1` | 111.3 | 95.7 | 94.0 |
| `AgentWorktreeGuard.Tests.ps1` | 67.8 | 57.8 | 50.9 |
| `WorktreeMergedCleanupEligibility.Tests.ps1` | 64.5 | 63.0 | 37.1 |
| `WatchTask.Tests.ps1` | 66.4 | 56.3 | 44.3 |
| Total | 444.4 | 384.4 | 330.7 |

The five Suites lost 113.7 seconds, or 25.6 percent. The time is Suite time, run alone. A Gate
runs Suites in parallel, so its wall-clock saving is smaller.

What changed, per Suite:

- `CiPowerShellSuiteRunner`: 7 driver runs removed and 4 merged into existing cases. Two barrier
  timeouts are shorter, and the Lane "off" iteration is gone.
- `StageTransition`: 6 cases merged into existing fixtures. Fixture seeds are cached per seed
  shape. The cache saved only 1.7 seconds of the 17 the auditor estimated.
- `AgentWorktreeGuard`: 11 duplicate cases removed and 1 merged. A git probe cache runs around the
  three long decision loops, the shim loop shares one stub harness, and the no-regression loop
  keeps one command per tier.
- `WorktreeMergedCleanupEligibility`: 6 cases removed and 3 merged. Two loops lost a repeated
  iteration. This Suite gained most from the speed-ups: 25.9 seconds, against an estimate of 11.
- `WatchTask`: 4 cases removed and 4 merged. The replacement race waits 3 seconds after the
  replacement prints, not 10. The range checks run in the same process.

Two of the new seams were proved with a mutation. Removing the `-Index` range check fails the
range case. Removing `git` from the shim's candidate pattern fails all 12 git commands in the
shim loop. Each commit body names the test that still catches each removed case.

The deferred work is listed in `docs/development/test-audit-deferred.md`.

### Batch 2

Batch 1 used more tokens than planned, so batch 2 ran with lean settings. An auditor returned only
the cases it would change that save 0.5 seconds or more. Refuters ran at medium effort, and
tested every REMOVE and every MERGE that saves 1 second or more. Run `wf_b44c3500-c14` took 36.8
minutes and 0.84 million subagent tokens, for 5 auditors and 4 refuters. `BacklogStaleOpen` had
no claim to refute. Every refuter left the worktree clean.

The auditors proposed 42 changes, about 112 seconds in all: 31 SPEED UP, 10 MERGE and 1 REMOVE.
The refuters tested 9 claims and upheld all 9. Two MERGE claims saved less than 1 second each, so
no refuter tested them.

The user approved two of three groups on 2026-10-19:

- Group A: apply the 9 upheld claims, about 25 seconds.
- Group B: apply the 18 SPEED UP proposals that only change a number, such as a sleep, a timeout
  or a filler-commit count, about 28 seconds.
- Group C: defer the 13 SPEED UP proposals that need new fixture code, and the 2 untested MERGE
  claims, about 59 seconds. Batch 1's seed cache saved only 1.7 of an estimated 17 seconds, so
  fixture rewrites carry more risk for their estimate.

Each Suite ran alone, three times per point, after one warm-up run. The table gives the median in
seconds.

| Suite | Before | After |
|---|---|---|
| `MeasureTestModes.Tests.ps1` | 68.1 | 45.4 |
| `WorktreeMergedCleanupSweep.Tests.ps1` | 46.3 | 30.3 |
| `WorktreeMergedCleanup.Tests.ps1` | 41.4 | 29.0 |
| `WorktreeSweepRemoteBase.Tests.ps1` | 32.6 | 29.8 |
| `BacklogStaleOpen.Tests.ps1` | 30.6 | 22.4 |
| Total | 219.0 | 156.9 |

The five Suites lost 62.1 seconds, or 28.4 percent, against an estimate of about 53.

What changed, per Suite:

- `MeasureTestModes`: 3 cases merged into existing cases. Stub sleeps are zero where a case
  asserts only calls or signals, and smaller where it compares run times. The warm-up ceiling
  case waits for a 3 second settle target, not 5.
- `WorktreeMergedCleanupSweep`: 3 sweeps merged into 2 existing sweeps. The kill timeout is 1
  second, not 3.
- `WorktreeMergedCleanup`: 17 negative eligibility checks removed. Each one repeated a negative
  `Test-BranchOwnWorkWasMerged` check, which runs the same verdict. The three config sections
  share one repository.
- `WorktreeSweepRemoteBase`: the report-mode sweep merged into the end-to-end `-Cleanup` sweep.
  The refuter showed that `WorktreeLeftoverBranch.Tests.ps1` still catches a stale report-mode
  base.
- `BacklogStaleOpen`: the cases use a limit of 3 and fewer filler commits, in place of the
  default limit of 12 and up to 29 commits. Two cases still pin the default limit.

One change made a case stronger. The bulk-edit row now uses 3 filler commits, so it fails when
the bulk edit is read as the stamp. With 9 filler commits it passed on that defect. A mutation
proved it: dropping the `-G` Stage-line filter from the stamp lookup fails only that row.

The deferred rows are under `## Batch 2` in `docs/development/test-audit-deferred.md`. The
workflow reference is `docs/development/test-audit-workflow.md`.

### Gate reuse per Suite

Each candidate Suite carries a `reuse` field in `tests/powershell-suites.json`. Two are eligible:

- `StageTransition.Tests.ps1`: eligible. Its git repositories are fixtures, and its `gh` is a fake.
- `WatchTask.Tests.ps1`: not eligible. Its script lists the directories next to the real
  checkout, which no key covers. The review of pull request 454 found this; it was eligible at
  first.
- `WorktreeMergedCleanup.Tests.ps1`: eligible. Its shared helper now names
  `scripts/cleanup-merged-worktrees.ps1` by a written-out path, so the resolver can follow it.
- `BacklogStaleOpen.Tests.ps1`: not eligible. Its last two checks read the live repository: its
  backlog items and its base branch. The final review found this; it was marked eligible at first.
- `CiPowerShellSuiteRunner.Tests.ps1`: not eligible. It runs `cmd` and reads the machine's core
  count.
- `AgentWorktreeGuard.Tests.ps1`: not eligible. It runs bash, cmd and Windows PowerShell, and
  reads the user profile.
- `WorktreeMergedCleanupEligibility.Tests.ps1`: not eligible. Its sweep child calls the real `gh`.
- `WorktreeMergedCleanupSweep.Tests.ps1`: not eligible. Its sweep child calls the real `gh`.
- `WorktreeSweepRemoteBase.Tests.ps1`: not eligible. It runs Windows PowerShell 5.1, and its sweep
  child calls the real `gh`.
- `MeasureTestModes.Tests.ps1`: not eligible. It dot-sources a runspace parameter, which the
  resolver cannot follow.

Two PowerShell Mode runs on 2026-10-19 proved reuse. Both passed all 73 Suites. The second printed
`REUSED` for the four Suites eligible then and ran the other 69. Then `# probe` was appended to
`scripts/watch-task.ps1` for one more run. `WatchTask` ran again and passed, and the other three
eligible Suites were reused. The file's bytes were restored afterwards.

## After

Measured on 2026-10-20 at revision `e138787f`, the final revision: the last commit that changes
a script or a Suite. The commands and their order are the ones under `## Before`, each with
`-BaseRef HEAD`. No run printed `Sharing the test Lane pool with:`. The coverage step was in the
same state as before in every case: it skipped itself in case 1, case 3, `Docs` and `Script`, and
it ran for `Code`.

One commit came after this measurement. CI failed at Ship on the warm-up ceiling case in
`MeasureTestModes.Tests.ps1`, whose settle target audit batch 2 had cut from 5 to 3 seconds.
Commit `cbd3797a` put the original 300 ms runs and 5 second target back. That adds about 2
seconds to one Suite, which runs beside the others, so the Gate times move by less than that.
Every target is missed by 90 seconds or more, so no verdict can change. On 2026-10-22 the user
chose to keep this measurement rather than run it again.

### 1. Gate time

Case 1, full Gate with evidence reuse switched off:

- Warm-up: 317.39 s (discarded).
- Counted runs: 313.95 s, 315.62 s, 319.10 s.
- **Median: 315.62 s**, against 350.84 s before: 10.0 percent lower. Spread: 1.6 percent.
- Step medians: build 5.75 s, format 47.15 s, PowerShell 262.83 s, coverage 0.18 s, diff check
  0.03 s.

Case 3, second Gate with no input changed, evidence reuse on:

- Warm-up: 267.46 s (discarded).
- Counted runs: 272.97 s, 307.70 s, 309.37 s.
- **Median: 307.70 s**, against 336.01 s before: 8.4 percent lower. Spread: 11.8 percent.
- Step medians: build 5.06 s, format 47.69 s, PowerShell 254.45 s, coverage 0.16 s, diff check
  0.02 s.
- Two Suites were eligible for reuse. Case 1 against case 3 is the saving that reuse alone buys:
  8.4 seconds of PowerShell step.

### 2. Affected-test time

Preparation run: 319.33 s (build 6.21 s, format 46.97 s, PowerShell 265.96 s, coverage 0.16 s,
diff check 0.02 s).

| Change | Warm-up | Counted runs | Median | Before | Change |
|---|---|---|---|---|---|
| Docs | 280.79 s | 278.61 s, 296.83 s, 342.47 s | **296.83 s** | 342.80 s | -13.4 % |
| Script | 302.87 s | 308.77 s, 305.29 s, 297.84 s | **305.29 s** | 346.29 s | -11.8 % |
| Code | 486.48 s | 491.60 s, 492.46 s, 526.03 s | **492.46 s** | 513.63 s | -4.1 % |

Step medians per change:

| Change | build | format | PowerShell | coverage | diff check |
|---|---|---|---|---|---|
| Docs | 5.30 s | 41.80 s | 251.40 s | 0.17 s | 0.03 s |
| Script | 5.63 s | 50.23 s | 251.62 s | 0.15 s | 0.03 s |
| Code | 6.39 s | 49.53 s | 236.81 s | 199.69 s | 0.02 s |

### Verdict

| # | Measure | Before | After | Target | Verdict |
|---|---|---|---|---|---|
| 1 | Gate time, reuse off | 350.8 s | 315.6 s | 210 s or less | **missed** |
| 2 | Affected-test time, Docs | 342.8 s | 296.8 s | 90 s or less | **missed** |
| 2 | Affected-test time, Script | 346.3 s | 305.3 s | 150 s or less | **missed** |
| 2 | Affected-test time, Code | 513.6 s | 492.5 s | 300 s or less | **missed** |

Every number fell, and every target was missed. The build, format and diff check steps take about
50 seconds together, and the PowerShell step still takes 237 to 263 seconds. The audit made the
Suites faster. Reuse adds little, because only 2 of 73 Suites are eligible: the two reviews took
away `BacklogStaleOpen` and `WatchTask`, which read state no key covers.

Stop S6, answered by the user on 2026-10-20: **accept the result.** The answer was given on the
first measurement below; this one, on the final revision, misses the same four targets. The
misses stand as recorded. The remaining speed-ups stay in backlog 195.

### The first measurement, at `8a326f89`

Taken on 2026-10-19 and 2026-10-20, before the two review fixes and the Simplify commit. Plan rule
G9 asked for this task to run again on the final revision, which the section above does.

- Case 1: median 311.31 s. One run stalled for about half an hour, most likely in machine sleep,
  and the median does not use it.
- Case 3: median 241.55 s. Four Suites were eligible then, and reuse saved 57.4 seconds of
  PowerShell step.
- Case 2: `Docs` 287.78 s, `Script` 251.47 s, `Code` 456.28 s.

An attempt at case 1 failed in its second run. `WorktreeMergedCleanupSweep.Tests.ps1` stopped
with "Cannot convert value System.Object[] to type System.Boolean": an `Assert-True` received an
array. The same Suite then passed 12 runs in a row on its own, and it passed in every other Gate
run. The message names no line, so the cause is not found. It is recorded here as one flaky
failure under load.

### Gate executions

From this worktree's `TestResults/gate-log.jsonl`, between 2026-10-19 20:14 and 23:43 UTC, after
Task 10. This is reported on its own, and is not compared with the stage-exits measure.

- 27 PowerShell-step runs over the real Suites. 20 ran with reuse on, and 7 with reuse off.
- 1,928 Suite results executed and 43 reused.
- Elapsed time per run: 194.5 s to 281.6 s, plus the one stalled run of 2,021 s.
- Budget warnings: `TestFastPowerShellMode.Tests.ps1` 7 times, and six other Suites once each.
- The log also holds 6 lines from fake Suites, all written before Task 11 fixed the test that
  leaked them.

### Audit results per batch

| Batch | Removed | Merged | Reworked | Sped up | Deferred |
|---|---|---|---|---|---|
| 1 | 28 cases | 18 cases | 0 | 12 proposals | 80 SPEED UP, 6 REWORK |
| 2 | 17 duplicate checks (1 claim) | 8 cases | 0 | 18 proposals | 13 SPEED UP, 2 MERGE |

Refuted claims: 9 in batch 1, none in batch 2. The deferred rows are in
`docs/development/test-audit-deferred.md`, and backlog 195 carries them.

### Baselines refreshed

`baselineSeconds` in `tests/powershell-suites.json` now holds the case-1 median of each Suite the
audit changed, and of `GateEvidence.Tests.ps1`, from the final-revision run above:

| Suite | Before | After |
|---|---|---|
| `CiPowerShellSuiteRunner.Tests.ps1` | 177.4 | 150.6 |
| `StageTransition.Tests.ps1` | null | 136.6 |
| `AgentWorktreeGuard.Tests.ps1` | 111.5 | 86.7 |
| `WorktreeMergedCleanupEligibility.Tests.ps1` | 102.1 | 65.0 |
| `WatchTask.Tests.ps1` | 85.2 | 70.2 |
| `MeasureTestModes.Tests.ps1` | 84.7 | 68.9 |
| `WorktreeMergedCleanupSweep.Tests.ps1` | 78.8 | 52.0 |
| `WorktreeMergedCleanup.Tests.ps1` | 71.9 | 55.9 |
| `WorktreeSweepRemoteBase.Tests.ps1` | 65.3 | 55.6 |
| `BacklogStaleOpen.Tests.ps1` | 57.2 | 41.0 |
| `GateEvidence.Tests.ps1` | null | 33.8 |

`TestFastPowerShellMode.Tests.ps1` warned in 7 runs but was not audited, so its baseline is
unchanged.

## Backlog 195

Backlog 195 applied or rejected the deferred rows of four Suites. Each Suite ran alone with
`scripts/run-powershell-suites.ps1 -Suite <file>`: one warm-up run, then three counted runs. The
numbers below are the medians of the counted runs, in seconds. A run that printed "Sharing the
test Lane pool with:" would not count. No run printed it.

### Final Suite time, run alone

These after measurements cover the final code, at `2b527da5`. That includes the second review
round: the installed-jq shim runs and the reused-fixture checks. Each Suite had one warm-up and
three counted runs. No run shared the Lane pool.

| Suite | Historical before (s) | Final counted runs (s) | Final median (s) |
|---|---|---|---|
| `WatchTask.Tests.ps1` | 42.0 | 27.9, 29.0, 27.5 | 27.9 |
| `CiPowerShellSuiteRunner.Tests.ps1` | 113.4 | 82.0, 82.2, 87.3 | 82.2 |
| `StageTransition.Tests.ps1` | 92.8 | 75.4, 72.7, 69.6 | 72.7 |
| `AgentWorktreeGuard.Tests.ps1` | 42.6 | 47.4, 46.4, 45.9 | 46.4 |

The before sets come from the original task measurements, on earlier machine load.
They provide historical context, not a controlled measurement of this recovery's saving.
These medians replace two earlier sets from earlier code: 31.2, 82.0, 65.5 and 38.6 s, then
28.3, 78.2, 68.4 and 44.9 s at `4989055f`. AgentWorktreeGuard is higher than both, because
it gained the shim coverage repairs and the installed-jq runs.
The original samples and discarded drifted sets remain in commit a539e7db.
The samples are saved locally in `.superpowers/review4-medians.json` and matching logs.

### Changes timed on their own

A change timed on its own had a stopwatch around the code it touched. The Suite printed the
stopwatch at its end, and the stopwatch was never committed. The three runs after one change are
the before set of the next change. A change stays only when its median fell by 1 s or more.

| Suite | Change | Rows | Before | After | Verdict |
|---|---|---|---|---|---|
| `WatchTask` | W-A: run the script in this process | 71, 72, 75, 76, 87 to 90 | 9.06 | 1.91 | kept |
| `WatchTask` | W-B: `Start-ThreadJob` in all 15 job cases | 73, 77 to 86 | 26.32 | 21.90 | kept |
| `WatchTask` | W-C: cap the stubbed 500 ms sleeps at 50 ms | 70, 74 | 4.54 | 1.41 | kept |
| `CiPowerShellSuiteRunner` | C-B: runs that fail before any Suite run in this process | 37, 42, 43, 44, 48 to 52 | 6.96 | 0.82 | kept |
| `CiPowerShellSuiteRunner` | C-A: `Resolve-SuiteWorkerCount`, its cases, and two runner runs kept | 31, 32, 34, 35 | 11.19 | 3.47 | kept |
| `StageTransition` | S-A: the loop skips four edges that named cases prove | 53 | 23.69 | 19.83 | superseded; rejected after recovery |
| `StageTransition` | S-B: four driver refusals run on `$fx` | 54, 56, 60, 69 | 2.86 | 0.52 | kept |
| `StageTransition` | S-C: six round cases run on `$rd` | 61, 62, 63, 65, 66, 67 | 6.69 | 2.22 | kept |
| `AgentWorktreeGuard` | G-A: seven decision loops run inside the probe memo | 20, 21, 23 to 27 | 4.02 | 1.62 | kept |

The W-B stopwatch read 24.29 s in the first before set, and 26.32 s after W-A. Its cases did not
change in between, so the difference is machine drift. Both numbers are more than 1 s above its
after median. The C-A stopwatch read 12.66 s in the first before set, and 11.19 s after C-B, for
the same reason. The S-B stopwatch read 2.40 s in the first before set and 2.86 s after S-A. The
S-C stopwatch read 7.25 s, then 6.93 s, then 6.69 s. Each is more than 1 s above its after
median either way.

The G-A row comes from the back-to-back pair at the end. Its first pair read 13.01 s before and
2.36 s after, but the machine sped up between the two sets, so that pair overstates the gain.
Even at the slow speed, the first after run read 3.39 s.

The review replaced the entry-point helpers with fresh runspaces. The original helper timings
above are historical. A new comparison ran the actual affected cases in focused Suite slices.
Only the invocation helper was timed. Fixtures and assertions were identical for both variants.
Each variant had one warm-up and three counted runs, back to back.

| Calls | Child-process samples (s) | Runspace samples (s) | Child median | Runspace median | Verdict |
|---|---|---|---|---|---|
| WatchTask entry points | 10.255, 9.904, 9.878 | 1.759, 1.790, 1.778 | 9.904 | 1.778 | kept; saving exceeds 1 s |
| Runner pre-suite refusals | 5.266, 5.300, 5.425 | 0.959, 0.933, 0.924 | 5.300 | 0.933 | kept; saving exceeds 1 s |

The runner comparison includes the retained bad-environment-value entry point and the C-B cases.
Its first child warm-up was discarded: the scratch wrapper returned zero for a binding error.
After fixing that wrapper, the complete runner comparison restarted before any samples counted.
The WatchTask child cases did not hit that wrapper defect.
No timing instrumentation is present in tracked code.

### Mutations

Each mutation changed one line of a script and was undone with `git checkout`.

- `WatchTask`: the no-files path in `scripts/watch-task.ps1` returns 0. Only "No files: exit code
  must be 1, got 0" failed. So a run in this process still passes its exit code to the case.
- `WatchTask`: the unfinished-tail branch of `Show-Tail` never runs. Both "No final newline"
  assertions failed.
- `WatchTask`: the UTF-8 switch before `git worktree list` is gone. Only "Accented worktree"
  failed, which now sits in the checkout-preference case.
- `WatchTask`: the follow loop asks for the task state only after a pass read new text. The
  reworked same-size case failed with "the watcher must still stop, but it was running after
  25s". The old version of the case passed under the same mutation.
- `WatchTask`: the state check that ends the follow loop never runs. The old and the new same-size
  case both failed. The whole Suite cannot run under this mutation, because the read-retry case
  starts a child with no timeout, and that child never ends. Both cases ran alone instead.
- `CiPowerShellSuiteRunner`: the runner uses 1 in place of the count from
  `Resolve-SuiteWorkerCount`. Eight cases failed, among them "An explicit -MaxParallel is named
  on the Workers line".
- `CiPowerShellSuiteRunner`: the runner passes `-MaxParallel ''` and no `-MaxParallelGiven`. Five
  cases failed, among them the Workers-line case and "A -MaxParallel that is not a whole number of
  at least one fails the run".
- `CiPowerShellSuiteRunner`: the runner passes `-EnvMaxParallel $null`. Two cases failed: "A bad
  AHKFLOW_SUITE_MAX_PARALLEL fails the run and names the variable" and "Only the adaptive default
  asks the machine about its hardware".
- `CiPowerShellSuiteRunner`: the runner leaves out `-InActions`. Two cases failed: "A run inside
  GitHub Actions uses every logical processor" and the hardware-probe case.
- `CiPowerShellSuiteRunner`: the runner's whole `Error` branch is gone, so a refused value carries
  on with a count of 0. Exactly two cases failed: the bad-variable case and the `-MaxParallel`
  value loop. Both runs still ended with exit code 1, from a later error. Only the missing message
  told them apart, so the cases must keep asserting the message.

Four small changes narrow a check, so each also ran on a scratch slice of the Suite that held only
the changed case:

- Row 36: when either Lane catch path returns no result, the merged case fails with "got 1". The
  runner still prints `FAILED:` for both Suites through its missing-result fallback, so the case
  counts the catch-path message once per Suite.
- Row 39: with de-duplication removed from `Select-SuiteEntry`, the in-process case fails with
  "Got: Alpha.Tests.ps1,Alpha.Tests.ps1".
- Row 40: with group markers printed outside GitHub Actions too, the Workers-line case fails.
- Row 41: with a timings save after each Suite, the watcher fails with "The timings file existed
  while a suite was still running", at the then-current 500 ms grace. Review restored 1500 ms for scheduling tolerance.

Two more mutations changed `Resolve-TransitionTarget` in `scripts/stage-transition.common.ps1`:

- `StageTransition`: four edges return `5-simplify`: 2-design success, 6-verify failure, 8-review
  success and 9-ship failure. The whole Suite cannot run under this mutation. The old Ship case
  reads a gh log that the mutated Ship never writes, and that `Get-Content` error stops the Suite
  before three of the four named cases run. So the four named cases ran alone, as a slice. Each
  one failed: "Design success must write 3-plan into the item", "Verify failure must target
  4-execute", "A Ship with no PLAN-PROGRESS.md must write 9-ship" and "A Ship failure must set
  6-verify".
- `StageTransition`: only 9-ship failure returns `5-simplify`. Under the first mutation, the
  9-ship failure case's own setup Ship is mutated too. Alone, exactly one assertion failed: "A
  Ship failure must set 6-verify".

After review, rows 62 and 67 also assert their exact refusal text. Two mutations of
`Invoke-RoundTransition` in `scripts/take-stage-transition.ps1` proved it, each on a slice. One
refused every round before the evidence check, and the other refused it after the pull request
check. Under each, only the new text assertion of its own case failed. The old exit-code and body
assertions passed under both.

The `AgentWorktreeGuard` mutations changed `scripts/agents/invoke-agent-worktree-guard.ps1` or
`.claude/hooks/pre-bash-guard.sh`. Each was undone by writing back the file's saved bytes.

- Row 22: the Claude run left "Allow paths emit no JSON on any adapter", and the Claude Bash
  Allow exit printed `{}` before `exit 0`, on the same line. Only "Unknown decision action fails
  closed, verified structurally on every adapter branch" failed. That case only looks for the
  text of the Allow line, and this mutation changed that text. A second mutation kept the line
  and printed `{}` on the line before it. The whole Suite passed, so row 22 was rejected.
- Row 28: the raw prefilter got the same leading boundary as `CANDIDATE_PATTERN`. With the old
  payload, which held a literal `&&`, the case passed. With `\u0026\u0026`, "Bash shim forwards a
  payload whose metacharacters are unicode-escaped" failed. Both ran on a slice of the Suite.
- Rows 102 to 104: one pattern at a time was set to `.`, which matches every input. With both
  candidate patterns changed, all three reworked cases failed. With `WORKTREE_SESSION_PATTERN`
  changed, only "Shim: a main-session redirect still exits in Bash" failed. With
  `WRITE_CANDIDATE_PATTERN` changed, only "Shim: a worktree-session read still exits in Bash"
  failed. These ran on a slice of the Suite.
- Rows 102 to 104, after review: two more mutations made the shim print at both of its early
  exits. With `{}` on stdout, the main-session redirect case and the worktree-session read case
  failed. With a line on stderr, the noncandidate case failed. Before the review fix, all three
  cases passed under both mutations.

### Earlier recovery evidence

The earlier Gate tables are superseded. Their complete results remain in commit a539e7db.
Those Gates passed, but shared the Lane pool with other worktrees.
They do not supply the current quiet-Gate baselines.

The first recovery controlled jq availability and restored the existing-progress Ship-failure case.
The latter starts without closure history and must preserve the existing progress prefix.
Focused mutations caught a wrong Copilot adapter, read forwarding, and removal of the existing-progress guard.
Production files were restored byte-for-byte after each probe.

### Final S-A verdict after recovery

At 4b9244eb, the current loop ran alone against the same loop with the skip disabled.
Both versions retained the new existing-progress assertions. Each had one warm-up and three counted runs.
A scratch Stopwatch covered the loop; no tracked source contained timing instrumentation.

| Variant | Warm-up | Counted runs (s) | Median (s) |
|---|---|---|---|
| All legal edges | 23.819 | 24.307, 23.813, 23.423 | 23.813 |
| Three skipped edges | 19.956 | 19.414, 22.814, 24.483 | 22.814 |

Saving: 0.999 s. D2 requires at least 1 s, so row 53 is rejected.
The after set drifted upward; it is not evidence for rounding the saving up or keeping the change.
The skip table and skip condition are removed. Every legal edge runs again.
Existing-progress success and preservation assertions remain.
Earlier S-A and isolated Suite timings are historical measurements of earlier revisions.

### Current review recovery

Final isolated medians are recorded above.

The full Gate ran at `2b527da5` with `AHKFLOW_GATE_REUSE=off`. All five steps passed: all 73
Suites, and 94.8% line and 83.2% branch coverage. Another worktree shared the Lane pool during
its PowerShell step, so its Suite durations are not used. The PowerShell step then ran again on
its own, at the same revision and with reuse off. The first retry also shared the pool and was
discarded. The second retry shared nothing, and all 73 Suites passed.

`baselineSeconds` in `tests/powershell-suites.json` now holds that quiet run's durations:

| Suite | Before 195 | After 195 |
|---|---|---|
| `AgentWorktreeGuard.Tests.ps1` | 86.7 | 89.7 |
| `CiPowerShellSuiteRunner.Tests.ps1` | 150.6 | 130.4 |
| `StageTransition.Tests.ps1` | 136.6 | 127.6 |
| `WatchTask.Tests.ps1` | 70.2 | 49.0 |

A Gate duration is one run among six parallel workers, so it is higher than a median taken alone.
The logs are saved locally in `.superpowers/review4-gate.log` and
`.superpowers/review4-quiet-powershell-2.log`.
The production worker-count contract is unchanged. Row 41 is now rejected: the 1500 ms watcher grace is restored.

Fresh recovery proofs:

- Output-discard and caller-variable-inheritance mutations fail the durable runspace regression case.
- Redirecting the fixture back to the real summary fails the environment-isolation case.
- Omitting the second exclusive or parallel entry produces only three acquisition errors; the case requires four.
- Saving immediately after the first completed Suite fails the watcher's runtime ordering assertion at 1500 ms.
- An injected NoFollow throw records failures in both cases; execution reaches the end of the slice.
- The validation error ID is stable under en-US, nl-NL, and de-DE.
- Bypassing either parsed shim condition fails the corrected cases.
- Making jq's empty extraction succeed fails the Auto-forwarding case.

The new common helper loads in Windows PowerShell 5.1. All four final Suites passed their timing runs.
The worker-count API and production scripts are unchanged by this recovery.

## Backlog 201

Backlog 201 applies or rejects the 22 deferred rows of the six git-fixture Suites. The plan is
`docs/superpowers/plans/2026-10-29-apply-the-deferred-git-fixture-test-speed-ups-plan-201.md`.
Each time below is a median of three counted runs after one warm-up run, with the Suite run
alone through `scripts/run-powershell-suites.ps1 -Suite <file>`. No timed run shared the Lane
pool. A D2 time comes from a temporary stopwatch that was never committed.

### Suite time, run alone

| Suite | Before (s) | After (s) |
|---|---|---|
| `WorktreeMergedCleanup.Tests.ps1` | 34.6 | |
| `WorktreeMergedCleanupSweep.Tests.ps1` | 31.1 | |
| `WorktreeMergedCleanupEligibility.Tests.ps1` | 34.4 | |

### Changes timed on their own

- **T-A**, rows 119 and 122: one seed repository per Suite run, copied for every
  `New-TempGitRepo` and `New-WorktreeToolingRepo` call. Commit `9fc18691`. The stopwatch spans
  both builders and the final seed check and removal.

  | Suite | T-A before (s) | T-A after (s) |
  |---|---|---|
  | `WorktreeMergedCleanup.Tests.ps1` | 6.49 | 1.29 |
  | `WorktreeMergedCleanupSweep.Tests.ps1` | 4.49 | 2.24 |
  | `WorktreeMergedCleanupEligibility.Tests.ps1` | 5.78 | 3.29 |
  | Sum | 16.76 | 6.82 |

  Kept: the sum fell by 9.94 s. The Suite medians in the same runs were 25.3 s, 31.9 s and
  37.4 s. Only `WorktreeMergedCleanup` fell as a whole Suite. The other two did not: their counted
  runs spread over 28.5 to 32.0 s and 34.3 to 38.6 s, wider than the 2 to 3 s that T-A saves there.

### Mutations

- T-A seed check: a stray file written into the plain seed just before the final
  `Remove-TempGitRepoSeeds` call. `WorktreeMergedCleanup` failed with "A case wrote into the
  shared seed repository '...\wtclean-seed-42c32906\repo'." No `wtclean-seed-*` folder was left.
- T-A trap: the Suite's first `Assert-Equal` made to fail. The run failed with "No config value
  must read as unset. (expected 'MUTATED', got 'unset')". The count of `wtclean-seed-*` folders
  in the temp folder was 0 before the run and 0 after it.

### Linux runs

- `WorktreeMergedCleanup.Tests.ps1` at `9fc1869108df0a6d79ea191fa24363ad0c0cb5b8`. Log
  `.superpowers/201-linux/linux-9fc18691-20261029-181729.log`. Image
  `mcr.microsoft.com/dotnet/sdk@sha256:2fa828c68761b1b8c23d7662dc134421b9d3b59fe1425fdbc80804e390cdb24d`,
  kernel `Linux 6.18.54.1-microsoft-standard-WSL2`, PowerShell 7.6.6, git 2.43.0. The runner
  printed "Platform: linux". The Suite passed, and `LINUX_EXIT=0`.
