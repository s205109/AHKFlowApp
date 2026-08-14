# Plan progress — backlog 087

Plan: `docs/superpowers/plans/2026-08-13-backlog-template-stage-field-plan.md`

| Task | Deliverable commit | Tests | Deferrals |
|---|---|---|---|
| 1 — template carries the Stage field | `63c56695` | `pwsh ./tests/BacklogNumbering.Tests.ps1` green, 94 items checked | none |
| 2 — backfill the existing items | `a51829f8` | `test-fast.ps1 -Mode PowerShell` green, all 22 suites. 72 files changed, 72 insertions, 1 deletion | none |
| 3 — Get-BacklogProblem checks the Stage field | `936810f0` | `test-fast.ps1 -Mode PowerShell` green, all 22 suites. Cases 16-19 added; 16, 17, 18 red before the check, green after | none |
| 4 — reconcile workflow.md, backlog 072, backlog 087 | `b2e30e5e` | `test-fast.ps1 -Mode PowerShell` green, all 22 suites | none |
| Simplify — one read per file in `Get-BacklogItem` | `d06cc784` | `test-fast.ps1 -Mode PowerShell` green, all 22 suites | none |
| Review round 1 — 7 stale `workflow.md` citations | see below | `test-fast.ps1 -Mode PowerShell` green, all 22 suites | none |

## Review round 1

Task 4 added one line to `docs/development/workflow.md`, and the same commit wrote citations
against the pre-edit file. Six citations drifted by one, and a seventh was already stale on `main`.
All seven point at the right text again, checked by re-reading each target line. No behaviour
changed: every edit is a comment or a document.
