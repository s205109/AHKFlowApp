# Progress: backlog 210

Plan: `docs/superpowers/plans/2026-11-13-profile-delete-says-what-it-costs-plan-210.md`.
Execution: subagent-driven, one implementer and one task review per task, then a final
whole-branch review. Every task review and the final review were clean.

- Task 1: done at 2eb3a9a3. Tests: pass, handler 2/2 and endpoint 1/1. Deferrals: none.
- Task 2: done at 2acd58bc. Tests: pass, wording 8/8. Deferrals: none.
- Task 3: done at 3ca60249. Tests: pass, Profiles page 32/32. Deferrals: none.
- Task 4: done at 25d10278. Tests: pass, UI.Blazor suite 1145/1145. Deferrals: none.
- Task 5: done at 2b6449d9, moved to E2E group B at ddb470b3. Tests: pass, E2E lane 96/96; the mutation `MarkNoProfile="false"` turned the chip assertion red. Deferrals: none.
- Ruling: the E2E class sits in group B, not the plan's group A. `docs/development/testing-workflow.md` says to use the smallest group, and B is the smallest.
- Final review fix: the `ProfileUsageDto` comment says an apply-to-all item never counts, at e6770257.
- Simplify: done at fbaa219a. One shared hotstring and hotkey subject in `CountWording`, a `Total` on the UI `ProfileUsageDto`, the cancel test uses `StubDialog`, and the E2E seed drops unused bodies. Skipped: a `ProfileChips` wrapper (the plan's grilling settled Q2 on a parameter), the CLI "no profile" text (spec section 6, backlog 211), and a shared link filter (it would change the delete handler).
- Verify: the artifacts AGENTS.md names, all green. API and use case: the Task 1 handler and endpoint integration tests. UI flow: `ProfileDeleteFlowTests` in the E2E lane, with its mutation check. UI wiring and text: the bUnit tests from Tasks 2 to 4.
- Document: both acceptance boxes ticked at 092ae990. `CONTEXT.md` already holds "No profile". Spec sections 5 and 6 ship in backlog 211. Nothing else to document.
- Deferral: `tests/WorkflowPdfGenerator.Tests.ps1:174-183` lets the missing-browser case fall back to a real local browser, then expects "Chromium" in any failure. It failed in one Gate run here and passed in a later one. It is not part of this branch and needs its own backlog item.
- Gate green at fbaa219a.
