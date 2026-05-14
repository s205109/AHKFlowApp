# CLI search flags & case-sensitivity cleanup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `--grep` alias on `ahkflow hotstring list`, document collation-driven case-insensitive search semantics, and clean up stale backlog notes (019 + 023).

**Architecture:** Single new alias on an existing `System.CommandLine` `Option<string?>`. No behavior change — `--grep` reuses the same option value, handler, and code path as `--search`. Inline comments + one new architecture doc explain why no `ignoreCase` flag exists. Backlog edits align AC text with what shipped.

**Tech Stack:** .NET 10, System.CommandLine 3.0.0-preview.3, xUnit, FluentAssertions, NSubstitute, EF Core (no changes), SQL Server (collation context only).

**Spec:** [docs/superpowers/specs/2026-05-14-cli-search-flags-and-case-sensitivity-cleanup-design.md](../specs/2026-05-14-cli-search-flags-and-case-sensitivity-cleanup-design.md)

---

## File Structure

**Modified (4 files):**
- `src/Tools/AHKFlowApp.CLI/Commands/Hotstrings/ListHotstringCommand.cs` — add `--grep`/`-g` aliases on the existing `search` option
- `tests/AHKFlowApp.CLI.Tests/Commands/Hotstrings/ListHotstringCommandTests.cs` — add a parity test for `--grep` vs `--search`
- `src/Backend/AHKFlowApp.Application/Queries/Hotstrings/ListHotstringsQuery.cs` — inline comment above the `EF.Functions.Like` block
- `src/Backend/AHKFlowApp.Application/Queries/Hotkeys/ListHotkeysQuery.cs` — inline comment above the `EF.Functions.Like` block
- `.claude/backlog/019-hotstrings-search-filtering.md` — tick CLI AC, update text, refresh completion date
- `.claude/backlog/023-hotkeys-search-filtering.md` — delete stale "Known no-op" paragraph

**Created (1 file):**
- `docs/architecture/search-semantics.md` — short note: list search uses LIKE with default CI collation, no `ignoreCase` flag

---

## Task 1: Failing test for `--grep` parity with `--search`

**Files:**
- Test: `tests/AHKFlowApp.CLI.Tests/Commands/Hotstrings/ListHotstringCommandTests.cs`

- [ ] **Step 1: Add a parity test for `--grep` and `-g`**

Append this `[Theory]` to `ListHotstringCommandTests`, immediately after the existing `SearchPassedThrough` `[Fact]` at line 85:

```csharp
[Theory]
[InlineData("--search")]
[InlineData("-s")]
[InlineData("--grep")]
[InlineData("-g")]
public async Task SearchAliases_AllPassedThroughIdentically(string flag)
{
    (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();

    await Run(["hotstring", "list", flag, "btw"], hs, profiles);

    await hs.Received(1).ListAsync(null, "btw", 1, 50, Arg.Any<CancellationToken>());
}
```

- [ ] **Step 2: Run the new test and confirm it fails**

Run:

```
dotnet test tests/AHKFlowApp.CLI.Tests --filter "FullyQualifiedName~SearchAliases_AllPassedThroughIdentically"
```

Expected: 2 of 4 inline cases fail (`--grep`, `-g`) — System.CommandLine surfaces unrecognized tokens. The `--search` and `-s` cases pass. Confirm that's what you see before moving on.

- [ ] **Step 3: Do not commit yet** (Task 2 ships the implementation in the same commit per project convention "feature + its tests = one commit").

---

## Task 2: Add `--grep` / `-g` aliases to the CLI option

**Files:**
- Modify: `src/Tools/AHKFlowApp.CLI/Commands/Hotstrings/ListHotstringCommand.cs:15`

- [ ] **Step 1: Replace the `search` option declaration**

Find this line in `ListHotstringCommand.Build` (currently line 15):

```csharp
Option<string?> search = new("--search", "-s") { Description = "Search trigger / replacement." };
```

Replace with:

```csharp
Option<string?> search = new("--search", "-s", "--grep", "-g")
{
    Description = "Search trigger / replacement (case-insensitive).",
};
```

The `Option<T>` constructor takes a primary name plus any number of alias strings. All four resolve to the same option value, so `parse.GetValue(search)` continues to work unchanged.

- [ ] **Step 2: Run the full `ListHotstringCommand` test suite**

Run:

```
dotnet test tests/AHKFlowApp.CLI.Tests --filter "FullyQualifiedName~ListHotstringCommandTests"
```

Expected: all tests pass, including the four `SearchAliases_AllPassedThroughIdentically` inline cases.

- [ ] **Step 3: Verify `--help` shows the alias**

Run:

```
dotnet run --project src/Tools/AHKFlowApp.CLI -- hotstring list --help
```

Expected: `-s, --search, -g, --grep` (or similar grouping, depending on System.CommandLine help format) appears in the options list, with the new "(case-insensitive)" suffix in the description.

- [ ] **Step 4: Commit**

```
git add src/Tools/AHKFlowApp.CLI/Commands/Hotstrings/ListHotstringCommand.cs tests/AHKFlowApp.CLI.Tests/Commands/Hotstrings/ListHotstringCommandTests.cs
git commit -m "feat(cli): add --grep alias for hotstring list --search"
```

---

## Task 3: Inline collation comment in hotstrings query handler

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Queries/Hotstrings/ListHotstringsQuery.cs:71`

- [ ] **Step 1: Add comment above the `Search` filter block**

Find this block (currently lines 71–77):

```csharp
        if (!string.IsNullOrWhiteSpace(request.Search))
        {
            string pattern = $"%{request.Search.Trim()}%";
            query = query.Where(h =>
                EF.Functions.Like(h.Trigger, pattern) ||
                EF.Functions.Like(h.Replacement, pattern));
        }
```

Replace with:

```csharp
        // Case-insensitive: relies on the database collation (SQL_Latin1_General_CP1_CI_AS).
        // Do not add an ignoreCase parameter — see docs/architecture/search-semantics.md.
        if (!string.IsNullOrWhiteSpace(request.Search))
        {
            string pattern = $"%{request.Search.Trim()}%";
            query = query.Where(h =>
                EF.Functions.Like(h.Trigger, pattern) ||
                EF.Functions.Like(h.Replacement, pattern));
        }
```

- [ ] **Step 2: Build to confirm no syntax issue**

Run:

```
dotnet build src/Backend/AHKFlowApp.Application --configuration Release --no-restore
```

Expected: build succeeds, zero warnings.

- [ ] **Step 3: Do not commit yet** (Task 4 adds the matching comment in `ListHotkeysQuery`; ship both in one commit).

---

## Task 4: Inline collation comment in hotkeys query handler

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Queries/Hotkeys/ListHotkeysQuery.cs:75`

- [ ] **Step 1: Add comment above the `Search` filter block**

Find this block (currently lines 75–82):

```csharp
        if (!string.IsNullOrWhiteSpace(request.Search))
        {
            string pattern = $"%{request.Search.Trim()}%";
            query = query.Where(h =>
                EF.Functions.Like(h.Description, pattern) ||
                EF.Functions.Like(h.Key, pattern) ||
                EF.Functions.Like(h.Parameters, pattern));
        }
```

Replace with:

```csharp
        // Case-insensitive: relies on the database collation (SQL_Latin1_General_CP1_CI_AS).
        // Do not add an ignoreCase parameter — see docs/architecture/search-semantics.md.
        if (!string.IsNullOrWhiteSpace(request.Search))
        {
            string pattern = $"%{request.Search.Trim()}%";
            query = query.Where(h =>
                EF.Functions.Like(h.Description, pattern) ||
                EF.Functions.Like(h.Key, pattern) ||
                EF.Functions.Like(h.Parameters, pattern));
        }
```

- [ ] **Step 2: Build the application project**

Run:

```
dotnet build src/Backend/AHKFlowApp.Application --configuration Release --no-restore
```

Expected: build succeeds, zero warnings.

- [ ] **Step 3: Commit Task 3 + Task 4 together**

```
git add src/Backend/AHKFlowApp.Application/Queries/Hotstrings/ListHotstringsQuery.cs src/Backend/AHKFlowApp.Application/Queries/Hotkeys/ListHotkeysQuery.cs
git commit -m "docs(application): pin collation-driven CI search; forbid ignoreCase param"
```

---

## Task 5: Create `docs/architecture/search-semantics.md`

**Files:**
- Create: `docs/architecture/search-semantics.md`

- [ ] **Step 1: Write the doc**

Create `docs/architecture/search-semantics.md` with exactly this content:

```markdown
# Search semantics

## Where this applies

`ListHotstringsQuery` and `ListHotkeysQuery` (Application layer). The CLI `ahkflow hotstring list --search` / `--grep` and the Blazor UI search boxes route through these handlers.

## How matching works

Both handlers use `EF.Functions.Like(field, "%term%")` on the searchable columns:

- Hotstrings: `Trigger`, `Replacement`.
- Hotkeys: `Description`, `Key`, `Parameters`.

The `LIKE` predicate inherits the SQL Server column collation. The application's default collation is `SQL_Latin1_General_CP1_CI_AS` (case-insensitive, accent-sensitive), so `BTW` matches `btw` without any application-level normalization.

## Why there is no `ignoreCase` flag

We deliberately do **not** expose an `ignoreCase` query parameter on the API or a `--ignore-case` flag on the CLI:

- Case-insensitive matching is the user-facing default we want.
- A no-op flag (that accepts `ignoreCase=false` but returns CI results anyway) would mislead callers.
- True case-sensitive search would require pushing a `COLLATE SQL_Latin1_General_CP1_CS_AS` clause into every search predicate. There is no current user need for that, and it would tie application code to a SQL Server collation literal.
- An earlier review note (backlog 023) referred to an `ignoreCase` query param as a "known no-op". That param was never actually shipped — the note has been removed.

## If case-sensitive search becomes a requirement

Add a `COLLATE`-aware override to the search predicate (e.g. `EF.Functions.Collate(h.Trigger, "SQL_Latin1_General_CP1_CS_AS")`), gate it on a `CaseSensitive` flag on the query record, and expose it through the controller and CLI together. Update this doc when you do.
```

- [ ] **Step 2: Verify the file renders**

Run:

```
dotnet format --verify-no-changes docs
```

(If `dotnet format` doesn't touch `docs/`, skip — this step exists only to catch accidental mixed-line-ending issues. Visually confirm the file in your editor instead.)

- [ ] **Step 3: Commit**

```
git add docs/architecture/search-semantics.md
git commit -m "docs(architecture): document collation-driven CI search semantics"
```

---

## Task 6: Update backlog 019 (Hotstrings search & filtering)

**Files:**
- Modify: `.claude/backlog/019-hotstrings-search-filtering.md:21`
- Modify: `.claude/backlog/019-hotstrings-search-filtering.md:28`

- [ ] **Step 1: Rewrite the CLI acceptance criterion**

Find line 21:

```markdown
- [ ] CLI supports `--grep` and `--ignore-case` flags matching the UI behavior and returns JSON when `--json` is used. (Deferred to 029)
```

Replace with:

```markdown
- [x] CLI `ahkflow hotstring list` supports text search via `--search` / `-s` (alias `--grep` / `-g`) and returns JSON when `--json` is used. Case-insensitive matching is the default (no flag) — see `docs/architecture/search-semantics.md`.
```

- [ ] **Step 2: Refresh the completion footer**

Find line 28:

```markdown
**Completed:** 2026-04-29 (API + UI; CLI deferred to 029)
```

Replace with:

```markdown
**Completed:** 2026-05-14 (API + UI on 2026-04-29; CLI alias + docs on 2026-05-14)
```

- [ ] **Step 3: Commit**

```
git add .claude/backlog/019-hotstrings-search-filtering.md
git commit -m "chore(backlog): close 019 CLI AC; --grep ships, --ignore-case dropped by design"
```

---

## Task 7: Update backlog 023 (Hotkeys search & filtering)

**Files:**
- Modify: `.claude/backlog/023-hotkeys-search-filtering.md:39-40`

- [ ] **Step 1: Delete the stale "Known no-op" paragraph**

Find lines 39–40 (the two-line block beginning with `Known no-op (cross-cutting, not 023):`):

```markdown
Known no-op (cross-cutting, not 023):
- `ignoreCase` query param exists but is unused — SQL Server's default collation is already CI. Same defect on Hotstrings. Either remove or implement properly as a separate cleanup.
```

Also delete the blank line that follows (between this block and `## Out of scope`), so the file goes straight from the "Deliberate non-goals" list into `## Out of scope` with one blank line separating them.

- [ ] **Step 2: Verify the file still parses cleanly**

Open the file and confirm:

- The "Deliberate non-goals" bulleted list ends correctly.
- `## Out of scope` is the next header.
- No orphaned blank lines or stray indentation.

- [ ] **Step 3: Commit**

```
git add .claude/backlog/023-hotkeys-search-filtering.md
git commit -m "chore(backlog): drop 023 phantom ignoreCase note; param never shipped"
```

---

## Task 8: Final verification

- [ ] **Step 1: Full build**

Run:

```
dotnet build --configuration Release --no-restore
```

Expected: solution builds with zero errors and zero new warnings.

- [ ] **Step 2: Full test suite**

Run:

```
dotnet test --configuration Release --no-build --verbosity normal
```

Expected: all tests pass, including the four new inline cases in `SearchAliases_AllPassedThroughIdentically`.

- [ ] **Step 3: Format check**

Run:

```
dotnet format --verify-no-changes
```

Expected: zero diff.

- [ ] **Step 4: Manual CLI smoke test (optional, requires running API)**

If a local API is running with seed data:

```
dotnet run --project src/Tools/AHKFlowApp.CLI -- hotstring list --grep btw
dotnet run --project src/Tools/AHKFlowApp.CLI -- hotstring list --search btw
```

Expected: identical rows from both invocations.

- [ ] **Step 5: Verify the commit history is clean**

Run:

```
git log --oneline main..HEAD
```

Expected: among the branch's commits, you see (in order) the spec commit from the brainstorm session plus exactly these 5 new ones from this plan:

1. `feat(cli): add --grep alias for hotstring list --search`
2. `docs(application): pin collation-driven CI search; forbid ignoreCase param`
3. `docs(architecture): document collation-driven CI search semantics`
4. `chore(backlog): close 019 CLI AC; --grep ships, --ignore-case dropped by design`
5. `chore(backlog): drop 023 phantom ignoreCase note; param never shipped`

Pre-existing branch commits unrelated to this work are fine.

---

## Done criteria

- `ahkflow hotstring list --grep btw` works identically to `--search btw`.
- `--help` lists all four spellings and the case-insensitive note.
- Backlog 019 CLI AC is ticked and reflects what shipped (no `--ignore-case`).
- Backlog 023 no longer references a phantom `ignoreCase` query param.
- `docs/architecture/search-semantics.md` exists and is linked from both query handlers.
- `dotnet build`, `dotnet test`, `dotnet format --verify-no-changes` all green.
