# Window snap operations + Win-in-Send guardrail — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `SnapLeft` / `SnapRight` as first-class `Window` operations, move the two seeded snap samples off Raw bodies, and warn (non-blocking) when a SendKeys hotkey sends Win + an arrow key.

**Architecture:** Two enum values in the domain `WindowOp` plus its frontend numeric mirror; the half-work-area `WinMove` AHK moves from two catalog string constants into the emitter's `WindowCall` switch, so the block body lives once. The catalog's snap rows convert from `Raw(…)` to `Typed(… WindowOp.SnapLeft/SnapRight)`. The UI gains two dropdown labels (enum-driven, no markup change) and a `MudAlert` in the SendKeys panel gated on `_sendWin && arrow key`.

**Tech Stack:** .NET 10, EF Core (no migration needed), Blazor WebAssembly + MudBlazor 9.x, xUnit + FluentAssertions + bUnit + Testcontainers.

**Source spec:** `docs/superpowers/specs/2026-07-24-window-snap-and-win-send-guardrail-design.md`

## Global Constraints

- **No DB migration.** `WindowOp` persists as `int`; new enum values add no schema change and leave existing rows untouched.
- **Enum values are wire contract.** `SnapLeft = 5`, `SnapRight = 6` in *both* `AHKFlowApp.Domain/Enums/WindowOp.cs` and `AHKFlowApp.UI.Blazor/DTOs/WindowOp.cs`, with identical numeric values.
- **Catalog count stays 19.** The snap conversion is in-place — no row is added or removed by this plan. Do not touch any seed-count assertion.
- **Spec §5 is already implemented** on this branch's base (`feat: seed two SendKeys sample hotkeys`, catalog rows `Play / pause media` + `Select to end of line`, counts already 17 → 19). This plan does **not** re-do it.
- **Deviation from spec §2 — read this before Task 2.** The spec claims the emitted output is byte-identical so golden assertions do not change. That holds for SnapLeft but **not** SnapRight: the existing catalog constant emits width `(r - l) // 2`, while spec §1's formula emits `r - (l + (r - l) // 2)` (the fix for odd work-area widths). Task 2 therefore updates one existing assertion in `AhkScriptGeneratorIntegrationTests`. This is intentional — the new formula is the spec's, and it is what closes the uncovered-strip gap.
- `dotnet format` runs via hook after edits — do not revert its changes.
- Run `dotnet build` and `dotnet test` before opening a PR.

---

### Task 1: Domain enum values + emitter snap bodies

**Files:**
- Modify: `src/Backend/AHKFlowApp.Domain/Enums/WindowOp.cs:19`
- Modify: `src/Backend/AHKFlowApp.Application/Services/HotkeyEmitter.cs:41-49`
- Test: `tests/AHKFlowApp.Application.Tests/Services/HotkeyEmitterTests.cs`
- Test: `tests/AHKFlowApp.Application.Tests/Validation/HotkeyKindConditionalRulesTests.cs`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `AHKFlowApp.Domain.Enums.WindowOp.SnapLeft` (= 5) and `.SnapRight` (= 6). `HotkeyEmitter.Emit(Hotkey)` returns a multi-line brace block for those two ops; every other op keeps its one-line form.

- [ ] **Step 1: Write the two failing emitter tests**

Add after the `Emit_Window_Restore` test in `tests/AHKFlowApp.Application.Tests/Services/HotkeyEmitterTests.cs` (currently ends at line 51):

```csharp
    // Snap is the only Window op with a block body: the half-work-area WinMove needs three
    // statements. Pinned byte-for-byte because this string is what lands in the user's script.
    [Fact]
    public void Emit_Window_SnapLeft() =>
        Line(new HotkeyBuilder().WithKey("Left").WithCtrl().WithAlt().WithWindow(WindowOp.SnapLeft))
            .Should().Be(
                "^!Left::{\n" +
                "    WinRestore(\"A\")\n" +
                "    MonitorGetWorkArea(MonitorGetPrimary(), &l, &t, &r, &b)\n" +
                "    WinMove(l, t, (r - l) // 2, b - t, \"A\")\n" +
                "}");

    // SnapRight's width is measured back from r rather than repeating (r - l) // 2, so an odd
    // work-area width leaves no uncovered strip between the two halves.
    [Fact]
    public void Emit_Window_SnapRight() =>
        Line(new HotkeyBuilder().WithKey("Right").WithCtrl().WithAlt().WithWindow(WindowOp.SnapRight))
            .Should().Be(
                "^!Right::{\n" +
                "    WinRestore(\"A\")\n" +
                "    MonitorGetWorkArea(MonitorGetPrimary(), &l, &t, &r, &b)\n" +
                "    WinMove(l + (r - l) // 2, t, r - (l + (r - l) // 2), b - t, \"A\")\n" +
                "}");
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~HotkeyEmitterTests.Emit_Window_Snap"`

Expected: **compile error** — `'WindowOp' does not contain a definition for 'SnapLeft'`. A compile failure is the correct red here; the enum member does not exist yet.

- [ ] **Step 3: Add the two enum values**

In `src/Backend/AHKFlowApp.Domain/Enums/WindowOp.cs`, after `ToggleAlwaysOnTop = 4,`:

```csharp

    /// <summary>Left half of the primary monitor's work area — a <c>WinMove</c> block body.</summary>
    SnapLeft = 5,

    /// <summary>Right half of the primary monitor's work area — a <c>WinMove</c> block body.</summary>
    SnapRight = 6,
```

- [ ] **Step 4: Add the emitter cases**

In `src/Backend/AHKFlowApp.Application/Services/HotkeyEmitter.cs`, add two arms to `WindowCall` immediately after the `ToggleAlwaysOnTop` arm (before the `_ =>` default):

```csharp
        WindowOp.SnapLeft => SnapBody("l", "(r - l) // 2"),
        WindowOp.SnapRight => SnapBody("l + (r - l) // 2", "r - (l + (r - l) // 2)"),
```

Then add this private helper directly below the `WindowCall` method (above `RemapRhs`):

```csharp
    // Snap to one half of the PRIMARY monitor's work area (which excludes the taskbar). WinRestore
    // first so a maximized window can be moved; `//` is AHK integer division. The right half's width
    // is measured back from r instead of reusing the left half's, so an odd work-area width leaves
    // no uncovered strip. Resolving the window's own monitor is a later refinement (design non-goal).
    private static string SnapBody(string x, string width) =>
        "{\n" +
        $"    WinRestore({ActiveWindow})\n" +
        "    MonitorGetWorkArea(MonitorGetPrimary(), &l, &t, &r, &b)\n" +
        $"    WinMove({x}, t, {width}, b - t, {ActiveWindow})\n" +
        "}";
```

- [ ] **Step 5: Run the emitter tests to verify they pass**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~HotkeyEmitterTests"`

Expected: PASS, all tests in the class.

- [ ] **Step 6: Write the validator test**

`HotkeyRules` gates `Window` with `d.WindowOp is not WindowOp op || !Enum.IsDefined(op)`, so the new values are accepted automatically — this test pins that. Add to `tests/AHKFlowApp.Application.Tests/Validation/HotkeyKindConditionalRulesTests.cs`, after the existing `Raw` body tests (around line 223):

```csharp
    // Enum.IsDefined is the whole Window gate, so new WindowOp values need no validator change.
    // Pinned so a future "allowed ops" list cannot silently drop snap.
    [Theory]
    [InlineData(WindowOp.SnapLeft)]
    [InlineData(WindowOp.SnapRight)]
    public void Window_AcceptsSnapOps(WindowOp op) =>
        Validate(Base(HotkeyActionKind.Window) with { WindowOp = op }).IsValid.Should().BeTrue();
```

- [ ] **Step 7: Run the validator test**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~HotkeyKindConditionalRulesTests"`

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add src/Backend/AHKFlowApp.Domain/Enums/WindowOp.cs src/Backend/AHKFlowApp.Application/Services/HotkeyEmitter.cs tests/AHKFlowApp.Application.Tests/Services/HotkeyEmitterTests.cs tests/AHKFlowApp.Application.Tests/Validation/HotkeyKindConditionalRulesTests.cs
git commit -m "feat: emit SnapLeft/SnapRight WindowOp block bodies"
```

---

### Task 2: Catalog snap samples become `Window` kind

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Constants/DefaultHotkeyCatalog.cs:35-45` (rows + comment) and `:88-105` (delete two constants)
- Test: `tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorIntegrationTests.cs:139-140`

**Interfaces:**
- Consumes: `WindowOp.SnapLeft` / `WindowOp.SnapRight` and the emitter block bodies from Task 1.
- Produces: no new API. `DefaultHotkeyCatalog.All` keeps 19 rows; the two snap rows now report `HotkeyActionKind.Window` instead of `Raw`.

- [ ] **Step 1: Update the integration-test assertion to the new SnapRight width**

This is the one place the emitted text changes (see the Global Constraints deviation note). In `tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorIntegrationTests.cs`, replace line 140:

```csharp
        output.Should().Contain("    WinMove(l + (r - l) // 2, t, (r - l) // 2, b - t, \"A\")");
```

with:

```csharp
        output.Should().Contain("    WinMove(l + (r - l) // 2, t, r - (l + (r - l) // 2), b - t, \"A\")");
```

Leave lines 137-139 exactly as they are — SnapLeft's emit and both `::{\n    WinRestore("A")` prefixes are unchanged.

- [ ] **Step 2: Run the integration test to verify it fails**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~AhkScriptGeneratorIntegrationTests.Generate_FromSeededCatalog_EmitsCorrectedAndNewLines"`

Expected: FAIL — the catalog still seeds the old Raw constant, so the output contains the old width string, not the new one. (Requires Docker: this test uses the SQL Server Testcontainer fixture.)

- [ ] **Step 3: Convert the two catalog rows**

In `src/Backend/AHKFlowApp.Application/Constants/DefaultHotkeyCatalog.cs`, replace lines 44-45:

```csharp
        Raw("Snap window left",  true, true, false, false, "Left",  SnapLeftBody,  ["Window Management"]),
        Raw("Snap window right", true, true, false, false, "Right", SnapRightBody, ["Window Management"]),
```

with:

```csharp
        Typed("Snap window left",  "Left",  HotkeyActionKind.Window, ["Window Management"],
            ctrl: true, alt: true, windowOp: WindowOp.SnapLeft),
        Typed("Snap window right", "Right", HotkeyActionKind.Window, ["Window Management"],
            ctrl: true, alt: true, windowOp: WindowOp.SnapRight),
```

- [ ] **Step 4: Update the comment above those rows**

The comment block at lines 35-39 still says snap needs a Raw body. Replace its last sentence — `Max/Min use the typed Window kind; snap L/R need a half-work-area WinMove that no WindowOp expresses, so they are Raw bodies.` — with:

```
        // window functions are deterministic. All four use the typed Window kind; the snap pair's
        // half-work-area WinMove block lives in the emitter, not here.
```

Keep the preceding sentences (the `LLKHF_INJECTED` / Aero-Snap explanation) verbatim — they are still the reason these rows are not SendKeys.

- [ ] **Step 5: Delete the two Raw body constants**

Remove lines 88-105 of the same file in full — the `// Snap the active window to the left/right half…` comment block plus both `SnapLeftBody` and `SnapRightBody` constants. Leave `PastePlainTextBody` (lines 75-86) untouched.

- [ ] **Step 6: Run the integration test to verify it passes**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~AhkScriptGeneratorIntegrationTests"`

Expected: PASS.

- [ ] **Step 7: Run the seed-count suites to prove the count is unchanged**

Run:

```bash
dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~SeedHotkeysCommandHandlerTests|FullyQualifiedName~ListHotkeysLazySeedTests|FullyQualifiedName~SeedAllCommandHandlerTests"
```

Expected: PASS with no edits — the catalog is still 19 rows.

- [ ] **Step 8: Commit**

```bash
git add src/Backend/AHKFlowApp.Application/Constants/DefaultHotkeyCatalog.cs tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorIntegrationTests.cs
git commit -m "refactor: seed snap samples as Window kind, drop Raw bodies"
```

---

### Task 3: Frontend enum mirror + snap labels

**Files:**
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/WindowOp.cs:10`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Helpers/HotkeyActionDisplay.cs:60-68`
- Create: `tests/AHKFlowApp.UI.Blazor.Tests/DTOs/WindowOpTests.cs`
- Test: `tests/AHKFlowApp.UI.Blazor.Tests/Helpers/HotkeyActionDisplayTests.cs`
- Test: `tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotkeys/HotkeyEditDialogTests.cs`

**Interfaces:**
- Consumes: the numeric values fixed in Task 1 (`SnapLeft = 5`, `SnapRight = 6`) — the frontend enum must match them exactly.
- Produces: `AHKFlowApp.UI.Blazor.DTOs.WindowOp.SnapLeft` / `.SnapRight`, and `HotkeyActionDisplay.WindowOpLabel` returning `"Snap left"` / `"Snap right"`. The `HotkeyEditDialog` op dropdown enumerates this frontend enum via `Enum.GetValues<WindowOp>()`, so it picks the entries up with no markup change.

- [ ] **Step 1: Write the wire-value pin test**

The frontend enum is deserialized from an int and hand-mirrors the domain enum, so its ordinals are contract. This mirrors the existing `HotstringImportRowStatusTests` precedent. Create `tests/AHKFlowApp.UI.Blazor.Tests/DTOs/WindowOpTests.cs`:

```csharp
using AHKFlowApp.UI.Blazor.DTOs;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.DTOs;

public sealed class WindowOpTests
{
    [Theory]
    [InlineData(WindowOp.Minimize, 0)]
    [InlineData(WindowOp.Maximize, 1)]
    [InlineData(WindowOp.Restore, 2)]
    [InlineData(WindowOp.Close, 3)]
    [InlineData(WindowOp.ToggleAlwaysOnTop, 4)]
    [InlineData(WindowOp.SnapLeft, 5)]
    [InlineData(WindowOp.SnapRight, 6)]
    public void OrdinalValue_MatchesBackendMirror(WindowOp op, int expected)
    {
        // WindowOp is deserialized from an int and hand-mirrors
        // AHKFlowApp.Domain.Enums.WindowOp — these ordinals must stay in lockstep with that file.
        ((int)op).Should().Be(expected);
    }
}
```

- [ ] **Step 2: Write the two failing label tests**

Add to `tests/AHKFlowApp.UI.Blazor.Tests/Helpers/HotkeyActionDisplayTests.cs`, after `Summary_Window_IsOperationLabel` (currently ends at line 81):

```csharp
    [Theory]
    [InlineData(WindowOp.SnapLeft, "Snap left")]
    [InlineData(WindowOp.SnapRight, "Snap right")]
    public void WindowOpLabel_Snap_IsHumanReadable(WindowOp op, string expected) =>
        HotkeyActionDisplay.WindowOpLabel(op).Should().Be(expected);
```

- [ ] **Step 3: Run both tests to verify they fail**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~WindowOpTests|FullyQualifiedName~WindowOpLabel_Snap"`

Expected: **compile error** — `'WindowOp' does not contain a definition for 'SnapLeft'` (the frontend mirror, not the domain one).

- [ ] **Step 4: Add the frontend enum values**

In `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/WindowOp.cs`, after `ToggleAlwaysOnTop = 4,`:

```csharp
    SnapLeft = 5,
    SnapRight = 6,
```

- [ ] **Step 5: Add the two labels**

In `src/Frontend/AHKFlowApp.UI.Blazor/Helpers/HotkeyActionDisplay.cs`, add two arms to `WindowOpLabel` after the `ToggleAlwaysOnTop` arm:

```csharp
        DTOs.WindowOp.SnapLeft => "Snap left",
        DTOs.WindowOp.SnapRight => "Snap right",
```

- [ ] **Step 6: Run both tests to verify they pass**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~WindowOpTests|FullyQualifiedName~WindowOpLabel_Snap"`

Expected: PASS.

- [ ] **Step 7: Add the dialog dropdown test**

The op `MudSelect` lives in a popover, so asserting on rendered `MudSelectItem`s is brittle in bUnit. Instead drive the select's `ValueChanged` with a snap value — the same technique `CorrectingWindowOp_ClearsItsStaleSaveError` uses at line 422 — which proves the dropdown is typed to carry it and the dialog stores it. Add to `tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotkeys/HotkeyEditDialogTests.cs`, after `CorrectingWindowOp_ClearsItsStaleSaveError` (currently ends at line 427):

```csharp
    // The op dropdown enumerates the frontend WindowOp, so a value missing there is a value the
    // user cannot pick. Driving ValueChanged is what selecting the item does, minus the popover.
    [Theory]
    [InlineData(WindowOp.SnapLeft)]
    [InlineData(WindowOp.SnapRight)]
    public async Task WindowPanel_AcceptsSnapOps(WindowOp op)
    {
        HotkeyEditModel item = new() { Description = "d", Key = "n", ActionKind = HotkeyActionKind.Window };
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(item);

        await provider.InvokeAsync(() => provider.FindComponent<MudSelect<WindowOp?>>()
            .Instance.ValueChanged.InvokeAsync(op));

        item.WindowOp.Should().Be(op);
    }
```

- [ ] **Step 8: Run the dialog test suite**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HotkeyEditDialogTests"`

Expected: PASS, all tests in the class.

- [ ] **Step 9: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/DTOs/WindowOp.cs src/Frontend/AHKFlowApp.UI.Blazor/Helpers/HotkeyActionDisplay.cs tests/AHKFlowApp.UI.Blazor.Tests/DTOs/WindowOpTests.cs tests/AHKFlowApp.UI.Blazor.Tests/Helpers/HotkeyActionDisplayTests.cs tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotkeys/HotkeyEditDialogTests.cs
git commit -m "feat: snap ops in frontend WindowOp mirror and labels"
```

---

### Task 4: Win + Arrow warning in the SendKeys panel

**Files:**
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Helpers/HotkeyActionDisplay.cs:18-19` (add a second constant beside `RawWarningText`)
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyEditDialog.razor:83-99` (alert) and the `@code` block near `:307`
- Test: `tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotkeys/HotkeyEditDialogTests.cs`

**Interfaces:**
- Consumes: `HotkeyActionDisplay.WindowOpLabel` wording from Task 3 (the warning text names "Snap left / Snap right").
- Produces: `HotkeyActionDisplay.SendWinArrowWarningText` (const string) and a `data-test="send-win-arrow-warning"` element in the SendKeys panel.

- [ ] **Step 1: Add an arrow key to the test catalog**

The dialog's test double (`CatalogKeys`, line 20-25) has no arrow key, so no test can select one. Replace the array with:

```csharp
    private static readonly HotkeyKeyDto[] CatalogKeys =
    [
        new("F1", "Function keys", ["HotkeyKey", "RemapDest", "SendToken"], true),
        new("c", "Letters & digits", ["HotkeyKey", "RemapDest", "SendToken"], false),
        new("Volume_Up", "Media & browser", ["SendToken"], true),
        new("Left", "Navigation & editing", ["HotkeyKey", "RemapDest", "SendToken"], true),
    ];
```

`Left` is a named key in the real registry (`HotkeyKeys.s_namedKeys`), carries all roles, and has `RequiresBracesInSend: true` — this mirrors it.

- [ ] **Step 2: Write the three failing warning tests**

Add to `tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotkeys/HotkeyEditDialogTests.cs`, after `SendKeysPanel_StoredTokenDecomposesIntoCheckboxesAndKey` (currently ends at line 500):

```csharp
    // Injected Win is not honoured by the shell's Aero-Snap handler, so Send("#{Left}") silently
    // does nothing. The warning is advisory only — see SendKeysPanel_WinArrowWarning_DoesNotBlockSave.
    [Fact]
    public async Task SendKeysPanel_WinPlusArrow_ShowsTheSnapWarning()
    {
        HotkeyEditModel item = new() { ActionKind = HotkeyActionKind.SendKeys };
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(item);

        provider.Find("input[data-test=\"send-win-checkbox\"]").Change(true);
        await SetKeyAsync(provider, "send-key-picker", "Left");

        provider.WaitForAssertion(() => provider.Find("[data-test=\"send-win-arrow-warning\"]")
            .TextContent.Should().Contain("won't snap the window"));
    }

    // Send "#e" really does open Explorer, so a blanket all-Win warning would be wrong: only the
    // arrow gesture is documented to fail.
    [Fact]
    public async Task SendKeysPanel_WinPlusNonArrow_ShowsNoWarning()
    {
        HotkeyEditModel item = new() { ActionKind = HotkeyActionKind.SendKeys };
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(item);

        provider.Find("input[data-test=\"send-win-checkbox\"]").Change(true);
        await SetKeyAsync(provider, "send-key-picker", "c");

        provider.FindAll("[data-test=\"send-win-arrow-warning\"]").Should().BeEmpty();
    }

    [Fact]
    public async Task SendKeysPanel_ArrowWithoutWin_ShowsNoWarning()
    {
        HotkeyEditModel item = new() { ActionKind = HotkeyActionKind.SendKeys };
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(item);

        await SetKeyAsync(provider, "send-key-picker", "Left");

        provider.FindAll("[data-test=\"send-win-arrow-warning\"]").Should().BeEmpty();
    }

    // Non-blocking by design: the token is valid AHK and the user may have a reason.
    [Fact]
    public async Task SendKeysPanel_WinArrowWarning_DoesNotBlockSave()
    {
        HotkeyDto created = new(Guid.NewGuid(), [], true, "Snap attempt", "n", true, false, false, false,
            HotkeyActionKind.SendKeys, null, "#{Left}", null, null, null, null, null,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        _api.CreateAsync(Arg.Any<CreateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Ok(created));

        HotkeyEditModel item = new() { Description = "Snap attempt", Key = "n", ActionKind = HotkeyActionKind.SendKeys };
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(item);

        provider.Find("input[data-test=\"send-win-checkbox\"]").Change(true);
        await SetKeyAsync(provider, "send-key-picker", "Left");
        provider.Find("button.commit-edit").Click();

        provider.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotkeyDto>(d => d.SendKeysContent == "#{Left}"),
            Arg.Any<CancellationToken>()));
    }
```

The `HotkeyDto` positional argument list follows `HotkeyDto.cs`: id, profile ids, applies-to-all, description, key, ctrl, alt, shift, win, kind, then the seven payload slots (`Text`, `SendKeysContent`, `RunTarget`, `RunTargetKind`, `WindowOp`, `RemapDest`, `Body`), then the two timestamps. `"#{Left}"` sits in the second payload slot, `SendKeysContent`.

- [ ] **Step 3: Run the tests to verify they fail**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~SendKeysPanel_Win|FullyQualifiedName~SendKeysPanel_Arrow"`

Expected: FAIL — `SendKeysPanel_WinPlusArrow_ShowsTheSnapWarning` throws `ElementNotFoundException` for `[data-test="send-win-arrow-warning"]`. The three negative/save tests pass already (nothing renders yet); that is fine — they are regression guards for the next step.

- [ ] **Step 4: Add the warning constant**

In `src/Frontend/AHKFlowApp.UI.Blazor/Helpers/HotkeyActionDisplay.cs`, directly below `RawWarningText` (line 19):

```csharp

    /// <summary>
    /// Advisory shown when a SendKeys row sends Win + an arrow. Injected LWin (SendInput's atomic
    /// batch, flagged LLKHF_INJECTED) is not honoured by the shell's Aero-Snap handler, so the send
    /// silently does nothing. Non-blocking: the token is valid AHK and Save is unaffected. Scoped to
    /// arrows only — injected Win *does* fire some shortcuts (Send "#e" opens Explorer).
    /// </summary>
    public const string SendWinArrowWarningText =
        "Sending Win + Arrow won't snap the window — Windows ignores injected Win for Aero Snap. " +
        "To snap the active window, use a Window action (Snap left / Snap right). " +
        "For other Win shortcuts, use Raw.";
```

- [ ] **Step 5: Add the arrow-detection helper to the dialog**

In `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyEditDialog.razor`, add this computed property to the `@code` block, directly below the `_sendKey` field declaration (line 307):

```csharp
    // The four arrow canonicals from the key registry. Compared case-insensitively because a stored
    // token is decomposed back into _sendKey verbatim, and AHK itself is case-insensitive on key names.
    private static readonly string[] s_arrowKeys = ["Up", "Down", "Left", "Right"];

    private bool ShowSendWinArrowWarning =>
        _sendWin && _sendKey is not null && s_arrowKeys.Contains(_sendKey, StringComparer.OrdinalIgnoreCase);
```

- [ ] **Step 6: Render the alert**

In the same file, inside the SendKeys panel `<div data-test="sendkeys-panel">`, after the closing `</MudStack>` of the modifier row and before the `<KeyPicker …>` (i.e. between lines 93 and 94):

```razor
                        @if (ShowSendWinArrowWarning)
                        {
                            <MudAlert Severity="Severity.Warning" Dense="true" Class="mb-2"
                                      UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "send-win-arrow-warning" })">
                                @HotkeyActionDisplay.SendWinArrowWarningText
                            </MudAlert>
                        }
```

This mirrors the Raw panel's alert at line 155-158 exactly, minus the `@if` gate.

- [ ] **Step 7: Run the four tests to verify they pass**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~SendKeysPanel"`

Expected: PASS, including the two pre-existing `SendKeysPanel_*` compose/decompose tests.

- [ ] **Step 8: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Helpers/HotkeyActionDisplay.cs src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyEditDialog.razor tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotkeys/HotkeyEditDialogTests.cs
git commit -m "feat: warn on SendKeys Win+Arrow, steer to Window snap"
```

---

### Task 5: Document the snap emit in the AHK v2 syntax reference

**Files:**
- Modify: `docs/development/ahk-v2-syntax.md:322` (the `Window` row of the per-action table) and `:334-335` (insert after the example block)

**Interfaces:**
- Consumes: the exact emitted strings pinned by Task 1's emitter tests. The doc must quote them verbatim.
- Produces: nothing consumed by other tasks.

The base branch deliberately reverted these rows (`docs: revert snap doc rows, keep snap out of this PR`) so the doc never described ops the code lacked. This task restores them now that the code exists.

- [ ] **Step 1: Extend the `Window` row of the per-action table**

In `docs/development/ahk-v2-syntax.md`, replace line 322:

```markdown
| `Window` | `WindowOp` | `WinMinimize("A")`, `WinMaximize("A")`, `WinRestore("A")`, `WinClose("A")`, `WinSetAlwaysOnTop(-1, "A")` |
```

with:

```markdown
| `Window` | `WindowOp` | five one-line ops — `WinMinimize("A")`, `WinMaximize("A")`, `WinRestore("A")`, `WinClose("A")`, `WinSetAlwaysOnTop(-1, "A")` — plus two block-bodied snap ops (see below) |
```

- [ ] **Step 2: Add the snap paragraph**

Insert immediately after the fenced `ahk` example block that ends with `F1::return` (line 334) and before the `Only the three kinds that embed user text…` paragraph:

````markdown
`Window`'s two snap ops (`SnapLeft`, `SnapRight`) are the only non-one-line emit: each is a
brace block that restores the window, reads the **primary** monitor's work area
(`MonitorGetWorkArea(MonitorGetPrimary(), &l, &t, &r, &b)`), then `WinMove`s to the left or right
half. SnapRight's width is `r - (l + (r-l)//2)` so an odd work-area width still reaches `r`:

```ahk
^!Left::
{
    WinRestore("A")
    MonitorGetWorkArea(MonitorGetPrimary(), &l, &t, &r, &b)
    WinMove(l, t, (r - l) // 2, b - t, "A")
}
```
````

- [ ] **Step 3: Verify the doc matches the emitter**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~HotkeyEmitterTests.Emit_Window_Snap" --verbosity normal`

Expected: PASS. Then read the two expected strings in those tests and confirm the `WinMove` lines quoted in the doc are character-identical.

- [ ] **Step 4: Commit**

```bash
git add docs/development/ahk-v2-syntax.md
git commit -m "docs: document block-bodied snap ops"
```

---

### Task 6: Full verification

**Files:** none modified — this task only runs and reports.

- [ ] **Step 1: Build the solution**

Run: `dotnet build --configuration Release`

Expected: 0 errors, 0 new warnings.

- [ ] **Step 2: Run the full test suite**

Run: `dotnet test --configuration Release --no-build`

Expected: all green. Docker must be running — the Application and API integration suites use SQL Server Testcontainers.

- [ ] **Step 3: Check formatting**

Run: `dotnet format --verify-no-changes`

Expected: no diff. If it reports changes, run `dotnet format` and amend the owning commit.

- [ ] **Step 4: Report**

State the actual `dotnet test` summary line (passed/failed/skipped counts). If anything failed, quote the shortest decisive failure line — do not claim completion.

---

## Unresolved questions

1. SnapRight width changes from `(r-l)//2` to `r-(l+(r-l)//2)` — spec's formula, breaks §2's "byte-identical" claim. Confirm OK?
2. Warning copy: spec has bold markdown (`**Window**`, `**Raw**`); `MudAlert` renders plain text. Plan drops the asterisks. Want bold via markup instead?
