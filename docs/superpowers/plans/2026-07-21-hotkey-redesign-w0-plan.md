# Hotkey Redesign — Wave 0 (Safety + Foundation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Escape hotkey output at emission and validate hotkey keys against a real registry, closing the escaping half of issue #195 without changing the action model.

**Architecture:** Extract the inline `AhkScriptGenerator.FormatHotkey` into a `HotkeyEmitter` that routes free text through an escape routine now *shared* with `HotstringEmitter`. Add a canonical key registry with per-role capability flags, and swap the interim character denylist on `Key` for real registry/`vk`/`sc` validation. Collapse the 10-argument `Hotkey.Create`/`Restore`/`Update` signatures into a flat `HotkeyDefinition` record, mirroring `HotstringDefinition`. No new actions, no new columns, no migration.

**Tech Stack:** .NET 10, EF Core, FluentValidation, Ardalis.Result, xUnit + FluentAssertions.

**Source spec:** `docs/superpowers/specs/2026-07-21-hotkey-redesign-design.md` (§5, §9 W0).

## Global Constraints

- Target framework `net10.0`; Microsoft.* packages on 10.x.
- Primary constructors for DI; records for DTOs/commands/value objects; file-scoped namespaces; Allman braces; `sealed` by default; `internal` unless a wider surface is needed.
- No repository pattern — handlers inject `AppDbContext` directly. No AutoMapper/Mapster — explicit mapping.
- Handlers return `Result<T>`; controllers map via `result.ToActionResult(this)`.
- Propagate `CancellationToken` through every async call. No `.Result` / `.Wait()`.
- FluentAssertions over raw `Assert`. Test naming `MethodName_Scenario_ExpectedResult`. AAA with blank-line separation.
- Builder pattern for test data — `tests/AHKFlowApp.TestUtilities/Builders/`.
- Conventional commits, extremely concise. Atomic: one logical change per commit, feature + its tests together.
- **`dotnet format` needs an explicit workspace** — bare `dotnet format` fails with "Both a MSBuild project file and solution file found". Always `dotnet format AHKFlowApp.slnx`.
- **This is a worktree** (`feature/wt-hotkey-redesign`). Commit here, never in the main checkout.
- **Behavior-preserving except for escaping.** W0 must not change which hotkeys emit, their order, or their action semantics. The one intended output change is that `Parameters` is now escaped.

---

## File Structure

**Create:**
- `src/Backend/AHKFlowApp.Application/Services/AhkEscaping.cs` — AHK v2 string-literal escaping, shared by both emitters. Sole owner of the backtick-first ordering rule.
- `src/Backend/AHKFlowApp.Application/Services/HotkeyEmitter.cs` — single emission point for a hotkey line.
- `src/Backend/AHKFlowApp.Application/Constants/HotkeyKeys.cs` — canonical key registry, alias table, `vk`/`sc` grammar, canonicalization.
- `src/Backend/AHKFlowApp.Domain/Entities/HotkeyDefinition.cs` — flat record of every definitional field.
- `tests/AHKFlowApp.Application.Tests/Services/AhkEscapingTests.cs`
- `tests/AHKFlowApp.Application.Tests/Services/HotkeyEmitterTests.cs`
- `tests/AHKFlowApp.Application.Tests/Constants/HotkeyKeysTests.cs`
- `tests/AHKFlowApp.Application.Tests/Validation/HotkeyRulesTests.cs`

**Modify:**
- `src/Backend/AHKFlowApp.Application/Services/HotstringEmitter.cs` — drop the private `EscapeStringLiteral`, call `AhkEscaping`.
- `src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs` — delete `FormatHotkey`, delegate to `HotkeyEmitter`.
- `src/Backend/AHKFlowApp.Domain/Entities/Hotkey.cs` — definition-based factories + private `Apply`.
- `src/Backend/AHKFlowApp.Application/Validation/HotkeyRules.cs` — registry-backed `ValidKey`, relaxed `ValidParameters`.
- `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/CreateHotkeyCommand.cs`, `UpdateHotkeyCommand.cs`, `RestoreHotkeyCommand.cs`, `RevertHotkeyCommand.cs`
- `src/Backend/AHKFlowApp.Application/Queries/Hotkeys/ListHotkeysQuery.cs` — lazy-seed call site.
- `src/Backend/AHKFlowApp.Application/Commands/Dev/SeedHotkeysCommand.cs`
- `tests/AHKFlowApp.TestUtilities/Builders/HotkeyBuilder.cs`
- `tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorTests.cs`
- `docs/development/ahk-v2-syntax.md`

**Why `AhkEscaping` is its own file:** two emitters need it, and the backtick-first ordering is the single rule most likely to be silently broken by a well-meaning edit. It gets one home and one test.

---

### Task 1: Shared AHK escaping helper

Pure refactor. `HotstringEmitter` keeps byte-identical output; the new file just becomes its owner so `HotkeyEmitter` can reuse it in Task 2 instead of cloning it.

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/Services/AhkEscaping.cs`
- Create: `tests/AHKFlowApp.Application.Tests/Services/AhkEscapingTests.cs`
- Modify: `src/Backend/AHKFlowApp.Application/Services/HotstringEmitter.cs:215-221`

**Interfaces:**
- Consumes: nothing.
- Produces: `internal static class AhkEscaping` with `public static string EscapeStringLiteral(string value)`.

- [ ] **Step 1: Write the failing test**

Create `tests/AHKFlowApp.Application.Tests/Services/AhkEscapingTests.cs`:

```csharp
using AHKFlowApp.Application.Services;
using FluentAssertions;

namespace AHKFlowApp.Application.Tests.Services;

public sealed class AhkEscapingTests
{
    [Fact]
    public void EscapeStringLiteral_Backtick_IsEscapedFirst()
    {
        string result = AhkEscaping.EscapeStringLiteral("a`nb");

        result.Should().Be("a``nb");
    }

    [Fact]
    public void EscapeStringLiteral_DoubleQuote_IsEscaped()
    {
        string result = AhkEscaping.EscapeStringLiteral("he said \"hi\"");

        result.Should().Be("he said `\"hi`\"");
    }

    [Fact]
    public void EscapeStringLiteral_Whitespace_IsEscaped()
    {
        string result = AhkEscaping.EscapeStringLiteral("a\r\nb\tc");

        result.Should().Be("a`r`nb`tc");
    }

    [Fact]
    public void EscapeStringLiteral_PlainText_IsUnchanged()
    {
        string result = AhkEscaping.EscapeStringLiteral("notepad.exe");

        result.Should().Be("notepad.exe");
    }
}
```

The first test is the ordering guard. A literal backtick-n in the input must become an escaped backtick followed by `n` — if backtick replacement ran *last*, the routine would emit a three-character sequence instead.

- [ ] **Step 2: Run test to verify it fails**

```bash
dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~AhkEscapingTests"
```

Expected: FAIL — `The type or namespace name 'AhkEscaping' could not be found`.

- [ ] **Step 3: Write the implementation**

Create `src/Backend/AHKFlowApp.Application/Services/AhkEscaping.cs`:

```csharp
namespace AHKFlowApp.Application.Services;

/// <summary>
/// AHK v2 string-literal escaping, shared by <see cref="HotstringEmitter"/> and
/// <see cref="HotkeyEmitter"/>. Used for the contents of a quoted literal —
/// <c>SendText "..."</c>, <c>Send "..."</c>, <c>Run("...")</c>.
/// </summary>
internal static class AhkEscaping
{
    /// <summary>
    /// Escapes a value for embedding inside an AHK v2 quoted string literal.
    /// </summary>
    /// <remarks>
    /// The backtick must be replaced <em>first</em>. Escaping it after the others would
    /// re-escape the backticks they just introduced, turning <c>`n</c> into <c>``n</c>.
    /// Note this differs from the hotstring <c>Escape</c> routine, which escapes <c>;</c>
    /// but not <c>"</c> — that one is for unquoted inline replacements, where a quote is
    /// just a character and a semicolon would start a comment.
    /// </remarks>
    public static string EscapeStringLiteral(string value) =>
        value
            .Replace("`", "``")
            .Replace("\"", "`\"")
            .Replace("\n", "`n")
            .Replace("\r", "`r")
            .Replace("\t", "`t");
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~AhkEscapingTests"
```

Expected: PASS, 4 tests.

- [ ] **Step 5: Point HotstringEmitter at the shared helper**

In `src/Backend/AHKFlowApp.Application/Services/HotstringEmitter.cs`, delete the private method at the bottom of the class:

```csharp
    private static string EscapeStringLiteral(string value) =>
        value
            .Replace("`", "``")
            .Replace("\"", "`\"")
            .Replace("\n", "`n")
            .Replace("\r", "`r")
            .Replace("\t", "`t");
```

Then replace its two call sites with the shared helper. At line ~112:

```csharp
        return $"{PasteHelperName}(\"{AhkEscaping.EscapeStringLiteral(hs.Replacement)}\"{endCharArgument})";
```

At line ~156:

```csharp
            lines.Add($"SendText \"{AhkEscaping.EscapeStringLiteral(textAccumulator.ToString())}\"");
```

Both files are in the same namespace (`AHKFlowApp.Application.Services`), so no `using` is needed.

- [ ] **Step 6: Verify hotstring output is unchanged**

```bash
dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~HotstringEmitter|FullyQualifiedName~AhkScriptGenerator"
```

Expected: PASS, no failures. These are the existing goldens — they are the proof this refactor changed nothing.

- [ ] **Step 7: Commit**

```bash
dotnet format AHKFlowApp.slnx
git add src/Backend/AHKFlowApp.Application/Services/AhkEscaping.cs \
        src/Backend/AHKFlowApp.Application/Services/HotstringEmitter.cs \
        tests/AHKFlowApp.Application.Tests/Services/AhkEscapingTests.cs
git commit -m "refactor: extract shared AhkEscaping helper

hotkey emitter needs same routine; one home for backtick-first rule"
```

---

### Task 2: HotkeyEmitter with escaping

This is the task that closes the escaping half of #195. Because emission is a single point, escaping applies to every row regardless of how it was written — including the paths that bypass validators (restore, revert, lazy seed).

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/Services/HotkeyEmitter.cs`
- Create: `tests/AHKFlowApp.Application.Tests/Services/HotkeyEmitterTests.cs`
- Modify: `src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs:76,85-101`
- Modify: `tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorTests.cs:424-439`

**Interfaces:**
- Consumes: `AhkEscaping.EscapeStringLiteral(string)` from Task 1.
- Produces: `internal static class HotkeyEmitter` with `public static string Emit(Hotkey hk)`.

- [ ] **Step 1: Write the failing test**

Create `tests/AHKFlowApp.Application.Tests/Services/HotkeyEmitterTests.cs`:

```csharp
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.TestUtilities.Builders;
using FluentAssertions;

namespace AHKFlowApp.Application.Tests.Services;

public sealed class HotkeyEmitterTests
{
    [Fact]
    public void Emit_RunAction_EmitsRunCall()
    {
        Hotkey hk = new HotkeyBuilder()
            .WithKey("n")
            .WithWin()
            .WithAction(HotkeyAction.Run)
            .WithParameters("notepad")
            .Build();

        string line = HotkeyEmitter.Emit(hk);

        line.Should().Be("#n::Run(\"notepad\")");
    }

    [Fact]
    public void Emit_ModifiersSet_EmitsInFixedCtrlAltShiftWinOrder()
    {
        Hotkey hk = new HotkeyBuilder()
            .WithKey("c")
            .WithCtrl().WithAlt().WithShift().WithWin()
            .WithAction(HotkeyAction.Run)
            .WithParameters("calc.exe")
            .Build();

        string line = HotkeyEmitter.Emit(hk);

        line.Should().StartWith("^!+#c::");
    }

    [Fact]
    public void Emit_ParametersContainDoubleQuote_AreEscaped()
    {
        Hotkey hk = new HotkeyBuilder()
            .WithKey("a")
            .WithCtrl()
            .WithAction(HotkeyAction.Send)
            .WithParameters("he said \"hi\"")
            .Build();

        string line = HotkeyEmitter.Emit(hk);

        line.Should().Be("^a::Send(\"he said `\"hi`\"\")");
    }

    [Fact]
    public void Emit_ParametersContainBacktick_AreEscaped()
    {
        Hotkey hk = new HotkeyBuilder()
            .WithKey("a")
            .WithCtrl()
            .WithAction(HotkeyAction.Send)
            .WithParameters("100`% done")
            .Build();

        string line = HotkeyEmitter.Emit(hk);

        line.Should().Be("^a::Send(\"100``% done\")");
    }

    [Fact]
    public void Emit_UnsupportedAction_Throws()
    {
        Hotkey hk = new HotkeyBuilder().WithAction((HotkeyAction)99).Build();

        Action act = () => HotkeyEmitter.Emit(hk);

        act.Should().Throw<InvalidOperationException>()
            .WithMessage("*99*");
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~HotkeyEmitterTests"
```

Expected: FAIL — `The type or namespace name 'HotkeyEmitter' could not be found`.

- [ ] **Step 3: Write the implementation**

Create `src/Backend/AHKFlowApp.Application/Services/HotkeyEmitter.cs`:

```csharp
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.Services;

/// <summary>
/// Single emission point for hotkey lines, mirroring <see cref="HotstringEmitter"/>.
/// The left-hand side is modifiers in the fixed order <c>^ ! + #</c> followed by the key;
/// the right-hand side is the action call.
/// </summary>
/// <remarks>
/// Every free-text value passes through <see cref="AhkEscaping.EscapeStringLiteral"/>.
/// Because the generator and the profile download both route through here, escaping
/// reaches rows written by paths that never see a validator — history restore, history
/// revert, and the development lazy seed.
/// </remarks>
internal static class HotkeyEmitter
{
    public static string Emit(Hotkey hk)
    {
        string function = hk.Action switch
        {
            HotkeyAction.Send => "Send",
            HotkeyAction.Run => "Run",
            _ => throw new InvalidOperationException($"Unsupported HotkeyAction: {hk.Action}"),
        };

        return $"{BuildModifiers(hk)}{hk.Key}::{function}(\"{AhkEscaping.EscapeStringLiteral(hk.Parameters)}\")";
    }

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

- [ ] **Step 4: Run test to verify it passes**

```bash
dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~HotkeyEmitterTests"
```

Expected: PASS, 5 tests.

- [ ] **Step 5: Delegate from AhkScriptGenerator**

In `src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs`, change the hotkey loop body:

```csharp
        foreach (Hotkey hk in hkList)
        {
            lines.AddRange(HotstringEmitter.DescriptionCommentLines(hk.Description));
            lines.Add(HotkeyEmitter.Emit(hk));
        }
```

Then delete the entire `private static string FormatHotkey(Hotkey hk)` method from the bottom of the class. If `AHKFlowApp.Domain.Enums` is now unused in this file, remove the `using`.

- [ ] **Step 6: Flip the characterization test**

In `tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorTests.cs`, the existing test at line 424 pins the *old* unescaped behavior and will now fail. Replace it:

```csharp
    [Fact]
    public void Generate_Hotkey_EscapesParametersInStringLiteral()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotkey hk = new HotkeyBuilder()
            .WithDescription("d")
            .WithKey("a")
            .WithCtrl(true)
            .WithAction(AHKFlowApp.Domain.Enums.HotkeyAction.Send)
            .WithParameters("he said \"hi\"")
            .Build();

        string output = DefaultSut().Generate(profile, [], [hk]);

        output.Should().Contain("^a::Send(\"he said `\"hi`\"\")");
    }
```

The rename is the point: the old name (`..._EmitsParametersVerbatim_NoEscaping`) documented the bug as intended behavior. Leaving the name while changing the assertion would strand a lie in the test suite.

- [ ] **Step 7: Run the full generator suite**

```bash
dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~AhkScriptGeneratorTests"
```

Expected: PASS. Hotstring assertions unchanged; the hotkey assertion now expects escaping.

- [ ] **Step 8: Commit**

```bash
dotnet format AHKFlowApp.slnx
git add src/Backend/AHKFlowApp.Application/Services/HotkeyEmitter.cs \
        src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs \
        tests/AHKFlowApp.Application.Tests/Services/HotkeyEmitterTests.cs \
        tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorTests.cs
git commit -m "fix: escape hotkey parameters at emission

extract HotkeyEmitter from inline FormatHotkey; single emission point
covers restore/revert/seed which bypass validators. refs #195"
```

---

### Task 3: Canonical key registry

Keyboard keys only. Mouse and wheel entries are Wave 2 — adding them now would ship a picker group with no UI and no validation path to exercise it.

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/Constants/HotkeyKeys.cs`
- Create: `tests/AHKFlowApp.Application.Tests/Constants/HotkeyKeysTests.cs`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `[Flags] internal enum HotkeyKeyRoles { None, HotkeyKey, ComboPrefix, SendToken, RemapSource, RemapDest, All }`
  - `internal sealed record HotkeyKeyEntry(string Canonical, string Group, HotkeyKeyRoles Roles, bool RequiresBracesInSend)`
  - `internal static class HotkeyKeys` with:
    - `public static IReadOnlyList<HotkeyKeyEntry> All { get; }`
    - `public static bool TryCanonicalize(string? key, out string canonical)`
    - `public static bool IsValidHotkeyKey(string? key)`

- [ ] **Step 1: Write the failing test**

Create `tests/AHKFlowApp.Application.Tests/Constants/HotkeyKeysTests.cs`:

```csharp
using AHKFlowApp.Application.Constants;
using FluentAssertions;

namespace AHKFlowApp.Application.Tests.Constants;

public sealed class HotkeyKeysTests
{
    [Theory]
    [InlineData("a", "a")]
    [InlineData("A", "a")]
    [InlineData("F5", "F5")]
    [InlineData("f5", "F5")]
    [InlineData("Numpad0", "Numpad0")]
    [InlineData("Volume_Up", "Volume_Up")]
    public void TryCanonicalize_KnownKey_ReturnsCanonicalCasing(string input, string expected)
    {
        bool ok = HotkeyKeys.TryCanonicalize(input, out string canonical);

        ok.Should().BeTrue();
        canonical.Should().Be(expected);
    }

    [Theory]
    [InlineData("Esc", "Escape")]
    [InlineData("Return", "Enter")]
    [InlineData("Del", "Delete")]
    [InlineData("Ins", "Insert")]
    [InlineData("BS", "Backspace")]
    public void TryCanonicalize_Alias_ResolvesToCanonicalName(string alias, string expected)
    {
        bool ok = HotkeyKeys.TryCanonicalize(alias, out string canonical);

        ok.Should().BeTrue();
        canonical.Should().Be(expected);
    }

    [Theory]
    [InlineData("vk1B", "vk1b")]
    [InlineData("VK1B", "vk1b")]
    [InlineData("sc001", "sc001")]
    [InlineData("SC01F", "sc01f")]
    public void TryCanonicalize_VkOrScCode_LowercasesTheCode(string input, string expected)
    {
        bool ok = HotkeyKeys.TryCanonicalize(input, out string canonical);

        ok.Should().BeTrue();
        canonical.Should().Be(expected);
    }

    [Fact]
    public void TryCanonicalize_CombinedVkAndSc_IsRejected()
    {
        bool ok = HotkeyKeys.TryCanonicalize("vk1Bsc001", out _);

        ok.Should().BeFalse();
    }

    [Theory]
    [InlineData("")]
    [InlineData(null)]
    [InlineData("NotAKey")]
    [InlineData("vk")]
    [InlineData("vkZZ")]
    [InlineData("sc12345")]
    [InlineData("Joy1")]
    public void TryCanonicalize_UnknownOrMalformed_IsRejected(string? input)
    {
        bool ok = HotkeyKeys.TryCanonicalize(input, out _);

        ok.Should().BeFalse();
    }

    [Fact]
    public void All_HasNoDuplicateCanonicalNames()
    {
        HotkeyKeys.All.Select(e => e.Canonical)
            .Should().OnlyHaveUniqueItems();
    }

    [Fact]
    public void All_EveryEntryIsUsableAsAHotkeyKey()
    {
        HotkeyKeys.All.Should().OnlyContain(e => e.Roles.HasFlag(HotkeyKeyRoles.HotkeyKey));
    }

    [Fact]
    public void All_NamedKeysRequireBracesInSend_LettersDoNot()
    {
        HotkeyKeys.All.Single(e => e.Canonical == "Volume_Up")
            .RequiresBracesInSend.Should().BeTrue();

        HotkeyKeys.All.Single(e => e.Canonical == "a")
            .RequiresBracesInSend.Should().BeFalse();
    }
}
```

`Joy1` is in the rejection list on purpose — AHK does not support modifier prefixes on joystick hotkeys, which contradicts the modifier-flag model outright, so joystick is excluded from the registry by design rather than by omission.

- [ ] **Step 2: Run test to verify it fails**

```bash
dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~HotkeyKeysTests"
```

Expected: FAIL — `The type or namespace name 'HotkeyKeys' could not be found`.

- [ ] **Step 3: Write the implementation**

Create `src/Backend/AHKFlowApp.Application/Constants/HotkeyKeys.cs`:

```csharp
using System.Text.RegularExpressions;

namespace AHKFlowApp.Application.Constants;

/// <summary>Roles a registry key may legally play. Each role has its own AHK grammar.</summary>
[Flags]
internal enum HotkeyKeyRoles
{
    None = 0,

    /// <summary>Usable as the activating key of a hotkey.</summary>
    HotkeyKey = 1,

    /// <summary>Usable as the prefix of a custom combination (<c>a &amp; b</c>).</summary>
    ComboPrefix = 2,

    /// <summary>Usable inside a <c>Send</c> token.</summary>
    SendToken = 4,

    /// <summary>Usable as the source of a remap.</summary>
    RemapSource = 8,

    /// <summary>Usable as the destination of a remap.</summary>
    RemapDest = 16,

    All = HotkeyKey | ComboPrefix | SendToken | RemapSource | RemapDest,
}

/// <param name="Canonical">The single spelling persisted and emitted.</param>
/// <param name="Group">Picker grouping label.</param>
/// <param name="Roles">Which roles this key may play.</param>
/// <param name="RequiresBracesInSend">
/// True for named keys, which AHK requires be braced inside a Send string
/// (<c>{Volume_Up}</c>). False for single printable characters, which are bare (<c>c</c>).
/// </param>
internal sealed record HotkeyKeyEntry(
    string Canonical,
    string Group,
    HotkeyKeyRoles Roles,
    bool RequiresBracesInSend);

/// <summary>
/// Canonical registry of hotkey keys — the single source shared by validation and (from
/// Wave 1) the key picker.
/// </summary>
/// <remarks>
/// Scope is a curated subset, not AHK's full key list, with <c>vkNN</c>/<c>scNNN</c> as the
/// documented escape hatch for anything omitted. Joystick keys are excluded deliberately:
/// AHK does not support modifier prefixes such as <c>^</c> and <c>+</c> on joystick hotkeys,
/// and the axis names (JoyX, JoyY, JoyPOV, …) cannot be hotkeys at all — both contradict the
/// modifier-flag model. Mouse and wheel entries arrive in Wave 2 alongside their picker group.
/// </remarks>
internal static class HotkeyKeys
{
    public const string GroupLetterOrDigit = "Letters & digits";
    public const string GroupFunction = "Function keys";
    public const string GroupNamed = "Named & cursor";
    public const string GroupNumpad = "Numpad";
    public const string GroupMedia = "Media & browser";

    // A hotkey definition accepts vkNN or scNNN, but never the combined vkNNscNNN form —
    // AHK raises an error for "vk1Bsc001::". Combining is supported only by Send,
    // GetKeyName, GetKeyVK, GetKeySC and A_MenuMaskKey.
    private static readonly Regex s_virtualKey =
        new("^vk[0-9a-f]{1,2}$", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private static readonly Regex s_scanCode =
        new("^sc[0-9a-f]{1,4}$", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private static readonly string[] s_namedKeys =
    [
        "Enter", "Escape", "Space", "Tab", "Backspace", "Delete", "Insert",
        "Home", "End", "PgUp", "PgDn", "Up", "Down", "Left", "Right",
        "CapsLock", "ScrollLock", "PrintScreen", "Pause", "AppsKey",
    ];

    private static readonly string[] s_numpadKeys =
    [
        "Numpad0", "Numpad1", "Numpad2", "Numpad3", "Numpad4",
        "Numpad5", "Numpad6", "Numpad7", "Numpad8", "Numpad9",
        "NumpadDot", "NumpadAdd", "NumpadSub", "NumpadMult", "NumpadDiv",
        "NumpadEnter", "NumLock",
    ];

    private static readonly string[] s_mediaKeys =
    [
        "Volume_Up", "Volume_Down", "Volume_Mute",
        "Media_Play_Pause", "Media_Stop", "Media_Next", "Media_Prev",
        "Browser_Back", "Browser_Forward", "Browser_Refresh", "Browser_Stop",
        "Browser_Search", "Browser_Favorites", "Browser_Home",
        "Launch_Mail", "Launch_Media",
    ];

    // Accepted spellings that resolve to a canonical entry. AHK accepts several of these
    // itself; persisting one spelling keeps duplicate detection honest, so that "Esc" and
    // "Escape" cannot become two rows for the same physical binding.
    private static readonly Dictionary<string, string> s_aliases = new(StringComparer.OrdinalIgnoreCase)
    {
        ["Esc"] = "Escape",
        ["Return"] = "Enter",
        ["Del"] = "Delete",
        ["Ins"] = "Insert",
        ["BS"] = "Backspace",
        ["Break"] = "Pause",
        ["PgDown"] = "PgDn",
        ["PageUp"] = "PgUp",
        ["PageDown"] = "PgDn",
    };

    private static readonly IReadOnlyList<HotkeyKeyEntry> s_all = BuildRegistry();

    private static readonly Dictionary<string, HotkeyKeyEntry> s_byName =
        s_all.ToDictionary(e => e.Canonical, StringComparer.OrdinalIgnoreCase);

    public static IReadOnlyList<HotkeyKeyEntry> All => s_all;

    /// <summary>
    /// Resolves any accepted spelling to the single canonical form, or returns false if the
    /// value is neither a registry key nor a well-formed <c>vk</c>/<c>sc</c> code.
    /// </summary>
    public static bool TryCanonicalize(string? key, out string canonical)
    {
        canonical = string.Empty;
        if (string.IsNullOrWhiteSpace(key))
            return false;

        string trimmed = key.Trim();

        if (s_aliases.TryGetValue(trimmed, out string? aliased))
        {
            canonical = aliased;
            return true;
        }

        if (s_byName.TryGetValue(trimmed, out HotkeyKeyEntry? entry))
        {
            canonical = entry.Canonical;
            return true;
        }

        if (s_virtualKey.IsMatch(trimmed) || s_scanCode.IsMatch(trimmed))
        {
            canonical = trimmed.ToLowerInvariant();
            return true;
        }

        return false;
    }

    public static bool IsValidHotkeyKey(string? key) => TryCanonicalize(key, out _);

    private static List<HotkeyKeyEntry> BuildRegistry()
    {
        List<HotkeyKeyEntry> entries = [];

        for (char c = 'a'; c <= 'z'; c++)
            entries.Add(new(c.ToString(), GroupLetterOrDigit, HotkeyKeyRoles.All, RequiresBracesInSend: false));

        for (char c = '0'; c <= '9'; c++)
            entries.Add(new(c.ToString(), GroupLetterOrDigit, HotkeyKeyRoles.All, RequiresBracesInSend: false));

        for (int i = 1; i <= 24; i++)
            entries.Add(new($"F{i}", GroupFunction, HotkeyKeyRoles.All, RequiresBracesInSend: true));

        foreach (string name in s_namedKeys)
            entries.Add(new(name, GroupNamed, RolesForNamed(name), RequiresBracesInSend: true));

        foreach (string name in s_numpadKeys)
            entries.Add(new(name, GroupNumpad, HotkeyKeyRoles.All, RequiresBracesInSend: true));

        foreach (string name in s_mediaKeys)
            entries.Add(new(name, GroupMedia, HotkeyKeyRoles.All, RequiresBracesInSend: true));

        return entries;
    }

    // Pause is excluded as a remap destination: the name collides with AHK's built-in Pause
    // function, so a remap must target vk13 instead.
    private static HotkeyKeyRoles RolesForNamed(string name) =>
        name == "Pause"
            ? HotkeyKeyRoles.All & ~HotkeyKeyRoles.RemapDest
            : HotkeyKeyRoles.All;
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~HotkeyKeysTests"
```

Expected: PASS, 25 tests (the `[Theory]` cases count individually).

- [ ] **Step 5: Commit**

```bash
dotnet format AHKFlowApp.slnx
git add src/Backend/AHKFlowApp.Application/Constants/HotkeyKeys.cs \
        tests/AHKFlowApp.Application.Tests/Constants/HotkeyKeysTests.cs
git commit -m "feat: canonical hotkey key registry

curated subset + vk/sc escape hatch; joystick excluded (no modifier
support). role flags feed the per-role validators from wave 1"
```

---

### Task 4: HotkeyDefinition record and Apply refactor

Collapses four 10-argument positional call sites into one record, mirroring `HotstringDefinition`. Doing this *before* the validation task means canonicalization lands in one place instead of four.

**Files:**
- Create: `src/Backend/AHKFlowApp.Domain/Entities/HotkeyDefinition.cs`
- Modify: `src/Backend/AHKFlowApp.Domain/Entities/Hotkey.cs:31-116`
- Modify: `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/CreateHotkeyCommand.cs:71-82`
- Modify: `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/RestoreHotkeyCommand.cs:57-70`
- Modify: `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/RevertHotkeyCommand.cs:60-70`
- Modify: `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/UpdateHotkeyCommand.cs`
- Modify: `src/Backend/AHKFlowApp.Application/Queries/Hotkeys/ListHotkeysQuery.cs:217`
- Modify: `src/Backend/AHKFlowApp.Application/Commands/Dev/SeedHotkeysCommand.cs:94`
- Modify: `tests/AHKFlowApp.TestUtilities/Builders/HotkeyBuilder.cs:67-70`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `public sealed record HotkeyDefinition(string Description, string Key, bool Ctrl, bool Alt, bool Shift, bool Win, HotkeyAction Action, string Parameters, bool AppliesToAllProfiles)`
  - `Hotkey.Create(Guid ownerOid, HotkeyDefinition definition, TimeProvider clock)`
  - `Hotkey.Restore(Guid id, Guid ownerOid, HotkeyDefinition definition, DateTimeOffset createdAt, TimeProvider clock)`
  - `Hotkey.Update(HotkeyDefinition definition, TimeProvider clock)`

- [ ] **Step 1: Write the failing test**

Add to `tests/AHKFlowApp.Domain.Tests/Entities/HotkeyTests.cs` (create the file if absent):

```csharp
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using FluentAssertions;
using Microsoft.Extensions.Time.Testing;

namespace AHKFlowApp.Domain.Tests.Entities;

public sealed class HotkeyTests
{
    private static HotkeyDefinition Definition() => new(
        Description: "Open Notepad",
        Key: "n",
        Ctrl: false,
        Alt: false,
        Shift: false,
        Win: true,
        Action: HotkeyAction.Run,
        Parameters: "notepad.exe",
        AppliesToAllProfiles: true);

    [Fact]
    public void Create_FromDefinition_CopiesEveryField()
    {
        FakeTimeProvider clock = new();
        Guid owner = Guid.NewGuid();

        Hotkey hk = Hotkey.Create(owner, Definition(), clock);

        hk.OwnerOid.Should().Be(owner);
        hk.Description.Should().Be("Open Notepad");
        hk.Key.Should().Be("n");
        hk.Win.Should().BeTrue();
        hk.Action.Should().Be(HotkeyAction.Run);
        hk.Parameters.Should().Be("notepad.exe");
        hk.AppliesToAllProfiles.Should().BeTrue();
        hk.CreatedAt.Should().Be(clock.GetUtcNow());
        hk.UpdatedAt.Should().Be(clock.GetUtcNow());
    }

    [Fact]
    public void Update_FromDefinition_ReplacesFieldsAndAdvancesUpdatedAt()
    {
        FakeTimeProvider clock = new();
        Hotkey hk = Hotkey.Create(Guid.NewGuid(), Definition(), clock);
        DateTimeOffset created = hk.CreatedAt;
        clock.Advance(TimeSpan.FromMinutes(5));

        hk.Update(Definition() with { Key = "b", Parameters = "calc.exe" }, clock);

        hk.Key.Should().Be("b");
        hk.Parameters.Should().Be("calc.exe");
        hk.CreatedAt.Should().Be(created);
        hk.UpdatedAt.Should().Be(clock.GetUtcNow());
    }

    [Fact]
    public void Restore_FromDefinition_KeepsOriginalCreatedAt()
    {
        FakeTimeProvider clock = new();
        DateTimeOffset originallyCreated = clock.GetUtcNow().AddDays(-3);
        Guid id = Guid.NewGuid();

        Hotkey hk = Hotkey.Restore(id, Guid.NewGuid(), Definition(), originallyCreated, clock);

        hk.Id.Should().Be(id);
        hk.CreatedAt.Should().Be(originallyCreated);
        hk.UpdatedAt.Should().Be(clock.GetUtcNow());
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
dotnet test tests/AHKFlowApp.Domain.Tests --filter "FullyQualifiedName~HotkeyTests"
```

Expected: FAIL — `The type or namespace name 'HotkeyDefinition' could not be found`.

- [ ] **Step 3: Create the definition record**

Create `src/Backend/AHKFlowApp.Domain/Entities/HotkeyDefinition.cs`:

```csharp
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Domain.Entities;

/// <summary>
/// Definitional fields of a hotkey, grouped so factory signatures stay stable as actions
/// and options grow across the redesign waves. Mirrors <see cref="HotstringDefinition"/>.
/// </summary>
public sealed record HotkeyDefinition(
    string Description,
    string Key,
    bool Ctrl,
    bool Alt,
    bool Shift,
    bool Win,
    HotkeyAction Action,
    string Parameters,
    bool AppliesToAllProfiles);
```

- [ ] **Step 4: Rewrite the entity factories**

In `src/Backend/AHKFlowApp.Domain/Entities/Hotkey.cs`, replace everything from `public static Hotkey Create(` to the end of `Update` with:

```csharp
    public static Hotkey Create(Guid ownerOid, HotkeyDefinition definition, TimeProvider clock)
    {
        DateTimeOffset now = clock.GetUtcNow();
        Hotkey hk = new()
        {
            Id = Guid.NewGuid(),
            OwnerOid = ownerOid,
            CreatedAt = now,
            UpdatedAt = now,
        };
        hk.Apply(definition);
        return hk;
    }

    public static Hotkey Restore(
        Guid id,
        Guid ownerOid,
        HotkeyDefinition definition,
        DateTimeOffset createdAt,
        TimeProvider clock)
    {
        Hotkey hk = new()
        {
            Id = id,
            OwnerOid = ownerOid,
            CreatedAt = createdAt,
            UpdatedAt = clock.GetUtcNow(),
        };
        hk.Apply(definition);
        return hk;
    }

    public void Update(HotkeyDefinition definition, TimeProvider clock)
    {
        Apply(definition);
        UpdatedAt = clock.GetUtcNow();
    }

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
    }
```

- [ ] **Step 5: Run the domain test to verify it passes**

```bash
dotnet test tests/AHKFlowApp.Domain.Tests --filter "FullyQualifiedName~HotkeyTests"
```

Expected: PASS, 3 tests. The rest of the solution will not compile yet — that is Step 6.

- [ ] **Step 6: Update all six call sites**

`CreateHotkeyCommand.cs` — replace the `Hotkey.Create(...)` block:

```csharp
        var entity = Hotkey.Create(
            ownerOid,
            new HotkeyDefinition(
                input.Description,
                input.Key,
                input.Ctrl,
                input.Alt,
                input.Shift,
                input.Win,
                input.Action,
                input.Parameters,
                input.AppliesToAllProfiles),
            clock);
```

`UpdateHotkeyCommand.cs` — replace the `entity.Update(...)` block with the same shape:

```csharp
        entity.Update(
            new HotkeyDefinition(
                input.Description,
                input.Key,
                input.Ctrl,
                input.Alt,
                input.Shift,
                input.Win,
                input.Action,
                input.Parameters,
                input.AppliesToAllProfiles),
            clock);
```

`RestoreHotkeyCommand.cs`:

```csharp
        var entity = Hotkey.Restore(
            request.Id,
            ownerOid,
            new HotkeyDefinition(
                snapshot.Description,
                snapshot.Key,
                snapshot.Ctrl,
                snapshot.Alt,
                snapshot.Shift,
                snapshot.Win,
                snapshot.Action,
                snapshot.Parameters,
                snapshot.AppliesToAllProfiles),
            snapshot.CreatedAt,
            clock);
```

`RevertHotkeyCommand.cs`:

```csharp
        entity.Update(
            new HotkeyDefinition(
                snapshot.Description,
                snapshot.Key,
                snapshot.Ctrl,
                snapshot.Alt,
                snapshot.Shift,
                snapshot.Win,
                snapshot.Action,
                snapshot.Parameters,
                snapshot.AppliesToAllProfiles),
            clock);
```

`ListHotkeysQuery.cs` — the lazy seed loop:

```csharp
                var hk = Hotkey.Create(
                    ownerOid,
                    new HotkeyDefinition(descr, key, ctrl, alt, shift, win, action, param,
                        AppliesToAllProfiles: true),
                    clock);
```

`SeedHotkeysCommand.cs` — the create branch inside the seed loop:

```csharp
                var entity = Hotkey.Create(
                    ownerOid,
                    new HotkeyDefinition(descr, key, ctrl, alt, shift, win, action, param,
                        AppliesToAllProfiles: true),
                    clock);
```

Add `using AHKFlowApp.Domain.Entities;` to any file that lacks it.

`HotkeyBuilder.Build()`:

```csharp
    public Hotkey Build()
    {
        var entity = Hotkey.Create(
            _ownerOid,
            new HotkeyDefinition(_description, _key, _ctrl, _alt, _shift, _win,
                _action, _parameters, _appliesToAllProfiles),
            _clock);

        foreach (Guid pid in _profileIds)
            entity.Profiles.Add(HotkeyProfile.Create(entity.Id, pid));

        foreach (Guid cid in _categoryIds)
            entity.Categories.Add(HotkeyCategory.Create(entity.Id, cid));

        return entity;
    }
```

- [ ] **Step 7: Build and run the full suite**

```bash
dotnet build AHKFlowApp.slnx --configuration Release
dotnet test tests/AHKFlowApp.Domain.Tests tests/AHKFlowApp.Application.Tests
```

Expected: build succeeds, all tests PASS. This is a pure signature refactor — any behavioral test failure means an argument was mapped to the wrong record property. The positional-to-named conversion is exactly where a `Ctrl`/`Alt` transposition hides, so do not skip this step.

- [ ] **Step 8: Commit**

```bash
dotnet format AHKFlowApp.slnx
git add -A
git commit -m "refactor: HotkeyDefinition record replaces positional factories

mirrors HotstringDefinition; one place to add wave 1 action columns"
```

---

### Task 5: Registry-backed key validation

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Validation/HotkeyRules.cs:17-36`
- Modify: `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/CreateHotkeyCommand.cs`
- Modify: `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/UpdateHotkeyCommand.cs`
- Create: `tests/AHKFlowApp.Application.Tests/Validation/HotkeyRulesTests.cs`

**Interfaces:**
- Consumes: `HotkeyKeys.IsValidHotkeyKey(string?)`, `HotkeyKeys.TryCanonicalize(string?, out string)` from Task 3; `HotkeyDefinition` from Task 4.
- Produces: unchanged public shape — `ValidKey<T>(this IRuleBuilderInitial<T, string>)`.

- [ ] **Step 1: Write the failing test**

Create `tests/AHKFlowApp.Application.Tests/Validation/HotkeyRulesTests.cs`:

```csharp
using AHKFlowApp.Application.Commands.Hotkeys;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Enums;
using FluentAssertions;
using FluentValidation.Results;

namespace AHKFlowApp.Application.Tests.Validation;

public sealed class HotkeyRulesTests
{
    private static ValidationResult ValidateKey(string key)
    {
        CreateHotkeyDto dto = new(
            Description: "d",
            Key: key,
            Ctrl: true,
            Action: HotkeyAction.Run,
            Parameters: "notepad.exe",
            AppliesToAllProfiles: true);

        return new CreateHotkeyCommandValidator().Validate(new CreateHotkeyCommand(dto));
    }

    [Theory]
    [InlineData("a")]
    [InlineData("F5")]
    [InlineData("Escape")]
    [InlineData("Esc")]
    [InlineData("Numpad0")]
    [InlineData("Volume_Up")]
    [InlineData("vk1B")]
    [InlineData("sc001")]
    public void ValidKey_KnownKeyOrCode_IsAccepted(string key)
    {
        ValidationResult result = ValidateKey(key);

        result.Errors.Should().NotContain(e => e.PropertyName.EndsWith("Key"));
    }

    [Theory]
    [InlineData("NotAKey")]
    [InlineData("vk1Bsc001")]
    [InlineData("Joy1")]
    [InlineData("")]
    public void ValidKey_UnknownKey_IsRejected(string key)
    {
        ValidationResult result = ValidateKey(key);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName.EndsWith("Key"));
    }

    [Fact]
    public void ValidParameters_DoubleQuoteAndBacktick_AreNowAccepted()
    {
        CreateHotkeyDto dto = new(
            Description: "d",
            Key: "a",
            Ctrl: true,
            Action: HotkeyAction.Send,
            Parameters: "he said \"hi\" 100`%",
            AppliesToAllProfiles: true);

        ValidationResult result = new CreateHotkeyCommandValidator()
            .Validate(new CreateHotkeyCommand(dto));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void ValidParameters_ControlCharacter_IsStillRejected()
    {
        CreateHotkeyDto dto = new(
            Description: "d",
            Key: "a",
            Ctrl: true,
            Action: HotkeyAction.Send,
            Parameters: "bad\0value",
            AppliesToAllProfiles: true);

        ValidationResult result = new CreateHotkeyCommandValidator()
            .Validate(new CreateHotkeyCommand(dto));

        result.IsValid.Should().BeFalse();
    }
}
```

`CreateHotkeyDto` (`DTOs/HotkeyDto.cs:48`) defaults every parameter after `Key`, so the omitted ones need no value. `HotkeyKeys`, `HotkeyEmitter` and `AhkEscaping` are `internal`, which the test project can see — `AHKFlowApp.Application.csproj:20` already declares `<InternalsVisibleTo Include="AHKFlowApp.Application.Tests" />`.

Note the last two tests belong to Task 6's relaxation but are written here so the whole validator surface lands in one file. They fail until Task 6.

- [ ] **Step 2: Run test to verify it fails**

```bash
dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~HotkeyRulesTests"
```

Expected: FAIL — `ValidKey_UnknownKey_IsRejected` fails for `NotAKey`, `vk1Bsc001` and `Joy1` (the interim denylist accepts them), and both `ValidParameters` tests fail.

- [ ] **Step 3: Rewrite ValidKey**

In `src/Backend/AHKFlowApp.Application/Validation/HotkeyRules.cs`, add the using and replace the comment block plus `ValidKey`:

```csharp
using AHKFlowApp.Application.Constants;
```

```csharp
    // Key is validated against the canonical registry (or a vkNN / scNNN code) rather than
    // by rejecting known-bad characters. This is the whitelist half of issue #195: an
    // accepted Key is a real AHK key name, so the emitted left-hand side cannot break the
    // script. Escaping of the right-hand side lives in HotkeyEmitter.
    public static IRuleBuilderOptions<T, string> ValidKey<T>(this IRuleBuilderInitial<T, string> rb) =>
        rb.Cascade(CascadeMode.Stop)
          .NotEmpty().WithMessage("Key is required.")
          .MaximumLength(KeyMaxLength).WithMessage($"Key must be {KeyMaxLength} characters or fewer.")
          .Must(HotkeyKeys.IsValidHotkeyKey)
              .WithMessage("Key must be a known key name (for example a, F5, Escape, Numpad0) "
                         + "or a vkNN / scNNN code. Combined vkNNscNNN is not valid in a hotkey.");
```

- [ ] **Step 4: Canonicalize on write**

In `CreateHotkeyCommand.cs`, immediately before building the `HotkeyDefinition`:

```csharp
        HotkeyKeys.TryCanonicalize(input.Key, out string canonicalKey);
```

and use `canonicalKey` instead of `input.Key` in the definition. Apply the identical change in `UpdateHotkeyCommand.cs`. Add `using AHKFlowApp.Application.Constants;` to both files.

Ignoring the boolean return is correct here and only here: the validating decorator runs before the handler, so an invalid key never reaches this line. Do not add a defensive branch — the codebase does not re-validate inside internal methods.

- [ ] **Step 5: Run tests**

```bash
dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~HotkeyRulesTests"
```

Expected: the two `ValidKey_*` theories PASS. The two `ValidParameters_*` tests still FAIL — Task 6 fixes them.

- [ ] **Step 6: Commit**

```bash
dotnet format AHKFlowApp.slnx
git add src/Backend/AHKFlowApp.Application/Validation/HotkeyRules.cs \
        src/Backend/AHKFlowApp.Application/Commands/Hotkeys/CreateHotkeyCommand.cs \
        src/Backend/AHKFlowApp.Application/Commands/Hotkeys/UpdateHotkeyCommand.cs \
        tests/AHKFlowApp.Application.Tests/Validation/HotkeyRulesTests.cs
git commit -m "feat: validate hotkey Key against canonical registry

replaces interim character denylist; canonicalize on write so Esc and
Escape cannot become two rows. refs #195"
```

---

### Task 6: Relax the interim text denylist

Safe only now: Task 2 put escaping in front of every emission, so `"` and backtick in `Parameters` can no longer break the script.

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Validation/HotkeyRules.cs:38-47`

**Interfaces:**
- Consumes: escaping from Task 2; the tests written in Task 5.
- Produces: unchanged shape — `ValidParameters<T>(this IRuleBuilderInitial<T, string>)`.

- [ ] **Step 1: Confirm the tests still fail**

```bash
dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~ValidParameters"
```

Expected: FAIL — `ValidParameters_DoubleQuoteAndBacktick_AreNowAccepted` reports "Parameters must not contain double-quote characters."

- [ ] **Step 2: Relax the rule**

Replace `ValidParameters` in `HotkeyRules.cs`:

```csharp
    // Double-quote and backtick are no longer rejected: HotkeyEmitter escapes Parameters
    // into the emitted string literal, so they are ordinary characters now. Control
    // characters stay rejected — the escape routine only covers \n, \r and \t, and the
    // rest have no meaningful representation in a single-line definition.
    public static IRuleBuilderOptions<T, string> ValidParameters<T>(this IRuleBuilderInitial<T, string> rb) =>
        rb.Cascade(CascadeMode.Stop)
          .MaximumLength(ParametersMaxLength)
              .WithMessage($"Parameters must be {ParametersMaxLength} characters or fewer.")
          .Must(p => p is null || !p.Any(c => char.IsControl(c) && c is not '\n' and not '\r' and not '\t'))
              .WithMessage("Parameters must not contain control characters.");
```

Newline, carriage return and tab are now permitted because the emitter escapes them to `` `n ``, `` `r `` and `` `t `` — the value stays on one physical line.

- [ ] **Step 3: Run tests to verify they pass**

```bash
dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~HotkeyRulesTests"
```

Expected: PASS, all cases.

- [ ] **Step 4: Run the whole backend suite**

```bash
dotnet test tests/AHKFlowApp.Domain.Tests tests/AHKFlowApp.Application.Tests
```

Expected: PASS. If an existing endpoint or validator test asserted that a quote is rejected, update it — that assertion pinned the interim workaround, and the workaround is what this wave removes.

- [ ] **Step 5: Commit**

```bash
dotnet format AHKFlowApp.slnx
git add src/Backend/AHKFlowApp.Application/Validation/HotkeyRules.cs
git commit -m "feat: relax hotkey parameter denylist

quote and backtick now escaped at emission; keep control-char rejection
except \n \r \t which the emitter escapes. closes #195"
```

---

### Task 7: Document current semantics

The spec calls for recording Send-vs-Run semantics while they are still true — Wave 1 replaces the enum, and undocumented behavior is what makes the Wave 1 legacy mapping guesswork.

**Files:**
- Modify: `docs/development/ahk-v2-syntax.md` — the `## Escaping` and `## Hotkeys` sections.

- [ ] **Step 1: Update the escaping table**

In `## Escaping`, the two-column table currently attributes `EscapeStringLiteral` to hotstrings only. Change the "Used for" row so the second column reads:

```
contents of `SendText "..."` / `Send "..."` / `Run("...")` — hotstrings **and** hotkeys, via the shared `AhkEscaping` helper
```

- [ ] **Step 2: Rewrite the Hotkeys section**

Replace the paragraph beginning "Both hotkey `Key` and `Parameters` are interpolated **without**…" through the end of that section with:

```markdown
`Parameters` is escaped by `AhkEscaping.EscapeStringLiteral` before being embedded in the
emitted string literal — the same routine the hotstring emitter uses. `Key` is validated
against the canonical registry in `HotkeyKeys` (or a `vkNN` / `scNNN` code) at the create
and update boundaries, so an accepted key is a real AHK key name.

Two limits are worth stating plainly:

- **Snapshots bypass validation.** History restore and revert rehydrate a stored snapshot
  without running validators, as does the development lazy seed. Escaping still applies —
  it happens at emission, in `HotkeyEmitter`, which every path goes through — but a `Key`
  written before validation landed can return unvalidated until the row is next edited.
  This mirrors the hotstring trust model.
- **Only the combined form of VK/SC is rejected.** `vkNN` and `scNNN` are each accepted;
  `vkNNscNNN` is not, because AHK raises an error for it in a hotkey definition. The
  combined form is supported only by `Send`, `GetKeyName`, `GetKeyVK`, `GetKeySC` and
  `A_MenuMaskKey`.

### Current action semantics (pre-Wave-1)

| `HotkeyAction` | Emits | Notes |
|---|---|---|
| `Send` | `Send("<escaped Parameters>")` | `Parameters` is an AHK key sequence — `^v`, `{Up}`. Not validated as one; any string is accepted and escaped. |
| `Run` | `Run("<escaped Parameters>")` | `Parameters` is a **command line**, not a path — arguments are permitted and in use (`rundll32.exe user32.dll,LockWorkStation`). |

An unknown action throws rather than emitting a broken line. Wave 1 replaces this enum with
`HotkeyActionKind`; this table is the reference its data migration maps *from*.
```

- [ ] **Step 3: Verify the doc has no stale claims**

```bash
grep -n "verbatim\|NoEscaping\|not a guarantee" docs/development/ahk-v2-syntax.md
```

Expected: no matches inside the Hotkeys section. Any hit is a leftover sentence describing the pre-W0 behavior — delete it.

- [ ] **Step 4: Commit**

```bash
git add docs/development/ahk-v2-syntax.md
git commit -m "docs: record hotkey escaping + pre-wave-1 action semantics"
```

---

## Wave 0 Definition of Done

- [ ] `dotnet build AHKFlowApp.slnx --configuration Release` clean.
- [ ] `dotnet test` green across `Domain.Tests`, `Application.Tests`, `API.Tests`, `Infrastructure.Tests`.
- [ ] `dotnet format AHKFlowApp.slnx --verify-no-changes` clean.
- [ ] A hotkey whose `Parameters` contains `"` downloads a profile that loads in AHK v2 without error — the #195 reproduction, now fixed.
- [ ] No new columns, no migration, no action-model change in the diff.

## Waves 1–4 Roadmap

Each wave gets its own plan, written against the code that actually landed — writing bite-sized steps for Wave 2 now would mean inventing signatures for types Wave 1 has not yet shaped.

| Wave | Deliverable | Gate to open the next plan |
|---|---|---|
| **W1** | `HotkeyActionKind`/`WindowOp`/`RunTargetKind`, action columns, legacy row migration + `LegacyHotkeySnapshotConverter` + parity fixtures, per-action validation, preview endpoint, grid Action column with chip + display helper, `CONTEXT.md` W1 terms, ADR 0004 | Migration/converter parity tests green against the dev lazy-seed corpus |
| **W2** | Combo/toggle/key-up columns, mouse + wheel registry entries, combo and toggle UI, self-lockout and prefix-suppression warnings, unique-index rework | Toggle/combo goldens (examples 3, 16, 18, 19) green |
| **W3** | Context columns, `#HotIf` grouping for hotkeys, dialog context panel, index finalize, variant-precedence test | Example 20 golden green; precedence test green |
| **W4** | OKLCH chip tints, single edit-button routing, glyph legend, full `ahk-v2-syntax.md` hotkey rewrite, backlog-034 label sweep | All 20 goldens green |

**Cross-wave invariant:** goldens are cumulative. Every wave adds its examples to the suite and keeps all earlier ones passing.
