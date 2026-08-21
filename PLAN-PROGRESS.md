# PLAN-PROGRESS — backlog 112

Plan: `docs/superpowers/plans/2026-08-21-stale-plans-citations-plan-112.md`

This file replaces backlog 093's copy, which shipped without being deleted at Stage 9.

| Task | Deliverable commit | Tests | Notes |
|---|---|---|---|
| 1 — Freeze the shipped plans and specs | `8a1840a` in the plans repo | citation check 82 → 32 | Done. All 18 files frozen. Every remaining problem is in a live 102 or 110 file, as planned. The commit also swept two other sessions' uncommitted edits, because `git add plans specs` stages the shared working tree; nothing was lost, the history was already pushed, and the plan's Step 4 now stages by name |
| 2 — Scope the pre-push scan to this branch's plans | - | - | Not started |
| 3 — Write the rules into the process | - | - | Not started |
| 4 — Enforce the freeze at pre-push | - | - | Not started |
| 5 — Verify against the acceptance boxes | - | - | Not started |

## Decisions carried from plan review

- Acceptance box 1 is revised in the item. Do not tick the original wording.
- `-OnlyPath` is in scope. The warning-only fallback is rejected.
- Freeze at Ship, not Document. The freeze check throws, it does not warn.
- A reopened item gets a workflow line, not a check. It goes in Task 3 Step 1.
