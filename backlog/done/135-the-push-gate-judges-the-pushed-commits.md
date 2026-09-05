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
