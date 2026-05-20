# Test & Dev Tooling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Track where each item from `2026-05-19-test-dev-tooling-design.md` actually lands. No new tasks — every concrete item is absorbed into another plan in this batch.

**Architecture:** Pointer plan. The Test/Dev Tooling spec was a small set of test-builder extensions; once Categories and Schema Polish were planned, those extensions naturally belonged inside their parent tasks. This file records the absorption mapping so the spec→plan paper trail stays 1:1.

**Tech Stack:** Builders in `tests/AHKFlowApp.TestUtilities/Builders/`. No new packages.

---

## Absorption Map

| # | Spec item | Lands in |
| - | --- | --- |
| 1 | `CategoryBuilder` | [`docs/superpowers/plans/2026-05-19-categories.md`](2026-05-19-categories.md) — **Task 3a** |
| 2 | `HotstringBuilder.WithDescription(string?)` | [`docs/superpowers/plans/2026-05-19-schema-polish.md`](2026-05-19-schema-polish.md) — **Task 8** |
| 3 | `HotstringBuilder.WithCategory(ies)` / `HotkeyBuilder.WithCategory(ies)` | [`docs/superpowers/plans/2026-05-19-categories.md`](2026-05-19-categories.md) — **Task 18** |
| 4 | Header-template tests | n/a — reuse existing `ProfileBuilder.WithHeader(...)` (added earlier in `ProfileBuilder.cs`). No new builder. |
| 5 | `SeedAllAsync(HttpClient, reset=true)` integration helper | **Deferred.** See unresolved questions below. |

The absorbing tasks own their own verification; this file does not duplicate their checklists.

## Out of Scope

- Re-verifying that the absorbed builder extensions work — the parent plans' tests cover that.
- Greenfield `AHKFlowApp.TestUtilities` setup — already exists and is referenced from every test project.
- Touching production code from `tests/AHKFlowApp.TestUtilities` (it's a test-only project).

## Tasks

None. If `SeedAllAsync` is later promoted from deferred to in-scope, add a single task here with the helper shape and the first integration test that consumes it.

## Unresolved Questions

- `SeedAllAsync` helper — defer until first integration test wants it, or add proactively now?
  - Default (this plan): **defer**. Design hedges, no current caller, ~10 LOC to add later, signature shouldn't be locked in without a real consumer shaping it.
