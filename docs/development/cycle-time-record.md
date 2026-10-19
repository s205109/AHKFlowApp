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

## After

Empty until Task 14.
