# 130 - Fail the push when a shipped item's plan has no ticked steps

## Metadata

- **Epic**: Test reliability
- **Type**: Feature
- **Interfaces**: none (developer tooling)
- **Difficulty**: moderate
- **Stage**: 0-intake

## Summary

Worktree cleanup refuses to remove a worktree whose plan holds unticked steps and none ticked. An
agent that carries out every step but never ticks the boxes leaves that worktree stuck. Run the
same check at the push, where it is cheap to fix, instead of leaving it to a sweep weeks later.

## User story

As a developer running the worktree sweep, I want a stuck worktree to be impossible by the time
the work merges, so that cleanup never keeps a worktree whose plan was in fact carried out.

## Acceptance criteria

- [ ] `scripts/pre-push-quick-checks.ps1` refuses a push when a backlog item this branch owns is
      at `Stage: 9-ship`, names a plan under `docs/superpowers/plans/`, and that plan holds one or
      more `- [ ]` steps with zero `- [x]` steps.
- [ ] The refusal names the plan file and says the steps that were carried out must be ticked.
- [ ] A plan with at least one ticked step passes, whatever its unticked count. Work can be
      descoped, so a partly ticked plan is not an error.
- [ ] An item that names no plan, or names `none`, passes.
- [ ] The check takes its verdict from `Test-WorktreePlanWasImplemented`
      (`scripts/worktree-git.common.ps1:1293`, "function Test-WorktreePlanWasImplemented"), so the
      push and the cleanup sweep can never disagree about what counts as implemented.
- [ ] A test suite covers the refusal and each pass case against fixtures, in the style of
      (`tests/PrePushHook.Tests.ps1:1`, "#Requires -Version 7.0").

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
- Spec: none — the rule already exists and the sweep proves it. This item changes where it runs.
- Plan: none — moderate difficulty, so it goes to Plan when somebody picks it up.
