# CLI search flags & case-sensitivity cleanup — Design

**Date:** 2026-05-14
**Type:** Cleanup / small feature
**Touches:** CLI (`ahkflow hotstring list`), backlog 019 + 023, application-layer comments, new architecture doc

## Context

Two stale items surfaced during review:

1. **Backlog 019** (Hotstrings search & filtering) still has an unchecked CLI acceptance criterion calling for `--grep` and `--ignore-case` flags. The capability shipped under the flag name `--search` / `-s`; the AC text was never updated. The "Deferred to 029" note is misleading — 029 is CLI authentication, unrelated.
2. **Backlog 023** (Hotkeys search & filtering) carries a "Known no-op" paragraph claiming an `ignoreCase` query param exists but does nothing. A code search confirms no such param exists on either controller or query handler. The note is factually wrong and refers to a phantom parameter that was never shipped.

User intent: AHKFlow search should be case-insensitive by default. The current behavior already satisfies this — SQL Server's default collation (`Latin1_General_CI_AS`) makes `EF.Functions.Like` case-insensitive without any application-layer flag.

## Goals

- Make backlog AC text match what shipped.
- Add a `--grep` alias on the CLI so grep-fluent users have the expected flag name.
- Close off the "should we add `ignoreCase`?" question in code and docs so future contributors don't reintroduce a phantom flag.

## Non-goals

- Backend query params (no `ignoreCase`, no `COLLATE` work).
- Hotkeys CLI (out of scope per backlog 023).
- Provider-independent search semantics (would require normalized columns or `EF.Functions.Collate`; YAGNI).
- True case-sensitive search.

## Design

### 1. CLI: `--grep` alias

Add `--grep` / `-g` as alias for the existing `--search` / `-s` option on `ahkflow hotstring list`. `System.CommandLine` supports multiple aliases on a single `Option<T>`:

```csharp
// src/Tools/AHKFlowApp.CLI/Commands/Hotstrings/ListHotstringCommand.cs
Option<string?> search = new("--search", "-s", "--grep", "-g")
{
    Description = "Search trigger / replacement (case-insensitive).",
};
```

No new parsing logic, no precedence rules. One option, four spellings, same value.

Update the `--search` description to make the case-insensitive behavior visible at `--help`.

### 2. CLI tests

Extend `tests/AHKFlowApp.CLI.Tests/Commands/Hotstrings/ListHotstringCommandTests.cs` with a parameterized test that runs `list --grep <term>` and `list --search <term>` against the same in-memory API fixture and asserts identical output. One new test, not a doubling of the suite.

### 3. Backlog 019 edits

`.claude/backlog/019-hotstrings-search-filtering.md`:

- Tick CLI AC `[x]`.
- Replace the AC text on line 21 with: `CLI \`ahkflow hotstring list\` supports text search via \`--search\` / \`-s\` (alias \`--grep\` / \`-g\`) and returns JSON when \`--json\` is used. Case-insensitive matching is the default (no flag).`
- Remove the `(Deferred to 029)` parenthetical.
- Update the **Completed** footer to today's date (CLI portion shipped on the merge date of this PR).

### 4. Backlog 023 edits

`.claude/backlog/023-hotkeys-search-filtering.md`:

- Delete the entire "Known no-op (cross-cutting, not 023)" paragraph (lines 39–40). No code change required — the param does not exist.

### 5. Inline code comment

In both `src/Backend/AHKFlowApp.Application/Queries/Hotstrings/ListHotstringsQuery.cs` and `src/Backend/AHKFlowApp.Application/Queries/Hotkeys/ListHotkeysQuery.cs`, above the `EF.Functions.Like` block:

```csharp
// Case-insensitive: relies on SQL Server's default collation (Latin1_General_CI_AS).
// Do not add an ignoreCase parameter — see docs/architecture/search-semantics.md.
```

### 6. Architecture doc

Create `docs/architecture/search-semantics.md` (~15 lines). Cover:

- List endpoints search via `LIKE` (`EF.Functions.Like`).
- Case-insensitivity is collation-driven (`Latin1_General_CI_AS`), not application-level.
- An `ignoreCase` query param is explicitly **not** offered. Rationale: case-sensitive search would require a `COLLATE … CS_AS` clause on every search predicate, has no demonstrated user need, and the current behavior matches user intent ("CI by default").
- Cross-link from the inline comments above.

## Verification

After changes:

1. `dotnet build --configuration Release --no-restore`
2. `dotnet test tests/AHKFlowApp.CLI.Tests --filter "FullyQualifiedName~ListHotstringCommand"`
3. `dotnet format` (zero diff expected on existing files)
4. Manual: `ahkflow hotstring list --grep btw` against local API returns the same rows as `--search btw`.
5. `ahkflow hotstring list --help` shows the alias `--grep` and a case-insensitive note in the description.

## Files

**Modified:**

- `src/Tools/AHKFlowApp.CLI/Commands/Hotstrings/ListHotstringCommand.cs` — add alias spellings, update description
- `src/Backend/AHKFlowApp.Application/Queries/Hotstrings/ListHotstringsQuery.cs` — inline comment
- `src/Backend/AHKFlowApp.Application/Queries/Hotkeys/ListHotkeysQuery.cs` — inline comment
- `tests/AHKFlowApp.CLI.Tests/Commands/Hotstrings/ListHotstringCommandTests.cs` — alias parity test
- `.claude/backlog/019-hotstrings-search-filtering.md` — AC rewrite, footer date
- `.claude/backlog/023-hotkeys-search-filtering.md` — remove stale paragraph

**Created:**

- `docs/architecture/search-semantics.md`

## Unresolved questions

None.
