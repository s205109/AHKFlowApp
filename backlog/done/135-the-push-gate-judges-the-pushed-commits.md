# 135 - The push gate judges the pushed commits

## Metadata

- **Epic**: Test reliability
- **Type**: Fix
- **Interfaces**: none (developer tooling)
- **Difficulty**: moderate
- **Stage**: 9-ship

## Summary

The shipped-plan gate reads the backlog from the working tree, so an uncommitted edit decides
whether a committed record is judged. Read every backlog file from the commits git is about to
send instead, so the push is judged on what actually leaves the machine.

## User story

As a developer pushing a branch, I want the push gate to judge the commits that go to the remote,
so that a clean working tree cannot hide a bad record that is already committed.

## Acceptance criteria

- [x] `.githooks/pre-push.ps1` reads the ref lines git writes on its stdin and collects the local
      commit of each pushed ref. A ref being deleted carries an all-zero commit and contributes
      nothing.
- [x] The hook reads stdin only when `[Console]::IsInputRedirected` is true, so running the hook
      by hand does not block on a terminal that will never close.
- [x] `scripts/pre-push-quick-checks.ps1` takes a `-PushedCommit` parameter, resolves a merge base
      for each pushed commit on its own, and runs the shipped-plan check once per commit. With no
      commits passed, it judges `HEAD`.
- [x] `scripts/check-shipped-plan-ticked.ps1` takes a `-TargetCommit` parameter and reads the
      backlog diff, the item's path, and the item's Stage line from that commit.
- [x] `scripts/check-shipped-plan-ticked.ps1` no longer dot-sources `scripts/backlog.common.ps1`.
      Its `Get-BacklogItem` reads the working tree, which is what this check must not read.
- [x] The plan file the item names is still read from disk. `docs/superpowers` is a second
      repository that this one ignores, so no commit here ever carries a plan.
- [x] Pushing a branch that is not checked out judges that branch's commits, and not the commits
      of whatever `HEAD` happens to be.
- [x] A committed item at `Stage: 9-ship` whose plan has no ticked step is refused, even when the
      working tree copy of that item was edited to another stage and left uncommitted.
- [x] `tests/ShippedPlanTicked.Tests.ps1` covers the commit-based reads against fixtures, and
      `tests/PrePushHook.Tests.ps1` covers the stdin parsing that supplies the commits.
- [x] `tests/powershell-suites.json` records the measured baseline for
      `ShippedPlanTicked.Tests.ps1` after the suite grew.

## Out of scope

- The build step and the test slice in `scripts/pre-push-quick-checks.ps1`. They keep judging the
  working tree on purpose: that is the code the developer is about to be judged on by CI.
- Changing what the worktree cleanup sweep does with its verdict. This item changes where the
  push-time check reads its facts, not the rule it applies.
- The citation freshness check, which reads the working tree in the same way. It is a separate
  rule with its own trade-offs.

## Notes / dependencies

- Follows `backlog/done/130-fail-the-push-when-a-shipped-it-0c4f5d37.md`. That item's plan chose
  the working tree on purpose. This item reverses that choice for the backlog reads only, because
  the working tree and the pushed commits can disagree.
- Spec: none — one design decision, recorded in the plan.
- Plan: `docs/superpowers/plans/2026-09-05-the-push-gate-judges-the-pushed-commits-135.md`

## Gate evidence

`pwsh ./scripts/pre-push-quick-checks.ps1` on this branch: build succeeded with 0 warnings, the
fast test slice passed (44 + 8 + 956 + 1749 + 182 tests), citations passed, shipped plans frozen,
and the shipped-plan check passed.

The defect was proven against this item itself. Repository state for all three runs: item 135
committed at `Stage: 9-ship` in `backlog/done/`, its plan holding 7 unticked steps and 0 ticked,
and an uncommitted edit on disk moving the same item's Stage line to `6-verify`.

1. This branch's check, run in that state:

   ```
   Backlog item 135 reads 'Stage: 9-ship', and no step in its plan is ticked.
     Steps: 7 unticked, 0 ticked
   RESULT: 1 shipped item carries a plan with no ticked step.
   EXITCODE=1
   ```

2. The version on `main` (`cf0b2c67`), run in the same state, with nothing else changed:

   ```
   RESULT: every shipped plan carries a ticked step. Looked at 1 backlog item(s) this branch
   touches, of which it ships 0, judged against cf0b2c67f05780de93fc28944e682570fd108d2e.
   EXITCODE=0
   ```

   It read the uncommitted `6-verify` line, decided the branch ships nothing, and passed. That is
   the hole this item closes.

3. This branch's check, after the seven plan steps were ticked and committed:

   ```
   RESULT: every shipped plan carries a ticked step. Looked at 1 backlog item(s) this branch
   touches, of which it ships 1, judged against cf0b2c67f05780de93fc28944e682570fd108d2e.
   EXITCODE=0
   ```
