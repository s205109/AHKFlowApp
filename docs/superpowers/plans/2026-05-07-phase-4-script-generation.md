# Phase 4: AHK Script Generation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a pure `AhkScriptGenerator` service in the Application layer that turns a `Profile` plus its filtered `Hotstring`s and `Hotkey`s into a valid AutoHotkey v2 `.ahk` script. No HTTP endpoint and no UI in this phase — Phase 5 will own the download endpoint and Downloads page.

**Architecture:** A single `public sealed class AhkScriptGenerator` with one method `Generate(Profile, IEnumerable<Hotstring>, IEnumerable<Hotkey>) -> string`. Caller pre-filters rows (junction OR `AppliesToAllProfiles=true`); generator only renders. Output uses `\n` line endings, AHK v2 syntax (`Send("…")` / `Run("…")` as functions), modifier prefix order `^!+#` (Ctrl/Alt/Shift/Win), hotstring `:options:trigger::replacement` with options `*` (no ending char) and `?` (inside word). Section headers always emit, even when empty. No escaping of `Parameters`/`Replacement` — caller's responsibility.

**Tech Stack:** .NET 10, EF Core 10 (SQL Server) for the integration test, xUnit + FluentAssertions + Testcontainers, MediatR (no MediatR contract for the generator — pure DI).

**Maps to backlog:** 026.
**Spec:** `docs/superpowers/specs/2026-04-30-ahkflow-alignment-design.md` (Phase 4).

---

## Locked decisions (resolved before plan)

| # | Decision |
|---|---|
| L1 | **AHK v2 syntax** for hotkey lines: `^!a::Send("hello")`, `^!+#F5::Run("notepad.exe")`. Backlog 026 had a v1 example (`Send, hello`) — wrong; will be fixed in Task 2. |
| L2 | **No escaping** of `Parameters` / `Replacement`. Emitted verbatim inside the AHK string literal. Documented as user responsibility. |
| L3 | **Section headers always emit.** `; --- Hotstrings ---` and `; --- Hotkeys ---` appear even when their list is empty. |
| L4 | **Pre-filtered inputs.** Generator signature is `Generate(Profile, IEnumerable<Hotstring>, IEnumerable<Hotkey>)`. Phase 5's Downloads handler will own the EF filter query. |
| L5 | **Line endings = `\n`** (LF only). Deterministic across platforms. Output is `string.Join("\n", lines)` — no trailing newline. |
| L6 | **Ordering** uses `StringComparer.Ordinal` (deterministic, culture-independent). Hotstrings by `Trigger` ASC; hotkeys by `Description` ASC. |

---

## Branch Setup

Phase 3 is merged to `main`. Phase 4 branches from `main`:

```bash
git checkout main
git pull --ff-only
git checkout -b feature/026-script-generation
```

---

## File Map

| Action | File |
|--------|------|
| Modify | `.claude/backlog/026-generate-ahk-per-profile.md` (fix v1→v2 example; pin locked decisions) |
| Create | `src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs` |
| Modify | `src/Backend/AHKFlowApp.Application/DependencyInjection.cs` (register `AhkScriptGenerator` as singleton) |
| Modify | `tests/AHKFlowApp.TestUtilities/Builders/HotkeyBuilder.cs` (add `InProfile` / `WithProfiles` / `AppliesToAllProfiles` mirroring `HotstringBuilder`) |
| Create | `tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorTests.cs` (pure unit tests) |
| Create | `tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorIntegrationTests.cs` (real SQL via Testcontainers) |
| Create | `tests/AHKFlowApp.Application.Tests/Services/ScriptGeneratorDbFixture.cs` |

No API/UI/Domain/Infrastructure changes in this phase. No migration. No new packages.

---

## Task 1: Update backlog 026 to match locked decisions

**Files:**
- Modify: `.claude/backlog/026-generate-ahk-per-profile.md`

- [ ] **Step 1: Replace the hotkey example and add a note about format decisions**

Open `.claude/backlog/026-generate-ahk-per-profile.md`. Replace the line (acceptance criterion 4):

```
- [ ] Hotkey translation: `^!+#` modifier prefix order = Ctrl, Alt, Shift, Win; line is `{modifiers}{Key}::{Action}, {Parameters}` (e.g. `^!a::Send, hello`).
```

with:

```
- [ ] Hotkey translation (AHK v2): `^!+#` modifier prefix order = Ctrl, Alt, Shift, Win; line is `{modifiers}{Key}::{Action}("{Parameters}")` (e.g. `^!a::Send("hello")`, `^!+#F5::Run("notepad.exe")`). `Send` and `Run` are emitted as v2 function calls.
```

- [ ] **Step 2: Add a "Format decisions" subsection above "Notes / dependencies"**

Insert before `## Notes / dependencies`:

```
## Format decisions (locked in plan 2026-05-07)

- AHK v2 syntax — matches `#Requires AutoHotkey v2.0` in default `HeaderTemplate`.
- Line endings: `\n` (LF) only. No trailing newline at end of file.
- Section headers `; --- Hotstrings ---` and `; --- Hotkeys ---` always emit, even when their list is empty.
- No escaping of `Parameters` / `Replacement`. Emitted verbatim inside the AHK string literal — user is responsible for escaping their own quotes/backticks.
- Ordering uses `StringComparer.Ordinal` (culture-independent).
- Generator signature is pre-filtered: caller passes only the rows that belong to this profile (junction membership OR `AppliesToAllProfiles=true`). The Downloads handler in Phase 5 owns the EF query.
```

- [ ] **Step 3: Commit**

```powershell
git add .claude/backlog/026-generate-ahk-per-profile.md
git commit -m "docs(026): pin AHK v2 generator format decisions"
```

---

## Task 2: Application — `AhkScriptGenerator` skeleton + DI registration

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs`
- Modify: `src/Backend/AHKFlowApp.Application/DependencyInjection.cs`

- [ ] **Step 1: Create the service file with an empty Generate method (will fail tests; that's the point)**

```csharp
using AHKFlowApp.Domain.Entities;

namespace AHKFlowApp.Application.Services;

public sealed class AhkScriptGenerator
{
    public string Generate(
        Profile profile,
        IEnumerable<Hotstring> hotstrings,
        IEnumerable<Hotkey> hotkeys)
    {
        throw new NotImplementedException();
    }
}
```

- [ ] **Step 2: Register the generator as a singleton in DI**

Open `src/Backend/AHKFlowApp.Application/DependencyInjection.cs`. Add the using and the registration:

```csharp
using AHKFlowApp.Application.Behaviors;
using AHKFlowApp.Application.Services;
using FluentValidation;
using Microsoft.Extensions.DependencyInjection;

namespace AHKFlowApp.Application;

public static class DependencyInjection
{
    public static IServiceCollection AddApplication(this IServiceCollection services)
    {
        services.AddMediatR(cfg =>
        {
            cfg.RegisterServicesFromAssembly(typeof(DependencyInjection).Assembly);
            cfg.AddOpenBehavior(typeof(ValidationBehavior<,>));
        });

        services.AddValidatorsFromAssembly(typeof(DependencyInjection).Assembly);

        services.AddSingleton<AhkScriptGenerator>();

        return services;
    }
}
```

- [ ] **Step 3: Build**

```powershell
dotnet build src/Backend/AHKFlowApp.Application --configuration Release
```

Expected: `Build succeeded.`

- [ ] **Step 4: Commit**

```powershell
git add src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs src/Backend/AHKFlowApp.Application/DependencyInjection.cs
git commit -m "feat(026): scaffold AhkScriptGenerator service + DI registration"
```

---

## Task 3: Unit test — empty profile

**Files:**
- Create: `tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorTests.cs`

- [ ] **Step 1: Write the failing test**

```csharp
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.TestUtilities.Builders;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Services;

public sealed class AhkScriptGeneratorTests
{
    private readonly AhkScriptGenerator _sut = new();

    [Fact]
    public void Generate_EmptyProfile_EmitsHeaderSectionMarkersAndFooter()
    {
        Profile profile = new ProfileBuilder()
            .WithHeader("#Requires AutoHotkey v2.0")
            .WithFooter("; end of file")
            .Build();

        string output = _sut.Generate(profile, [], []);

        output.Should().Be(
            "#Requires AutoHotkey v2.0\n" +
            "; --- Hotstrings ---\n" +
            "; --- Hotkeys ---\n" +
            "; end of file");
    }

    [Fact]
    public void Generate_EmptyHeaderAndFooter_StillEmitsSectionMarkers()
    {
        Profile profile = new ProfileBuilder().WithHeader("").WithFooter("").Build();

        string output = _sut.Generate(profile, [], []);

        output.Should().Be(
            "\n" +
            "; --- Hotstrings ---\n" +
            "; --- Hotkeys ---\n");
    }
}
```

- [ ] **Step 2: Run the test and confirm it fails (NotImplementedException)**

```powershell
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --filter "FullyQualifiedName~AhkScriptGeneratorTests" --verbosity normal
```

Expected: 2 tests failed with `NotImplementedException`.

- [ ] **Step 3: Implement the empty-profile behavior**

Replace the body of `AhkScriptGenerator.Generate`:

```csharp
using AHKFlowApp.Domain.Entities;

namespace AHKFlowApp.Application.Services;

public sealed class AhkScriptGenerator
{
    private const string HotstringsSection = "; --- Hotstrings ---";
    private const string HotkeysSection = "; --- Hotkeys ---";

    public string Generate(
        Profile profile,
        IEnumerable<Hotstring> hotstrings,
        IEnumerable<Hotkey> hotkeys)
    {
        ArgumentNullException.ThrowIfNull(profile);
        ArgumentNullException.ThrowIfNull(hotstrings);
        ArgumentNullException.ThrowIfNull(hotkeys);

        List<string> lines = [profile.HeaderTemplate, HotstringsSection, HotkeysSection, profile.FooterTemplate];
        return string.Join("\n", lines);
    }
}
```

- [ ] **Step 4: Run the test and confirm pass**

```powershell
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --filter "FullyQualifiedName~AhkScriptGeneratorTests" --verbosity normal
```

Expected: 2 passed.

- [ ] **Step 5: Commit**

```powershell
git add src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorTests.cs
git commit -m "feat(026): generate empty-profile output with section markers"
```

---

## Task 4: Unit tests — hotstring formatting (option flags)

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs`
- Modify: `tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorTests.cs`

Hotstring format: `:{options}:{Trigger}::{Replacement}` where options is the concatenation of:
- `*` if `IsEndingCharacterRequired == false`
- `?` if `IsTriggerInsideWord == true`

Both flags can be present together (`*?`); when neither, options is empty (`::trigger::replacement`).

- [ ] **Step 1: Add the hotstring tests**

Append to `AhkScriptGeneratorTests`:

```csharp
[Theory]
[InlineData(true, false, "::btw::by the way")]                  // default — no options
[InlineData(false, false, ":*:btw::by the way")]                // ending char NOT required
[InlineData(true, true, ":?:btw::by the way")]                  // trigger inside word
[InlineData(false, true, ":*?:btw::by the way")]                // both options
public void Generate_Hotstring_FormatsOptionsCorrectly(
    bool isEndingCharacterRequired,
    bool isTriggerInsideWord,
    string expectedLine)
{
    Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
    Hotstring hs = new HotstringBuilder()
        .WithTrigger("btw")
        .WithReplacement("by the way")
        .WithEndingCharacterRequired(isEndingCharacterRequired)
        .WithTriggerInsideWord(isTriggerInsideWord)
        .Build();

    string output = _sut.Generate(profile, [hs], []);

    output.Should().Be(
        "H\n" +
        "; --- Hotstrings ---\n" +
        expectedLine + "\n" +
        "; --- Hotkeys ---\n" +
        "F");
}

[Fact]
public void Generate_MultipleHotstrings_AllAppearUnderHotstringsSection()
{
    Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
    Hotstring hs1 = new HotstringBuilder().WithTrigger("a").WithReplacement("alpha")
        .WithEndingCharacterRequired(true).WithTriggerInsideWord(false).Build();
    Hotstring hs2 = new HotstringBuilder().WithTrigger("b").WithReplacement("beta")
        .WithEndingCharacterRequired(true).WithTriggerInsideWord(false).Build();

    string output = _sut.Generate(profile, [hs1, hs2], []);

    output.Should().Be(
        "H\n" +
        "; --- Hotstrings ---\n" +
        "::a::alpha\n" +
        "::b::beta\n" +
        "; --- Hotkeys ---\n" +
        "F");
}
```

- [ ] **Step 2: Run and confirm failures**

```powershell
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --filter "FullyQualifiedName~AhkScriptGeneratorTests" --verbosity normal
```

Expected: 5 failures (4 theory rows + 1 multi-hotstring fact). Existing 2 still pass.

- [ ] **Step 3: Implement hotstring formatting**

Replace the body of `AhkScriptGenerator`:

```csharp
using AHKFlowApp.Domain.Entities;

namespace AHKFlowApp.Application.Services;

public sealed class AhkScriptGenerator
{
    private const string HotstringsSection = "; --- Hotstrings ---";
    private const string HotkeysSection = "; --- Hotkeys ---";

    public string Generate(
        Profile profile,
        IEnumerable<Hotstring> hotstrings,
        IEnumerable<Hotkey> hotkeys)
    {
        ArgumentNullException.ThrowIfNull(profile);
        ArgumentNullException.ThrowIfNull(hotstrings);
        ArgumentNullException.ThrowIfNull(hotkeys);

        List<string> lines = [profile.HeaderTemplate, HotstringsSection];

        foreach (Hotstring hs in hotstrings)
            lines.Add(FormatHotstring(hs));

        lines.Add(HotkeysSection);
        lines.Add(profile.FooterTemplate);

        return string.Join("\n", lines);
    }

    private static string FormatHotstring(Hotstring hs)
    {
        string options = "";
        if (!hs.IsEndingCharacterRequired) options += "*";
        if (hs.IsTriggerInsideWord) options += "?";
        return $":{options}:{hs.Trigger}::{hs.Replacement}";
    }
}
```

- [ ] **Step 4: Run and confirm all pass**

```powershell
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --filter "FullyQualifiedName~AhkScriptGeneratorTests" --verbosity normal
```

Expected: 7 passed.

- [ ] **Step 5: Commit**

```powershell
git add src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorTests.cs
git commit -m "feat(026): emit hotstring lines with `*` and `?` option flags"
```

---

## Task 5: Unit tests — hotkey formatting (modifiers, action enum)

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs`
- Modify: `tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorTests.cs`

Hotkey format: `{modifiers}{Key}::{ActionFn}("{Parameters}")` where:
- modifier prefix order is fixed: `^` (Ctrl), `!` (Alt), `+` (Shift), `#` (Win)
- `ActionFn` is `Send` for `HotkeyAction.Send`, `Run` for `HotkeyAction.Run`
- `Parameters` is emitted verbatim inside the v2 string literal — no escaping (L2)

- [ ] **Step 1: Add the hotkey tests**

Append to `AhkScriptGeneratorTests`:

```csharp
[Theory]
[InlineData(false, false, false, false, "n")]               // no modifiers
[InlineData(true, false, false, false, "^n")]               // Ctrl
[InlineData(false, true, false, false, "!n")]               // Alt
[InlineData(false, false, true, false, "+n")]               // Shift
[InlineData(false, false, false, true, "#n")]               // Win
[InlineData(true, true, false, false, "^!n")]               // Ctrl+Alt
[InlineData(true, true, true, true, "^!+#n")]               // all four, prefix-order locked
public void Generate_Hotkey_FormatsModifierPrefixesCorrectly(
    bool ctrl, bool alt, bool shift, bool win, string expectedLhs)
{
    Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
    Hotkey hk = new HotkeyBuilder()
        .WithDescription("d")
        .WithKey("n")
        .WithCtrl(ctrl).WithAlt(alt).WithShift(shift).WithWin(win)
        .WithAction(AHKFlowApp.Domain.Enums.HotkeyAction.Send)
        .WithParameters("hi")
        .Build();

    string output = _sut.Generate(profile, [], [hk]);

    output.Should().Be(
        "H\n" +
        "; --- Hotstrings ---\n" +
        "; --- Hotkeys ---\n" +
        $"{expectedLhs}::Send(\"hi\")\n" +
        "F");
}

[Theory]
[InlineData(AHKFlowApp.Domain.Enums.HotkeyAction.Send, "Send")]
[InlineData(AHKFlowApp.Domain.Enums.HotkeyAction.Run, "Run")]
public void Generate_Hotkey_EmitsCorrectActionFunctionName(
    AHKFlowApp.Domain.Enums.HotkeyAction action, string expectedFn)
{
    Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
    Hotkey hk = new HotkeyBuilder()
        .WithDescription("d")
        .WithKey("F5")
        .WithCtrl(false).WithAlt(false).WithShift(false).WithWin(false)
        .WithAction(action)
        .WithParameters("notepad.exe")
        .Build();

    string output = _sut.Generate(profile, [], [hk]);

    output.Should().Contain($"F5::{expectedFn}(\"notepad.exe\")");
}

[Fact]
public void Generate_Hotkey_EmitsParametersVerbatim_NoEscaping()
{
    // L2 — escaping is the user's responsibility. Verify we pass quotes through unchanged.
    Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
    Hotkey hk = new HotkeyBuilder()
        .WithDescription("d")
        .WithKey("a")
        .WithCtrl(true)
        .WithAction(AHKFlowApp.Domain.Enums.HotkeyAction.Send)
        .WithParameters("he said \"hi\"")
        .Build();

    string output = _sut.Generate(profile, [], [hk]);

    output.Should().Contain("^a::Send(\"he said \"hi\"\")");
}
```

- [ ] **Step 2: Run and confirm failures**

```powershell
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --filter "FullyQualifiedName~AhkScriptGeneratorTests" --verbosity normal
```

Expected: 10 new failures (7 modifier theory rows + 2 action theory rows + 1 escaping fact). Earlier 7 still pass.

- [ ] **Step 3: Implement hotkey formatting**

Replace the body of `AhkScriptGenerator`:

```csharp
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.Services;

public sealed class AhkScriptGenerator
{
    private const string HotstringsSection = "; --- Hotstrings ---";
    private const string HotkeysSection = "; --- Hotkeys ---";

    public string Generate(
        Profile profile,
        IEnumerable<Hotstring> hotstrings,
        IEnumerable<Hotkey> hotkeys)
    {
        ArgumentNullException.ThrowIfNull(profile);
        ArgumentNullException.ThrowIfNull(hotstrings);
        ArgumentNullException.ThrowIfNull(hotkeys);

        List<string> lines = [profile.HeaderTemplate, HotstringsSection];

        foreach (Hotstring hs in hotstrings)
            lines.Add(FormatHotstring(hs));

        lines.Add(HotkeysSection);

        foreach (Hotkey hk in hotkeys)
            lines.Add(FormatHotkey(hk));

        lines.Add(profile.FooterTemplate);

        return string.Join("\n", lines);
    }

    private static string FormatHotstring(Hotstring hs)
    {
        string options = "";
        if (!hs.IsEndingCharacterRequired) options += "*";
        if (hs.IsTriggerInsideWord) options += "?";
        return $":{options}:{hs.Trigger}::{hs.Replacement}";
    }

    private static string FormatHotkey(Hotkey hk)
    {
        string prefix = "";
        if (hk.Ctrl) prefix += "^";
        if (hk.Alt) prefix += "!";
        if (hk.Shift) prefix += "+";
        if (hk.Win) prefix += "#";

        string fn = hk.Action switch
        {
            HotkeyAction.Send => "Send",
            HotkeyAction.Run => "Run",
            _ => throw new InvalidOperationException($"Unsupported HotkeyAction: {hk.Action}"),
        };

        return $"{prefix}{hk.Key}::{fn}(\"{hk.Parameters}\")";
    }
}
```

- [ ] **Step 4: Run and confirm all pass**

```powershell
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --filter "FullyQualifiedName~AhkScriptGeneratorTests" --verbosity normal
```

Expected: 17 passed.

- [ ] **Step 5: Commit**

```powershell
git add src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorTests.cs
git commit -m "feat(026): emit AHK v2 hotkey lines with ^!+# modifier order"
```

---

## Task 6: Unit tests — deterministic ordering

**Files:**
- Modify: `tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorTests.cs`

The implementation in Task 5 iterates the input collections in caller-supplied order. Acceptance criterion 6 says hotstrings ordered by `Trigger` ASC and hotkeys by `Description` ASC. Add tests that verify the generator sorts them itself (so callers don't have to).

- [ ] **Step 1: Add the ordering tests**

Append to `AhkScriptGeneratorTests`:

```csharp
[Fact]
public void Generate_Hotstrings_AreSortedByTriggerOrdinalAscending()
{
    Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
    Hotstring c = new HotstringBuilder().WithTrigger("c").WithReplacement("c-rep")
        .WithEndingCharacterRequired(true).WithTriggerInsideWord(false).Build();
    Hotstring a = new HotstringBuilder().WithTrigger("a").WithReplacement("a-rep")
        .WithEndingCharacterRequired(true).WithTriggerInsideWord(false).Build();
    Hotstring b = new HotstringBuilder().WithTrigger("b").WithReplacement("b-rep")
        .WithEndingCharacterRequired(true).WithTriggerInsideWord(false).Build();

    string output = _sut.Generate(profile, [c, a, b], []);

    int posA = output.IndexOf("::a::a-rep", StringComparison.Ordinal);
    int posB = output.IndexOf("::b::b-rep", StringComparison.Ordinal);
    int posC = output.IndexOf("::c::c-rep", StringComparison.Ordinal);
    posA.Should().BeLessThan(posB);
    posB.Should().BeLessThan(posC);
}

[Fact]
public void Generate_Hotkeys_AreSortedByDescriptionOrdinalAscending()
{
    Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
    Hotkey z = new HotkeyBuilder().WithDescription("Zeta").WithKey("z")
        .WithAction(AHKFlowApp.Domain.Enums.HotkeyAction.Send).WithParameters("z").Build();
    Hotkey a = new HotkeyBuilder().WithDescription("Alpha").WithKey("a")
        .WithAction(AHKFlowApp.Domain.Enums.HotkeyAction.Send).WithParameters("a").Build();
    Hotkey m = new HotkeyBuilder().WithDescription("Mike").WithKey("m")
        .WithAction(AHKFlowApp.Domain.Enums.HotkeyAction.Send).WithParameters("m").Build();

    string output = _sut.Generate(profile, [], [z, a, m]);

    int posA = output.IndexOf("a::Send(\"a\")", StringComparison.Ordinal);
    int posM = output.IndexOf("m::Send(\"m\")", StringComparison.Ordinal);
    int posZ = output.IndexOf("z::Send(\"z\")", StringComparison.Ordinal);
    posA.Should().BeLessThan(posM);
    posM.Should().BeLessThan(posZ);
}

[Fact]
public void Generate_Ordering_IsCultureIndependent_OrdinalNotInvariant()
{
    // Ordinal sort: uppercase letters precede lowercase. Lock this in so future
    // refactors don't silently swap to InvariantCultureIgnoreCase.
    Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
    Hotstring lower = new HotstringBuilder().WithTrigger("aa").WithReplacement("lower")
        .WithEndingCharacterRequired(true).WithTriggerInsideWord(false).Build();
    Hotstring upper = new HotstringBuilder().WithTrigger("AA").WithReplacement("upper")
        .WithEndingCharacterRequired(true).WithTriggerInsideWord(false).Build();

    string output = _sut.Generate(profile, [lower, upper], []);

    int posUpper = output.IndexOf("::AA::upper", StringComparison.Ordinal);
    int posLower = output.IndexOf("::aa::lower", StringComparison.Ordinal);
    posUpper.Should().BeLessThan(posLower);  // 'A' (0x41) < 'a' (0x61) in Ordinal
}
```

- [ ] **Step 2: Run and confirm failures**

```powershell
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --filter "FullyQualifiedName~AhkScriptGeneratorTests" --verbosity normal
```

Expected: 3 failures (the 3 ordering tests).

- [ ] **Step 3: Add ordering to the generator**

Modify the two `foreach` loops in `Generate`:

```csharp
        foreach (Hotstring hs in hotstrings.OrderBy(h => h.Trigger, StringComparer.Ordinal))
            lines.Add(FormatHotstring(hs));

        lines.Add(HotkeysSection);

        foreach (Hotkey hk in hotkeys.OrderBy(h => h.Description, StringComparer.Ordinal))
            lines.Add(FormatHotkey(hk));
```

- [ ] **Step 4: Run and confirm all pass**

```powershell
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --filter "FullyQualifiedName~AhkScriptGeneratorTests" --verbosity normal
```

Expected: 20 passed.

- [ ] **Step 5: Commit**

```powershell
git add src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorTests.cs
git commit -m "feat(026): order hotstrings by Trigger and hotkeys by Description (Ordinal)"
```

---

## Task 7: Extend `HotkeyBuilder` with profile-association helpers

**Files:**
- Modify: `tests/AHKFlowApp.TestUtilities/Builders/HotkeyBuilder.cs`

The integration test in Task 9 needs to seed hotkeys that belong to a specific profile via the junction. `HotstringBuilder` already has `InProfile` / `WithProfiles` / `AppliesToAllProfiles`; mirror them on `HotkeyBuilder`.

- [ ] **Step 1: Replace `HotkeyBuilder.cs`**

Open `tests/AHKFlowApp.TestUtilities/Builders/HotkeyBuilder.cs` and replace the file with:

```csharp
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.TestUtilities.Builders;

public sealed class HotkeyBuilder
{
    private Guid _ownerOid = Guid.NewGuid();
    private string _description = "Open Notepad";
    private string _key = "n";
    private bool _ctrl;
    private bool _alt;
    private bool _shift;
    private bool _win;
    private HotkeyAction _action = HotkeyAction.Run;
    private string _parameters = "notepad.exe";
    private bool _appliesToAllProfiles = true;
    private Guid[] _profileIds = [];
    private TimeProvider _clock = TimeProvider.System;

    public HotkeyBuilder WithOwner(Guid ownerOid) { _ownerOid = ownerOid; return this; }
    public HotkeyBuilder WithDescription(string description) { _description = description; return this; }
    public HotkeyBuilder WithKey(string key) { _key = key; return this; }
    public HotkeyBuilder WithCtrl(bool value = true) { _ctrl = value; return this; }
    public HotkeyBuilder WithAlt(bool value = true) { _alt = value; return this; }
    public HotkeyBuilder WithShift(bool value = true) { _shift = value; return this; }
    public HotkeyBuilder WithWin(bool value = true) { _win = value; return this; }
    public HotkeyBuilder WithAction(HotkeyAction action) { _action = action; return this; }
    public HotkeyBuilder WithParameters(string parameters) { _parameters = parameters; return this; }
    public HotkeyBuilder WithClock(TimeProvider clock) { _clock = clock; return this; }

    public HotkeyBuilder InProfile(Guid profileId)
    {
        _appliesToAllProfiles = false;
        _profileIds = [profileId];
        return this;
    }

    public HotkeyBuilder WithProfiles(params Guid[] profileIds)
    {
        _appliesToAllProfiles = false;
        _profileIds = profileIds;
        return this;
    }

    public HotkeyBuilder AppliesToAll(bool value = true)
    {
        _appliesToAllProfiles = value;
        if (value) _profileIds = [];
        return this;
    }

    public Hotkey Build()
    {
        Hotkey entity = Hotkey.Create(
            _ownerOid, _description, _key, _ctrl, _alt, _shift, _win,
            _action, _parameters, _appliesToAllProfiles, _clock);

        foreach (Guid pid in _profileIds)
            entity.Profiles.Add(HotkeyProfile.Create(entity.Id, pid));

        return entity;
    }
}
```

- [ ] **Step 2: Build the test utilities project**

```powershell
dotnet build tests/AHKFlowApp.TestUtilities --configuration Release
```

Expected: `Build succeeded.`

- [ ] **Step 3: Re-run the existing hotkey tests to confirm no regression**

```powershell
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --filter "FullyQualifiedName~Hotkeys" --verbosity normal
```

Expected: all green (no behavior change for existing builder users — `AppliesToAll(true)` was already the default).

- [ ] **Step 4: Commit**

```powershell
git add tests/AHKFlowApp.TestUtilities/Builders/HotkeyBuilder.cs
git commit -m "test(026): add InProfile/WithProfiles to HotkeyBuilder"
```

---

## Task 8: Integration test — generator output against real DB

**Files:**
- Create: `tests/AHKFlowApp.Application.Tests/Services/ScriptGeneratorDbFixture.cs`
- Create: `tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorIntegrationTests.cs`

Acceptance criterion 7: seed a profile + mixed rows, generate, assert exact text. Phase 5 will own the EF query; here we replicate it inline so the test exercises the full pipeline (DB → filter → generator).

- [ ] **Step 1: Create the DB fixture**

```csharp
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Fixtures;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.Services;

public sealed class ScriptGeneratorDbFixture : IAsyncLifetime
{
    private readonly SqlContainerFixture _sql = new();

    public string ConnectionString => _sql.ConnectionString;

    public async Task InitializeAsync()
    {
        await _sql.InitializeAsync();
        await using AppDbContext ctx = CreateContext();
        await ctx.Database.MigrateAsync();
    }

    public Task DisposeAsync() => _sql.DisposeAsync();

    public AppDbContext CreateContext()
    {
        DbContextOptions<AppDbContext> options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(ConnectionString)
            .Options;
        return new AppDbContext(options);
    }
}

[CollectionDefinition("ScriptGeneratorDb")]
public sealed class ScriptGeneratorDbCollection : ICollectionFixture<ScriptGeneratorDbFixture>;
```

- [ ] **Step 2: Write the integration test**

```csharp
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.Services;

[Collection("ScriptGeneratorDb")]
public sealed class AhkScriptGeneratorIntegrationTests(ScriptGeneratorDbFixture fx)
{
    private readonly Guid _ownerOid = Guid.NewGuid();
    private readonly AhkScriptGenerator _sut = new();

    [Fact]
    public async Task Generate_FromSeededDb_ProducesExactExpectedText()
    {
        await using AppDbContext ctx = fx.CreateContext();

        Profile work = new ProfileBuilder()
            .WithOwner(_ownerOid)
            .WithName("Work")
            .AsDefault()
            .WithHeader("#Requires AutoHotkey v2.0\n#SingleInstance Force")
            .WithFooter("; end")
            .Build();
        Profile personal = new ProfileBuilder()
            .WithOwner(_ownerOid)
            .WithName("Personal")
            .AsDefault(false)
            .WithHeader("#Requires AutoHotkey v2.0")
            .WithFooter("")
            .Build();

        Hotstring hsAny = new HotstringBuilder().WithOwner(_ownerOid)
            .WithTrigger("btw").WithReplacement("by the way")
            .WithEndingCharacterRequired(false).WithTriggerInsideWord(true)
            .AppliesToAllProfiles().Build();
        Hotstring hsWorkOnly = new HotstringBuilder().WithOwner(_ownerOid)
            .WithTrigger("addr").WithReplacement("123 Main St")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false)
            .InProfile(work.Id).Build();
        Hotstring hsPersonalOnly = new HotstringBuilder().WithOwner(_ownerOid)
            .WithTrigger("zzz").WithReplacement("good night")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false)
            .InProfile(personal.Id).Build();

        Hotkey hkAny = new HotkeyBuilder().WithOwner(_ownerOid)
            .WithDescription("Open Notepad").WithKey("n").WithCtrl().WithAlt()
            .WithAction(HotkeyAction.Run).WithParameters("notepad.exe")
            .AppliesToAll().Build();
        Hotkey hkWorkOnly = new HotkeyBuilder().WithOwner(_ownerOid)
            .WithDescription("Reload").WithKey("F5").WithCtrl()
            .WithAction(HotkeyAction.Send).WithParameters("{F5}")
            .InProfile(work.Id).Build();

        ctx.Profiles.AddRange(work, personal);
        ctx.Hotstrings.AddRange(hsAny, hsWorkOnly, hsPersonalOnly);
        ctx.Hotkeys.AddRange(hkAny, hkWorkOnly);
        await ctx.SaveChangesAsync();

        // Mirror the EF query Phase 5 will own: rows in this profile's junction
        // OR rows where AppliesToAllProfiles=true.
        Guid pid = work.Id;
        List<Hotstring> hotstringsForWork = await ctx.Hotstrings.AsNoTracking()
            .Where(h => h.OwnerOid == _ownerOid &&
                        (h.AppliesToAllProfiles || h.Profiles.Any(p => p.ProfileId == pid)))
            .ToListAsync();
        List<Hotkey> hotkeysForWork = await ctx.Hotkeys.AsNoTracking()
            .Where(h => h.OwnerOid == _ownerOid &&
                        (h.AppliesToAllProfiles || h.Profiles.Any(p => p.ProfileId == pid)))
            .ToListAsync();
        Profile workReloaded = await ctx.Profiles.AsNoTracking().FirstAsync(p => p.Id == pid);

        string output = _sut.Generate(workReloaded, hotstringsForWork, hotkeysForWork);

        output.Should().Be(
            "#Requires AutoHotkey v2.0\n" +
            "#SingleInstance Force\n" +
            "; --- Hotstrings ---\n" +
            "::addr::123 Main St\n" +        // Ordinal: 'a' < 'b' so addr before btw
            ":*?:btw::by the way\n" +
            "; --- Hotkeys ---\n" +
            "^!n::Run(\"notepad.exe\")\n" +  // 'O' < 'R' so Open Notepad before Reload
            "^F5::Send(\"{F5}\")\n" +
            "; end");
    }
}
```

- [ ] **Step 3: Run the integration test**

```powershell
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --filter "FullyQualifiedName~AhkScriptGeneratorIntegrationTests" --verbosity normal
```

Expected: 1 passed. (Testcontainers will pull SQL Server image on first run — may take a few minutes.)

- [ ] **Step 4: Commit**

```powershell
git add tests/AHKFlowApp.Application.Tests/Services/ScriptGeneratorDbFixture.cs tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorIntegrationTests.cs
git commit -m "test(026): integration test for generator over real seeded DB"
```

---

## Task 9: Final verification, format, push, PR

- [ ] **Step 1: Full build + format check**

```powershell
dotnet build --configuration Release --no-restore
dotnet format --verify-no-changes
```

Expected: both succeed with no output. If `dotnet format` reports issues, run `dotnet format` (without `--verify-no-changes`), then `git add` and amend the most recent feature commit, or commit as `style(026): apply dotnet format`.

- [ ] **Step 2: Full test pass**

```powershell
dotnet test --configuration Release --no-build --verbosity normal
```

Expected: all tests pass — including pre-existing suites for Hotkeys/Hotstrings/Profiles (no regression).

- [ ] **Step 3: Push and open PR**

```powershell
git push -u origin feature/026-script-generation
gh pr create --title "feat(026): AHK v2 script generation per profile" --body "$(cat <<'EOF'
## Summary
- Adds `AhkScriptGenerator` service in Application layer (pure, no DB).
- Emits AHK v2 syntax: `Send("…")` / `Run("…")` as functions; modifier order `^!+#`; hotstring options `*` / `?`.
- Section headers always emit; ordering by `StringComparer.Ordinal`; line endings `\n`.
- Updates backlog 026 to fix v1→v2 example and pin format decisions.
- Extends `HotkeyBuilder` with `InProfile` / `WithProfiles` for tests.
- Phase 5 (Downloads endpoint + UI) consumes this generator.

Maps to backlog: 026. Spec: Phase 4 of `docs/superpowers/specs/2026-04-30-ahkflow-alignment-design.md`.

## Test plan
- [ ] `dotnet test --configuration Release` — all green
- [ ] Unit tests cover empty profile, hotstring option flags, all modifier combos, both `HotkeyAction` values, parameter pass-through, and Ordinal ordering
- [ ] Integration test seeds 2 profiles + mixed Any/specific rows, asserts exact `.ahk` text
- [ ] No new packages; no migrations; no API/UI changes
EOF
)"
```

Expected: PR URL printed.

---

## Self-Review

**Spec coverage** (Phase 4 / backlog 026):
- ✅ Pure service in Application layer, no DB calls — Task 2 (skeleton + DI), Task 3+ (impl).
- ✅ Profile-scoped filter (junction OR `AppliesToAllProfiles=true`) — caller's responsibility (L4); Task 8's integration test demonstrates the EF query Phase 5 will own.
- ✅ Output structure `{Header}\n; --- Hotstrings ---\n...\n; --- Hotkeys ---\n...\n{Footer}` — Tasks 3, 4, 5 build this incrementally; Task 8 asserts the exact string.
- ✅ Modifier prefix order `^!+#` — Task 5 theory test row `(true, true, true, true, "^!+#n")`.
- ✅ Hotkey line shape `{mods}{Key}::{ActionFn}("{Parameters}")` (v2, locked in L1) — Task 5 + backlog rewrite Task 1.
- ✅ Hotstring shape `:{options}:{Trigger}::{Replacement}` — Task 4 with Theory rows for all four flag combos.
- ✅ Deterministic ordering — Task 6, with explicit Ordinal vs invariant test to lock the comparer.
- ✅ Unit tests on empty profile + every modifier combo + both `HotkeyAction` values + both hotstring flags + ordering + Any inclusion (covered by integration test) — Tasks 3, 4, 5, 6, 8.
- ✅ Integration test: seeded profile + mixed rows, exact text — Task 8.

**Placeholder scan:** none. Every test has full code; every implementation has full code; every command is exact.

**Type consistency:**
- `Generate(Profile, IEnumerable<Hotstring>, IEnumerable<Hotkey>) -> string` is used identically in Tasks 3–8.
- `HotkeyAction.Send` / `HotkeyAction.Run` are the only enum values referenced (matches the existing enum).
- `HotstringBuilder.WithEndingCharacterRequired(bool)` / `WithTriggerInsideWord(bool)` match the existing builder.
- `HotkeyBuilder` extensions added in Task 7 (`InProfile`, `WithProfiles`, `AppliesToAll`) are used in Task 8 only.
- Integration test query uses `h.AppliesToAllProfiles || h.Profiles.Any(p => p.ProfileId == pid)` — same shape Phase 2/3 already use in `ListHotstringsQuery`.

---

## Unresolved questions

(none — the four format decisions were locked before plan; everything else is mechanical)
