# 130 - Fail the push when a shipped item's plan has no ticked steps

## Metadata

- **Epic**: Test reliability
- **Type**: Feature
- **Interfaces**: none (developer tooling)
- **Difficulty**: moderate
- **Stage**: 9-ship

## Summary

Worktree cleanup refuses to remove a worktree whose plan holds unticked steps and none ticked. An
agent that carries out every step but never ticks the boxes leaves that worktree stuck. Run the
same check at the push, where it is cheap to fix, instead of leaving it to a sweep weeks later.

## User story

As a developer running the worktree sweep, I want a stuck worktree to be impossible by the time
the work merges, so that cleanup never keeps a worktree whose plan was in fact carried out.

## Acceptance criteria

- [x] `scripts/pre-push-quick-checks.ps1` refuses a push when a backlog item this branch owns is
      at `Stage: 9-ship`, names a plan under `docs/superpowers/plans/`, and that plan holds one or
      more `- [ ]` steps with zero `- [x]` steps.
- [x] The refusal names the plan file and says the steps that were carried out must be ticked.
- [x] A plan with at least one ticked step passes, whatever its unticked count. Work can be
      descoped, so a partly ticked plan is not an error.
- [x] An item that names no plan, or names `none`, passes.
- [x] The check takes its verdict from `Test-WorktreePlanWasImplemented`
      (`scripts/worktree-git.common.ps1:1314`, "function Test-WorktreePlanWasImplemented"), so the
      push and the cleanup sweep can never disagree about what counts as implemented.
- [x] A test suite covers the refusal and each pass case against fixtures, in the style of
      (`tests/PrePushHook.Tests.ps1:1`, "#Requires -Version 5.1").
- [x] The check judges only the items this branch ships, and not every item it touches. An item
      already shipped in the merge base, at `Stage: 9-ship` and already under `backlog/done/`, is
      skipped whatever this branch does to it.
- [x] Items 107, 110, 111, 112, 119 and 121 no longer hold a plan with zero ticked steps. Each tick
      is backed by the merged diff, and any step that was never carried out stays unticked with the
      reason written into the plan.
- [x] The gate was driven once for real: `pwsh ./scripts/pre-push-quick-checks.ps1` refused with
      this plan's steps unticked, and passed with them ticked. Both outputs are in this item.

## Out of scope

- Changing what the cleanup sweep does with its verdict. This item moves the same check earlier;
  it does not alter the sweep.
- Ticking plan steps automatically. A tick claims that a step was carried out, and only the agent
  doing the work can make that claim.
- The `PLAN-PROGRESS.md` per-task record. It stays as it is.

## Notes / dependencies

- **Where this came from.** `backlog/done/126-run-the-powershell-suites-in-parallel.md` and
  `backlog/done/129-watch-task-drops-output-under-load.md` both shipped with every plan step
  unticked. The sweep kept their worktrees, saying "the plan for item N was never implemented",
  for 68 and 21 steps. Both plans had in fact been carried out in full. The ticks were added by
  hand afterwards, in the plans repository at `1ce9238` and `2c9c4bc`.
- **Why the push is the right place.** The pre-push gate already reads this branch's backlog items
  and the plans it owns, for the citation check and the plan-source parity check. Nothing there
  looks at tick state, so the gap survives the push and the merge, and only shows up when somebody
  runs the sweep.
- **Reuse the rule, do not copy it.** `Test-WorktreePlanWasImplemented` already resolves the
  `- Plan:` bullet, handles the "names no plan" and "names none" cases, and counts the boxes. A
  second copy of that rule would drift from the sweep's copy.
- **The debt is eight items, not two.** Measured on 2026-09-03 by running
  `Test-WorktreePlanWasImplemented` over every item in `backlog/done/`: 107, 110, 111, 112, 119 and
  121 also carry a plan with zero ticked steps, at 27, 50, 18, 31, 32 and 26 steps. The sweep still
  refuses to remove a worktree for any of them. This item clears all six.
- **Only the shipping branch is judged.** A branch that merely edits an already-shipped item is not
  judged for it. Without that rule the six items above would refuse a push from any branch that
  touched them, and the gate would be switched off within a week.
- Spec: none — the rule already exists and the sweep proves it. This item changes where it runs.
- Plan: `docs/superpowers/plans/2026-09-03-fail-the-push-on-an-unticked-plan-130.md`

## Evidence that the gate fires

A fixture suite proves the rule, and a source assertion proves the pre-push step is written down.
Neither proves pre-push runs it. So the real hook was driven twice on 2026-09-03, with this item at
`Stage: 9-ship` and already moved into `backlog/done/`.

**First run, with every step in the plan unticked.** The run got past the frozen-plan step, which
is the step before it, and then failed:

```
==> Checking that shipped plans are frozen
RESULT: every shipped plan and spec is frozen.
  + Shipped plans are frozen.

==> Checking that a shipped item's plan has a ticked step

Backlog item 130 reads 'Stage: 9-ship', and no step in its plan is ticked.

  Item:  backlog/done/130-fail-the-push-when-a-shipped-it-0c4f5d37.md
  Plan:  docs/superpowers/plans/2026-09-03-fail-the-push-on-an-unticked-plan-130.md
  Steps: 39 unticked, 0 ticked

Tick every step you carried out, then push again. A tick claims the step was done, so tick
only those. A plan with some steps ticked and some not passes: work can be descoped.

The plan belongs to the private plans repository, so it takes its own commit:
  git -C docs/superpowers add <the plan file>
  git -C docs/superpowers commit -m "tick the plan steps"

Skip this check with: SKIP_PUSH_HOOK=1 git push

RESULT: 1 shipped item carries a plan with no ticked step.
```

The hook threw `A backlog item this branch ships carries a plan with no ticked step.`

**Second run, with the carried-out steps ticked again.** Same hook, same commit, nothing else
changed:

```
==> Checking that shipped plans are frozen
  + Shipped plans are frozen.

==> Checking that a shipped item's plan has a ticked step
RESULT: every shipped plan carries a ticked step. Looked at 2 backlog item(s) this branch touches, of which it ships 1, judged against 54d4f7e863a9cbc417830335399461d715006f0a.
  + Every shipped plan carries a ticked step.
  + Pre-push quick checks passed.
```

## Evidence that the six older plans are clear

Re-run of the measurement that found them, from the worktree root on 2026-09-03: dot-source
`scripts/worktree-git.common.ps1` and call `Test-WorktreePlanWasImplemented` for every item in
`backlog/done/`. Every item answered `Allow = True`, including 107, 110, 111, 112, 119 and 121.
Before the audit those six answered `Allow = False` with 27, 50, 18, 31, 32 and 26 unticked steps.

The audit ticked only what the merged tree, the commit log, or a re-run of the step's own command
proves. Fifteen steps across the six plans stay unticked, and each plan's header says which ones and
why. Most are "run the suite and watch it fail" red steps, which leave no trace anywhere.
