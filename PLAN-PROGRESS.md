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
