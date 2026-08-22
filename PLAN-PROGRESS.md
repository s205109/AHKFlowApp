# PLAN-PROGRESS — backlog 112

Plan: `docs/superpowers/plans/2026-08-21-stale-plans-citations-plan-112.md`

This file replaces backlog 093's copy, which shipped without being deleted at Stage 9.

| Task | Deliverable commit | Tests | Notes |
|---|---|---|---|
| 1 — Freeze the shipped plans and specs | `8a1840a` (plans repo) | citation check 82 → 32 | Done. All 18 frozen |
| 2 — Scope the pre-push scan to this branch's plans | `5ac75473` | `CitationFreshness.Tests.ps1`, 6 new cases | Done. `-OnlyPath` on `Get-CitationProblem` and the entry script; the hook computes the owned set from the backlog diff against `origin/main` |
| 3 — Write the rules into the process | `9ddd32f1` | 4 parity checks green | Done. No exit string changed, so no PDF regeneration |
| 4 — Enforce the freeze at pre-push | `964a1857` | `ArchivedPlanFrozen.Tests.ps1`, 9 cases | Done. The suite caught two real PowerShell unrolling bugs before the check shipped |
| 5 — Verify against the acceptance boxes | `ad6d8749` | full gate green | Done. All four boxes ticked with evidence |

## Recovery tasks from review round 1, 2026-08-22

Review found five defects. All five reproduced against this worktree. Stage went back to
`4-execute`. Boxes 2 and 4 are unticked until these are green.

- **R1 (high) — ownership is measured against a moving tip.** `scripts/pre-push-quick-checks.ps1`
  runs `git diff --name-only origin/main -- backlog`. After today's merges that yields 13 paths and
  10 backlog numbers, instead of the 2 this branch actually touches. Fix: diff against
  `git merge-base HEAD origin/main`. Measured: tip gives 073, 094, 098, 099, 102, 107, 110, 111,
  112, 113; merge-base gives 107 and 112.
- **R2 (high) — an array does not survive `pwsh -File`.** With three owned plans the child process
  fails with `A positional parameter cannot be found that accepts argument '...plan-102.md'`. With
  two, the second path binds to the wrong parameter and is silently dropped. It works today only
  because this branch owns exactly one plan. Fix: pass the list through a temp manifest file, which
  has no quoting or arity failure mode. The suite must exercise the real child-process boundary,
  not just `Get-CitationProblem` in process.
- **R3 (high) — the freeze check blocks a worktree for another worktree's live plan.**
  `scripts/check-archived-plan-frozen.ps1` judges the shared plans repository against only this
  worktree's `backlog/`. A plan whose item is open on another branch has no item here, so it is
  classified as shipped and demanded frozen. Proven: running it with a backlog that lacks those
  items reports all five live 073/102/110 files as shipped. Item 113 is already open on `main` and
  absent here, so this fires as soon as `plan-113.md` is written. This recreates the exact
  cross-worktree blocking this item exists to remove. Fix: classify a file as archived only when
  its item is demonstrably in this worktree's `backlog/done/`. Unknown means skip, never archived.
- **R4 (medium) — ownership ignores the authoritative `- Plan:` pointer.** The script decides by
  filename suffix while its own docstring admits `plan-105.md` belongs to item 107. Reopening 107
  and unfreezing that plan, which `docs/development/workflow.md` now requires, would leave the check
  calling a live plan archived. Fix: resolve plans through the `- Plan:` bullet in `backlog/done/`
  items, and fall back to the trailing number.
- **R5 (medium) — a failed `origin/main` lookup silently disables the check.** If the git command
  fails, `$ownedPlan` stays empty, the hook prints `No plan on this branch: nothing to check.` and
  passes. Fix: fail closed. A missing or unreadable base ref must throw.

Also newly eligible for freezing once this branch integrates today's `main`, because their items
merged into `backlog/done/`: `plans/2026-08-21-cleanup-ux-plan-073.md`,
`specs/2026-08-21-cleanup-ux-design-073.md`, `plans/2026-08-21-friction-recall-interval-plan-102.md`,
`plans/2026-08-21-guard-ambiguous-parse-plan-110.md`,
`specs/2026-08-21-guard-ambiguous-parse-design-110.md`. Merged today: #334, #335, #336, #338. The
`PLAN-PROGRESS.md` conflict is mechanical — keep this branch's backlog-112 version through Review,
delete it at Ship.

## Stage verdicts

- **5 Simplify — nothing to simplify.** The change is two new files, one filter parameter, one hook
  step, and documentation. There is no duplication to fold and no dead code to delete.
- **6 Verify — green.** Verification artifacts: `tests/ArchivedPlanFrozen.Tests.ps1` (9 cases, new)
  and 6 new cases in `tests/CitationFreshness.Tests.ps1`. No AGENTS.md exemption claimed: this
  branch produced durable tests rather than relying on one.
- **7 Document — done.** All four acceptance boxes ticked against what the branch does, each with
  its evidence written into the item.

## The five-step gate, run on 2026-08-21

| Step | Result |
|---|---|
| `dotnet build AHKFlowApp.slnx --configuration Release` | succeeded, via the push hook |
| `dotnet format AHKFlowApp.slnx --verify-no-changes` | exit 0 |
| `pwsh ./scripts/test-fast.ps1 -Mode PowerShell` | All 38 suite(s) passed |
| `pwsh ./scripts/test-fast.ps1 -Mode Coverage` | All per-assembly thresholds met. Line 94.6%, branch 82.6% |
| `git diff --check main...HEAD` | exit 0 |

## Box 2 evidence

A real `git push`, no `SKIP_PUSH_HOOK`, no `--no-verify`:

```
+ Build succeeded.
+ Fast test slice passed.
==> Checking citations in the private plans repository
Checking 1: plans/2026-08-21-stale-plans-citations-plan-112.md
+ This branch's plan citations passed.
+ Plans agree with the source.
==> Checking that shipped plans are frozen
+ Shipped plans are frozen.
+ Pre-push quick checks passed.
   2df740fe..ad6d8749  fix/wt-stale-citations-in-the-plans-re-75722759
```

## Two findings for the reviewer, neither fixed here

**A load-sensitive Blazor flake.** The first full hook run failed the fast slice on
`DevConfigTests.AddCacheBustedDevConfigAsync_WhenFetchNeverCompletes_GivesUpAndReturns` and
`HotstringsPageTests.Page_WhileReloadIsInFlight_RendersLoadingIndicator`. Both pass in isolation,
and both passed on the successful push. This branch changes no C# file, so they are not its work,
and they are not backlog 068, which covers PowerShell suites. They can fail a push for reasons
unrelated to the branch. Needs its own item; an agent cannot file one from inside this worktree,
because `new-worktree.ps1` refuses to nest.

**Task 1's first commit swept two other sessions' work.** `git -C docs/superpowers add plans specs`
staged 65 changed lines in the backlog-102 plan and 6 in the backlog-110 plan, both uncommitted
work belonging to live sessions, and committed them under this item's message. Nothing was lost.
The history was already pushed and two sessions were live, so it was left rather than rewritten.
The plan's Step 4, the `AGENTS.md` rule, and the check's own output now all say to stage
plans-repository files by name.
