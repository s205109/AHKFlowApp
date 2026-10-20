# 196 - Measure the three slow cycle measures

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (measurement record)
- **Difficulty**: moderate
- **Stage**: 0-intake

## Summary

Backlog 188 set five targets for the development cycle. It judged two of them at its own closure.
The other three need weeks of new data, so this item measures them again once enough has
gathered, and judges each against its target.

## User story

As a developer, I want the CI critical path, the stage exits per item and the flaky failures
measured after backlog 188, so that I know whether its changes made the cycle faster and steadier.

## Acceptance criteria

- [ ] `docs/development/cycle-time-record.md` holds an after value for each of the three measures,
      taken with the commands below, in a window that is ready.
- [ ] Each measure carries a verdict, met or missed, against its target below.
- [ ] A missed target is reported as missed.

## The three measures

The before numbers and the methods come from backlog 188's record,
`docs/development/cycle-time-record.md`, under `## Before`. Repeat each method exactly.

| # | Measure | Before | Target |
|---|---|---|---|
| 3 | CI critical path | 771 s | 450 s or less |
| 4 | Gate-required stage exits per item | 2 | 2 or less |
| 5 | Flaky failures per 30 days | 4 | 1 or less |

### 3. CI critical path

The last 10 runs of `ci.yml` with event `pull_request`, conclusion `success` and attempt 1. A
run's critical path is the latest `completedAt` among its required CI jobs, minus the run's
`startedAt`. Read the required jobs from branch protection again; on 2026-10-18 they were
`build-test`, `powershell-suites`, `bicep-lint`, `codex-skills-hash-parity` and
`repo-invariants`. Report each run id, its value, and the median.

```powershell
gh api repos/s205109/AHKFlowApp/branches/main/protection/required_status_checks --jq .contexts
gh run list --repo s205109/AHKFlowApp --workflow ci.yml --event pull_request --status success --limit 40 --json databaseId,attempt,startedAt
gh run view <id> --repo s205109/AHKFlowApp --json jobs --jq '.jobs[] | {name, completedAt}'
```

### 4. Gate-required stage exits per item

The last 10 items moved into `backlog/done/` on `origin/main`, inside the window. In each item's
history, read the pairs of removed and added `- **Stage**:` lines. Count a change from
`4-execute` to any higher stage, and a change from `8-review` to any higher stage. Backlog 188
counted `6-verify` in place of `4-execute`; backlog 191 changes which stage the Gate guards. A
move back to `4-execute` is a failure edge and does not count. Report each item, its two counts,
and the median total.

```powershell
git log origin/main --no-renames --diff-filter=A --name-only --format= -- backlog/done/
git log origin/main --follow -p --format=%H -- backlog/done/<file>
```

This is a proxy. It does not see failed Gate attempts or repeated Gates inside one stage.

### 5. Flaky failures

Every run of `ci.yml` and `shipping-pr-closes-item.yml` created in the window. A failure is any
failed attempt; read earlier attempts of a rerun with
`gh api repos/s205109/AHKFlowApp/actions/runs/<id>/attempts/<n>`. A failure is flaky when a later
attempt of the same run, or a later run of the same workflow on the same `headSha`, succeeded.
Report the count per 30 days, and each flaky failure's run, date, Suite and case.

```powershell
gh run list --repo s205109/AHKFlowApp --workflow ci.yml --created ">=<window start>" --limit 500 --json databaseId,attempt,conclusion,headSha,createdAt
gh run list --repo s205109/AHKFlowApp --workflow shipping-pr-closes-item.yml --created ">=<window start>" --limit 500 --json databaseId,attempt,conclusion,headSha,createdAt
```

## The windows

- CI critical path and flaky failures: the window starts at backlog 188's last merge into `main`.
- Stage exits: the window starts at backlog 191's merge into `main`.
- A window is ready when all three of these have passed since its start, whichever comes last:
  30 days, 10 pull-request runs of `ci.yml`, and 10 tracked items shipped into `backlog/done/`.

Do not measure a window before it is ready. Until then, this item waits at `0-intake`.

## Out of scope

- Measures 1 and 2, Gate time and affected-test time. Backlog 188 judged them at its closure.
- Changing the CI jobs or the Suites to meet a target. File a new item for that.

## Notes / dependencies

- Depends on backlog 188 (the record and the before numbers) and backlog 191 (the stage-exits
  window).
- Backlog 188's own after record noted one flaky failure under load in
  `WorktreeMergedCleanupSweep.Tests.ps1`, on 2026-10-19, outside CI. It does not count here, which
  covers CI runs only.
- Spec: none — the methods are in backlog 188's record and spec.
- Plan: none yet — written at Stage 3.
