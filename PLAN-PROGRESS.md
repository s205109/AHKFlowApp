# Progress — backlog 168, focus ring and icon button names

Plan: `docs/superpowers/plans/2026-10-16-focus-ring-and-icon-button-names-plan-168.md`

One line per finished task, written after its deliverable commit: the task, the deliverable
commit, the tests state, and deferrals.

Execution: inline (`superpowers:executing-plans`), one session, progress update after each task.

- [x] Task 1 — one focus ring policy for nav links, buttons and checkboxes. `983bd4d1`.
      `KeyboardAccessFlowTests` 1/1 pass; it failed first on the nav link, `outline-style` was
      `none`, as planned. Deferrals: none.
- [x] Task 2 — the app-bar buttons name what pressing them does. `ac7f95bc`.
      `KeyboardAccessFlowTests` 2/2 pass; the new test failed first with an empty name, as
      planned. Deferrals: none.
- [x] Task 3 — the eighteen page and dialog buttons name their target. `9624551e`.
      `AHKFlowApp.UI.Blazor.Tests` 1049/1049 pass in Release; the nine new tests failed first
      with a null `aria-label`. `KeyboardAccessFlowTests` 3/3 pass; the row test failed first
      with an empty name. Deviation: the bUnit project ran directly in Release instead of
      `test-fast.ps1 -Mode Fast`, because the harness refuses `pwsh` inside the entered
      worktree. Deferrals: the full Fast slice runs at the Gate.
