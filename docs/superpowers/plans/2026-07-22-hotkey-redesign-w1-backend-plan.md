# Hotkey Redesign — Wave 1 Backend (Typed Actions) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the two-value `HotkeyAction`/`Parameters` model with the seven-kind `HotkeyActionKind` typed-column model — per-kind emission, per-role validation, legacy-row migration with a parity-tested converter, and a preview endpoint — closing the action half of the redesign on the backend.

**Architecture:** Discriminated typed columns on `Hotkey` (§8), gated by `ActionKind`. Every action is safe by construction: SendText/Run escape free text at emission (W0's shared `AhkEscaping`), SendKeys/Remap persist validated tokens, Window/Disable emit from enums, Raw is the sole verbatim path. The column swap is atomic in the database but staged in code via **expand → cutover → contract**: Migration A adds the typed columns and back-fills them from the legacy pair (T-SQL mirroring a parity-tested C# converter); the emitter, validators, DTOs, and commands then move onto the typed columns; Migration B drops the legacy pair and retires the enum. Each task ends on a green build and green tests.

**Tech Stack:** .NET 10, EF Core (SQL Server), FluentValidation, Ardalis.Result, xUnit + FluentAssertions + NSubstitute, Testcontainers (SQL Server).

**Source spec:** `docs/superpowers/specs/2026-07-21-hotkey-redesign-design.md` (§1, §5, §7, §8, §9 W1, §10, §11). Predecessor plan: `docs/superpowers/plans/2026-07-21-hotkey-redesign-w0-plan.md` (landed).

**Scope:** Backend only. The UI half of W1 (dialog action panels, `HotkeyActionChip`, `HotkeyActionDisplay`, grid inline-edit gating, mobile list, preview panel, bUnit + E2E) is a **separate plan** authored next. This plan delivers the API, persistence, emission, validation, history, and preview endpoint — independently testable via Application + Infrastructure + API test projects.

> **Separately testable, not separately deployable.** Task 6 removes `Action`/`Parameters` from
> `HotkeyDto`/`CreateHotkeyDto`/`UpdateHotkeyDto`, and the live UI still both sends and reads them
> (`src/Frontend/AHKFlowApp.UI.Blazor/Validation/HotkeyEditModel.cs`). The frontend keeps its own DTO
> mirror, so nothing fails to compile — the hotkeys page breaks at **runtime**: every create/update
> posts a payload whose `ActionKind` fields are absent (400 from the kind-conditional validator), and
> every read shows an empty action. Keeping a JSON compatibility contract instead was rejected: it
> would resurrect the legacy pair on the DTOs that Task 6 exists to remove, for one wave, and Task 11
> would have to delete it again anyway.
> **Gate:** do not merge this plan's Task 6 or later until the W1 UI plan is ready to land with it.

### Cutover procedure (not "separate PRs are fine")

`deploy-api.yml` and `deploy-frontend.yml` both trigger on push to `main`, under disjoint path
filters (`src/Backend/**` + `tests/**` vs `src/Frontend/**`). They are independent pipelines, so
merge order *is* deploy order and nothing sequences them for us:

1. **One merge, not two.** Backend and UI land in a **single merge commit to `main`** — one PR, or a
   stacked pair merged as one commit. Two merges are two pushes: the first one deploys half the
   change and leaves TEST broken until the second lands and finishes. Separate *branches* are fine;
   separate *merges* are not.
2. **TEST window is bounded, not zero.** One push starts both workflows concurrently, so whichever
   finishes first serves against the other's old half until it catches up — a few minutes on TEST
   only. That window is accepted, not designed away: closing it needs the compatibility contract
   rejected above. Treat TEST as unavailable for hotkeys until **both** workflows are green, then
   smoke-test the hotkeys page before calling the wave done.
3. **PROD is ordered by hand.** Both PROD deploys are `workflow_dispatch`. Dispatch **API first**,
   wait for green plus `/health`, then dispatch the frontend. API-first is not arbitrary: the API
   is the half the other depends on and the half carrying the migrations (`deploy-api.yml`'s
   `migrate-db` job), so it is the one that can fail. If it does, stop — do not ship a UI whose
   only contract never landed. The reverse order also leaves a new UI posting typed payloads to an
   API that answers 400 to every one of them.
4. **Cached clients outlive both deploys.** The UI is a WASM PWA: a browser holding the old bundle
   keeps posting the old shape until its service worker picks up the new build and the tab reloads.
   Deploy ordering cannot fix that; it is the same staleness envelope as any breaking DTO change,
   and it resolves on reload.

## Global Constraints

- Target framework `net10.0`; Microsoft.* packages on 10.x. Never hardcode package versions; CPM (`Directory.Packages.props`) — no `Version=` in csproj.
- Primary constructors for DI; records for DTOs/commands/value objects; file-scoped namespaces; Allman braces; `sealed` by default; `internal` unless a wider surface is needed.
- No repository pattern — handlers inject `IAppDbContext` directly. No AutoMapper/Mapster — explicit mapping in `Mapping/HotkeyMappings.cs` and inline `Select`.
- Handlers return `Result<T>`; controllers map via `result.ToProblemActionResult(this)`.
- Propagate `CancellationToken` through every async call. No `.Result` / `.Wait()`. `TimeProvider`, never `DateTime.UtcNow`.
- FluentAssertions over raw `Assert`. Test naming `MethodName_Scenario_ExpectedResult`. AAA with blank-line separation. Builder pattern for test data (`tests/AHKFlowApp.TestUtilities/Builders/`).
- Integration tests use Testcontainers (SQL Server) via `SqlContainerFixture` + `[Collection("SqlServer")]`. **Never `UseInMemoryDatabase`.**
- Conventional commits, extremely concise. Atomic: one logical change per commit, feature + its tests together.
- `dotnet format` needs an explicit workspace: `dotnet format AHKFlowApp.slnx` (bare `dotnet format` fails with "Both a MSBuild project file and solution file found").
- `dotnet test` accepts **one** project path — run projects as separate commands, or `dotnet test AHKFlowApp.slnx` for everything.
- **This is a worktree** (`feature/wt-hotkey-redesign`). Commit here, never in the main checkout.
- `GenerateDocumentationFile` is on and `TreatWarningsAsErrors` is true (only CS1591 suppressed). An unresolvable `<see cref>` is CS1574 — an **error**. Reference not-yet-created types with `<c>...</c>`.
- **Enum-value safety:** legacy `HotkeyAction` ints must not silently read as a valid `HotkeyActionKind`. The converter keys off the **legacy members' presence**, never their numeric value (§8).

## Strategy: expand → cutover → contract

The database column swap (`Action`/`Parameters` → `ActionKind` + typed columns) is atomic, but code stays green throughout by staging it:

1. **Expand (Task 4).** Add the typed columns and `ActionKind` alongside the still-present `Action`/`Parameters`. Migration A adds the columns and back-fills them from the legacy pair. `HotkeyDefinition` gains the typed fields (defaulted); every write path populates them via `LegacyHotkeyDefinitionConverter`. The existing (W0) emitter still reads `Action`/`Parameters`, so existing goldens are unchanged.
2. **Cutover (Tasks 5–10).** Move the emitter, DTOs, mappings, commands, list query, validation, history, and preview onto the typed columns. Legacy `Action`/`Parameters` linger only where not yet re-pointed.
3. **Contract (Task 11).** Migration B drops `Action`/`Parameters`; the `HotkeyAction` enum is retired; legacy fields leave `HotkeyDefinition` and the entity. `HotkeySnapshot` keeps `Action`/`Parameters` as **optional legacy members** forever (old history JSON still holds them).

---

## File Structure

**Create:**
- `src/Backend/AHKFlowApp.Domain/Enums/HotkeyActionKind.cs` — seven-kind action discriminator.
- `src/Backend/AHKFlowApp.Domain/Enums/WindowOp.cs` — window operation.
- `src/Backend/AHKFlowApp.Domain/Enums/RunTargetKind.cs` — run-target label.
- `src/Backend/AHKFlowApp.Application/Constants/DefaultHotkeyCatalog.cs` — the one sample-hotkey set, replacing the duplicated `s_lazySeed` / `s_samples` arrays (Task 6).
- `src/Backend/AHKFlowApp.Application/Services/LegacyHotkeyDefinitionConverter.cs` — legacy (`Action`+`Parameters`) → typed `HotkeyDefinition`; single C# home of the transform (§8).
- `src/Backend/AHKFlowApp.Application/Services/LegacyHotkeySnapshotConverter.cs` — `HotkeySnapshot` (legacy or typed) → typed `HotkeyDefinition`, for restore/revert.
- `src/Backend/AHKFlowApp.Application/Queries/Hotkeys/GetHotkeyPreviewQuery.cs` — transient-emit preview (clone of `GetHotstringPreviewQuery`).
- `src/Backend/AHKFlowApp.Infrastructure/Migrations/<ts>_HotkeyTypedActions.cs` — **Migration A**: add typed columns + T-SQL back-fill.
- `src/Backend/AHKFlowApp.Infrastructure/Migrations/<ts>_DropLegacyHotkeyAction.cs` — **Migration B**: drop `Action`/`Parameters`.
- `tests/AHKFlowApp.TestUtilities/Fixtures/LegacyHotkeyFixtures.cs` — shared golden set (migration ↔ converter parity), seeded from the dev lazy-seed rows.
- `tests/AHKFlowApp.Application.Tests/Constants/HotkeyKeysRemapRolesTests.cs`
- `tests/AHKFlowApp.Application.Tests/Validation/HotkeyTokenRulesTests.cs`
- `tests/AHKFlowApp.Application.Tests/Services/LegacyHotkeyDefinitionConverterTests.cs`
- `tests/AHKFlowApp.Application.Tests/Services/LegacyHotkeySnapshotConverterTests.cs`
- `tests/AHKFlowApp.Application.Tests/Validation/HotkeyKindConditionalRulesTests.cs`
- `tests/AHKFlowApp.Infrastructure.Tests/Migrations/HotkeyTypedActionsMigrationTests.cs`
- `tests/AHKFlowApp.Application.Tests/Hotkeys/GetHotkeyPreviewQueryTests.cs`
- `docs/adr/0004-hotkey-typed-actions-and-raw-escape-hatch.md`

**Modify:**
- `src/Backend/AHKFlowApp.Application/Constants/HotkeyKeys.cs` — modifier-key entries + `IsValidRemapSource`/`IsValidRemapDest`.
- `src/Backend/AHKFlowApp.Application/Validation/HotkeyRules.cs` — `ValidSendKeysContent`, `ValidRemapDest`, kind-conditional composite; retire `ValidAction`/`ValidParameters`.
- `src/Backend/AHKFlowApp.Application/Services/HotkeyEmitter.cs` — per-kind emission over typed columns; `$` auto-emit for SendKeys.
- `src/Backend/AHKFlowApp.Domain/Entities/Hotkey.cs` — typed columns + `Apply`.
- `src/Backend/AHKFlowApp.Domain/Entities/HotkeyDefinition.cs` — typed fields.
- `src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/HotkeyConfiguration.cs` — typed column config.
- `src/Backend/AHKFlowApp.Application/DTOs/HotkeyDto.cs` — typed fields on `HotkeyDto`/`CreateHotkeyDto`/`UpdateHotkeyDto`.
- `src/Backend/AHKFlowApp.Application/DTOs/HistorySnapshots.cs` — `HotkeySnapshot` typed + legacy-optional.
- `src/Backend/AHKFlowApp.Application/Mapping/HotkeyMappings.cs` — typed `ToDto`.
- `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/{Create,Update,Restore,Revert}HotkeyCommand.cs`
- `src/Backend/AHKFlowApp.Application/Queries/Hotkeys/ListHotkeysQuery.cs` — typed filters/sort; `s_lazySeed` → `DefaultHotkeyCatalog`.
- `src/Backend/AHKFlowApp.Application/Commands/Dev/SeedHotkeysCommand.cs` — `s_samples` → `DefaultHotkeyCatalog`.
- `src/Backend/AHKFlowApp.API/Controllers/HotkeysController.cs` — `POST /preview`.
- `tests/AHKFlowApp.TestUtilities/Builders/HotkeyBuilder.cs` — typed builder methods.
- `CONTEXT.md` — W1 terms (Action, Remap, Run target, Raw).
- `docs/development/ahk-v2-syntax.md` — per-kind hotkey emission.

**Retire (Task 11):** `src/Backend/AHKFlowApp.Domain/Enums/HotkeyAction.cs`, `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HotkeyAction.cs` (frontend mirror — coordinate with the UI plan; leave a compile shim if the UI plan has not landed, see Task 11).

---

### Task 1: New enums

Pure additive. `HotkeyAction` stays until Task 11.

**Files:**
- Create: `src/Backend/AHKFlowApp.Domain/Enums/HotkeyActionKind.cs`
- Create: `src/Backend/AHKFlowApp.Domain/Enums/WindowOp.cs`
- Create: `src/Backend/AHKFlowApp.Domain/Enums/RunTargetKind.cs`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum HotkeyActionKind`, `enum WindowOp`, `enum RunTargetKind` in `AHKFlowApp.Domain.Enums`.

- [ ] **Step 1: Write the enums**

`HotkeyActionKind.cs`:

```csharp
namespace AHKFlowApp.Domain.Enums;

/// <summary>
/// What a hotkey does when it fires. Replaces the two-value <see cref="HotkeyAction"/>.
/// </summary>
/// <remarks>
/// Values are natural and unrelated to legacy <see cref="HotkeyAction"/> ints on purpose: the
/// legacy-to-typed converter keys off the presence of the legacy snapshot members, never their
/// numeric value, so a stale <c>Action = 1</c> can never masquerade as a valid new kind (spec §8).
/// </remarks>
public enum HotkeyActionKind
{
    /// <summary>Type literal text (<c>SendText("...")</c>). Free text, escaped at emission.</summary>
    SendText = 0,

    /// <summary>Send a validated key token (<c>Send("{Volume_Up}")</c>).</summary>
    SendKeys = 1,

    /// <summary>Launch an application, URL, or folder (<c>Run("...")</c>). Free text, escaped.</summary>
    Run = 2,

    /// <summary>Operate on the active window (<c>WinMinimize("A")</c>, …).</summary>
    Window = 3,

    /// <summary>Make one key behave as another (<c>origin::dest</c>).</summary>
    Remap = 4,

    /// <summary>Disable a key (<c>key::return</c>).</summary>
    Disable = 5,

    /// <summary>Verbatim action body (<c>origin::{ body }</c>). The sole unchecked path.</summary>
    Raw = 6,
}
```

`WindowOp.cs`:

```csharp
namespace AHKFlowApp.Domain.Enums;

/// <summary>Operation a <see cref="HotkeyActionKind.Window"/> hotkey performs on the active window.</summary>
public enum WindowOp
{
    /// <summary><c>WinMinimize("A")</c>.</summary>
    Minimize = 0,

    /// <summary><c>WinMaximize("A")</c>.</summary>
    Maximize = 1,

    /// <summary><c>WinRestore("A")</c>.</summary>
    Restore = 2,

    /// <summary><c>WinClose("A")</c>.</summary>
    Close = 3,

    /// <summary><c>WinSetAlwaysOnTop(-1, "A")</c>.</summary>
    ToggleAlwaysOnTop = 4,
}
```

`RunTargetKind.cs`:

```csharp
namespace AHKFlowApp.Domain.Enums;

/// <summary>
/// Label for a <see cref="HotkeyActionKind.Run"/> target. Display-only: all three kinds emit the
/// same <c>Run("&lt;escaped&gt;")</c>, so the label carries no emission behavior (spec §8).
/// </summary>
public enum RunTargetKind
{
    /// <summary>An application or command line.</summary>
    Application = 0,

    /// <summary>A URL (<c>http://</c> / <c>https://</c>).</summary>
    Url = 1,

    /// <summary>A filesystem folder.</summary>
    Folder = 2,
}
```

- [ ] **Step 2: Build**

Run: `dotnet build src/Backend/AHKFlowApp.Domain --configuration Release`
Expected: 0 errors, 0 warnings.

- [ ] **Step 3: Commit**

```bash
dotnet format AHKFlowApp.slnx
git add src/Backend/AHKFlowApp.Domain/Enums/HotkeyActionKind.cs \
        src/Backend/AHKFlowApp.Domain/Enums/WindowOp.cs \
        src/Backend/AHKFlowApp.Domain/Enums/RunTargetKind.cs
git commit -m "feat: add HotkeyActionKind, WindowOp, RunTargetKind enums

typed-action model for wave 1; HotkeyAction retired in the cutover"
```

---

### Task 2: Registry modifier keys + remap-role predicates

Adds the modifier-key entries W0 deferred (spec §7 goldens 13–14 need `Ctrl`, `RAlt`) and the two remap-role lookups the validators read. Mouse/wheel stay Wave 2.

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Constants/HotkeyKeys.cs`
- Create: `tests/AHKFlowApp.Application.Tests/Constants/HotkeyKeysRemapRolesTests.cs`

**Interfaces:**
- Consumes: existing `HotkeyKeys` (`All`, `TryCanonicalize`, `HotkeyKeyRoles`, `HotkeyKeyEntry`) from W0.
- Produces: `HotkeyKeys.IsValidRemapSource(string?)`, `HotkeyKeys.IsValidRemapDest(string?)`; modifier-key registry group.

- [ ] **Step 1: Write the failing test**

Create `tests/AHKFlowApp.Application.Tests/Constants/HotkeyKeysRemapRolesTests.cs`:

```csharp
using AHKFlowApp.Application.Constants;
using FluentAssertions;

namespace AHKFlowApp.Application.Tests.Constants;

public sealed class HotkeyKeysRemapRolesTests
{
    [Theory]
    [InlineData("CapsLock")]   // golden 13 source
    [InlineData("RAlt")]       // golden 14 source
    [InlineData("a")]
    [InlineData("vk1B")]
    public void IsValidRemapSource_RemappableKeyOrCode_IsTrue(string key)
    {
        HotkeyKeys.IsValidRemapSource(key).Should().BeTrue();
    }

    [Theory]
    [InlineData("Ctrl")]       // golden 13 dest
    [InlineData("a")]
    [InlineData("Escape")]
    [InlineData("vk1B")]
    public void IsValidRemapDest_RemappableKeyOrCode_IsTrue(string key)
    {
        HotkeyKeys.IsValidRemapDest(key).Should().BeTrue();
    }

    [Fact]
    public void IsValidRemapDest_Pause_IsFalse()
    {
        // Pause collides with the built-in Pause function name; a remap must target vk13 instead.
        HotkeyKeys.IsValidRemapDest("Pause").Should().BeFalse();
        HotkeyKeys.IsValidRemapDest("vk13").Should().BeTrue();
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("NotAKey")]
    [InlineData("{Ctrl}")]     // braces are not a remap dest
    public void IsValidRemapDest_UnknownOrBraced_IsFalse(string? key)
    {
        HotkeyKeys.IsValidRemapDest(key).Should().BeFalse();
    }

    [Fact]
    public void All_ModifierKeysCanBeRemapSourceAndDest()
    {
        HotkeyKeys.HotkeyKeyEntryByCanonical("RAlt").Roles.Should().HaveFlag(HotkeyKeyRoles.RemapSource);
        HotkeyKeys.HotkeyKeyEntryByCanonical("Ctrl").Roles.Should().HaveFlag(HotkeyKeyRoles.RemapDest);
    }

    [Fact]
    public void TryCanonicalize_ModifierAlias_Resolves()
    {
        HotkeyKeys.TryCanonicalize("Control", out string c).Should().BeTrue();
        c.Should().Be("Ctrl");
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~HotkeyKeysRemapRolesTests"`
Expected: FAIL — `IsValidRemapSource` / `IsValidRemapDest` / `HotkeyKeyEntryByCanonical` not defined.

- [ ] **Step 3: Add the modifier group and predicates**

In `src/Backend/AHKFlowApp.Application/Constants/HotkeyKeys.cs`, add a group constant beside the existing ones:

```csharp
    public const string GroupModifiers = "Modifiers";
```

Add the modifier-key table beside `s_namedKeys`:

```csharp
    // Modifier keys. They ARE valid hotkey keys (Ctrl::), valid Send tokens ({LWin}), and valid
    // remap source and destination (CapsLock::Ctrl, RAlt::RButton). Deferred from W0 because remap
    // — their only reason to exist as picker entries — had no action kind until W1.
    private static readonly string[] s_modifierKeys =
    [
        "Ctrl", "Alt", "Shift", "LWin", "RWin",
        "LCtrl", "RCtrl", "LAlt", "RAlt", "LShift", "RShift",
    ];
```

Register the group inside `BuildRegistry()`, after the media keys loop:

```csharp
        foreach (string name in s_modifierKeys)
            entries.Add(new(name, GroupModifiers, HotkeyKeyRoles.All, RequiresBracesInSend: true));
```

Add these modifier aliases to `s_aliases`:

```csharp
        ["Control"] = "Ctrl",
        ["Windows"] = "LWin",
        ["Win"] = "LWin",
```

Add the lookup helper and the two remap predicates (after `IsValidHotkeyKey`):

```csharp
    /// <summary>Returns the registry entry for a canonical name. Throws if absent — callers pass
    /// names they already know are in the registry (tests, picker construction).</summary>
    public static HotkeyKeyEntry HotkeyKeyEntryByCanonical(string canonical) => s_byName[canonical];

    /// <summary>Accepted non-canonical spellings, keyed by alias (<c>Esc</c> → <c>Escape</c>).
    /// Read by the Migration A name-list generator, which must accept every spelling
    /// <see cref="TryCanonicalize"/> resolves — the migration itself never canonicalizes.</summary>
    public static IReadOnlyDictionary<string, string> Aliases => s_aliases;

    /// <summary>
    /// True if <paramref name="key"/> may be the source of a remap: a registry key carrying the
    /// <see cref="HotkeyKeyRoles.RemapSource"/> role, or a <c>vk</c>/<c>sc</c> code. Wheel keys
    /// (Wave 2) will carry the role cleared.
    /// </summary>
    public static bool IsValidRemapSource(string? key) => HasRole(key, HotkeyKeyRoles.RemapSource);

    /// <summary>
    /// True if <paramref name="key"/> may be the destination of a remap: a registry key carrying
    /// the <see cref="HotkeyKeyRoles.RemapDest"/> role, or a <c>vk</c>/<c>sc</c> code. Excludes
    /// <c>Pause</c> (collides with the built-in function — use <c>vk13</c>) and braced tokens.
    /// </summary>
    public static bool IsValidRemapDest(string? key) => HasRole(key, HotkeyKeyRoles.RemapDest);

    private static bool HasRole(string? key, HotkeyKeyRoles role)
    {
        if (!TryCanonicalize(key, out string canonical))
            return false;

        // vk/sc codes are not in s_byName; they satisfy any single-key role.
        if (!s_byName.TryGetValue(canonical, out HotkeyKeyEntry? entry))
            return true;

        return entry.Roles.HasFlag(role);
    }
```

`RolesForNamed` already clears `RemapDest` for `Pause` (W0), so `IsValidRemapDest("Pause")` returns false via the flag; `vk13` returns true via the vk/sc branch.

- [ ] **Step 4: Run tests to verify they pass**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~HotkeyKeysRemapRolesTests|FullyQualifiedName~HotkeyKeysTests"`
Expected: PASS. (Re-run the W0 `HotkeyKeysTests` too — the new entries must not break `All_HasNoDuplicateCanonicalNames` or `All_EveryEntryIsUsableAsAHotkeyKey`.)

- [ ] **Step 5: Commit**

```bash
dotnet format AHKFlowApp.slnx
git add src/Backend/AHKFlowApp.Application/Constants/HotkeyKeys.cs \
        tests/AHKFlowApp.Application.Tests/Constants/HotkeyKeysRemapRolesTests.cs
git commit -m "feat: registry modifier keys + remap-role predicates

CapsLock/RAlt/Ctrl now resolvable; IsValidRemapSource/Dest feed W1 validators"
```

---

### Task 3: SendKeys & RemapDest token grammars

Two pure validators — the §8 grammars that make SendKeys/Remap safe by construction. Kept out of `HotkeyRules` extension methods so they are unit-testable as plain functions.

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Validation/HotkeyRules.cs` (add a nested static `Tokens` class)
- Create: `tests/AHKFlowApp.Application.Tests/Validation/HotkeyTokenRulesTests.cs`

**Interfaces:**
- Consumes: `HotkeyKeys.TryCanonicalize`, `HotkeyKeys.IsValidRemapDest`, `HotkeyKeys.HotkeyKeyEntryByCanonical`, `HotkeyKeyRoles` (Tasks 2, W0).
- Produces: `HotkeyRules.Tokens.IsValidSendKeysContent(string?)`, `HotkeyRules.Tokens.IsValidRemapDest(string?)`.

- [ ] **Step 1: Write the failing test**

Create `tests/AHKFlowApp.Application.Tests/Validation/HotkeyTokenRulesTests.cs`:

```csharp
using AHKFlowApp.Application.Validation;
using FluentAssertions;

namespace AHKFlowApp.Application.Tests.Validation;

public sealed class HotkeyTokenRulesTests
{
    [Theory]
    [InlineData("^v")]                 // ctrl + printable, bare
    [InlineData("c")]                  // bare printable
    [InlineData("{Up}")]               // named key braced
    [InlineData("{Volume_Up}")]        // named key braced
    [InlineData("^!{Delete}")]         // modifiers + braced named
    [InlineData("+{Left}")]
    public void IsValidSendKeysContent_ValidToken_IsTrue(string token)
    {
        HotkeyRules.Tokens.IsValidSendKeysContent(token).Should().BeTrue();
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("Volume_Up")]          // named key MUST be braced
    [InlineData("*c")]                 // * is not a Send modifier
    [InlineData("^ab")]                // more than one key
    [InlineData("{{date:yyyy-MM-dd}}")]// macro leak — double brace
    [InlineData("{Up")]                // unbalanced brace
    [InlineData("^")]                  // modifiers with no key
    [InlineData("{NotAKey}")]          // braced unknown name
    public void IsValidSendKeysContent_InvalidToken_IsFalse(string? token)
    {
        HotkeyRules.Tokens.IsValidSendKeysContent(token).Should().BeFalse();
    }

    [Theory]
    [InlineData("Ctrl")]
    [InlineData("a")]
    [InlineData("vk1B")]
    public void IsValidRemapDest_Valid_IsTrue(string dest)
    {
        HotkeyRules.Tokens.IsValidRemapDest(dest).Should().BeTrue();
    }

    [Theory]
    [InlineData(null)]
    [InlineData("Pause")]              // built-in function name collision
    [InlineData("{Ctrl}")]             // no braces on a remap dest
    [InlineData("^a")]                 // no modifiers on a remap dest
    public void IsValidRemapDest_Invalid_IsFalse(string? dest)
    {
        HotkeyRules.Tokens.IsValidRemapDest(dest).Should().BeFalse();
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~HotkeyTokenRulesTests"`
Expected: FAIL — `HotkeyRules.Tokens` not defined.

- [ ] **Step 3: Add the `Tokens` grammar helper**

In `src/Backend/AHKFlowApp.Application/Validation/HotkeyRules.cs`, add `using AHKFlowApp.Application.Constants;` (already present) and a nested static class:

```csharp
    /// <summary>
    /// Pure token grammars for the two validated-token action kinds (spec §8). Public so validators
    /// and unit tests share exactly one implementation of each rule.
    /// </summary>
    public static class Tokens
    {
        /// <summary>
        /// A <c>SendKeys</c> token: optional <c>^ ! + #</c> modifiers (each at most once, any order;
        /// <c>*</c> is NOT a Send modifier) then exactly one key — a single printable character bare
        /// (<c>c</c>), or a registry key with the <see cref="HotkeyKeyRoles.SendToken"/> role braced
        /// (<c>{Volume_Up}</c>). A named key unbraced, a double-brace macro leak, and multiple keys
        /// are all rejected.
        /// </summary>
        public static bool IsValidSendKeysContent(string? content)
        {
            if (string.IsNullOrEmpty(content))
                return false;

            int i = 0;
            var seen = new HashSet<char>();
            while (i < content.Length && content[i] is '^' or '!' or '+' or '#')
            {
                if (!seen.Add(content[i]))
                    return false; // duplicate modifier
                i++;
            }

            string key = content[i..];
            if (key.Length == 0)
                return false; // modifiers but no key

            if (key[0] == '{')
            {
                if (key.Length < 3 || key[^1] != '}')
                    return false;
                string inner = key[1..^1];
                // Exactly one braced token: no nested/second brace (rejects {{date...}} and {a}{b}).
                if (inner.Length == 0 || inner.Contains('{') || inner.Contains('}'))
                    return false;
                return HotkeyKeys.TryCanonicalize(inner, out string canonical)
                    && HotkeyKeys.HotkeyKeyEntryByCanonical(canonical).Roles.HasFlag(HotkeyKeyRoles.SendToken);
            }

            // Bare: exactly one printable, non-brace, non-modifier character. Quote and backtick
            // stay valid here — Send can type them. They are hostile to the *string literal*, not
            // to Send, so the emitter escapes them (Task 5); this validator owns Send semantics only.
            return key.Length == 1 && !char.IsControl(key[0]) && key[0] is not '{' and not '}';
        }

        /// <summary>
        /// A <c>RemapDest</c> token: a single registry key with the <see cref="HotkeyKeyRoles.RemapDest"/>
        /// role, or a <c>vk</c>/<c>sc</c> code. No modifiers, no braces (spec §8).
        /// </summary>
        public static bool IsValidRemapDest(string? dest) => HotkeyKeys.IsValidRemapDest(dest);
    }
```

Note: `HotkeyKeyEntryByCanonical(inner)` is only reached after `TryCanonicalize` succeeds, but `TryCanonicalize` also accepts `vk`/`sc` codes (not in `s_byName`). Guard by looking the entry up safely — replace the braced return with:

```csharp
                if (!HotkeyKeys.TryCanonicalize(inner, out string canonical))
                    return false;
                // vk/sc codes are valid Send tokens; named keys must carry the SendToken role.
                return !HotkeyKeys.IsRegistryName(canonical)
                    || HotkeyKeys.HotkeyKeyEntryByCanonical(canonical).Roles.HasFlag(HotkeyKeyRoles.SendToken);
```

and add to `HotkeyKeys` a tiny predicate beside `HotkeyKeyEntryByCanonical`:

```csharp
    /// <summary>True if <paramref name="canonical"/> is a named registry entry (not a vk/sc code).</summary>
    public static bool IsRegistryName(string canonical) => s_byName.ContainsKey(canonical);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~HotkeyTokenRulesTests"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
dotnet format AHKFlowApp.slnx
git add src/Backend/AHKFlowApp.Application/Validation/HotkeyRules.cs \
        src/Backend/AHKFlowApp.Application/Constants/HotkeyKeys.cs \
        tests/AHKFlowApp.Application.Tests/Validation/HotkeyTokenRulesTests.cs
git commit -m "feat: SendKeys + RemapDest token grammars

pure §8 validators; * rejected as send modifier, named keys must brace"
```

---

### Task 4: Expand — typed columns, converter, Migration A, parity

The largest task. Adds the typed columns beside the legacy pair, back-fills them, and proves the migration's T-SQL agrees byte-for-byte with the C# converter. Existing emission is untouched (the W0 emitter still reads `Action`/`Parameters`), so this task changes stored data shape without changing any generated script.

**Files:**
- Modify: `src/Backend/AHKFlowApp.Domain/Entities/HotkeyDefinition.cs`
- Modify: `src/Backend/AHKFlowApp.Domain/Entities/Hotkey.cs:69-80` (`Apply`) + new properties
- Modify: `src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/HotkeyConfiguration.cs`
- Create: `src/Backend/AHKFlowApp.Application/Services/LegacyHotkeyDefinitionConverter.cs`
- Create: `tests/AHKFlowApp.TestUtilities/Fixtures/LegacyHotkeyFixtures.cs`
- Create: `tests/AHKFlowApp.Application.Tests/Services/LegacyHotkeyDefinitionConverterTests.cs`
- Create: `src/Backend/AHKFlowApp.Infrastructure/Migrations/<ts>_HotkeyTypedActions.cs` (via `dotnet ef`)
- Create: `tests/AHKFlowApp.Infrastructure.Tests/Migrations/HotkeyTypedActionsMigrationTests.cs`
- Modify: `tests/AHKFlowApp.TestUtilities/Builders/HotkeyBuilder.cs`

**Interfaces:**
- Consumes: `HotkeyActionKind`, `RunTargetKind` (Task 1); `HotkeyKeys.All`, `HotkeyKeys.Aliases`, `HotkeyKeys.HotkeyKeyEntryByCanonical` (Task 2); `HotkeyRules.Tokens.IsValidSendKeysContent`, `AhkEscaping.EscapeStringLiteral` (Task 3, W0).
- Produces:
  - `HotkeyDefinition` with trailing typed fields (defaulted): `HotkeyActionKind ActionKind = HotkeyActionKind.Raw, string? Text = null, string? SendKeysContent = null, string? RunTarget = null, RunTargetKind? RunTargetKind = null, WindowOp? WindowOp = null, string? RemapDest = null, string? Body = null` — **and the legacy `Action`/`Parameters` stay** through the cutover.
  - `Hotkey` typed properties mirroring those fields.
  - `LegacyHotkeyDefinitionConverter.ToTyped(HotkeyAction action, string parameters) : (HotkeyActionKind, string? Text, string? SendKeysContent, string? RunTarget, RunTargetKind?, WindowOp?, string? RemapDest, string? Body)` and `LegacyHotkeyDefinitionConverter.Apply(HotkeyDefinition legacy) : HotkeyDefinition` (returns the same definition with typed fields filled from its legacy pair).
  - `LegacyHotkeyFixtures.All : IReadOnlyList<LegacyHotkeyFixture>`.

- [ ] **Step 1: Extend `HotkeyDefinition` with typed fields**

`src/Backend/AHKFlowApp.Domain/Entities/HotkeyDefinition.cs`:

```csharp
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Domain.Entities;

/// <summary>
/// Definitional fields of a hotkey, grouped so factory signatures stay stable as actions and options
/// grow across the redesign waves. Mirrors <see cref="HotstringDefinition"/>.
/// </summary>
/// <remarks>
/// During Wave 1 the legacy <see cref="Action"/> / <see cref="Parameters"/> pair and the typed
/// columns coexist (expand phase). The legacy pair is removed in the contract task once every write
/// path and the emitter read the typed columns.
/// </remarks>
public sealed record HotkeyDefinition(
    string Description,
    string Key,
    bool Ctrl,
    bool Alt,
    bool Shift,
    bool Win,
    HotkeyAction Action,
    string Parameters,
    bool AppliesToAllProfiles,
    HotkeyActionKind ActionKind = HotkeyActionKind.Raw,
    string? Text = null,
    string? SendKeysContent = null,
    string? RunTarget = null,
    RunTargetKind? RunTargetKind = null,
    WindowOp? WindowOp = null,
    string? RemapDest = null,
    string? Body = null);
```

- [ ] **Step 2: Add typed properties + map them in `Apply`**

In `src/Backend/AHKFlowApp.Domain/Entities/Hotkey.cs`, add properties after `Parameters` (line 23):

```csharp
    public HotkeyActionKind ActionKind { get; private set; }
    public string? Text { get; private set; }
    public string? SendKeysContent { get; private set; }
    public string? RunTarget { get; private set; }
    public RunTargetKind? RunTargetKind { get; private set; }
    public WindowOp? WindowOp { get; private set; }
    public string? RemapDest { get; private set; }
    public string? Body { get; private set; }
```

Extend `Apply` (keep the legacy assignments):

```csharp
    private void Apply(HotkeyDefinition definition)
    {
        Description = definition.Description;
        Key = definition.Key;
        Ctrl = definition.Ctrl;
        Alt = definition.Alt;
        Shift = definition.Shift;
        Win = definition.Win;
        Action = definition.Action;
        Parameters = definition.Parameters;
        AppliesToAllProfiles = definition.AppliesToAllProfiles;
        ActionKind = definition.ActionKind;
        Text = definition.Text;
        SendKeysContent = definition.SendKeysContent;
        RunTarget = definition.RunTarget;
        RunTargetKind = definition.RunTargetKind;
        WindowOp = definition.WindowOp;
        RemapDest = definition.RemapDest;
        Body = definition.Body;
    }
```

Add `using AHKFlowApp.Domain.Enums;` if not already present (it is).

- [ ] **Step 3: Configure the typed columns**

In `src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/HotkeyConfiguration.cs`, after the `Parameters` property block:

```csharp
        builder.Property(x => x.ActionKind)
            .IsRequired()
            .HasConversion<int>();

        builder.Property(x => x.Text);                                    // nvarchar(max), nullable
        builder.Property(x => x.SendKeysContent).HasMaxLength(100);
        builder.Property(x => x.RunTarget).HasMaxLength(4000);
        builder.Property(x => x.RunTargetKind).HasConversion<int>();      // nullable int
        builder.Property(x => x.WindowOp).HasConversion<int>();           // nullable int
        builder.Property(x => x.RemapDest).HasMaxLength(50);
        builder.Property(x => x.Body);                                    // nvarchar(max), nullable
```

The unique index stays `(OwnerOid, Key, Ctrl, Alt, Shift, Win)` at W1 — combo/context columns are W2/W3.

- [ ] **Step 4: Write the converter's failing test**

Create `tests/AHKFlowApp.Application.Tests/Services/LegacyHotkeyDefinitionConverterTests.cs`:

```csharp
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;

namespace AHKFlowApp.Application.Tests.Services;

public sealed class LegacyHotkeyDefinitionConverterTests
{
    [Theory]
    [MemberData(nameof(Cases))]
    public void ToTyped_LegacyPair_MatchesFixtureExpectation(LegacyHotkeyFixture f)
    {
        var typed = LegacyHotkeyDefinitionConverter.ToTyped(f.Action, f.Parameters);

        typed.ActionKind.Should().Be(f.ExpectedKind, "fixture '{0}'", f.Name);
        typed.Text.Should().Be(f.ExpectedText, "fixture '{0}'", f.Name);
        typed.SendKeysContent.Should().Be(f.ExpectedSendKeysContent, "fixture '{0}'", f.Name);
        typed.RunTarget.Should().Be(f.ExpectedRunTarget, "fixture '{0}'", f.Name);
        typed.RunTargetKind.Should().Be(f.ExpectedRunTargetKind, "fixture '{0}'", f.Name);
        typed.Body.Should().Be(f.ExpectedBody, "fixture '{0}'", f.Name);
    }

    public static TheoryData<LegacyHotkeyFixture> Cases()
    {
        var data = new TheoryData<LegacyHotkeyFixture>();
        foreach (LegacyHotkeyFixture f in LegacyHotkeyFixtures.All)
            data.Add(f);
        return data;
    }
}
```

- [ ] **Step 5: Write the fixtures (seeded from the dev lazy-seed rows)**

The lazy-seed rows cover the hand-written cases (spec §11): a Run with arguments, a Run that isn't a path (`Reload`), a bare scheme (`https://`), clean one-token Sends (`{Up}`, `^v`) that become SendKeys, and a leaked macro token (`{{date:yyyy-MM-dd}}`) that falls back to Raw. They are **not** the whole set: the generated half below walks the entire accepted SendKeys grammar (canonical names, aliases, vk/sc codes, braced and bare printables) plus the values that grammar rejects (zero codes, lone control characters), because every one of those is a place the T-SQL classifier can drift from the C# one.

Create `tests/AHKFlowApp.TestUtilities/Fixtures/LegacyHotkeyFixtures.cs`:

```csharp
using AHKFlowApp.Application.Constants;
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.TestUtilities.Fixtures;

/// <summary>
/// One legacy-hotkey conversion case: the legacy (<see cref="Action"/>, <see cref="Parameters"/>)
/// pair plus the exact typed columns it must convert to. Shared by the C# converter test and the
/// EF migration parity test so the two transforms cannot drift.
/// </summary>
public sealed record LegacyHotkeyFixture(
    string Name,
    HotkeyAction Action,
    string Parameters,
    HotkeyActionKind ExpectedKind,
    string? ExpectedText,
    string? ExpectedSendKeysContent,
    string? ExpectedRunTarget,
    RunTargetKind? ExpectedRunTargetKind,
    string? ExpectedBody);

/// <summary>
/// Golden set guarding the two copies of the legacy→typed transform: the C# converter
/// (<c>LegacyHotkeyDefinitionConverter</c>) and the EF data migration's hand-written T-SQL.
/// Seeded from the dev lazy-seed rows (<c>ListHotkeysQuery.s_lazySeed</c>) — they already exercise
/// every branch. Mirrors <c>ScriptToRawFixtures</c>.
/// </summary>
public static class LegacyHotkeyFixtures
{
    public static IReadOnlyList<LegacyHotkeyFixture> All { get; } = Build();

    private static IReadOnlyList<LegacyHotkeyFixture> Build() =>
    [
        // Run → Application (default label).
        new("run-app", HotkeyAction.Run, "notepad.exe",
            HotkeyActionKind.Run, null, null, "notepad.exe", RunTargetKind.Application, null),
        new("run-app-with-args", HotkeyAction.Run, "rundll32.exe user32.dll,LockWorkStation",
            HotkeyActionKind.Run, null, null, "rundll32.exe user32.dll,LockWorkStation", RunTargetKind.Application, null),
        new("run-not-a-path", HotkeyAction.Run, "Reload",
            HotkeyActionKind.Run, null, null, "Reload", RunTargetKind.Application, null),
        // Run → Url on an http(s) prefix, including a bare scheme.
        new("run-url-bare-scheme", HotkeyAction.Run, "https://",
            HotkeyActionKind.Run, null, null, "https://", RunTargetKind.Url, null),
        new("run-url-full", HotkeyAction.Run, "https://github.com",
            HotkeyActionKind.Run, null, null, "https://github.com", RunTargetKind.Url, null),
        // Send that is a valid SendKeys token → SendKeys.
        new("send-braced-token", HotkeyAction.Send, "{Up}",
            HotkeyActionKind.SendKeys, null, "{Up}", null, null, null),
        new("send-ctrl-v", HotkeyAction.Send, "^v",
            HotkeyActionKind.SendKeys, null, "^v", null, null, null),
        // Send that is not a valid token → Raw, body preserving the current (W0-escaped) emission.
        new("send-macro-leak", HotkeyAction.Send, "{{date:yyyy-MM-dd}}",
            HotkeyActionKind.Raw, null, null, null, null, "Send(\"{{date:yyyy-MM-dd}}\")"),
        new("send-freeform", HotkeyAction.Send, "hello world",
            HotkeyActionKind.Raw, null, null, null, null, "Send(\"hello world\")"),
        new("send-with-quote", HotkeyAction.Send, "say \"hi\"",
            HotkeyActionKind.Raw, null, null, null, null, "Send(\"say `\"hi`\"\")"),
        new("send-with-backtick", HotkeyAction.Send, "100`%",
            HotkeyActionKind.Raw, null, null, null, null, "Send(\"100``%\")"),
        // ValidParameters permits exactly \n, \r and \t, so all three reach the back-fill.
        new("send-with-lf", HotkeyAction.Send, "a\nb",
            HotkeyActionKind.Raw, null, null, null, null, "Send(\"a`nb\")"),
        new("send-with-cr", HotkeyAction.Send, "a\rb",
            HotkeyActionKind.Raw, null, null, null, null, "Send(\"a`rb\")"),
        new("send-with-tab", HotkeyAction.Send, "a\tb",
            HotkeyActionKind.Raw, null, null, null, null, "Send(\"a`tb\")"),
        // A *lone* control character is also a legal Parameters value, and it hits the single-character
        // branch the three cases above never reach: C# rejects it (char.IsControl), so it must be Raw.
        // A naked `@klen = 1` test in T-SQL accepts it — these three pin that divergence.
        new("send-lone-lf", HotkeyAction.Send, "\n",
            HotkeyActionKind.Raw, null, null, null, null, "Send(\"`n\")"),
        new("send-lone-cr", HotkeyAction.Send, "\r",
            HotkeyActionKind.Raw, null, null, null, null, "Send(\"`r\")"),
        new("send-lone-tab", HotkeyAction.Send, "\t",
            HotkeyActionKind.Raw, null, null, null, null, "Send(\"`t\")"),
        // Trailing space: two characters, so not a bare token. Pins the T-SQL LEN() trap —
        // LEN('a ') is 1, which would misclassify this as SendKeys on the migration side only.
        new("send-trailing-space", HotkeyAction.Send, "a ",
            HotkeyActionKind.Raw, null, null, null, null, "Send(\"a \")"),
        new("send-unknown-braced-name", HotkeyAction.Send, "{NotAKey}",
            HotkeyActionKind.Raw, null, null, null, null, "Send(\"{NotAKey}\")"),
        // Trailing space *inside* the braces. TryCanonicalize does not trim, so this is Raw — but
        // T-SQL's IN pad-compares, and would match 'a' in the frozen name list without a guard.
        new("send-braced-trailing-space", HotkeyAction.Send, "{a }",
            HotkeyActionKind.Raw, null, null, null, null, "Send(\"{a }\")"),
        // A zero code names no key, so TryCanonicalize rejects it — both classifiers must say Raw.
        new("send-zero-vk-code", HotkeyAction.Send, "{vk0}",
            HotkeyActionKind.Raw, null, null, null, null, "Send(\"{vk0}\")"),
        new("send-zero-sc-code", HotkeyAction.Send, "{sc000}",
            HotkeyActionKind.Raw, null, null, null, null, "Send(\"{sc000}\")"),
        .. EverySendKeysToken(),
    ];

    // Every spelling the C# grammar accepts — not only `HotkeyKeys.All`. `IsValidSendKeysContent`
    // defers to `TryCanonicalize`, which also resolves aliases (Esc → Escape) and vk/sc codes, and
    // its bare branch takes any single printable character. The migration's frozen SQL classifier
    // must mirror all of that: a spelling accepted by one side and not the other silently splits
    // user data between SendKeys (snapshot restore) and Raw (migrated row).
    private static IEnumerable<LegacyHotkeyFixture> EverySendKeysToken()
    {
        // Braced registry names, bare and modified. Not filtered on RequiresBracesInSend: `{a}` is
        // braced-legal too, and the SQL name list must therefore carry the letters and digits.
        foreach (HotkeyKeyEntry e in HotkeyKeys.All.Where(e => e.Roles.HasFlag(HotkeyKeyRoles.SendToken)))
        {
            yield return SendKeysCase($"{{{e.Canonical}}}");
            yield return SendKeysCase($"^{{{e.Canonical}}}");
        }

        // The unbraced half of the same entries — the C# bare-character branch.
        foreach (HotkeyKeyEntry e in HotkeyKeys.All.Where(e =>
                     e.Roles.HasFlag(HotkeyKeyRoles.SendToken) && !e.RequiresBracesInSend))
        {
            yield return SendKeysCase(e.Canonical);
        }

        // Alias spellings resolve to a canonical entry, so {Esc} is SendKeys — the SQL list must
        // hold the alias itself, since the migration never canonicalizes.
        foreach (string alias in HotkeyKeys.Aliases
                     .Where(kv => HotkeyKeys.HotkeyKeyEntryByCanonical(kv.Value).Roles.HasFlag(HotkeyKeyRoles.SendToken))
                     .Select(kv => kv.Key))
        {
            yield return SendKeysCase($"{{{alias}}}");
        }

        // vk/sc codes: accepted by TryCanonicalize, not registry names, so no role check applies.
        // Both widths and both cases, since the grammar is width-tolerant and case-insensitive.
        string[] codes = ["vk1", "vk01", "vkFF", "sc1", "sc001", "sc01B"];
        foreach (string code in codes)
            yield return SendKeysCase($"{{{code}}}");
    }

    private static LegacyHotkeyFixture SendKeysCase(string token) =>
        new($"send-token-{token}", HotkeyAction.Send, token,
            HotkeyActionKind.SendKeys, null, token, null, null, null);
}
```

`HotkeyKeys` is `internal`, and `AHKFlowApp.Application.csproj` grants `InternalsVisibleTo` to
`AHKFlowApp.Application.Tests` only — not to `AHKFlowApp.TestUtilities`, where the fixtures live.
Add a second `<InternalsVisibleTo Include="AHKFlowApp.TestUtilities" />` in the same item group.

> **Design decision (open question O2).** The `Raw` body reproduces the **W0-escaped** RHS (`Send("say `"hi`"")`), not the spec's pre-W0 unescaped text, so the generated download for a converted row is unchanged from what W0 emits today. Confirm before executing (see Unresolved questions).

- [ ] **Step 6: Write the converter**

Create `src/Backend/AHKFlowApp.Application/Services/LegacyHotkeyDefinitionConverter.cs`:

```csharp
using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.Services;

/// <summary>
/// Converts a legacy hotkey (two-value <see cref="HotkeyAction"/> + free <c>Parameters</c>) into the
/// typed W1 columns. The single C# home of the transform, shared by the write paths (expand phase)
/// and history restore/revert. The EF data migration hand-writes the same logic in T-SQL; a
/// Testcontainers parity test proves the two agree. Mirrors <c>ScriptToRawComposer</c>.
/// </summary>
/// <remarks>
/// Rules (spec §8): <c>Run</c> → <see cref="HotkeyActionKind.Run"/> with <c>RunTarget = Parameters</c>
/// and <c>RunTargetKind = Url</c> for an <c>http(s)://</c> prefix else <see cref="RunTargetKind.Application"/>;
/// <c>Send</c> that is a valid SendKeys token → <see cref="HotkeyActionKind.SendKeys"/>; every other
/// <c>Send</c> → <see cref="HotkeyActionKind.Raw"/> with a body reproducing the current escaped
/// emission byte-for-byte.
/// </remarks>
public static class LegacyHotkeyDefinitionConverter
{
    public readonly record struct TypedAction(
        HotkeyActionKind ActionKind,
        string? Text,
        string? SendKeysContent,
        string? RunTarget,
        RunTargetKind? RunTargetKind,
        WindowOp? WindowOp,
        string? RemapDest,
        string? Body);

    public static TypedAction ToTyped(HotkeyAction action, string parameters) => action switch
    {
        HotkeyAction.Run => new TypedAction(
            HotkeyActionKind.Run, null, null, parameters, RunTargetKindFor(parameters), null, null, null),

        HotkeyAction.Send when HotkeyRules.Tokens.IsValidSendKeysContent(parameters) => new TypedAction(
            HotkeyActionKind.SendKeys, null, parameters, null, null, null, null, null),

        _ => new TypedAction(
            HotkeyActionKind.Raw, null, null, null, null, null, null,
            $"Send(\"{AhkEscaping.EscapeStringLiteral(parameters)}\")"),
    };

    /// <summary>Returns <paramref name="legacy"/> with its typed fields filled from its legacy pair.</summary>
    public static HotkeyDefinition Apply(HotkeyDefinition legacy)
    {
        TypedAction t = ToTyped(legacy.Action, legacy.Parameters);
        return legacy with
        {
            ActionKind = t.ActionKind,
            Text = t.Text,
            SendKeysContent = t.SendKeysContent,
            RunTarget = t.RunTarget,
            RunTargetKind = t.RunTargetKind,
            WindowOp = t.WindowOp,
            RemapDest = t.RemapDest,
            Body = t.Body,
        };
    }

    private static RunTargetKind RunTargetKindFor(string parameters) =>
        parameters.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
        || parameters.StartsWith("https://", StringComparison.OrdinalIgnoreCase)
            ? Domain.Enums.RunTargetKind.Url
            : Domain.Enums.RunTargetKind.Application;
}
```

- [ ] **Step 7: Route the write paths through the converter**

So new rows carry typed columns too (not only migrated rows), wrap each `new HotkeyDefinition(...)` construction in the five write paths with `LegacyHotkeyDefinitionConverter.Apply(...)`. Add `using AHKFlowApp.Application.Services;` where missing.

`CreateHotkeyCommand.cs` — wrap the `Hotkey.Create` definition:

```csharp
        var entity = Hotkey.Create(
            ownerOid,
            LegacyHotkeyDefinitionConverter.Apply(new HotkeyDefinition(
                Description: input.Description, Key: canonicalKey,
                Ctrl: input.Ctrl, Alt: input.Alt, Shift: input.Shift, Win: input.Win,
                Action: input.Action, Parameters: input.Parameters,
                AppliesToAllProfiles: input.AppliesToAllProfiles)),
            clock);
```

Every `HotkeyDefinition` construction in this plan names its arguments — the record is nine
same-shaped parameters today and seventeen after Step 1, four of them adjacent `bool`s. Positional
calls there are a swap waiting to happen, and the compiler cannot see it.

Apply the same `LegacyHotkeyDefinitionConverter.Apply(new HotkeyDefinition(...))` wrap in:
- `UpdateHotkeyCommand.cs` (`entity.Update`)
- `RestoreHotkeyCommand.cs` (`Hotkey.Restore`)
- `RevertHotkeyCommand.cs` (`entity.Update`)
- `ListHotkeysQuery.cs` `EnsureHotkeysSeededAsync` (`Hotkey.Create` in the seed loop)
- `SeedHotkeysCommand.cs` (`Hotkey.Create` in the sample loop)

`HotkeyBuilder.Build()` — same wrap, so every test entity has typed columns:

```csharp
        var entity = Hotkey.Create(
            _ownerOid,
            LegacyHotkeyDefinitionConverter.Apply(new HotkeyDefinition(
                Description: _description, Key: _key,
                Ctrl: _ctrl, Alt: _alt, Shift: _shift, Win: _win,
                Action: _action, Parameters: _parameters,
                AppliesToAllProfiles: _appliesToAllProfiles)),
            _clock);
```

- [ ] **Step 8: Run the converter + solution build**

```bash
dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~LegacyHotkeyDefinitionConverterTests"
dotnet build AHKFlowApp.slnx --configuration Release
```
Expected: converter tests PASS; solution builds (typed columns are additive; nothing reads them yet).

- [ ] **Step 9: Generate Migration A**

```bash
dotnet ef migrations add HotkeyTypedActions \
  --project src/Backend/AHKFlowApp.Infrastructure \
  --startup-project src/Backend/AHKFlowApp.API
```

Open the generated `<ts>_HotkeyTypedActions.cs`. EF will scaffold the `AddColumn` calls (ActionKind non-nullable int default 0, plus the nullable typed columns). **Add the back-fill T-SQL at the end of `Up`**, after the columns exist, mirroring `LegacyHotkeyDefinitionConverter` (Run→2, Send-token→1, else Raw→6). It is a hand-written copy of the converter — the parity test (Step 10) proves they agree:

```csharp
        // Back-fill typed columns from the legacy (Action, Parameters) pair. Hand-written mirror of
        // LegacyHotkeyDefinitionConverter; the Infrastructure parity test proves byte-identical output.
        // Legacy Action: Send = 0, Run = 1.
        migrationBuilder.Sql(@"
-- Run → Run(2): RunTarget = Parameters, RunTargetKind = Url(1) for http(s) else Application(0).
UPDATE [Hotkeys]
SET [ActionKind] = 2,
    [RunTarget] = [Parameters],
    [RunTargetKind] = CASE
        WHEN [Parameters] LIKE 'http://%' OR [Parameters] LIKE 'https://%' THEN 1 ELSE 0 END
WHERE [Action] = 1;");

        migrationBuilder.Sql(@"
-- Send that is a valid SendKeys token → SendKeys(1). The token grammar, expressed in T-SQL, must
-- match HotkeyRules.Tokens.IsValidSendKeysContent for the fixture contract (see parity test):
--   optional ^ ! + # modifiers, then either exactly one printable char, or a single {Name} braced
--   token containing no further brace. Rejects {{...}} macro leaks and multi-key content.
UPDATE [Hotkeys]
SET [ActionKind] = 1,
    [SendKeysContent] = [Parameters]
WHERE [Action] = 0
  AND [dbo].[fn_IsSendKeysContent]([Parameters]) = 1;");

        migrationBuilder.Sql(@"
-- Every remaining Send → Raw(6): body reproduces the current escaped emission byte-for-byte.
-- All five AhkEscaping replacements, in its exact order: backtick first (so it cannot re-escape
-- the backticks the later rules introduce), then double-quote, LF, CR, tab. \n/\r/\t are NOT
-- excluded from Parameters — HotkeyRules.ValidParameters allows exactly those three control
-- characters — so dropping them here would emit a literal newline inside the string literal and
-- break the script.
UPDATE [Hotkeys]
SET [ActionKind] = 6,
    [Body] = 'Send(""' +
        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
            [Parameters], '`', '``'), '""', '`""'),
            CHAR(10), '`n'), CHAR(13), '`r'), CHAR(9), '`t') +
        '"")'
WHERE [Action] = 0 AND [ActionKind] <> 1;");
```

Because the SendKeys grammar is awkward in inline SQL, define a scalar function in the **same** `Up` **before** the back-fill and drop it after (keeps the classifier readable and testable):

```csharp
        migrationBuilder.Sql(@"
CREATE FUNCTION [dbo].[fn_IsSendKeysContent](@s NVARCHAR(4000))
RETURNS BIT
AS
BEGIN
    -- LEN() ignores trailing spaces, so every length here goes through the + N'|' - 1 idiom.
    -- Without it 'a ' measures as 1 and classifies as SendKeys, while the C# grammar sees two
    -- characters and sends it to Raw — a silent parity break on any value with a trailing space.
    DECLARE @n INT = LEN(@s + N'|') - 1;
    IF @s IS NULL OR @n = 0 RETURN 0;
    DECLARE @i INT = 1;
    -- consume optional distinct modifiers ^ ! + #
    DECLARE @seen NVARCHAR(4) = '';
    WHILE @i <= @n AND SUBSTRING(@s, @i, 1) IN ('^','!','+','#')
    BEGIN
        IF CHARINDEX(SUBSTRING(@s, @i, 1), @seen) > 0 RETURN 0;
        SET @seen = @seen + SUBSTRING(@s, @i, 1);
        SET @i = @i + 1;
    END
    DECLARE @key NVARCHAR(4000) = SUBSTRING(@s, @i, @n - @i + 1);
    DECLARE @klen INT = @n - @i + 1;
    IF @klen = 0 RETURN 0;
    IF LEFT(@key, 1) = '{'
    BEGIN
        IF SUBSTRING(@key, @klen, 1) <> '}' OR @klen < 3 RETURN 0;
        DECLARE @inner NVARCHAR(4000) = SUBSTRING(@key, 2, @klen - 2);
        DECLARE @ilen INT = LEN(@inner + N'|') - 1;
        IF CHARINDEX('{', @inner) > 0 OR CHARINDEX('}', @inner) > 0 RETURN 0;
        -- Second face of the trailing-space trap: SQL '=' and IN pad-compare, so '{a }' would match
        -- 'a' in the list below, while TryCanonicalize does not trim and sends it to Raw. LIKE does
        -- not pad-compare, so the vk/sc patterns need no equivalent guard.
        IF RIGHT(@inner, 1) = ' ' RETURN 0;
        -- Exhaustive: every spelling TryCanonicalize resolves to a SendToken entry as of Migration A
        -- — canonical names *and* alias spellings (Esc, Return, Del, …), letters and digits included
        -- ({a} is braced-legal), because the migration never canonicalizes. Generated, not hand-typed
        -- (see below), and frozen once the migration ships. A subset here would classify {F5} /
        -- {Enter} / {Esc} as Raw in the database while the C# converter — which consults the whole
        -- registry through TryCanonicalize — calls them SendKeys, so a snapshot restore would
        -- disagree with the migrated row for the same value.
        IF @inner COLLATE Latin1_General_CI_AS IN (<generated name list>) RETURN 1;
        -- vk/sc codes are accepted braced by the C# grammar with no role check: they are not
        -- registry names, so IsRegistryName is false and IsValidSendKeysContent short-circuits true.
        -- LIKE is not width- or case-tolerant on its own, hence one pattern per accepted width.
        IF @inner COLLATE Latin1_General_CI_AS LIKE 'vk[0-9a-f]'
           OR @inner COLLATE Latin1_General_CI_AS LIKE 'vk[0-9a-f][0-9a-f]'
           OR @inner COLLATE Latin1_General_CI_AS LIKE 'sc[0-9a-f]'
           OR @inner COLLATE Latin1_General_CI_AS LIKE 'sc[0-9a-f][0-9a-f]'
           OR @inner COLLATE Latin1_General_CI_AS LIKE 'sc[0-9a-f][0-9a-f][0-9a-f]'
        BEGIN
            -- An all-zero code names no key (TryCanonicalizeCode rejects it). The digits are
            -- already known hex, so ""all zero"" is ""contains no 1-9a-f"". LIKE never ignores
            -- trailing spaces, so the patterns above guarantee @ilen counts real characters.
            IF SUBSTRING(@inner, 3, @ilen - 2) COLLATE Latin1_General_CI_AS NOT LIKE '%[1-9a-f]%'
                RETURN 0;
            RETURN 1;
        END
        RETURN 0;
    END
    -- bare: exactly one printable non-brace char. UNICODE() < 32 and 127 are the control characters
    -- char.IsControl rejects in C#; ValidParameters lets \n, \r and \t into Parameters, so a lone
    -- one of those reaches here and must fall through to Raw.
    IF @klen = 1 AND @key NOT IN ('{','}') AND UNICODE(@key) >= 32 AND UNICODE(@key) <> 127 RETURN 1;
    RETURN 0;
END;");

        // ... the three back-fill UPDATE statements above ...

        migrationBuilder.Sql(@"DROP FUNCTION [dbo].[fn_IsSendKeysContent];");
```

Produce `<generated name list>` once, from the registry itself, and paste the literal into the migration — never hand-type it. It covers **every spelling `TryCanonicalize` resolves**, which is wider than `HotkeyKeys.All`: canonical names (no `RequiresBracesInSend` filter — `{a}` is legal braced) plus the alias keys. In a scratch xUnit fact or `dotnet script`:

```csharp
IEnumerable<string> canonical = HotkeyKeys.All
    .Where(e => e.Roles.HasFlag(HotkeyKeyRoles.SendToken))
    .Select(e => e.Canonical);

IEnumerable<string> aliases = HotkeyKeys.Aliases
    .Where(kv => HotkeyKeys.HotkeyKeyEntryByCanonical(kv.Value).Roles.HasFlag(HotkeyKeyRoles.SendToken))
    .Select(kv => kv.Key);

string list = string.Join(", ", canonical.Concat(aliases)
    .Select(n => $"'{n}'")
    .Order(StringComparer.Ordinal));
```

`HotkeyKeys.Aliases` is the accessor added in Task 2. vk/sc codes are *not* in the list — the function matches them by shape, since enumerating every code is neither finite-friendly nor frozen-friendly.

The pasted list is **frozen** at Migration A: a shipped migration must reproduce byte-identically forever. Later waves that add `SendToken` names (W2 mouse/wheel) do **not** edit this migration — the parity test below fails loudly instead, which is the signal to decide between a top-up migration and accepting Raw for the new names.

> **Design decision (open question O3, revised twice).** The T-SQL classifier mirrors the **whole
> accepted C# grammar**, not a name subset: the generated list of every SendToken canonical *and
> alias*, a shape match for vk/sc codes, and a control-character exclusion on the bare branch —
> all frozen at Migration A. Two earlier shapes were wrong. The original fixed seven-name list
> only covered the dev-seed names, so user rows holding `{F5}` or `{Enter}` migrated to Raw. The
> follow-up `SendToken && RequiresBracesInSend` list still dropped four classes the C# grammar
> accepts: aliases (`{Esc}`), vk/sc codes (`{vk1}`), braced printable characters (`{a}`), and —
> in the other direction — the bare branch accepted a lone `\n`/`\r`/`\t` that `char.IsControl`
> rejects in C#. Each is a value `LegacyHotkeySnapshotConverter` and the migrated row would
> classify differently, so a history restore disagrees with the row it restores over. The parity
> fixtures (Step 10) now iterate the full grammar, so any of the four fails the build instead of
> shipping a silent split.

Set `Down` to `throw new NotSupportedException(...)` (the back-fill is lossy in reverse; the column drops happen in Migration B), mirroring `RawHotstringKind.Down`.

- [ ] **Step 10: Write the migration parity test**

Create `tests/AHKFlowApp.Infrastructure.Tests/Migrations/HotkeyTypedActionsMigrationTests.cs` (model on `RawHotstringKindMigrationTests`). Seed legacy rows (Action int + Parameters) against the schema **before** `HotkeyTypedActions`, apply the migration, then assert each row's typed columns equal `LegacyHotkeyDefinitionConverter.ToTyped`:

```csharp
using AHKFlowApp.Application.Services;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace AHKFlowApp.Infrastructure.Tests.Migrations;

/// <summary>
/// Proves the HotkeyTypedActions migration's hand-written back-fill T-SQL agrees with
/// <c>LegacyHotkeyDefinitionConverter</c> over every <c>LegacyHotkeyFixtures</c> row.
/// </summary>
[Collection("SqlServer")]
public sealed class HotkeyTypedActionsMigrationTests(SqlContainerFixture sqlFixture)
{
    private const string DbName = "HotkeyTypedActions_Parity";

    private AppDbContext CreateContext()
    {
        SqlConnectionStringBuilder csb = new(sqlFixture.ConnectionString) { InitialCatalog = DbName };
        DbContextOptions<AppDbContext> options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(csb.ConnectionString, sql => sql.EnableRetryOnFailure())
            .Options;
        return new AppDbContext(options);
    }

    [Fact]
    public async Task Migration_BackfillsTypedColumns_MatchingConverter()
    {
        Dictionary<Guid, LegacyHotkeyFixture> seeded = [];

        await using (AppDbContext setup = CreateContext())
        {
            // Migrate up to the migration immediately before HotkeyTypedActions.
            IMigrator migrator = ((IInfrastructure<IServiceProvider>)setup).Instance.GetRequiredService<IMigrator>();
            await migrator.MigrateAsync("AddHotstringDelivery");

            foreach (LegacyHotkeyFixture f in LegacyHotkeyFixtures.All)
            {
                var id = Guid.NewGuid();
                var owner = Guid.NewGuid(); // unique owner so duplicate key+mods don't collide
                seeded[id] = f;

                await setup.Database.ExecuteSqlRawAsync(
                    """
                    INSERT INTO Hotkeys
                        (Id, OwnerOid, Description, [Key], Ctrl, Alt, Shift, Win,
                         Action, Parameters, AppliesToAllProfiles, CreatedAt, UpdatedAt)
                    VALUES
                        (@id, @owner, @descr, 'a', 0, 0, 0, 0,
                         @action, @params, 1, SYSDATETIMEOFFSET(), SYSDATETIMEOFFSET());
                    """,
                    new SqlParameter("@id", id),
                    new SqlParameter("@owner", owner),
                    new SqlParameter("@descr", f.Name),
                    new SqlParameter("@action", (int)f.Action),
                    new SqlParameter("@params", f.Parameters));
            }

            await setup.Database.MigrateAsync(); // apply HotkeyTypedActions
        }

        await using AppDbContext verify = CreateContext();

        foreach ((Guid id, LegacyHotkeyFixture f) in seeded)
        {
            Domain.Entities.Hotkey row = await verify.Hotkeys.AsNoTracking().SingleAsync(h => h.Id == id);
            var expected = LegacyHotkeyDefinitionConverter.ToTyped(f.Action, f.Parameters);

            row.ActionKind.Should().Be(expected.ActionKind, "fixture '{0}'", f.Name);
            row.SendKeysContent.Should().Be(expected.SendKeysContent, "fixture '{0}'", f.Name);
            row.RunTarget.Should().Be(expected.RunTarget, "fixture '{0}'", f.Name);
            row.RunTargetKind.Should().Be(expected.RunTargetKind, "fixture '{0}'", f.Name);
            row.Body.Should().Be(expected.Body, "fixture '{0}'", f.Name);
        }
    }
}
```

- [ ] **Step 11: Run parity + full suite**

```bash
dotnet test tests/AHKFlowApp.Infrastructure.Tests --filter "FullyQualifiedName~HotkeyTypedActionsMigrationTests"
dotnet test AHKFlowApp.slnx --configuration Release
```
Expected: parity PASS; full suite PASS (existing behavior unchanged — emitter still reads the legacy pair).

- [ ] **Step 12: Commit**

```bash
dotnet format AHKFlowApp.slnx
git add -A
git commit -m "feat: expand hotkey schema to typed action columns

add ActionKind + typed columns beside legacy pair; migration back-fills via
parity-tested converter. refs hotkey-redesign W1"
```

---

### Task 5: Per-kind HotkeyEmitter

Switches emission onto the typed columns. Old Send/Run goldens become their typed equivalents (SendKeys/Run/Raw); the new goldens are the §7 examples W1 can prove without combo/mouse/toggle/context (1, 2, 4–13, 15, and the Raw body of 10).

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Services/HotkeyEmitter.cs`
- Modify: `tests/AHKFlowApp.Application.Tests/Services/HotkeyEmitterTests.cs`
- Modify: `tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorTests.cs` (goldens that pinned the old Send/Run lines)
- Modify: `tests/AHKFlowApp.TestUtilities/Builders/HotkeyBuilder.cs` (typed `With*` methods)

**Interfaces:**
- Consumes: typed `Hotkey` columns (Task 4); `AhkEscaping.EscapeStringLiteral` (W0); `HotkeyKeys.HotkeyKeyEntryByCanonical` (Task 2).
- Produces: `HotkeyEmitter.Emit(Hotkey)` over `ActionKind`.

- [ ] **Step 1: Add typed builder methods**

In `tests/AHKFlowApp.TestUtilities/Builders/HotkeyBuilder.cs`, add fluent setters that populate the typed definition fields directly (bypassing the legacy converter so a test can assert a specific kind). Add private typed fields defaulting to null and a nullable `HotkeyActionKind? _actionKind`, plus:

```csharp
    public HotkeyBuilder WithSendText(string text)
    {
        _actionKind = HotkeyActionKind.SendText; _text = text; return this;
    }

    public HotkeyBuilder WithSendKeys(string content)
    {
        _actionKind = HotkeyActionKind.SendKeys; _sendKeysContent = content; return this;
    }

    public HotkeyBuilder WithRun(string target, RunTargetKind kind = RunTargetKind.Application)
    {
        _actionKind = HotkeyActionKind.Run; _runTarget = target; _runTargetKind = kind; return this;
    }

    public HotkeyBuilder WithWindow(WindowOp op)
    {
        _actionKind = HotkeyActionKind.Window; _windowOp = op; return this;
    }

    public HotkeyBuilder WithRemap(string dest)
    {
        _actionKind = HotkeyActionKind.Remap; _remapDest = dest; return this;
    }

    public HotkeyBuilder WithDisable()
    {
        _actionKind = HotkeyActionKind.Disable; return this;
    }

    public HotkeyBuilder WithRawBody(string body)
    {
        _actionKind = HotkeyActionKind.Raw; _body = body; return this;
    }
```

In `Build()`, when `_actionKind` is set, construct the typed `HotkeyDefinition` directly (do **not** route through `LegacyHotkeyDefinitionConverter`); otherwise keep the legacy path from Task 4:

```csharp
        HotkeyDefinition definition = _actionKind is HotkeyActionKind kind
            ? new HotkeyDefinition(
                Description: _description, Key: _key,
                Ctrl: _ctrl, Alt: _alt, Shift: _shift, Win: _win,
                Action: _action, Parameters: _parameters,
                AppliesToAllProfiles: _appliesToAllProfiles,
                ActionKind: kind, Text: _text, SendKeysContent: _sendKeysContent,
                RunTarget: _runTarget, RunTargetKind: _runTargetKind, WindowOp: _windowOp,
                RemapDest: _remapDest, Body: _body)
            : LegacyHotkeyDefinitionConverter.Apply(new HotkeyDefinition(
                Description: _description, Key: _key,
                Ctrl: _ctrl, Alt: _alt, Shift: _shift, Win: _win,
                Action: _action, Parameters: _parameters,
                AppliesToAllProfiles: _appliesToAllProfiles));

        var entity = Hotkey.Create(_ownerOid, definition, _clock);
```

- [ ] **Step 2: Rewrite the emitter test around typed kinds**

Replace `tests/AHKFlowApp.Application.Tests/Services/HotkeyEmitterTests.cs` with kind-driven goldens:

```csharp
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.TestUtilities.Builders;
using FluentAssertions;

namespace AHKFlowApp.Application.Tests.Services;

public sealed class HotkeyEmitterTests
{
    [Fact] // golden 1
    public void Emit_Run_App() =>
        Line(new HotkeyBuilder().WithKey("n").WithWin().WithRun("notepad"))
            .Should().Be("#n::Run(\"notepad\")");

    [Fact] // golden 4 — URL is the same emission as app
    public void Emit_Run_Url() =>
        Line(new HotkeyBuilder().WithKey("j").WithWin().WithRun("https://github.com", RunTargetKind.Url))
            .Should().Be("#j::Run(\"https://github.com\")");

    [Fact] // golden 5
    public void Emit_Window_AlwaysOnTop() =>
        Line(new HotkeyBuilder().WithKey("Space").WithCtrl().WithWindow(WindowOp.ToggleAlwaysOnTop))
            .Should().Be("^Space::WinSetAlwaysOnTop(-1, \"A\")");

    [Fact] // golden 6
    public void Emit_Window_Minimize() =>
        Line(new HotkeyBuilder().WithKey("Down").WithWin().WithWindow(WindowOp.Minimize))
            .Should().Be("#Down::WinMinimize(\"A\")");

    [Fact] // golden 8
    public void Emit_Window_Close() =>
        Line(new HotkeyBuilder().WithKey("w").WithCtrl().WithAlt().WithWindow(WindowOp.Close))
            .Should().Be("^!w::WinClose(\"A\")");

    [Fact] // golden 9 — SendText escapes free text (backtick-n from a newline)
    public void Emit_SendText_EscapesMultiline() =>
        Line(new HotkeyBuilder().WithKey("s").WithCtrl().WithAlt().WithSendText("Jane Smith\nAcme"))
            .Should().Be("^!s::SendText(\"Jane Smith`nAcme\")");

    [Fact] // golden 11 — SendKeys gets the auto $ prefix on a keyboard key
    public void Emit_SendKeys_MediaKey_AutoDollar() =>
        Line(new HotkeyBuilder().WithKey("p").WithWin().WithSendKeys("{Media_Play_Pause}"))
            .Should().Be("$#p::Send(\"{Media_Play_Pause}\")");

    // Quote and backtick are valid one-character SendKeys tokens; unescaped they would emit
    // Send(""") and Send("`") — both refuse to load. Escaping happens at the literal layer.
    [Theory]
    [InlineData("\"", "$a::Send(\"`\"\")")]
    [InlineData("`", "$a::Send(\"``\")")]
    public void Emit_SendKeys_EscapesLiteralHostileToken(string token, string expected) =>
        Line(new HotkeyBuilder().WithKey("a").WithSendKeys(token))
            .Should().Be(expected);

    [Fact] // golden 13
    public void Emit_Remap_BareKey() =>
        Line(new HotkeyBuilder().WithKey("CapsLock").WithRemap("Ctrl"))
            .Should().Be("CapsLock::Ctrl");

    [Fact] // golden 15
    public void Emit_Disable() =>
        Line(new HotkeyBuilder().WithKey("F1").WithDisable())
            .Should().Be("F1::return");

    [Fact] // golden 10 body — Raw wraps a verbatim body in braces
    public void Emit_Raw_WrapsBody() =>
        Line(new HotkeyBuilder().WithKey("v").WithCtrl().WithShift().WithRawBody("\n\tSendText A_Clipboard\n"))
            .Should().Be("^+v::{\n\tSendText A_Clipboard\n}");

    [Fact]
    public void Emit_UnsupportedKind_Throws()
    {
        Hotkey hk = new HotkeyBuilder().WithKey("a").Build();
        typeof(Hotkey).GetProperty("ActionKind")!.SetValue(hk, (HotkeyActionKind)99);

        Action act = () => HotkeyEmitter.Emit(hk);

        act.Should().Throw<InvalidOperationException>().WithMessage("*99*");
    }

    private static string Line(HotkeyBuilder b) => HotkeyEmitter.Emit(b.Build());
}
```

- [ ] **Step 3: Run to verify failure**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~HotkeyEmitterTests"`
Expected: FAIL — emitter still switches on `Action` (Send/Run), so kinds like Window/Remap throw or mis-emit.

- [ ] **Step 4: Rewrite the emitter**

Replace `src/Backend/AHKFlowApp.Application/Services/HotkeyEmitter.cs`:

```csharp
using AHKFlowApp.Application.Constants;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.Services;

/// <summary>
/// Single emission point for hotkey lines, mirroring <see cref="HotstringEmitter"/>. The left-hand
/// side is the auto <c>$</c> (SendKeys on a keyboard key) + modifiers in the fixed order <c>^ ! + #</c>
/// + the key; the right-hand side is per <see cref="HotkeyActionKind"/> (spec §1).
/// </summary>
/// <remarks>
/// Everything embedded in a quoted literal (<c>SendText</c>, <c>SendKeys</c>, <c>Run</c>) passes
/// through <see cref="AhkEscaping.EscapeStringLiteral"/>. Token validation and string-literal
/// escaping are separate layers: <c>"</c> and <c>`</c> are legal one-character SendKeys tokens
/// (Send types them), so a validated token still has to be escaped or it terminates the literal.
/// Remap emits a bare validated key name — no literal, nothing to escape. Raw wraps a verbatim
/// body in braces — the sole unchecked path.
/// </remarks>
internal static class HotkeyEmitter
{
    private const string ActiveWindow = "\"A\"";

    public static string Emit(Hotkey hk)
    {
        string rhs = hk.ActionKind switch
        {
            HotkeyActionKind.SendText => $"SendText(\"{AhkEscaping.EscapeStringLiteral(hk.Text ?? "")}\")",
            HotkeyActionKind.SendKeys => $"Send(\"{AhkEscaping.EscapeStringLiteral(hk.SendKeysContent ?? "")}\")",
            HotkeyActionKind.Run => $"Run(\"{AhkEscaping.EscapeStringLiteral(hk.RunTarget ?? "")}\")",
            HotkeyActionKind.Window => WindowCall(hk.WindowOp),
            HotkeyActionKind.Remap => hk.RemapDest ?? "",
            HotkeyActionKind.Disable => "return",
            HotkeyActionKind.Raw => $"{{{hk.Body}}}",
            _ => throw new InvalidOperationException($"Unsupported HotkeyActionKind: {hk.ActionKind}"),
        };

        return $"{Prefix(hk)}{BuildModifiers(hk)}{hk.Key}::{rhs}";
    }

    private static string WindowCall(WindowOp? op) => op switch
    {
        WindowOp.Minimize => $"WinMinimize({ActiveWindow})",
        WindowOp.Maximize => $"WinMaximize({ActiveWindow})",
        WindowOp.Restore => $"WinRestore({ActiveWindow})",
        WindowOp.Close => $"WinClose({ActiveWindow})",
        WindowOp.ToggleAlwaysOnTop => $"WinSetAlwaysOnTop(-1, {ActiveWindow})",
        _ => throw new InvalidOperationException($"Unsupported WindowOp: {op}"),
    };

    // $ forces the keyboard hook so a SendKeys binding cannot retrigger the script's own hotkeys
    // (spec §5). Emitted for every SendKeys on a keyboard key. Mouse/wheel keys (Wave 2) use the
    // mouse hook already and get no $ — until then, all registry keys are keyboard keys.
    private static string Prefix(Hotkey hk) =>
        hk.ActionKind == HotkeyActionKind.SendKeys ? "$" : "";

    private static string BuildModifiers(Hotkey hk)
    {
        string modifiers = "";
        if (hk.Ctrl) modifiers += "^";
        if (hk.Alt) modifiers += "!";
        if (hk.Shift) modifiers += "+";
        if (hk.Win) modifiers += "#";
        return modifiers;
    }
}
```

- [ ] **Step 5: Update the generator characterization goldens**

In `tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorTests.cs`, any test that built a hotkey via the legacy `WithAction(HotkeyAction.Send/Run).WithParameters(...)` and pinned `Send("...")`/`Run("...")` now emits the typed equivalent. Convert those builders to the typed `WithRun(...)` / `WithSendText(...)` and update the expected line. The W0 escaping golden `Generate_Hotkey_EscapesParametersInStringLiteral` becomes a `WithSendText("he said \"hi\"")` asserting `^a::SendText("he said `"hi`"")` (SendText, not Send). Keep hotstring goldens untouched.

- [ ] **Step 6: Run generator + emitter suites**

```bash
dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~HotkeyEmitterTests|FullyQualifiedName~AhkScriptGeneratorTests"
```
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
dotnet format AHKFlowApp.slnx
git add src/Backend/AHKFlowApp.Application/Services/HotkeyEmitter.cs \
        tests/AHKFlowApp.Application.Tests/Services/HotkeyEmitterTests.cs \
        tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorTests.cs \
        tests/AHKFlowApp.TestUtilities/Builders/HotkeyBuilder.cs
git commit -m "feat: per-kind hotkey emission over typed columns

SendText/SendKeys/Run/Window/Remap/Disable/Raw; auto \$ for SendKeys. refs W1"
```

---

### Task 6: Typed DTOs, mappings, commands, list query, seed

Moves the API surface and write paths onto the typed columns. The entity's legacy `Action`/`Parameters` are still `NOT NULL` until Migration B, so writes set them to **vestigial defaults** (`Send`, `""`) — dead data the emitter no longer reads (Task 5), dropped in Task 11. Not identity fields, so they never affect the unique index.

> **Breaking API change — the UI plan must land with this task.** Dropping `Action`/`Parameters`
> from the DTOs breaks the live hotkeys page at runtime (see the Scope note at the top). Everything
> up to Task 5 is additive and shippable alone; from here on, backend and UI release together.

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/DTOs/HotkeyDto.cs`
- Modify: `src/Backend/AHKFlowApp.Application/Mapping/HotkeyMappings.cs`
- Modify: `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/{Create,Update}HotkeyCommand.cs`
- Modify: `src/Backend/AHKFlowApp.Application/Queries/Hotkeys/ListHotkeysQuery.cs`
- Modify: `src/Backend/AHKFlowApp.Application/Commands/Dev/SeedHotkeysCommand.cs`
- Modify: existing Application/API tests that post `Action`/`Parameters` payloads.

**Interfaces:**
- Consumes: typed columns + `HotkeyActionKind`/`RunTargetKind`/`WindowOp`.
- Produces: `HotkeyDto`/`CreateHotkeyDto`/`UpdateHotkeyDto` carrying `ActionKind` + typed fields (no `Action`/`Parameters`); `ListHotkeysQuery.ActionKind` filter.

- [ ] **Step 1: Retype the DTOs**

Replace the three records in `src/Backend/AHKFlowApp.Application/DTOs/HotkeyDto.cs`. Drop `Action`/`Parameters`; add `ActionKind` + the nullable typed fields (XML docs abbreviated here — keep one line per param):

```csharp
public sealed record HotkeyDto(
    Guid Id,
    Guid[] ProfileIds,
    bool AppliesToAllProfiles,
    string Description,
    string Key,
    bool Ctrl,
    bool Alt,
    bool Shift,
    bool Win,
    HotkeyActionKind ActionKind,
    string? Text,
    string? SendKeysContent,
    string? RunTarget,
    RunTargetKind? RunTargetKind,
    WindowOp? WindowOp,
    string? RemapDest,
    string? Body,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    Guid[] CategoryIds);

public sealed record CreateHotkeyDto(
    string Description,
    string Key,
    HotkeyActionKind ActionKind,
    bool Ctrl = false,
    bool Alt = false,
    bool Shift = false,
    bool Win = false,
    string? Text = null,
    string? SendKeysContent = null,
    string? RunTarget = null,
    RunTargetKind? RunTargetKind = null,
    WindowOp? WindowOp = null,
    string? RemapDest = null,
    string? Body = null,
    Guid[]? ProfileIds = null,
    bool AppliesToAllProfiles = false,
    Guid[]? CategoryIds = null);

public sealed record UpdateHotkeyDto(
    string Description,
    string Key,
    HotkeyActionKind ActionKind,
    bool Ctrl,
    bool Alt,
    bool Shift,
    bool Win,
    string? Text,
    string? SendKeysContent,
    string? RunTarget,
    RunTargetKind? RunTargetKind,
    WindowOp? WindowOp,
    string? RemapDest,
    string? Body,
    Guid[]? ProfileIds,
    bool AppliesToAllProfiles,
    Guid[]? CategoryIds = null);
```

- [ ] **Step 2: Retype the mapping and list projection**

`HotkeyMappings.ToDto`:

```csharp
    public static HotkeyDto ToDto(this Hotkey h) => new(
        h.Id,
        h.Profiles.Select(p => p.ProfileId).ToArray(),
        h.AppliesToAllProfiles,
        h.Description, h.Key, h.Ctrl, h.Alt, h.Shift, h.Win,
        h.ActionKind, h.Text, h.SendKeysContent, h.RunTarget, h.RunTargetKind, h.WindowOp, h.RemapDest, h.Body,
        h.CreatedAt, h.UpdatedAt,
        h.Categories.Select(c => c.CategoryId).ToArray());
```

Update the inline `new HotkeyDto(...)` projections in `ListHotkeysQuery.cs` (~line 158) and `SeedHotkeysCommand.cs` (~line 133) to the same field order.

- [ ] **Step 3: Build the typed definition in Create/Update**

`CreateHotkeyCommand.cs` — replace the converter-wrapped construction from Task 4 with a direct typed definition (legacy pair vestigial):

```csharp
        var entity = Hotkey.Create(
            ownerOid,
            new HotkeyDefinition(
                Description: input.Description, Key: canonicalKey,
                Ctrl: input.Ctrl, Alt: input.Alt, Shift: input.Shift, Win: input.Win,
                Action: HotkeyAction.Send, Parameters: "",   // vestigial until Migration B
                AppliesToAllProfiles: input.AppliesToAllProfiles,
                ActionKind: input.ActionKind, Text: input.Text,
                SendKeysContent: input.SendKeysContent, RunTarget: input.RunTarget,
                RunTargetKind: input.RunTargetKind, WindowOp: input.WindowOp,
                RemapDest: input.RemapDest, Body: input.Body),
            clock);
```

Add `using AHKFlowApp.Domain.Enums;` for `HotkeyAction`. Apply the same shape to `UpdateHotkeyCommand.cs` (`entity.Update(new HotkeyDefinition(... input fields ...))`). Remove the now-unused `LegacyHotkeyDefinitionConverter` wrap from these two paths only (Restore/Revert keep the converter via Task 8; lazy-seed/Seed keep it since their tables are still legacy tuples — retyped in Steps 4–5).

- [ ] **Step 4: Retype the list query filter + sort**

In `ListHotkeysQuery.cs`:
- Change the record parameter `HotkeyAction? Action = null` → `HotkeyActionKind? ActionKind = null`; drop `ParametersFilter`.
- `AllowedSortFields`: replace `"action", "parameters"` with `"actionkind"`.
- Search/filter: replace the `Parameters` LIKE clause with the typed text columns:

```csharp
        if (!string.IsNullOrWhiteSpace(request.Search))
        {
            string pattern = $"%{request.Search.Trim()}%";
            query = query.Where(h =>
                EF.Functions.Like(h.Description, pattern) ||
                EF.Functions.Like(h.Key, pattern) ||
                EF.Functions.Like(h.RunTarget ?? "", pattern) ||
                EF.Functions.Like(h.Text ?? "", pattern) ||
                EF.Functions.Like(h.SendKeysContent ?? "", pattern) ||
                EF.Functions.Like(h.Body ?? "", pattern));
        }
```

- Replace `if (request.Action.HasValue) ... h.Action == request.Action.Value` with `h.ActionKind == request.ActionKind.Value`.
- In `ApplySorting`, replace the `"action"` / `"parameters"` cases with `"actionkind"` ordering by `h.ActionKind`.

- [ ] **Step 5: Retype the seed tuples**

`ListHotkeysQuery.s_lazySeed` and `SeedHotkeysCommand.s_samples` are today two byte-identical
12-row arrays kept in step by a "update both if seed set changes" comment. Collapse them into one
`DefaultHotkeyCatalog.All` (new file beside the converter, `Application/Constants/`), consumed by
both seed loops — the duplication is only tolerable while the shape is frozen, and this task
rewrites both copies anyway.

Keep the catalog expressed in the **legacy** tuple shape (`HotkeyAction`, `Parameters`) and keep the `LegacyHotkeyDefinitionConverter.Apply(...)` wrap in both seed loops (from Task 4). This is deliberate: the seed set is the parity-fixture source (§11), so leaving it in legacy shape keeps one authoritative copy of the sample data that the converter transforms — the same transform Migration A applies to real legacy rows. Comment the catalog to note it feeds `LegacyHotkeyFixtures`.

- [ ] **Step 6: Fix existing test payloads**

Search the Application + API test projects for `CreateHotkeyDto(` / `UpdateHotkeyDto(` / `.Action =` / `Parameters:` on hotkeys and convert to the typed shape (`ActionKind: HotkeyActionKind.Run, RunTarget: "notepad.exe"`, etc.). Confirm none remain:

```bash
grep -rn "HotkeyAction\.\(Send\|Run\)\|ParametersFilter" tests/AHKFlowApp.Application.Tests tests/AHKFlowApp.API.Tests
```

Expected: only `LegacyHotkeyFixtures` / seed / converter references remain (legitimate legacy-shape uses).

- [ ] **Step 7: Build + full suite**

```bash
dotnet build AHKFlowApp.slnx --configuration Release
dotnet test AHKFlowApp.slnx --configuration Release
```
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
dotnet format AHKFlowApp.slnx
git add -A
git commit -m "refactor: hotkey DTOs + list query onto typed action columns

drop Action/Parameters from the API surface; legacy pair vestigial pending drop"
```

---

### Task 7: Per-role + kind-conditional validation

Wires the §8 role grammars and the both-or-neither field rules into the Create/Update validators, now that the DTOs carry the typed fields. Retires `ValidAction`/`ValidParameters`.

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Validation/HotkeyRules.cs`
- Modify: `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/{Create,Update}HotkeyCommand.cs` (validators)
- Create: `tests/AHKFlowApp.Application.Tests/Validation/HotkeyKindConditionalRulesTests.cs`

**Interfaces:**
- Consumes: `HotkeyRules.Tokens.*` (Task 3); typed DTO fields (Task 6).
- Produces: `AddHotkeyActionRules<T>(...)` extension applied in both validators.

- [ ] **Step 1: Write the failing test**

Create `tests/AHKFlowApp.Application.Tests/Validation/HotkeyKindConditionalRulesTests.cs`. Validate through `CreateHotkeyCommandValidator` (matches the W0 `HotkeyRulesTests` pattern):

```csharp
using AHKFlowApp.Application.Commands.Hotkeys;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Enums;
using FluentAssertions;
using FluentValidation.Results;

namespace AHKFlowApp.Application.Tests.Validation;

public sealed class HotkeyKindConditionalRulesTests
{
    private static ValidationResult Validate(CreateHotkeyDto dto) =>
        new CreateHotkeyCommandValidator().Validate(new CreateHotkeyCommand(dto));

    private static CreateHotkeyDto Base(HotkeyActionKind kind) =>
        new("d", "a", kind, Ctrl: true);

    [Fact]
    public void Run_WithoutTarget_IsInvalid() =>
        Validate(Base(HotkeyActionKind.Run)).IsValid.Should().BeFalse();

    [Fact]
    public void Run_WithTarget_IsValid() =>
        Validate(Base(HotkeyActionKind.Run) with { RunTarget = "notepad.exe", RunTargetKind = RunTargetKind.Application })
            .IsValid.Should().BeTrue();

    // The two Run failures are separate fields. A merged check would blame RunTarget for a bad
    // RunTargetKind, and the client would highlight a control it filled in correctly.
    [Fact]
    public void Run_WithoutTarget_FailsOnRunTarget() =>
        Validate(Base(HotkeyActionKind.Run) with { RunTargetKind = RunTargetKind.Application })
            .Errors.Should().ContainSingle().Which.PropertyName.Should().Be("RunTarget");

    [Fact]
    public void Run_WithoutTargetKind_FailsOnRunTargetKind() =>
        Validate(Base(HotkeyActionKind.Run) with { RunTarget = "notepad.exe" })
            .Errors.Should().ContainSingle().Which.PropertyName.Should().Be("RunTargetKind");

    [Fact]
    public void Run_UndefinedTargetKind_FailsOnRunTargetKind() =>
        Validate(Base(HotkeyActionKind.Run) with { RunTarget = "notepad.exe", RunTargetKind = (RunTargetKind)99 })
            .Errors.Should().ContainSingle().Which.PropertyName.Should().Be("RunTargetKind");

    [Fact]
    public void SendKeys_InvalidToken_IsInvalid() =>
        Validate(Base(HotkeyActionKind.SendKeys) with { SendKeysContent = "Volume_Up" }) // must be braced
            .IsValid.Should().BeFalse();

    [Fact]
    public void SendKeys_ValidToken_IsValid() =>
        Validate(Base(HotkeyActionKind.SendKeys) with { SendKeysContent = "{Volume_Up}" }).IsValid.Should().BeTrue();

    [Fact]
    public void Remap_InvalidDest_IsInvalid() =>
        Validate(Base(HotkeyActionKind.Remap) with { RemapDest = "Pause" }).IsValid.Should().BeFalse();

    [Fact]
    public void Window_WithoutOp_IsInvalid() =>
        Validate(Base(HotkeyActionKind.Window)).IsValid.Should().BeFalse();

    [Fact]
    public void Disable_TakesNoFields_IsValid() =>
        Validate(Base(HotkeyActionKind.Disable)).IsValid.Should().BeTrue();

    [Fact]
    public void Run_WithForeignField_IsInvalid() =>  // both-or-neither: Run must not carry Body
        Validate(Base(HotkeyActionKind.Run) with { RunTarget = "x", RunTargetKind = RunTargetKind.Application, Body = "MsgBox 1" })
            .IsValid.Should().BeFalse();

    // Undefined enum ints deserialize happily; the validator, not the emitter, must reject them.
    [Fact]
    public void UndefinedActionKind_IsInvalid() =>
        Validate(Base((HotkeyActionKind)99)).IsValid.Should().BeFalse();

    [Fact]
    public void UndefinedWindowOp_IsInvalid() =>
        Validate(Base(HotkeyActionKind.Window) with { WindowOp = (WindowOp)99 }).IsValid.Should().BeFalse();

    [Fact]
    public void UndefinedRunTargetKind_IsInvalid() =>
        Validate(Base(HotkeyActionKind.Run) with { RunTarget = "notepad", RunTargetKind = (RunTargetKind)99 })
            .IsValid.Should().BeFalse();

    [Fact] // RunTargetKind is a foreign field outside Run
    public void SendText_WithRunTargetKind_IsInvalid() =>
        Validate(Base(HotkeyActionKind.SendText) with { Text = "hi", RunTargetKind = RunTargetKind.Url })
            .IsValid.Should().BeFalse();

    [Fact]
    public void Raw_HashDirective_IsInvalid() =>
        Validate(Base(HotkeyActionKind.Raw) with { Body = "#SingleInstance Force" }).IsValid.Should().BeFalse();

    [Fact]
    public void Raw_UnbalancedBraces_IsInvalid() =>
        Validate(Base(HotkeyActionKind.Raw) with { Body = "MsgBox 1 }" }).IsValid.Should().BeFalse();
}
```

- [ ] **Step 2: Run to verify failure**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~HotkeyKindConditionalRulesTests"`
Expected: FAIL — `AddHotkeyActionRules` not defined.

- [ ] **Step 3: Add the kind-conditional rule set**

In `HotkeyRules.cs`, remove `ValidAction` and `ValidParameters` (superseded), and add an extension that reads the whole DTO so it can express both-or-neither. Model it on the hotstring `AddRawKindRules` / `AddDateTimeKindRules` accessor-lambda pattern:

```csharp
    /// <summary>
    /// Kind-conditional action rules (spec §8): each <see cref="HotkeyActionKind"/> requires its own
    /// field(s) and forbids the others'. SendKeys/Remap fields are additionally token-validated; Raw
    /// is brace-balanced with no <c>#</c> directive.
    /// </summary>
    public static void AddHotkeyActionRules<T>(
        this AbstractValidator<T> v,
        Func<T, HotkeyActionKind> kind,
        Func<T, string?> text,
        Func<T, string?> sendKeys,
        Func<T, string?> runTarget,
        Func<T, RunTargetKind?> runTargetKind,
        Func<T, WindowOp?> windowOp,
        Func<T, string?> remapDest,
        Func<T, string?> body)
    {
        v.RuleFor(x => x).Custom((x, ctx) =>
        {
            HotkeyActionKind k = kind(x);

            // System.Text.Json deserializes any int into an enum field, so a payload can carry
            // ActionKind: 99. Without this the switch below matches nothing, ForbidExcept sees no
            // owner, the DTO validates, and the *emitter* is left to throw — a 500 on bad input.
            // Same for the two nested enums: `is null` alone accepts (WindowOp)99.
            if (!Enum.IsDefined(k))
            {
                ctx.AddFailure("ActionKind", "ActionKind must be a valid HotkeyActionKind value.");
                return;
            }

            // Required field present + valid, per kind.
            switch (k)
            {
                case HotkeyActionKind.SendText when string.IsNullOrEmpty(text(x)):
                    ctx.AddFailure("Text", "SendText requires Text."); break;
                case HotkeyActionKind.SendKeys when !Tokens.IsValidSendKeysContent(sendKeys(x)):
                    ctx.AddFailure("SendKeysContent", "SendKeys requires a valid key token (for example {Volume_Up} or ^c)."); break;
                // Two failures, two fields: a bad RunTargetKind must not be reported against
                // RunTarget, or the UI highlights the wrong control and the ProblemDetails names a
                // field the client never sent wrong.
                case HotkeyActionKind.Run when string.IsNullOrEmpty(runTarget(x)):
                    ctx.AddFailure("RunTarget", "Run requires a run target."); break;
                case HotkeyActionKind.Run when runTargetKind(x) is not RunTargetKind rtk || !Enum.IsDefined(rtk):
                    ctx.AddFailure("RunTargetKind", "Run requires a valid run target kind."); break;
                case HotkeyActionKind.Window when windowOp(x) is not WindowOp op || !Enum.IsDefined(op):
                    ctx.AddFailure("WindowOp", "Window requires a valid window operation."); break;
                case HotkeyActionKind.Remap when !Tokens.IsValidRemapDest(remapDest(x)):
                    ctx.AddFailure("RemapDest", "Remap requires a valid destination key."); break;
                case HotkeyActionKind.Raw:
                    ValidateRawBody(body(x), ctx); break;
            }

            // Foreign fields forbidden: only the kind's own field(s) may be set. RunTargetKind is
            // listed too — it is Run's second field, and omitting it let a SendText payload smuggle
            // one through.
            ForbidExcept(k, ctx,
                (HotkeyActionKind.SendText, "Text", !string.IsNullOrEmpty(text(x))),
                (HotkeyActionKind.SendKeys, "SendKeysContent", !string.IsNullOrEmpty(sendKeys(x))),
                (HotkeyActionKind.Run, "RunTarget", !string.IsNullOrEmpty(runTarget(x))),
                (HotkeyActionKind.Run, "RunTargetKind", runTargetKind(x) is not null),
                (HotkeyActionKind.Window, "WindowOp", windowOp(x) is not null),
                (HotkeyActionKind.Remap, "RemapDest", !string.IsNullOrEmpty(remapDest(x))),
                (HotkeyActionKind.Raw, "Body", !string.IsNullOrEmpty(body(x))));
        });
    }

    private static void ValidateRawBody(string? body, ValidationContext<object> ctx) { }  // replaced below

    private static void ForbidExcept<T>(
        HotkeyActionKind kind, ValidationContext<T> ctx,
        params (HotkeyActionKind Owner, string Field, bool IsSet)[] fields)
    {
        foreach (var (owner, field, isSet) in fields)
            if (owner != kind && isSet)
                ctx.AddFailure(field, $"{field} is only valid for the {owner} action.");
    }
```

The `ValidateRawBody` placeholder above cannot be generic-typed cleanly; inline the Raw check into the `case HotkeyActionKind.Raw` arm instead:

```csharp
                case HotkeyActionKind.Raw:
                    string b = body(x) ?? "";
                    if (string.IsNullOrEmpty(b))
                        ctx.AddFailure("Body", "Raw requires an action body.");
                    else if (b.Count(c => c == '{') != b.Count(c => c == '}'))
                        ctx.AddFailure("Body", "Raw body braces are unbalanced.");
                    else if (b.Split('\n').Any(line => line.TrimStart().StartsWith('#')))
                        ctx.AddFailure("Body", "Raw body must not contain a # directive.");
                    break;
```

Remove the placeholder `ValidateRawBody` method.

- [ ] **Step 4: Wire into the validators**

In `CreateHotkeyCommandValidator` and `UpdateHotkeyCommandValidator`, replace the `RuleFor(x => x.Input.Parameters).ValidParameters()` and `RuleFor(x => x.Input.Action).ValidAction()` lines with:

```csharp
        this.AddHotkeyActionRules(
            x => x.Input.ActionKind,
            x => x.Input.Text,
            x => x.Input.SendKeysContent,
            x => x.Input.RunTarget,
            x => x.Input.RunTargetKind,
            x => x.Input.WindowOp,
            x => x.Input.RemapDest,
            x => x.Input.Body);
```

Keep `ValidDescription` and `ValidKey`.

- [ ] **Step 5: Run validation + full suite**

```bash
dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~HotkeyKindConditionalRulesTests|FullyQualifiedName~HotkeyRulesTests|FullyQualifiedName~HotkeyTokenRulesTests"
dotnet test AHKFlowApp.slnx --configuration Release
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
dotnet format AHKFlowApp.slnx
git add -A
git commit -m "feat: kind-conditional + per-role hotkey validation

each action requires its field, forbids others; retire ValidAction/ValidParameters"
```

---

### Task 8: History snapshot — typed + legacy converter

`HotkeySnapshot` gains the typed fields and **keeps** `Action`/`Parameters` as optional legacy members. `LegacyHotkeySnapshotConverter` (the `ScriptToRawComposer.ToDefinition` analogue) turns any snapshot — legacy tombstone or new — into a typed `HotkeyDefinition`, applied by both Restore and Revert.

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/DTOs/HistorySnapshots.cs` (`HotkeySnapshot`)
- Create: `src/Backend/AHKFlowApp.Application/Services/LegacyHotkeySnapshotConverter.cs`
- Modify: `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/{Restore,Revert}HotkeyCommand.cs`
- Modify: the history recorder's snapshot builder (wherever `HotkeySnapshot` is constructed — `IEntityHistoryRecorder.RecordHotkeyAsync` implementation) to persist the typed fields.
- Create: `tests/AHKFlowApp.Application.Tests/Services/LegacyHotkeySnapshotConverterTests.cs`

**Interfaces:**
- Consumes: `LegacyHotkeyDefinitionConverter.ToTyped` (Task 4).
- Produces: `LegacyHotkeySnapshotConverter.ToDefinition(HotkeySnapshot) : HotkeyDefinition`.

- [ ] **Step 1: Extend `HotkeySnapshot`**

In `HistorySnapshots.cs`, add typed fields and demote `Action`/`Parameters` to optional legacy members (defaulted). New snapshots set the typed fields and leave the legacy members null; old JSON has the legacy members and null typed fields:

```csharp
public sealed record HotkeySnapshot(
    string Description,
    string Key,
    bool Ctrl,
    bool Alt,
    bool Shift,
    bool Win,
    bool AppliesToAllProfiles,
    Guid[] ProfileIds,
    Guid[] CategoryIds,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    HotkeyActionKind ActionKind = HotkeyActionKind.Raw,
    string? Text = null,
    string? SendKeysContent = null,
    string? RunTarget = null,
    RunTargetKind? RunTargetKind = null,
    WindowOp? WindowOp = null,
    string? RemapDest = null,
    string? Body = null,
    // Legacy members — present only in pre-W1 tombstones; the converter keys off their presence.
    HotkeyAction? Action = null,
    string? Parameters = null);
```

> Note the reordered positional list: `Action`/`Parameters` moved to the tail. Because history JSON is **property-named** (System.Text.Json), reordering positional record parameters does not break deserialization of old JSON — the names still bind. New required members were not added (all new members are defaulted), so old JSON still deserializes.

- [ ] **Step 2: Write the converter's failing test**

Create `tests/AHKFlowApp.Application.Tests/Services/LegacyHotkeySnapshotConverterTests.cs`:

```csharp
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;

namespace AHKFlowApp.Application.Tests.Services;

public sealed class LegacyHotkeySnapshotConverterTests
{
    [Theory]
    [MemberData(nameof(Legacy))]
    public void ToDefinition_LegacySnapshot_ConvertsViaSameRules(LegacyHotkeyFixture f)
    {
        HotkeySnapshot legacy = Snapshot() with { Action = f.Action, Parameters = f.Parameters };

        HotkeyDefinition def = LegacyHotkeySnapshotConverter.ToDefinition(legacy);

        var expected = LegacyHotkeyDefinitionConverter.ToTyped(f.Action, f.Parameters);
        def.ActionKind.Should().Be(expected.ActionKind, "fixture '{0}'", f.Name);
        def.RunTarget.Should().Be(expected.RunTarget, "fixture '{0}'", f.Name);
        def.SendKeysContent.Should().Be(expected.SendKeysContent, "fixture '{0}'", f.Name);
        def.Body.Should().Be(expected.Body, "fixture '{0}'", f.Name);
    }

    [Fact]
    public void ToDefinition_TypedSnapshot_PassesFieldsThrough()
    {
        HotkeySnapshot typed = Snapshot() with { ActionKind = HotkeyActionKind.Window, WindowOp = WindowOp.Close };

        HotkeyDefinition def = LegacyHotkeySnapshotConverter.ToDefinition(typed);

        def.ActionKind.Should().Be(HotkeyActionKind.Window);
        def.WindowOp.Should().Be(WindowOp.Close);
    }

    public static TheoryData<LegacyHotkeyFixture> Legacy()
    {
        var d = new TheoryData<LegacyHotkeyFixture>();
        foreach (LegacyHotkeyFixture f in LegacyHotkeyFixtures.All) d.Add(f);
        return d;
    }

    private static HotkeySnapshot Snapshot() => new(
        "d", "a", false, false, false, false, true, [], [],
        DateTimeOffset.UnixEpoch, DateTimeOffset.UnixEpoch);
}
```

- [ ] **Step 3: Write the converter**

Create `src/Backend/AHKFlowApp.Application/Services/LegacyHotkeySnapshotConverter.cs`:

```csharp
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.Services;

/// <summary>
/// Builds the <see cref="HotkeyDefinition"/> to persist when restoring or reverting a
/// <see cref="HotkeySnapshot"/>. A pre-W1 snapshot (legacy <see cref="HotkeySnapshot.Action"/> present)
/// is converted through the same rules as the data migration via
/// <see cref="LegacyHotkeyDefinitionConverter"/>; a W1 snapshot is applied as-is. The
/// <c>ScriptToRawComposer.ToDefinition</c> analogue (spec §8).
/// </summary>
public static class LegacyHotkeySnapshotConverter
{
    public static HotkeyDefinition ToDefinition(HotkeySnapshot s)
    {
        // A legacy snapshot: derive the typed columns from the legacy pair.
        if (s.Action is HotkeyAction legacyAction)
        {
            var t = LegacyHotkeyDefinitionConverter.ToTyped(legacyAction, s.Parameters ?? "");
            return new HotkeyDefinition(
                Description: s.Description, Key: s.Key,
                Ctrl: s.Ctrl, Alt: s.Alt, Shift: s.Shift, Win: s.Win,
                Action: legacyAction, Parameters: s.Parameters ?? "",
                AppliesToAllProfiles: s.AppliesToAllProfiles,
                ActionKind: t.ActionKind, Text: t.Text, SendKeysContent: t.SendKeysContent,
                RunTarget: t.RunTarget, RunTargetKind: t.RunTargetKind, WindowOp: t.WindowOp,
                RemapDest: t.RemapDest, Body: t.Body);
        }

        // A W1 snapshot: pass the typed fields through (legacy pair vestigial until Migration B).
        return new HotkeyDefinition(
            Description: s.Description, Key: s.Key,
            Ctrl: s.Ctrl, Alt: s.Alt, Shift: s.Shift, Win: s.Win,
            Action: HotkeyAction.Send, Parameters: "",
            AppliesToAllProfiles: s.AppliesToAllProfiles,
            ActionKind: s.ActionKind, Text: s.Text, SendKeysContent: s.SendKeysContent,
            RunTarget: s.RunTarget, RunTargetKind: s.RunTargetKind, WindowOp: s.WindowOp,
            RemapDest: s.RemapDest, Body: s.Body);
    }
}
```

- [ ] **Step 4: Route Restore/Revert through the converter**

In `RestoreHotkeyCommand.cs`, replace the `new HotkeyDefinition(snapshot.Description, …, snapshot.Action, snapshot.Parameters, …)` passed to `Hotkey.Restore` with:

```csharp
        var entity = Hotkey.Restore(
            request.Id, ownerOid,
            LegacyHotkeySnapshotConverter.ToDefinition(snapshot),
            snapshot.CreatedAt, clock);
```

In `RevertHotkeyCommand.cs`, replace the `entity.Update(new HotkeyDefinition(...))` with:

```csharp
        entity.Update(LegacyHotkeySnapshotConverter.ToDefinition(snapshot), clock);
```

Add `using AHKFlowApp.Application.Services;` to both.

- [ ] **Step 5: Persist typed fields in the recorder**

Find the `RecordHotkeyAsync` implementation that builds a `HotkeySnapshot` (search `new HotkeySnapshot(`). Update it to pass the entity's typed columns and leave `Action`/`Parameters` at their defaults (null). This keeps new tombstones typed while old ones stay legacy.

```bash
grep -rn "new HotkeySnapshot(" src
```

- [ ] **Step 6: Run converter + history command tests + full suite**

```bash
dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~LegacyHotkeySnapshotConverterTests"
dotnet test AHKFlowApp.slnx --configuration Release
```
Expected: PASS. (The existing Restore/Revert integration tests now exercise the converter path.)

- [ ] **Step 7: Commit**

```bash
dotnet format AHKFlowApp.slnx
git add -A
git commit -m "feat: legacy hotkey snapshot converter for restore/revert

typed snapshot + optional legacy members; converts old tombstones via shared rules"
```

---

### Task 9: Hotkey preview endpoint

Clone of `GetHotstringPreviewQuery`: build a transient never-saved `Hotkey` from the draft, run `HotkeyEmitter`, return the snippet. No `IAppDbContext`, no side effects. Preview parity: the snippet equals the row's line in a profile download (§11).

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/Queries/Hotkeys/GetHotkeyPreviewQuery.cs`
- Modify: `src/Backend/AHKFlowApp.Application/DTOs/HotkeyDto.cs` (add `HotkeyPreviewRequestDto`, `HotkeyPreviewDto`) — or a new `DTOs/HotkeyPreview.cs`
- Modify: `src/Backend/AHKFlowApp.API/Controllers/HotkeysController.cs` (`POST /preview`)
- Create: `tests/AHKFlowApp.Application.Tests/Hotkeys/GetHotkeyPreviewQueryTests.cs`

**Interfaces:**
- Consumes: `HotkeyEmitter.Emit`, `HotstringEmitter.DescriptionCommentLines` (shared comment formatter, W0), typed `Hotkey`, `AddHotkeyActionRules` (Task 7).
- Produces: `GetHotkeyPreviewQuery(HotkeyPreviewRequestDto)`, `HotkeyPreviewDto(string Snippet)`.

- [ ] **Step 1: Add the preview DTOs**

Create `src/Backend/AHKFlowApp.Application/DTOs/HotkeyPreview.cs`:

```csharp
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.DTOs;

/// <summary>Draft hotkey fields to preview, without saving. Mirrors the create/update editable set.</summary>
public sealed record HotkeyPreviewRequestDto(
    string Description,
    string Key,
    HotkeyActionKind ActionKind,
    bool Ctrl = false,
    bool Alt = false,
    bool Shift = false,
    bool Win = false,
    string? Text = null,
    string? SendKeysContent = null,
    string? RunTarget = null,
    RunTargetKind? RunTargetKind = null,
    WindowOp? WindowOp = null,
    string? RemapDest = null,
    string? Body = null);

/// <summary>The AutoHotkey snippet a hotkey draft would generate.</summary>
public sealed record HotkeyPreviewDto(string Snippet);
```

- [ ] **Step 2: Write the failing test**

Create `tests/AHKFlowApp.Application.Tests/Hotkeys/GetHotkeyPreviewQueryTests.cs`:

```csharp
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Hotkeys;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotkeys;

public sealed class GetHotkeyPreviewQueryTests
{
    private static async Task<string> Preview(HotkeyPreviewRequestDto dto)
    {
        var handler = new GetHotkeyPreviewQueryHandler(new FakeTimeProvider());
        Result<HotkeyPreviewDto> r = await handler.ExecuteAsync(new GetHotkeyPreviewQuery(dto), CancellationToken.None);
        r.IsSuccess.Should().BeTrue();
        return r.Value.Snippet;
    }

    [Fact]
    public async Task Run_EmitsRunLineWithDescriptionComment()
    {
        string snippet = await Preview(new HotkeyPreviewRequestDto(
            "Open Notepad", "n", HotkeyActionKind.Run, Win: true,
            RunTarget: "notepad", RunTargetKind: RunTargetKind.Application));

        snippet.Should().Contain("#n::Run(\"notepad\")");
    }

    [Fact]
    public async Task SendKeys_EmitsDollarPrefix()
    {
        string snippet = await Preview(new HotkeyPreviewRequestDto(
            "Volume", "p", HotkeyActionKind.SendKeys, Win: true, SendKeysContent: "{Media_Play_Pause}"));

        snippet.Should().Contain("$#p::Send(\"{Media_Play_Pause}\")");
    }
}
```

- [ ] **Step 3: Write the query + handler**

Create `src/Backend/AHKFlowApp.Application/Queries/Hotkeys/GetHotkeyPreviewQuery.cs` (mirror `GetHotstringPreviewQuery` structure — validator reuses `ValidKey` + `AddHotkeyActionRules`; handler builds a transient `Hotkey`):

```csharp
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using FluentValidation;

namespace AHKFlowApp.Application.Queries.Hotkeys;

public sealed record GetHotkeyPreviewQuery(HotkeyPreviewRequestDto Input);

public sealed class GetHotkeyPreviewQueryValidator : AbstractValidator<GetHotkeyPreviewQuery>
{
    public GetHotkeyPreviewQueryValidator()
    {
        RuleFor(x => x.Input.Description).ValidDescription();
        RuleFor(x => x.Input.Key).ValidKey();
        this.AddHotkeyActionRules(
            x => x.Input.ActionKind,
            x => x.Input.Text,
            x => x.Input.SendKeysContent,
            x => x.Input.RunTarget,
            x => x.Input.RunTargetKind,
            x => x.Input.WindowOp,
            x => x.Input.RemapDest,
            x => x.Input.Body);
    }
}

/// <summary>
/// Computes the exact AutoHotkey snippet a hotkey draft would generate, without persisting. Builds a
/// transient (never-saved) <see cref="Hotkey"/> to reuse <see cref="HotkeyEmitter"/> — no
/// <c>IAppDbContext</c>, no side effects. Clone of <c>GetHotstringPreviewQueryHandler</c>.
/// </summary>
internal sealed class GetHotkeyPreviewQueryHandler(TimeProvider clock)
    : IUseCaseHandler<GetHotkeyPreviewQuery, Result<HotkeyPreviewDto>>
{
    public Task<Result<HotkeyPreviewDto>> ExecuteAsync(GetHotkeyPreviewQuery request, CancellationToken ct)
    {
        HotkeyPreviewRequestDto i = request.Input;

        // Canonicalize the key so the preview matches what a save would persist and emit.
        HotkeyKeys.TryCanonicalize(i.Key, out string canonicalKey);

        Hotkey hk = Hotkey.Create(
            Guid.Empty,
            new HotkeyDefinition(
                Description: i.Description, Key: canonicalKey,
                Ctrl: i.Ctrl, Alt: i.Alt, Shift: i.Shift, Win: i.Win,
                Action: HotkeyAction.Send, Parameters: "", AppliesToAllProfiles: true,
                ActionKind: i.ActionKind, Text: i.Text, SendKeysContent: i.SendKeysContent,
                RunTarget: i.RunTarget, RunTargetKind: i.RunTargetKind, WindowOp: i.WindowOp,
                RemapDest: i.RemapDest, Body: i.Body),
            clock);

        string snippet = HotkeyEmitter.Emit(hk);
        string commentBlock = string.Join('\n', HotstringEmitter.DescriptionCommentLines(hk.Description));
        if (commentBlock.Length > 0)
            snippet = $"{commentBlock}\n{snippet}";

        return Task.FromResult(Result.Success(new HotkeyPreviewDto(snippet)));
    }
}
```

Add `using AHKFlowApp.Application.Constants;` for `HotkeyKeys`. `GetHotkeyPreviewQueryHandler` must be reachable from the test (same assembly, `internal`) — the test project already has `InternalsVisibleTo` for Application.Tests (mirror the hotstring preview test's access).

- [ ] **Step 4: Expose the endpoint**

In `HotkeysController.cs`, inject `IUseCase<GetHotkeyPreviewQuery, Result<HotkeyPreviewDto>> previewHotkey` and add:

```csharp
    /// <summary>Preview the AutoHotkey snippet a hotkey draft would generate, without saving it.</summary>
    [HttpPost("preview")]
    [ProducesResponseType(typeof(HotkeyPreviewDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<HotkeyPreviewDto>> Preview(
        [FromBody] HotkeyPreviewRequestDto dto,
        CancellationToken ct) =>
        (await previewHotkey.ExecuteAsync(new GetHotkeyPreviewQuery(dto), ct)).ToProblemActionResult(this);
```

Register the use case explicitly in `src/Backend/AHKFlowApp.Application/DependencyInjection.cs`, alongside its hotstring counterpart at line 54:

```csharp
            .AddUseCase<GetHotkeyPreviewQuery, Result<HotkeyPreviewDto>, GetHotkeyPreviewQueryHandler>()
```

There is **no** assembly scan — every handler in this project is registered by hand, and the only generic registration is the `ValidatingUseCase<,>` decorator (line 28). Without the line above, `HotkeysController` fails to activate the moment the preview endpoint is wired, and the UI plan's preview panel 500s on every keystroke. (An earlier revision of this task claimed auto-registration; corrected 2026-07-22.)

Confirm the controller carries `[Authorize]` like its siblings.

- [ ] **Step 5: Run + full suite**

```bash
dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~GetHotkeyPreviewQueryTests"
dotnet test AHKFlowApp.slnx --configuration Release
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
dotnet format AHKFlowApp.slnx
git add -A
git commit -m "feat: hotkey preview endpoint

transient-emit clone of hotstring preview; POST /api/v1/hotkeys/preview"
```

---

### Task 10: API integration goldens

WebApplicationFactory + Testcontainers: POST each action kind → 201 + correct DB state; duplicate identity → 409; malformed → 400 naming the field (§11).

**Files:**
- Modify: `tests/AHKFlowApp.API.Tests/.../HotkeysEndpointsTests.cs` (add cases; create the file if the hotkey endpoint tests live elsewhere — mirror `HotstringsEndpointsTests`).

**Interfaces:**
- Consumes: the typed API surface (Tasks 6–9).

- [ ] **Step 1: Write the failing tests**

Add to the hotkey endpoints test class. One representative per kind plus the two error paths:

```csharp
[Theory]
[MemberData(nameof(KindPayloads))]
public async Task Post_EachActionKind_Returns201AndPersistsTypedColumns(
    CreateHotkeyDto dto, HotkeyActionKind expectedKind)
{
    HttpResponseMessage res = await Client.PostAsJsonAsync("/api/v1/hotkeys", dto);

    res.StatusCode.Should().Be(HttpStatusCode.Created);
    HotkeyDto? created = await res.Content.ReadFromJsonAsync<HotkeyDto>();
    created!.ActionKind.Should().Be(expectedKind);
}

public static TheoryData<CreateHotkeyDto, HotkeyActionKind> KindPayloads() => new()
{
    { new("Type text", "a", HotkeyActionKind.SendText, Ctrl: true, Text: "hi"), HotkeyActionKind.SendText },
    { new("Send keys", "b", HotkeyActionKind.SendKeys, Ctrl: true, SendKeysContent: "{Up}"), HotkeyActionKind.SendKeys },
    { new("Run app", "c", HotkeyActionKind.Run, Ctrl: true, RunTarget: "notepad.exe", RunTargetKind: RunTargetKind.Application), HotkeyActionKind.Run },
    { new("Minimize", "d", HotkeyActionKind.Window, Ctrl: true, WindowOp: WindowOp.Minimize), HotkeyActionKind.Window },
    { new("Remap", "CapsLock", HotkeyActionKind.Remap, RemapDest: "Ctrl"), HotkeyActionKind.Remap },
    { new("Disable", "F1", HotkeyActionKind.Disable), HotkeyActionKind.Disable },
    { new("Raw", "e", HotkeyActionKind.Raw, Ctrl: true, Body: "MsgBox \"hi\""), HotkeyActionKind.Raw },
};

// Raw JSON, not a typed DTO: an out-of-range int is exactly what a hand-rolled client sends,
// and it is the only way to reach the undefined-enum path the validator now guards. Must be
// 400 from validation, never 500 from the emitter — and the ProblemDetails must name the field
// that is actually wrong, so a status-only assertion is not enough.
[Theory]
[InlineData("{\"description\":\"Bad\",\"key\":\"a\",\"ctrl\":true,\"actionKind\":99}", "ActionKind")]
[InlineData("{\"description\":\"Bad\",\"key\":\"a\",\"ctrl\":true,\"actionKind\":3,\"windowOp\":99}", "WindowOp")]
[InlineData("{\"description\":\"Bad\",\"key\":\"a\",\"ctrl\":true,\"actionKind\":2,\"runTarget\":\"notepad\",\"runTargetKind\":99}", "RunTargetKind")]
public async Task Post_UndefinedEnumValue_Returns400NamingField(string json, string expectedField)
{
    HttpResponseMessage res = await Client.PostAsync("/api/v1/hotkeys",
        new StringContent(json, Encoding.UTF8, "application/json"));

    res.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    (await res.Content.ReadAsStringAsync()).Should().Contain(expectedField);
}

[Fact]
public async Task Post_MalformedSendKeys_Returns400NamingField()
{
    var dto = new CreateHotkeyDto("Bad", "a", HotkeyActionKind.SendKeys, Ctrl: true, SendKeysContent: "Volume_Up");
    HttpResponseMessage res = await Client.PostAsJsonAsync("/api/v1/hotkeys", dto);

    res.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    (await res.Content.ReadAsStringAsync()).Should().Contain("SendKeysContent");
}

[Fact]
public async Task Post_DuplicateKeyAndModifiers_Returns409()
{
    var dto = new CreateHotkeyDto("First", "z", HotkeyActionKind.Disable);
    (await Client.PostAsJsonAsync("/api/v1/hotkeys", dto)).StatusCode.Should().Be(HttpStatusCode.Created);

    HttpResponseMessage second = await Client.PostAsJsonAsync("/api/v1/hotkeys",
        dto with { Description = "Second" });

    second.StatusCode.Should().Be(HttpStatusCode.Conflict);
}
```

- [ ] **Step 2: Run to verify (they should pass on the typed stack)**

Run: `dotnet test tests/AHKFlowApp.API.Tests --filter "FullyQualifiedName~HotkeysEndpointsTests"`
Expected: PASS. If any fail, the defect is in Tasks 6–9 wiring — fix there, not by weakening the test.

- [ ] **Step 3: Commit**

```bash
dotnet format AHKFlowApp.slnx
git add -A
git commit -m "test: hotkey endpoint goldens per action kind + 409 + 400"
```

---

### Task 11: Contract — drop legacy columns + retire enum

Migration B drops `Action`/`Parameters`. `HotkeyAction` is retired from the backend; `HotkeyDefinition`, the entity, `Apply`, and every vestigial write leave the legacy pair behind. `HotkeySnapshot` keeps its optional legacy members forever.

**Files:**
- Create: `src/Backend/AHKFlowApp.Infrastructure/Migrations/<ts>_DropLegacyHotkeyAction.cs` (via `dotnet ef`)
- Modify: `src/Backend/AHKFlowApp.Domain/Entities/Hotkey.cs` (drop `Action`/`Parameters` props + `Apply` lines)
- Modify: `src/Backend/AHKFlowApp.Domain/Entities/HotkeyDefinition.cs` (drop legacy positional params)
- Modify: `src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/HotkeyConfiguration.cs` (drop `Action`/`Parameters` config)
- Modify: `src/Backend/AHKFlowApp.Application/Services/{LegacyHotkeyDefinitionConverter,LegacyHotkeySnapshotConverter}.cs` (stop writing the legacy pair)
- Modify: all `new HotkeyDefinition(...)` call sites (remove the two vestigial args)
- Retire: `src/Backend/AHKFlowApp.Domain/Enums/HotkeyAction.cs`
- Modify: `tests/AHKFlowApp.TestUtilities/Fixtures/LegacyHotkeyFixtures.cs` (still references `HotkeyAction` for the legacy *input* — see note)

**Interfaces:**
- Consumes: everything on the typed stack.
- Produces: `HotkeyDefinition` without `Action`/`Parameters`; `Hotkey` without them; no `HotkeyAction` in Domain.

> **Legacy input still needs a discriminator.** `LegacyHotkeyFixtures` and `LegacyHotkey{Definition,Snapshot}Converter` consume a legacy *Send-vs-Run* input. Once the entity no longer has `Action`, that input can be a private 2-value enum local to the converter (`LegacyHotkeyDefinitionConverter.LegacyAction { Send, Run }`) or `HotkeyAction` can be **kept solely as a converter input type** and moved out of `Domain/Enums` into the Application converter file. Choose the latter to keep `HotkeySnapshot.Action` typed: move `HotkeyAction` into `LegacyHotkeyDefinitionConverter.cs` as a nested `public enum`, update the three references (fixtures, snapshot, converter), delete `Domain/Enums/HotkeyAction.cs`. The frontend mirror `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HotkeyAction.cs` is handled by the **UI plan**; if that plan has not landed, leave the frontend file untouched (it does not reference the backend type).

- [ ] **Step 1: Generate Migration B**

```bash
dotnet ef migrations add DropLegacyHotkeyAction \
  --project src/Backend/AHKFlowApp.Infrastructure \
  --startup-project src/Backend/AHKFlowApp.API
```

Before generating, apply Steps 2–4 so the model no longer has the columns (EF scaffolds the `DropColumn` calls from the model diff). Verify `Up` contains exactly two `DropColumn` calls (`Action`, `Parameters`) and nothing else. Set `Down` to re-add the columns as nullable (data is unrecoverable — document that a real rollback restores from backup), matching the `RawHotstringKind.Down` stance if a lossy note is preferable.

- [ ] **Step 2: Drop legacy from the entity + definition**

`Hotkey.cs`: delete the `Action` and `Parameters` properties (lines 22–23) and their two lines in `Apply`. `HotkeyDefinition.cs`: delete the `HotkeyAction Action` and `string Parameters` positional parameters (the record becomes typed-only, with `ActionKind` promoted to a required non-defaulted parameter and the typed fields following).

`HotkeyDefinition` final shape:

```csharp
public sealed record HotkeyDefinition(
    string Description,
    string Key,
    bool Ctrl,
    bool Alt,
    bool Shift,
    bool Win,
    HotkeyActionKind ActionKind,
    bool AppliesToAllProfiles,
    string? Text = null,
    string? SendKeysContent = null,
    string? RunTarget = null,
    RunTargetKind? RunTargetKind = null,
    WindowOp? WindowOp = null,
    string? RemapDest = null,
    string? Body = null);
```

- [ ] **Step 3: Drop legacy from config + converters + call sites**

`HotkeyConfiguration.cs`: remove the `Action` (HasConversion) and `Parameters` (HasMaxLength) property blocks.

`LegacyHotkeyDefinitionConverter.cs` / `LegacyHotkeySnapshotConverter.cs`: they now build the typed-only `HotkeyDefinition` (no `Action:`/`Parameters:` args). Move `HotkeyAction` into the converter file per the note above.

Update every `new HotkeyDefinition(...)` to the typed-only shape — delete the `Action:` and `Parameters:` arguments, keep every remaining argument **named**: `Create`/`Update` commands, `GetHotkeyPreviewQueryHandler`, `HotkeyBuilder`, and any test constructing a definition directly. Confirm:

```bash
grep -rn "Action: HotkeyAction\|Parameters: \"\"" src tests
```
Expected: no hits.

Then confirm nothing reverted to positional along the way — every constructed definition should
name its arguments:

```bash
grep -rn -A2 "new HotkeyDefinition(" src tests
```
Expected: the argument after each `(` is `Description:`, never a bare expression.

- [ ] **Step 4: Retire the enum**

Delete `src/Backend/AHKFlowApp.Domain/Enums/HotkeyAction.cs` (its role now lives in the converter file). Fix the three remaining references (`LegacyHotkeyFixtures`, `HotkeySnapshot`, converters) to the moved type.

- [ ] **Step 5: Build + full suite + migration diff check**

```bash
dotnet build AHKFlowApp.slnx --configuration Release
dotnet test AHKFlowApp.slnx --configuration Release
dotnet ef migrations has-pending-model-changes \
  --project src/Backend/AHKFlowApp.Infrastructure --startup-project src/Backend/AHKFlowApp.API
```
Expected: build 0/0; all tests PASS; **no pending model changes** (the model matches the two migrations).

- [ ] **Step 6: Commit**

```bash
dotnet format AHKFlowApp.slnx
git add -A
git commit -m "refactor: drop legacy hotkey Action/Parameters columns

migration B removes the vestigial pair; HotkeyAction retired to converter input"
```

---

### Task 12: Docs — CONTEXT.md, ADR 0004, ahk-v2-syntax

Terms land in the wave that introduces them (spec §6). One ADR records the typed-action model and the Raw escape-hatch trade-off.

**Files:**
- Modify: `CONTEXT.md`
- Create: `docs/adr/0004-hotkey-typed-actions-and-raw-escape-hatch.md`
- Modify: `docs/development/ahk-v2-syntax.md`

- [ ] **Step 1: CONTEXT.md — add W1 terms**

Add glossary entries (spec §6): **Action** (one of SendText, SendKeys, Run, Window, Remap, Disable, Raw — avoid "type"/"command"), **Remap** (an Action making one key behave as another), **Run target** (the app/URL/folder a Run launches), **Raw** (an Action holding a verbatim body). Keep **Trigger** hotstring-only.

- [ ] **Step 2: ADR 0004**

Create `docs/adr/0004-hotkey-typed-actions-and-raw-escape-hatch.md` following the repo's ADR format (Status/Context/Decision/Consequences). Record: discriminated typed columns over string/JSON; #195 closed by construction (structured LHS + escaped/tokenized RHS); Raw is the sole verbatim path and is **not** sandboxed (a syntax error aborts the whole profile — accepted, same trade-off as hotstring Raw); per-wave additive migrations with a parity-tested legacy converter.

- [ ] **Step 3: ahk-v2-syntax.md — per-kind emission**

Document each kind's emitted form (§1 table): SendText/Run escaped literal; SendKeys `$`-prefixed validated token; Window enum call on `"A"`; Remap `origin::dest`; Disable `::return`; Raw `::{ body }`. Note the auto-`$` rule (§5) and that Raw is unchecked.

- [ ] **Step 4: Commit**

```bash
git add CONTEXT.md docs/adr/0004-hotkey-typed-actions-and-raw-escape-hatch.md docs/development/ahk-v2-syntax.md
git commit -m "docs: W1 hotkey terms, ADR 0004, per-kind emission"
```

---

## Self-Review

**Spec coverage (§8 backend + §11):**
- Enums (`HotkeyActionKind`/`WindowOp`/`RunTargetKind`) → Task 1. `WindowMatchType` reuse is W3 (out of scope). ✓
- Typed columns + drop legacy → Tasks 4 (add) + 11 (drop). ✓
- `HotkeyDefinition`/`Apply` typed → Tasks 4, 11. ✓
- Per-kind emitter + `$` + Window forms → Task 5. ✓
- Grouping by `(ContextMatchType, ContextValue)` in `AhkScriptGenerator` → **W3** (context columns are W3); not in this plan. ✓ (noted)
- Five role validators + kind-conditional + relaxed denylist → Tasks 2, 3, 7. ✓
- Unique index → unchanged at W1 (combo/context are W2/W3). ✓
- Migration maps legacy + converter + parity fixtures → Tasks 4, 8. ✓
- `HotkeySnapshot` typed + legacy-optional + converter in restore/revert → Task 8. ✓
- Enum values not colliding with legacy ints (converter keys off presence) → Task 1 remark + Task 8 converter. ✓
- Preview endpoint (clone) → Task 9. ✓
- Integration goldens per kind + 409 + 400 → Task 10. ✓
- CONTEXT.md W1 + ADR 0004 → Task 12. ✓
- **UI surface** (dialog, chip, display helper, grid gating, mobile list, preview panel, bUnit, E2E, `IsInlineEditable` promotion for legacy-invalid keys) → **separate UI plan** (out of scope, by design).

**Placeholder scan:** the `ValidateRawBody` placeholder in Task 7 Step 3 is explicitly removed in the same step (Raw check inlined). Migration names use `<ts>` (EF-generated timestamp) — the actual file name is produced by `dotnet ef`; commands are exact. No TBD/TODO left.

**Type consistency:** `HotkeyActionKind` field order (SendText, SendKeys, Run, Window, Remap, Disable, Raw) is identical across enum (Task 1), converter (Task 4), emitter (Task 5), DTOs (Task 6), validator (Task 7), snapshot (Task 8). `LegacyHotkeyDefinitionConverter.ToTyped` return shape is reused verbatim by the parity test (Task 4) and the snapshot converter (Task 8). `HotkeyDefinition`'s parameter list is stated in full at both its expand shape (Task 4) and contract shape (Task 11); every *construction* in this plan names its arguments, matching the convention the live call sites already follow.

**Green-at-every-task:** Tasks 1–3 additive; Task 4 additive columns (existing emitter untouched); Tasks 5–10 each end on `dotnet test AHKFlowApp.slnx` green; Task 11 drops legacy after all reads are re-pointed. The only non-incremental risk is the expand→contract seam, which is why the legacy pair is kept vestigial rather than removed mid-cutover.

---

## Resolved questions

All five closed 2026-07-22, before execution. Decisions are binding on the tasks above.

1. **Two migrations vs one — two: expand + contract.** Migration A adds the typed columns and
   back-fills (Task 4); Migration B drops `Action`/`Parameters` (Task 11). Spec §8's singular
   phrasing predates the task split. Every task ends green individually.
2. **Legacy Send→Raw body escaping (O2) — reproduce the W0-escaped RHS.** The converter emits
   `Send("say `"hi`"")`, leaving downloads byte-identical to today. Spec text saying unescaped is
   pre-W0 and stale. Confirmed empirically on 2026-07-22: `^a::Send("he said `"hi`" 100``%")` was
   downloaded from the running app and loaded without error in AutoHotkey v2, so the escaped form
   is known-good output that this wave must not change.
3. **SendKeys classification in migration T-SQL (O3) — whole C# grammar, generated and frozen.**
   Revised twice on 2026-07-22 after review. The classifier mirrors everything
   `IsValidSendKeysContent` accepts: a generated frozen literal of every `SendToken` canonical
   *and* alias spelling, a shape match for `vk`/`sc` codes, and a control-character exclusion on
   the bare-character branch. The first decision — a fixed seven-name list — only covered
   dev-seed names, so `{F5}` and `{Enter}` migrated to `Raw`. The second —
   `SendToken && RequiresBracesInSend` — still dropped `{Esc}` (alias), `{vk1}` (code) and `{a}`
   (braced printable), and its bare branch accepted a lone `\n`/`\r`/`\t` that `char.IsControl`
   rejects in C#. In each case `LegacyHotkeySnapshotConverter` and the migrated row classify the
   same value differently, so a history restore disagrees with the row it restores over. Fixtures
   now iterate the full grammar, so any gap fails the parity test. Migrating all legacy `Send` to
   `Raw` stays rejected: the seed profile alone carries `{Up}`, `{Down}`, `{Left}`, `{Right}` and
   `^v`, which would all land in the unchecked `Raw` path.
4. **`HotkeyAction` retirement home — `LegacyHotkeyDefinitionConverter.cs`.** It becomes the
   converter's legacy-input enum, next to its only remaining consumer, and keeps
   `HotkeySnapshot.Action` typed instead of widening it to `int`.
5. **Worktree ports — UI 5603 / API 5602 (SQL 14330).** Not a contradiction: AGENTS.md's
   5600/5601 describes the main checkout, spec §11 describes a worktree. Both `launchSettings.json`
   files were read on 2026-07-22 to confirm. Worktree E2E smoke targets 5602/5603.

---

## Execution Handoff

Plan saved to `docs/superpowers/plans/2026-07-22-hotkey-redesign-w1-backend-plan.md`. **Do not execute until Wave 0 merges** (this builds on the landed W0 emitter/registry/definition). Two execution options when ready:

1. **Subagent-Driven (recommended)** — fresh subagent per task, two-stage review between tasks.
2. **Inline Execution** — batch execution in-session with checkpoints (`superpowers:executing-plans`).
