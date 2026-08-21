# PLAN-PROGRESS — backlog 112

Plan: `docs/superpowers/plans/2026-08-21-stale-plans-citations-plan-112.md`

This file replaces backlog 093's copy, which shipped without being deleted at Stage 9.

| Task | Deliverable commit | Tests | Notes |
|---|---|---|---|
| 1 — Freeze the shipped plans and specs | `8a1840a` (plans repo) | citation check 82 → 32 | Done. All 18 frozen. The commit also swept two other sessions' uncommitted edits, because `git add plans specs` stages the shared working tree. Nothing was lost, the history was already pushed, so it was left alone. The plan's Step 4 now stages by name |
| 2 — Scope the pre-push scan to this branch's plans | `5ac75473` | `CitationFreshness.Tests.ps1` green, 6 new cases | Done. `-OnlyPath` added to `Get-CitationProblem` and the entry script; the hook computes the owned set from the backlog diff against `origin/main` |
| 3 — Write the rules into the process | `9ddd32f1` | 4 parity checks green | Done. Ship action, both "records closed" statements, three `AGENTS.md` bullets. No exit string changed, so no PDF regeneration |
| 4 — Enforce the freeze at pre-push | `964a1857` | `ArchivedPlanFrozen.Tests.ps1` green, 9 cases | Done. The suite caught two real PowerShell unrolling bugs before the check shipped |
| 5 — Verify against the acceptance boxes | in progress | see below | Boxes 1, 3, 4 green. Box 2 outstanding |

## Task 5 evidence so far

- **Box 1, revised: green.** The full-corpus scan reports 42 problems, every one in a file owned
  by open item 073, 102, or 110. Zero in any shipped file. Zero in any file this branch owns. The
  branch-scoped scan the hook actually runs reports `every citation checks out`.
- **Box 3: green.** Every per-line suppression carries a reason after the token.
- **Box 4: green.** The Ship rule, the three `AGENTS.md` bullets, `check-archived-plan-frozen.ps1`
  wired into pre-push, and the branch scoping in the citation step.
- **Box 2: not yet proven.** See the blocker below.

## Open blocker for box 2

The first full `scripts/pre-push-quick-checks.ps1` run failed at line 38, on the fast test slice,
before reaching any citation step. Two Blazor tests failed under full-suite load:

```
AHKFlowApp.UI.Blazor.Tests.Startup.DevConfigTests.AddCacheBustedDevConfigAsync_WhenFetchNeverCompletes_GivesUpAndReturns
AHKFlowApp.UI.Blazor.Tests.Pages.HotstringsPageTests.Page_WhileReloadIsInFlight_RendersLoadingIndicator
Failed! - Failed: 2, Passed: 952, Skipped: 0, Total: 954
```

Both pass when run in isolation. This branch changes no C# file — only markdown, PowerShell, and
the plans repository — so these failures are not its work. They are a load-sensitive flake, and
they are **not** backlog 068, which covers PowerShell suites.

They block box 2 intermittently, because the push hook runs the fast slice before it reaches the
citation check. Needs its own backlog item; an agent cannot file one from inside this worktree,
because `new-worktree.ps1` refuses to nest.

## Decisions carried from plan review

- Acceptance box 1 is revised in the item. Do not tick the original wording.
- `-OnlyPath` is in scope. The warning-only fallback is rejected.
- Freeze at Ship, not Document. The freeze check throws, it does not warn.
- A reopened item gets a workflow line, not a check. Landed in Task 3.
