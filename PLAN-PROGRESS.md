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
- [x] Task 4 — a skip link moves focus into the page content. `54d85c3b`.
      `KeyboardAccessFlowTests` 4/4 pass; the skip link test failed first because no element
      matched `button.skip-link`. Layout before and after is identical: the same four
      rectangles, light theme. Deviation: a temporary E2E test took both measurements inside
      the E2E stack, because the worktree's own API had no database. The test was deleted
      before the commit.
      The first whole E2E run failed 96/97: `HotstringsCrudFlowTests` looked up the dialog's
      `Delete` button by role without a scope, and the row's new `Delete btw` name matched
      first. Fixed in `566f084a` by scoping the lookup to the dialog, as the other delete tests
      already do. The second whole run passed 97/97. Both runs used `dotnet test` with a TRX
      logger, because the harness refuses `pwsh` inside the entered worktree.
      E2E group totals from the passing run, summed from the TRX file: A 101.22 s, B 102.64 s,
      C 96.16 s, D 75.46 s, plus 41.34 s of fixture tests outside any group. Group B is no
      longer the smallest; group D is. Rebalancing belongs to backlog 155. Deferrals: none.
