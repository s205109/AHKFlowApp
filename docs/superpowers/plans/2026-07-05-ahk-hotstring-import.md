# Import Existing `.ahk` Hotstrings — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user paste or upload an AutoHotkey v2 script, preview which hotstring lines were recognized, and bulk-create them into a chosen profile target.

**Architecture:** A pure server-side parser (`AhkHotstringParser`, the inverse of `AhkScriptGenerator.FormatHotstring`) turns raw script text into typed rows. Two use cases sit on top: a read-only **preview** (parse + mark duplicates) and a **commit** (parse + insert survivors, with a duplicate-key detach/retry net). Both are exposed as endpoints on the existing `HotstringsController`; the Blazor UI reuses them from a single dialog. The client only ever sends raw text + profile target — never parsed rows.

**Tech Stack:** .NET 10, C# 14, EF Core (SQL Server), Ardalis.Result, FluentValidation, xUnit + FluentAssertions + Testcontainers, Blazor WebAssembly + MudBlazor 9.x, bUnit.

## Global Constraints

Copied verbatim from the spec ([2026-07-05-ahk-hotstring-import-design.md](../specs/2026-07-05-ahk-hotstring-import-design.md)). Every task's requirements implicitly include this section.

- **Parser is the single source of truth**, server-side only, for both preview and commit. The client never sends parsed rows back.
- **Option flags:** `*` → `IsEndingCharacterRequired = false`; `?` → `IsTriggerInsideWord = true`. Any other option letter → collected into `IgnoredFlags`, row status **Warning**, still importable.
- **Row status:** `Ready` | `Warning` (both import) · `Duplicate` | `Invalid` (both skipped). The parser only ever emits `Ready` / `Warning` / `Invalid` — it is **syntax-only** with no knowledge of duplicates. `Duplicate` is assigned only by the preview/import handlers.
- **Trigger** is trimmed of leading/trailing whitespace before validation; **replacement** is kept verbatim.
- **Validation constants** (reuse existing `HotstringRules`): trigger ≤ 50 chars, no linebreaks/tabs; replacement non-empty, ≤ 4000 chars.
- **Duplicate detection is case-insensitive** (matches the default SQL Server collation behind `IX_Hotstring_Owner_Trigger`). In-file repeats keep the first occurrence.
- **Multi-line continuation** (`(` … `)`) → **Invalid**, "Multi-line replacements are not supported." Inner lines are consumed so they don't misparse.
- **Comment (`;`), blank, hotkey, directive, plain-code lines** → silently ignored (not emitted, not reported).
- **Batch cap:** 1000 parsed hotstring rows per import; reject above with a clear message.
- **Script payload cap:** 1 MB (`1_048_576` characters), enforced by FluentValidation.
- **Profile target:** one target for the whole batch — `AppliesToAllProfiles` or a set of `ProfileIds`, validated with the existing `OwnedIdsValidation` + `AddProfileAssociationRules` patterns.
- **A fully-duplicate file is a 200 with `ImportedCount = 0`** and the per-row results — never an error. Per-line problems surface as row statuses, never HTTP errors.
- **Explicit mapping** — mirror the DTOs in the UI project; no shared-project change, no mapper library.
- Endpoints live on `HotstringsController` and inherit its `[Authorize]` + `[RequiredScope("access_as_user")]`.
- **Out of scope:** CLI `ahkflow hotstring import`, multi-line replacements, flag fidelity beyond `*`/`?`, hotkey import, overwrite/merge on collision.

## Design decision — how "existing duplicate" is detected in the commit path

The spec describes the commit as "drop Duplicate rows, insert the rest in one `SaveChanges`," plus a duplicate-key detach/retry for the race where a trigger is created between preview and commit.

This plan folds **both** existing-trigger detection and the race into the **same** detach/retry mechanism (the proven pattern from `ListHotstringsQuery` lazy-seed, `ListHotstringsQuery.cs:220-248`):

- The commit handler marks **in-file repeats** Duplicate purely (no DB), then attempts to insert every remaining Ready/Warning row.
- On a duplicate-key `DbUpdateException` (a pre-existing trigger **or** a concurrent insert), it detaches the pending entities, re-queries the owner's triggers, marks the now-colliding rows Duplicate, and re-saves the survivors.

Why: it produces results **identical** to preview for the same DB state (parity preserved), and — unlike a pre-query-then-filter design — the branch is **deterministically testable** by pre-seeding an overlapping trigger (exactly how the lazy-seed race is tested). The only cost is one rolled-back insert attempt when a returning user re-imports a script containing already-existing triggers; the primary onboarding case (empty account) has no duplicates and does a single `SaveChanges`.

Preview stays read-only: it queries existing triggers once and marks duplicates via the shared classifier.

One refinement over the spec's wording: the spec suggests detaching via `db.Hotstrings.Local` / `db.HotstringProfiles.Local`; the handler instead tracks the entities it created and detaches exactly those. Identical behavior today (the scoped context tracks nothing else), but robust if the handler ever gains a tracked query.

## File Structure

**Backend — `src/Backend/AHKFlowApp.Application/`**
- `DTOs/HotstringImportDtos.cs` — **new.** Status enum + all import DTOs (grouped, like `HistoryDtos.cs`).
- `Services/AhkHotstringParser.cs` — **new.** Pure syntax parser; inverse of `AhkScriptGenerator.FormatHotstring`.
- `Commands/Hotstrings/HotstringImportClassifier.cs` — **new.** Pure duplicate-marking helper (shared by both handlers).
- `Validation/HotstringImportRules.cs` — **new.** `MaxScriptLength`, `MaxRows` constants.
- `Commands/Hotstrings/PreviewHotstringImportCommand.cs` — **new.** Command + validator + read-only handler.
- `Commands/Hotstrings/ImportHotstringsCommand.cs` — **new.** Command + validator + commit handler (with detach/retry).
- `DependencyInjection.cs` — **modify.** Register the two use cases.

**Backend — `src/Backend/AHKFlowApp.API/`**
- `Controllers/HotstringsController.cs` — **modify.** Two new endpoints + two ctor use-case dependencies.

**Frontend — `src/Frontend/AHKFlowApp.UI.Blazor/`**
- `DTOs/HotstringImportDtos.cs` — **new.** Mirror of the enum + 4 DTOs.
- `Services/IHotstringsApiClient.cs` / `Services/HotstringsApiClient.cs` — **modify.** `PreviewImportAsync` / `ImportAsync`.
- `Components/Hotstrings/HotstringImportDialog.razor` — **new.** Single dialog: input → preview → confirm.
- `Pages/Hotstrings.razor` / `Pages/Hotstrings.razor.css` — **modify.** Desktop + mobile entry points.

**Tests**
- `tests/AHKFlowApp.Application.Tests/Hotstrings/AhkHotstringParserTests.cs`
- `tests/AHKFlowApp.Application.Tests/Hotstrings/HotstringImportClassifierTests.cs`
- `tests/AHKFlowApp.Application.Tests/Hotstrings/PreviewHotstringImportCommandHandlerTests.cs`
- `tests/AHKFlowApp.Application.Tests/Hotstrings/ImportHotstringsCommandHandlerTests.cs`
- `tests/AHKFlowApp.API.Tests/Hotstrings/HotstringImportEndpointsTests.cs`
- `tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotstrings/HotstringImportDialogTests.cs`

---

### Task 1: Import DTOs + status enum + parser (core, TDD)

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/DTOs/HotstringImportDtos.cs`
- Create: `src/Backend/AHKFlowApp.Application/Services/AhkHotstringParser.cs`
- Test: `tests/AHKFlowApp.Application.Tests/Hotstrings/AhkHotstringParserTests.cs`

**Interfaces:**
- Produces: `HotstringImportRowStatus` (enum: `Ready`, `Warning`, `Duplicate`, `Invalid`).
- Produces: `HotstringImportRowDto(int LineNumber, string Trigger, string Replacement, bool IsEndingCharacterRequired, bool IsTriggerInsideWord, string[] IgnoredFlags, HotstringImportRowStatus Status, string? Reason)`.
- Produces: `internal static IReadOnlyList<HotstringImportRowDto> AhkHotstringParser.Parse(string script)` — emits only `Ready` / `Warning` / `Invalid` rows, in line order.

- [ ] **Step 1: Create the DTO file with the enum and the row record**

`src/Backend/AHKFlowApp.Application/DTOs/HotstringImportDtos.cs`:

```csharp
namespace AHKFlowApp.Application.DTOs;

/// <summary>Outcome of a single parsed/classified import line.</summary>
public enum HotstringImportRowStatus
{
    /// <summary>Parsed cleanly; will import.</summary>
    Ready,

    /// <summary>Imports, but one or more unsupported option flags were dropped.</summary>
    Warning,

    /// <summary>Trigger already exists (for the owner or earlier in the file); skipped.</summary>
    Duplicate,

    /// <summary>Failed syntax/validation; skipped.</summary>
    Invalid,
}

/// <summary>One parsed line of an imported script.</summary>
public sealed record HotstringImportRowDto(
    int LineNumber,
    string Trigger,
    string Replacement,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord,
    string[] IgnoredFlags,
    HotstringImportRowStatus Status,
    string? Reason);
```

- [ ] **Step 2: Write the failing parser test class**

`tests/AHKFlowApp.Application.Tests/Hotstrings/AhkHotstringParserTests.cs`:

```csharp
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

[Trait("Category", "Unit")]
public sealed class AhkHotstringParserTests
{
    [Fact]
    public void Parse_PlainHotstring_ReturnsReadyWithDomainDefaults()
    {
        IReadOnlyList<HotstringImportRowDto> rows = AhkHotstringParser.Parse("::btw::by the way");

        rows.Should().ContainSingle();
        HotstringImportRowDto row = rows[0];
        row.Trigger.Should().Be("btw");
        row.Replacement.Should().Be("by the way");
        row.IsEndingCharacterRequired.Should().BeTrue();
        row.IsTriggerInsideWord.Should().BeFalse();
        row.IgnoredFlags.Should().BeEmpty();
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
        row.LineNumber.Should().Be(1);
    }

    [Fact]
    public void Parse_StarFlag_DropsEndingCharacterRequirement()
    {
        HotstringImportRowDto row = AhkHotstringParser.Parse(":*:btw::by the way")[0];

        row.IsEndingCharacterRequired.Should().BeFalse();
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_QuestionFlag_EnablesTriggerInsideWord()
    {
        HotstringImportRowDto row = AhkHotstringParser.Parse(":?:btw::by the way")[0];

        row.IsTriggerInsideWord.Should().BeTrue();
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_StarQuestionFlags_SetBothWithoutWarning()
    {
        HotstringImportRowDto row = AhkHotstringParser.Parse(":*?:btw::by the way")[0];

        row.IsEndingCharacterRequired.Should().BeFalse();
        row.IsTriggerInsideWord.Should().BeTrue();
        row.IgnoredFlags.Should().BeEmpty();
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_UnknownFlag_IsWarningWithIgnoredFlag()
    {
        HotstringImportRowDto row = AhkHotstringParser.Parse(":C:btw::by the way")[0];

        row.IgnoredFlags.Should().Contain("C");
        row.Status.Should().Be(HotstringImportRowStatus.Warning);
    }

    [Theory]
    [InlineData(":B0:btw::x", "B0")]
    [InlineData(":K5:btw::x", "K5")]
    [InlineData(":SI:btw::x", "SI")]
    public void Parse_ParameterizedOrMultiLetterFlag_PreservedAsExactToken(string line, string expectedToken)
    {
        HotstringImportRowDto row = AhkHotstringParser.Parse(line)[0];

        row.IgnoredFlags.Should().ContainSingle().Which.Should().Be(expectedToken);
        row.Status.Should().Be(HotstringImportRowStatus.Warning);
    }

    [Fact]
    public void Parse_NonHotstringLines_AreIgnored()
    {
        string script = string.Join('\n',
            "; a comment",
            "",
            "#Requires AutoHotkey v2.0",
            "^!k::Send(\"x\")",
            "MsgBox(\"hello\")");

        AhkHotstringParser.Parse(script).Should().BeEmpty();
    }

    [Fact]
    public void Parse_TriggerTooLong_IsInvalid()
    {
        string longTrigger = new('a', 51);

        HotstringImportRowDto row = AhkHotstringParser.Parse($"::{longTrigger}::x")[0];

        row.Status.Should().Be(HotstringImportRowStatus.Invalid);
        row.Reason.Should().Contain("50");
    }

    [Fact]
    public void Parse_EmptyReplacement_IsInvalid()
    {
        HotstringImportRowDto row = AhkHotstringParser.Parse("::btw::")[0];

        row.Status.Should().Be(HotstringImportRowStatus.Invalid);
        row.Reason.Should().Contain("Replacement");
    }

    [Fact]
    public void Parse_TabInTrigger_IsInvalid()
    {
        HotstringImportRowDto row = AhkHotstringParser.Parse("::b\tw::x")[0];

        row.Status.Should().Be(HotstringImportRowStatus.Invalid);
        row.Reason.Should().Contain("tabs");
    }

    [Fact]
    public void Parse_MultiLineContinuation_IsInvalidAndConsumesInnerLines()
    {
        string script = string.Join('\n',
            "::sig::",
            "(",
            "line one",
            "line two",
            ")",
            "::btw::by the way");

        IReadOnlyList<HotstringImportRowDto> rows = AhkHotstringParser.Parse(script);

        rows.Should().HaveCount(2);
        rows[0].Status.Should().Be(HotstringImportRowStatus.Invalid);
        rows[0].Reason.Should().Contain("Multi-line");
        rows[1].Trigger.Should().Be("btw");
        rows[1].Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_DoubleColonInsideReplacement_KeepsRemainderVerbatim()
    {
        HotstringImportRowDto row = AhkHotstringParser.Parse("::sig::a::b")[0];

        row.Trigger.Should().Be("sig");
        row.Replacement.Should().Be("a::b");
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_TriggerWithSurroundingWhitespace_IsTrimmed()
    {
        HotstringImportRowDto row = AhkHotstringParser.Parse(":: btw ::text")[0];

        row.Trigger.Should().Be("btw");
        row.Replacement.Should().Be("text");
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~AhkHotstringParserTests"`
Expected: FAIL — `AhkHotstringParser` does not exist (compile error).

- [ ] **Step 4: Implement the parser**

`src/Backend/AHKFlowApp.Application/Services/AhkHotstringParser.cs`:

```csharp
using System.Text.RegularExpressions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Validation;

namespace AHKFlowApp.Application.Services;

/// <summary>
/// Parses AutoHotkey v2 hotstring lines into typed rows — the syntax inverse of
/// <see cref="AhkScriptGenerator"/>'s <c>:{options}:{trigger}::{replacement}</c> format.
/// Pure and stateless; emits only Ready/Warning/Invalid (never Duplicate).
/// </summary>
internal static partial class AhkHotstringParser
{
    // :options:trigger::replacement — options and trigger contain no ':'; the trigger is
    // non-greedy so the FIRST '::' delimits, leaving any later '::' inside the replacement.
    [GeneratedRegex(@"^:([^:\r\n]*):(.*?)::(.*)$")]
    private static partial Regex HotstringLine();

    public static IReadOnlyList<HotstringImportRowDto> Parse(string script)
    {
        ArgumentNullException.ThrowIfNull(script);

        string[] lines = script.Replace("\r\n", "\n").Split('\n');
        List<HotstringImportRowDto> rows = [];

        for (int i = 0; i < lines.Length; i++)
        {
            string line = lines[i];
            string trimmed = line.Trim();

            if (trimmed.Length == 0 || trimmed.StartsWith(';'))
                continue;

            Match match = HotstringLine().Match(line);
            if (!match.Success)
                continue; // hotkey, directive, or plain code — not a hotstring candidate

            int lineNumber = i + 1;
            string trigger = match.Groups[2].Value.Trim();
            string replacement = match.Groups[3].Value;
            (bool endingRequired, bool insideWord, string[] ignoredFlags) = ParseOptions(match.Groups[1].Value);

            // "::trigger::" immediately followed by a "(" opens a continuation section.
            if (replacement.Length == 0 && i + 1 < lines.Length && lines[i + 1].Trim() == "(")
            {
                rows.Add(new HotstringImportRowDto(
                    lineNumber, trigger, replacement, endingRequired, insideWord, ignoredFlags,
                    HotstringImportRowStatus.Invalid, "Multi-line replacements are not supported."));

                i++; // consume "("
                while (i + 1 < lines.Length && lines[i + 1].Trim() != ")")
                    i++;
                if (i + 1 < lines.Length)
                    i++; // consume ")"
                continue;
            }

            string? reason = ValidateTrigger(trigger) ?? ValidateReplacement(replacement);
            HotstringImportRowStatus status = reason is not null
                ? HotstringImportRowStatus.Invalid
                : ignoredFlags.Length > 0
                    ? HotstringImportRowStatus.Warning
                    : HotstringImportRowStatus.Ready;

            rows.Add(new HotstringImportRowDto(
                lineNumber, trigger, replacement, endingRequired, insideWord, ignoredFlags, status, reason));
        }

        return rows;
    }

    private static (bool EndingRequired, bool InsideWord, string[] Ignored) ParseOptions(string options)
    {
        bool endingRequired = true;
        bool insideWord = false;
        List<string> ignored = [];

        for (int i = 0; i < options.Length; i++)
        {
            char c = options[i];
            switch (c)
            {
                case '*':
                    endingRequired = false;
                    break;
                case '?':
                    insideWord = true;
                    break;
                case ' ' or '\t':
                    break;
                case 'S' or 's' when i + 1 < options.Length && options[i + 1] is 'I' or 'P' or 'E' or 'i' or 'p' or 'e':
                    // Send-mode flags (SI/SP/SE) are two-letter tokens.
                    ignored.Add(options.Substring(i, 2));
                    i++;
                    break;
                default:
                    // A flag plus its trailing digits is one token (B0, C1, K5, P9, Z0, …),
                    // preserved verbatim so the preview reports exactly what was dropped.
                    int start = i;
                    while (i + 1 < options.Length && char.IsDigit(options[i + 1]))
                        i++;
                    ignored.Add(options[start..(i + 1)]);
                    break;
            }
        }

        return (endingRequired, insideWord, [.. ignored]);
    }

    private static string? ValidateTrigger(string trigger) =>
        trigger.Length == 0
            ? "Trigger is required."
            : trigger.Length > HotstringRules.TriggerMaxLength
                ? $"Trigger must be {HotstringRules.TriggerMaxLength} characters or fewer."
                : trigger.IndexOfAny(['\n', '\r', '\t']) >= 0
                    ? "Trigger must not contain line breaks or tabs."
                    : null;

    private static string? ValidateReplacement(string replacement) =>
        replacement.Length == 0
            ? "Replacement is required."
            : replacement.Length > HotstringRules.ReplacementMaxLength
                ? $"Replacement must be {HotstringRules.ReplacementMaxLength} characters or fewer."
                : null;
}
```

> Note: `HotstringRules` is `internal` in the same assembly — directly accessible. `[GeneratedRegex]` is the source-generated (AOT-friendly) regex idiom for .NET 10 / C# 14 and requires the class to be `internal static partial class`. (No regex exists elsewhere in the backend yet — this establishes the pattern. If you prefer to avoid the source generator, a `private static readonly Regex` field with `RegexOptions.Compiled` is an equivalent substitute.)

- [ ] **Step 5: Run the tests to verify they pass**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~AhkHotstringParserTests"`
Expected: PASS — 16 tests green (13 facts + 3 theory cases).

- [ ] **Step 6: Commit**

```bash
git add src/Backend/AHKFlowApp.Application/DTOs/HotstringImportDtos.cs \
        src/Backend/AHKFlowApp.Application/Services/AhkHotstringParser.cs \
        tests/AHKFlowApp.Application.Tests/Hotstrings/AhkHotstringParserTests.cs
git commit -m "feat: ahk hotstring import parser + row dto"
```

---

### Task 2: Duplicate classifier (pure, TDD)

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/HotstringImportClassifier.cs`
- Test: `tests/AHKFlowApp.Application.Tests/Hotstrings/HotstringImportClassifierTests.cs`

**Interfaces:**
- Consumes: `HotstringImportRowDto`, `HotstringImportRowStatus` (Task 1).
- Produces: `internal static string HotstringImportClassifier.DuplicateReason` and
  `internal static IReadOnlyList<HotstringImportRowDto> MarkDuplicates(IReadOnlyList<HotstringImportRowDto> rows, IReadOnlySet<string> existingTriggers)`.
  Marks a non-Invalid row **Duplicate** when its trigger is in `existingTriggers` (case-insensitive) or repeats an earlier accepted row (first occurrence wins). Preview passes the queried trigger set; commit passes an empty set (in-file repeats only).

- [ ] **Step 1: Write the failing classifier test**

`tests/AHKFlowApp.Application.Tests/Hotstrings/HotstringImportClassifierTests.cs`:

```csharp
using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

[Trait("Category", "Unit")]
public sealed class HotstringImportClassifierTests
{
    private static HotstringImportRowDto Row(string trigger, HotstringImportRowStatus status = HotstringImportRowStatus.Ready) =>
        new(1, trigger, "x", true, false, [], status, null);

    [Fact]
    public void MarkDuplicates_ExistingTrigger_MarkedDuplicate_CaseInsensitive()
    {
        IReadOnlySet<string> existing = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "BTW" };

        IReadOnlyList<HotstringImportRowDto> result =
            HotstringImportClassifier.MarkDuplicates([Row("btw")], existing);

        result[0].Status.Should().Be(HotstringImportRowStatus.Duplicate);
        result[0].Reason.Should().Be(HotstringImportClassifier.DuplicateReason);
    }

    [Fact]
    public void MarkDuplicates_InFileRepeat_KeepsFirstMarksRest()
    {
        IReadOnlyList<HotstringImportRowDto> result = HotstringImportClassifier.MarkDuplicates(
            [Row("btw"), Row("BTW")], new HashSet<string>());

        result[0].Status.Should().Be(HotstringImportRowStatus.Ready);
        result[1].Status.Should().Be(HotstringImportRowStatus.Duplicate);
    }

    [Fact]
    public void MarkDuplicates_InvalidRow_LeftUntouchedAndDoesNotClaimTrigger()
    {
        IReadOnlyList<HotstringImportRowDto> result = HotstringImportClassifier.MarkDuplicates(
            [Row("btw", HotstringImportRowStatus.Invalid), Row("btw")], new HashSet<string>());

        result[0].Status.Should().Be(HotstringImportRowStatus.Invalid);
        result[1].Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void MarkDuplicates_WarningRow_StaysWarningWhenUnique()
    {
        IReadOnlyList<HotstringImportRowDto> result = HotstringImportClassifier.MarkDuplicates(
            [Row("btw", HotstringImportRowStatus.Warning)], new HashSet<string>());

        result[0].Status.Should().Be(HotstringImportRowStatus.Warning);
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~HotstringImportClassifierTests"`
Expected: FAIL — `HotstringImportClassifier` does not exist.

- [ ] **Step 3: Implement the classifier**

`src/Backend/AHKFlowApp.Application/Commands/Hotstrings/HotstringImportClassifier.cs`:

```csharp
using AHKFlowApp.Application.DTOs;

namespace AHKFlowApp.Application.Commands.Hotstrings;

/// <summary>
/// Assigns the <see cref="HotstringImportRowStatus.Duplicate"/> status the parser cannot:
/// a non-Invalid row is a duplicate when its trigger already exists for the owner
/// (<paramref name="existingTriggers"/>) or repeats an earlier accepted row.
/// </summary>
internal static class HotstringImportClassifier
{
    public const string DuplicateReason = "A hotstring with this trigger already exists.";

    public static IReadOnlyList<HotstringImportRowDto> MarkDuplicates(
        IReadOnlyList<HotstringImportRowDto> rows,
        IReadOnlySet<string> existingTriggers)
    {
        HashSet<string> seen = new(StringComparer.OrdinalIgnoreCase);
        List<HotstringImportRowDto> result = new(rows.Count);

        foreach (HotstringImportRowDto row in rows)
        {
            if (row.Status == HotstringImportRowStatus.Invalid)
            {
                result.Add(row);
                continue;
            }

            bool duplicate = existingTriggers.Contains(row.Trigger) || !seen.Add(row.Trigger);
            result.Add(duplicate
                ? row with { Status = HotstringImportRowStatus.Duplicate, Reason = DuplicateReason }
                : row);
        }

        return result;
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~HotstringImportClassifierTests"`
Expected: PASS — 4 tests green.

- [ ] **Step 5: Commit**

```bash
git add src/Backend/AHKFlowApp.Application/Commands/Hotstrings/HotstringImportClassifier.cs \
        tests/AHKFlowApp.Application.Tests/Hotstrings/HotstringImportClassifierTests.cs
git commit -m "feat: hotstring import duplicate classifier"
```

---

### Task 3: Preview command, handler, validator + DI (TDD, Testcontainers)

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/Validation/HotstringImportRules.cs`
- Modify: `src/Backend/AHKFlowApp.Application/DTOs/HotstringImportDtos.cs` (add preview + request DTOs)
- Create: `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/PreviewHotstringImportCommand.cs`
- Modify: `src/Backend/AHKFlowApp.Application/DependencyInjection.cs`
- Test: `tests/AHKFlowApp.Application.Tests/Hotstrings/PreviewHotstringImportCommandHandlerTests.cs`

**Interfaces:**
- Consumes: `AhkHotstringParser.Parse` (Task 1), `HotstringImportClassifier.MarkDuplicates` (Task 2).
- Produces: `HotstringImportRules.MaxScriptLength = 1_048_576`, `HotstringImportRules.MaxRows = 1000`.
- Produces: `HotstringImportPreviewDto(HotstringImportRowDto[] Rows, int ReadyCount, int WarningCount, int DuplicateCount, int InvalidCount)`.
- Produces: `PreviewHotstringImportRequestDto(string Script)` (API request body).
- Produces: `PreviewHotstringImportCommand(string Script)` → `Result<HotstringImportPreviewDto>`.

- [ ] **Step 1: Add the constants**

`src/Backend/AHKFlowApp.Application/Validation/HotstringImportRules.cs`:

```csharp
namespace AHKFlowApp.Application.Validation;

internal static class HotstringImportRules
{
    /// <summary>Max raw script payload, in characters (~1 MB sanity bound).</summary>
    public const int MaxScriptLength = 1_048_576;

    /// <summary>Max parsed hotstring rows accepted per import.</summary>
    public const int MaxRows = 1000;
}
```

- [ ] **Step 2: Add the preview + request DTOs**

Append to `src/Backend/AHKFlowApp.Application/DTOs/HotstringImportDtos.cs`:

```csharp
/// <summary>Read-only preview of a parsed script, with per-status counts.</summary>
public sealed record HotstringImportPreviewDto(
    HotstringImportRowDto[] Rows,
    int ReadyCount,
    int WarningCount,
    int DuplicateCount,
    int InvalidCount);

/// <summary>Request body for the preview endpoint.</summary>
public sealed record PreviewHotstringImportRequestDto(string Script);
```

- [ ] **Step 3: Write the failing preview handler tests**

`tests/AHKFlowApp.Application.Tests/Hotstrings/PreviewHotstringImportCommandHandlerTests.cs`:

```csharp
using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using Ardalis.Result;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

[Collection("HotstringDb")]
[Trait("Category", "Integration")]
public sealed class PreviewHotstringImportCommandHandlerTests(HotstringDbFixture fx)
{
    private readonly TimeProvider _clock = TimeProvider.System;

    private PreviewHotstringImportCommandHandler Handler(AppDbContext db, Guid owner) =>
        new(db, CurrentUserHelper.For(owner));

    [Fact]
    public async Task Handle_ExistingTrigger_MarkedDuplicate_CaseInsensitive()
    {
        var owner = Guid.NewGuid();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(owner, "BTW", "existing", null, true, true, false, _clock));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        Result<HotstringImportPreviewDto> result = await Handler(db, owner).ExecuteAsync(
            new PreviewHotstringImportCommand("::btw::by the way"), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.DuplicateCount.Should().Be(1);
        result.Value.Rows[0].Status.Should().Be(HotstringImportRowStatus.Duplicate);
    }

    [Fact]
    public async Task Handle_InFileRepeat_FirstReadyRestDuplicate()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext db = fx.CreateContext();

        Result<HotstringImportPreviewDto> result = await Handler(db, owner).ExecuteAsync(
            new PreviewHotstringImportCommand("::btw::first\n::btw::second"), default);

        result.Value.ReadyCount.Should().Be(1);
        result.Value.DuplicateCount.Should().Be(1);
    }

    [Fact]
    public async Task Handle_CountsAllStatuses()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext db = fx.CreateContext();

        string script = string.Join('\n',
            "::ok::fine",          // Ready
            ":C:warn::flagged",    // Warning
            "::bad::");            // Invalid (empty replacement)

        Result<HotstringImportPreviewDto> result = await Handler(db, owner).ExecuteAsync(
            new PreviewHotstringImportCommand(script), default);

        result.Value.ReadyCount.Should().Be(1);
        result.Value.WarningCount.Should().Be(1);
        result.Value.InvalidCount.Should().Be(1);
    }

    [Fact]
    public async Task Handle_OverRowCap_ReturnsInvalid()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext db = fx.CreateContext();

        string script = string.Join('\n',
            Enumerable.Range(0, 1001).Select(i => $"::t{i}::r{i}"));

        Result<HotstringImportPreviewDto> result = await Handler(db, owner).ExecuteAsync(
            new PreviewHotstringImportCommand(script), default);

        result.Status.Should().Be(ResultStatus.Invalid);
    }

    [Fact]
    public async Task Handle_NoOid_ReturnsUnauthorized()
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new PreviewHotstringImportCommandHandler(db, CurrentUserHelper.For(null));

        Result<HotstringImportPreviewDto> result = await handler.ExecuteAsync(
            new PreviewHotstringImportCommand("::btw::x"), default);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }
}
```

- [ ] **Step 4: Run to verify it fails**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~PreviewHotstringImportCommandHandlerTests"`
Expected: FAIL — `PreviewHotstringImportCommand` / handler do not exist.

- [ ] **Step 5: Implement the command, validator, and handler**

`src/Backend/AHKFlowApp.Application/Commands/Hotstrings/PreviewHotstringImportCommand.cs`:

```csharp
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Application.Validation;
using Ardalis.Result;
using FluentValidation;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Hotstrings;

public sealed record PreviewHotstringImportCommand(string Script);

public sealed class PreviewHotstringImportCommandValidator : AbstractValidator<PreviewHotstringImportCommand>
{
    public PreviewHotstringImportCommandValidator()
    {
        RuleFor(x => x.Script)
            .Cascade(CascadeMode.Stop)
            .NotEmpty().WithMessage("Script is required.")
            .MaximumLength(HotstringImportRules.MaxScriptLength)
            .WithMessage($"Script must be {HotstringImportRules.MaxScriptLength} characters or fewer.");
    }
}

internal sealed class PreviewHotstringImportCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser)
    : IUseCaseHandler<PreviewHotstringImportCommand, Result<HotstringImportPreviewDto>>
{
    public async Task<Result<HotstringImportPreviewDto>> ExecuteAsync(
        PreviewHotstringImportCommand request,
        CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        IReadOnlyList<HotstringImportRowDto> parsed = AhkHotstringParser.Parse(request.Script);
        if (parsed.Count > HotstringImportRules.MaxRows)
            return Result.Invalid(new ValidationError
            {
                Identifier = nameof(PreviewHotstringImportCommand.Script),
                ErrorMessage = $"Import supports at most {HotstringImportRules.MaxRows} hotstrings per file.",
            });

        List<string> existing = await db.Hotstrings
            .Where(h => h.OwnerOid == ownerOid)
            .Select(h => h.Trigger)
            .ToListAsync(ct);
        HashSet<string> existingSet = new(existing, StringComparer.OrdinalIgnoreCase);

        IReadOnlyList<HotstringImportRowDto> rows = HotstringImportClassifier.MarkDuplicates(parsed, existingSet);

        return Result.Success(new HotstringImportPreviewDto(
            [.. rows],
            ReadyCount: rows.Count(r => r.Status == HotstringImportRowStatus.Ready),
            WarningCount: rows.Count(r => r.Status == HotstringImportRowStatus.Warning),
            DuplicateCount: rows.Count(r => r.Status == HotstringImportRowStatus.Duplicate),
            InvalidCount: rows.Count(r => r.Status == HotstringImportRowStatus.Invalid)));
    }
}
```

- [ ] **Step 6: Register the use case**

In `src/Backend/AHKFlowApp.Application/DependencyInjection.cs`, add to the `AddUseCase` chain (after the `SeedHotstringsCommand` line, ~line 51):

```csharp
            .AddUseCase<PreviewHotstringImportCommand, Result<HotstringImportPreviewDto>, PreviewHotstringImportCommandHandler>()
```

- [ ] **Step 7: Run to verify it passes**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~PreviewHotstringImportCommandHandlerTests"`
Expected: PASS — 5 tests green.

- [ ] **Step 8: Commit**

```bash
git add src/Backend/AHKFlowApp.Application/Validation/HotstringImportRules.cs \
        src/Backend/AHKFlowApp.Application/DTOs/HotstringImportDtos.cs \
        src/Backend/AHKFlowApp.Application/Commands/Hotstrings/PreviewHotstringImportCommand.cs \
        src/Backend/AHKFlowApp.Application/DependencyInjection.cs \
        tests/AHKFlowApp.Application.Tests/Hotstrings/PreviewHotstringImportCommandHandlerTests.cs
git commit -m "feat: hotstring import preview use case"
```

---

### Task 4: Import (commit) command, handler, validator + DI (TDD, Testcontainers)

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/DTOs/HotstringImportDtos.cs` (add request + result DTOs)
- Create: `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/ImportHotstringsCommand.cs`
- Modify: `src/Backend/AHKFlowApp.Application/DependencyInjection.cs`
- Test: `tests/AHKFlowApp.Application.Tests/Hotstrings/ImportHotstringsCommandHandlerTests.cs`

**Interfaces:**
- Consumes: `AhkHotstringParser.Parse`, `HotstringImportClassifier` (`.MarkDuplicates`, `.DuplicateReason`), `HotstringImportRules`, `OwnedIdsValidation.CheckOwnedIdsAsync`, `DbExceptions.IsDuplicateKeyViolation`, `Hotstring.Create`, `HotstringProfile.Create`.
- Produces: `ImportHotstringsRequestDto(string Script, bool AppliesToAllProfiles, Guid[]? ProfileIds)`.
- Produces: `HotstringImportResultDto(int ImportedCount, int WarningCount, HotstringImportRowDto[] Rows)` — `Rows` carries **every** processed line with its final status.
- Produces: `ImportHotstringsCommand(ImportHotstringsRequestDto Input)` → `Result<HotstringImportResultDto>`.

- [ ] **Step 1: Add the request + result DTOs**

Append to `src/Backend/AHKFlowApp.Application/DTOs/HotstringImportDtos.cs`:

```csharp
/// <summary>Request body for the commit endpoint: raw script + one profile target for the batch.</summary>
public sealed record ImportHotstringsRequestDto(
    string Script,
    bool AppliesToAllProfiles = true,
    Guid[]? ProfileIds = null);

/// <summary>Commit outcome. Rows carries every processed line with its final status.</summary>
public sealed record HotstringImportResultDto(
    int ImportedCount,
    int WarningCount,
    HotstringImportRowDto[] Rows);
```

- [ ] **Step 2: Write the failing commit handler tests**

`tests/AHKFlowApp.Application.Tests/Hotstrings/ImportHotstringsCommandHandlerTests.cs`:

```csharp
using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

[Collection("HotstringDb")]
[Trait("Category", "Integration")]
public sealed class ImportHotstringsCommandHandlerTests(HotstringDbFixture fx)
{
    private readonly TimeProvider _clock = TimeProvider.System;

    private ImportHotstringsCommandHandler Handler(AppDbContext db, Guid owner) =>
        new(db, CurrentUserHelper.For(owner), _clock);

    [Fact]
    public async Task Handle_ReadyAndWarningRows_Inserted_InvalidSkipped()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext db = fx.CreateContext();

        string script = string.Join('\n',
            "::ok::fine",         // Ready
            ":C:warn::flagged",   // Warning (imports)
            "::bad::");           // Invalid (skipped)

        Result<HotstringImportResultDto> result = await Handler(db, owner).ExecuteAsync(
            new ImportHotstringsCommand(new ImportHotstringsRequestDto(script)), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.ImportedCount.Should().Be(2);
        result.Value.WarningCount.Should().Be(1);

        await using AppDbContext verify = fx.CreateContext();
        (await verify.Hotstrings.CountAsync(h => h.OwnerOid == owner)).Should().Be(2);
    }

    [Fact]
    public async Task Handle_SpecificProfiles_LinksJunctionRows()
    {
        var owner = Guid.NewGuid();
        Profile profile = new ProfileBuilder().WithOwner(owner).WithName("Work").Build();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Profiles.Add(profile);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        Result<HotstringImportResultDto> result = await Handler(db, owner).ExecuteAsync(
            new ImportHotstringsCommand(new ImportHotstringsRequestDto(
                "::btw::by the way", AppliesToAllProfiles: false, ProfileIds: [profile.Id])), default);

        result.IsSuccess.Should().BeTrue();

        await using AppDbContext verify = fx.CreateContext();
        (await verify.HotstringProfiles.CountAsync(hp => hp.ProfileId == profile.Id)).Should().Be(1);
    }

    [Fact]
    public async Task Handle_UnknownProfile_ReturnsInvalid()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext db = fx.CreateContext();

        Result<HotstringImportResultDto> result = await Handler(db, owner).ExecuteAsync(
            new ImportHotstringsCommand(new ImportHotstringsRequestDto(
                "::btw::x", AppliesToAllProfiles: false, ProfileIds: [Guid.NewGuid()])), default);

        result.Status.Should().Be(ResultStatus.Invalid);
    }

    [Fact]
    public async Task Handle_InFileRepeat_ImportsFirstReportsSecondDuplicate()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext db = fx.CreateContext();

        Result<HotstringImportResultDto> result = await Handler(db, owner).ExecuteAsync(
            new ImportHotstringsCommand(new ImportHotstringsRequestDto("::btw::first\n::btw::second")), default);

        result.Value.ImportedCount.Should().Be(1);
        result.Value.Rows.Should().Contain(r => r.Status == HotstringImportRowStatus.Duplicate);

        await using AppDbContext verify = fx.CreateContext();
        (await verify.Hotstrings.CountAsync(h => h.OwnerOid == owner && h.Trigger == "btw")).Should().Be(1);
    }

    // Existing-trigger collision + the concurrent-create race share the detach/retry net:
    // pre-seeding an overlapping trigger forces the duplicate-key exception deterministically.
    [Fact]
    public async Task Handle_ExistingTrigger_DetachesReFiltersAndImportsTheRest()
    {
        var owner = Guid.NewGuid();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(owner, "btw", "pre-existing", null, true, true, false, _clock));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        Result<HotstringImportResultDto> result = await Handler(db, owner).ExecuteAsync(
            new ImportHotstringsCommand(new ImportHotstringsRequestDto("::btw::dup\n::new::fresh")), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.ImportedCount.Should().Be(1);
        result.Value.Rows.Single(r => r.Trigger == "btw").Status.Should().Be(HotstringImportRowStatus.Duplicate);
        result.Value.Rows.Single(r => r.Trigger == "new").Status.Should().Be(HotstringImportRowStatus.Ready);

        await using AppDbContext verify = fx.CreateContext();
        (await verify.Hotstrings.CountAsync(h => h.OwnerOid == owner && h.Trigger == "btw")).Should().Be(1);
        (await verify.Hotstrings.CountAsync(h => h.OwnerOid == owner && h.Trigger == "new")).Should().Be(1);
    }

    [Fact]
    public async Task Handle_FullyDuplicateFile_ImportsNothing_ReturnsSuccess()
    {
        var owner = Guid.NewGuid();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(owner, "btw", "x", null, true, true, false, _clock));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        Result<HotstringImportResultDto> result = await Handler(db, owner).ExecuteAsync(
            new ImportHotstringsCommand(new ImportHotstringsRequestDto("::btw::again")), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.ImportedCount.Should().Be(0);
    }

    [Fact]
    public async Task Handle_OverRowCap_ReturnsInvalid()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext db = fx.CreateContext();
        string script = string.Join('\n', Enumerable.Range(0, 1001).Select(i => $"::t{i}::r{i}"));

        Result<HotstringImportResultDto> result = await Handler(db, owner).ExecuteAsync(
            new ImportHotstringsCommand(new ImportHotstringsRequestDto(script)), default);

        result.Status.Should().Be(ResultStatus.Invalid);
    }
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~ImportHotstringsCommandHandlerTests"`
Expected: FAIL — `ImportHotstringsCommand` / handler do not exist.

- [ ] **Step 4: Implement the command, validator, and handler**

`src/Backend/AHKFlowApp.Application/Commands/Hotstrings/ImportHotstringsCommand.cs`:

```csharp
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Common;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using FluentValidation;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Hotstrings;

public sealed record ImportHotstringsCommand(ImportHotstringsRequestDto Input);

public sealed class ImportHotstringsCommandValidator : AbstractValidator<ImportHotstringsCommand>
{
    public ImportHotstringsCommandValidator()
    {
        RuleFor(x => x.Input.Script)
            .Cascade(CascadeMode.Stop)
            .NotEmpty().WithMessage("Script is required.")
            .MaximumLength(HotstringImportRules.MaxScriptLength)
            .WithMessage($"Script must be {HotstringImportRules.MaxScriptLength} characters or fewer.");

        this.AddProfileAssociationRules(
            x => x.Input.AppliesToAllProfiles,
            x => x.Input.ProfileIds);
    }
}

internal sealed class ImportHotstringsCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IUseCaseHandler<ImportHotstringsCommand, Result<HotstringImportResultDto>>
{
    public async Task<Result<HotstringImportResultDto>> ExecuteAsync(
        ImportHotstringsCommand request,
        CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        ImportHotstringsRequestDto input = request.Input;

        IReadOnlyList<HotstringImportRowDto> parsed = AhkHotstringParser.Parse(input.Script);
        if (parsed.Count > HotstringImportRules.MaxRows)
            return Result.Invalid(new ValidationError
            {
                Identifier = "Input.Script",
                ErrorMessage = $"Import supports at most {HotstringImportRules.MaxRows} hotstrings per file.",
            });

        Guid[] distinctProfileIds = input.ProfileIds?.Distinct().ToArray() ?? [];
        if (!input.AppliesToAllProfiles)
        {
            ValidationError? profileError = await OwnedIdsValidation.CheckOwnedIdsAsync(
                db.Profiles, p => p.OwnerOid == ownerOid && distinctProfileIds.Contains(p.Id),
                distinctProfileIds, "ProfileIds", ct);
            if (profileError is not null)
                return Result.Invalid(profileError);
        }

        // Mark in-file repeats (empty existing set); DB collisions are handled by the retry below.
        List<HotstringImportRowDto> final =
            [.. HotstringImportClassifier.MarkDuplicates(parsed, new HashSet<string>())];

        List<(int Index, HotstringImportRowDto Row)> pending =
        [
            .. final.Select((row, index) => (Index: index, Row: row))
                    .Where(x => x.Row.Status is HotstringImportRowStatus.Ready or HotstringImportRowStatus.Warning)
        ];

        List<Hotstring> created = [];
        List<HotstringProfile> createdLinks = [];
        AddEntities(pending);

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (ex.IsDuplicateKeyViolation())
        {
            // A trigger already existed (pre-existing or created concurrently). Detach exactly
            // this batch's pending entities, re-query the owner's triggers, drop the
            // now-colliding rows, and re-save the rest.
            foreach (Hotstring hs in created)
                db.Entry(hs).State = EntityState.Detached;
            foreach (HotstringProfile hp in createdLinks)
                db.Entry(hp).State = EntityState.Detached;
            created.Clear();
            createdLinks.Clear();

            HashSet<string> existing = new(
                await db.Hotstrings.Where(h => h.OwnerOid == ownerOid).Select(h => h.Trigger).ToListAsync(ct),
                StringComparer.OrdinalIgnoreCase);

            List<(int Index, HotstringImportRowDto Row)> survivors = [];
            foreach ((int index, HotstringImportRowDto row) in pending)
            {
                if (existing.Contains(row.Trigger))
                    final[index] = row with
                    {
                        Status = HotstringImportRowStatus.Duplicate,
                        Reason = HotstringImportClassifier.DuplicateReason,
                    };
                else
                    survivors.Add((index, row));
            }

            AddEntities(survivors);
            await db.SaveChangesAsync(ct);
        }

        int imported = final.Count(r => r.Status is HotstringImportRowStatus.Ready or HotstringImportRowStatus.Warning);
        int warnings = final.Count(r => r.Status == HotstringImportRowStatus.Warning);

        return Result.Success(new HotstringImportResultDto(imported, warnings, [.. final]));

        void AddEntities(List<(int Index, HotstringImportRowDto Row)> items)
        {
            foreach ((int _, HotstringImportRowDto row) in items)
            {
                Hotstring entity = Hotstring.Create(
                    ownerOid, row.Trigger, row.Replacement, description: null,
                    input.AppliesToAllProfiles, row.IsEndingCharacterRequired, row.IsTriggerInsideWord, clock);
                db.Hotstrings.Add(entity);
                created.Add(entity);

                if (!input.AppliesToAllProfiles)
                {
                    foreach (Guid pid in distinctProfileIds)
                    {
                        HotstringProfile link = HotstringProfile.Create(entity.Id, pid);
                        db.HotstringProfiles.Add(link);
                        createdLinks.Add(link);
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 5: Register the use case**

In `src/Backend/AHKFlowApp.Application/DependencyInjection.cs`, add to the chain right after the preview registration from Task 3:

```csharp
            .AddUseCase<ImportHotstringsCommand, Result<HotstringImportResultDto>, ImportHotstringsCommandHandler>()
```

- [ ] **Step 6: Run to verify it passes**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~ImportHotstringsCommandHandlerTests"`
Expected: PASS — 7 tests green.

- [ ] **Step 7: Commit**

```bash
git add src/Backend/AHKFlowApp.Application/DTOs/HotstringImportDtos.cs \
        src/Backend/AHKFlowApp.Application/Commands/Hotstrings/ImportHotstringsCommand.cs \
        src/Backend/AHKFlowApp.Application/DependencyInjection.cs \
        tests/AHKFlowApp.Application.Tests/Hotstrings/ImportHotstringsCommandHandlerTests.cs
git commit -m "feat: hotstring import commit use case"
```

---

### Task 5: API endpoints + integration tests

**Files:**
- Modify: `src/Backend/AHKFlowApp.API/Controllers/HotstringsController.cs`
- Test: `tests/AHKFlowApp.API.Tests/Hotstrings/HotstringImportEndpointsTests.cs`

**Interfaces:**
- Consumes: `PreviewHotstringImportCommand`, `ImportHotstringsCommand`, their result DTOs, and the request DTOs (Tasks 3–4).
- Produces: `POST api/v1/hotstrings/import/preview` → 200 `HotstringImportPreviewDto`, 400 on validation.
- Produces: `POST api/v1/hotstrings/import` → 200 `HotstringImportResultDto`, 400 on validation.

- [ ] **Step 1: Write the failing endpoint tests**

`tests/AHKFlowApp.API.Tests/Hotstrings/HotstringImportEndpointsTests.cs`:

```csharp
using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.Hotstrings;

[Collection("WebApi")]
public sealed class HotstringImportEndpointsTests(ApiTestFixture fixture)
{
    private readonly CustomWebApplicationFactory _factory = fixture.Factory;

    private HttpClient CreateAuthed(Guid? oid = null) =>
        _factory.CreateAuthenticatedClient(b => b.WithOid(oid ?? Guid.NewGuid()));

    [Fact]
    public async Task PostPreview_ReturnsRowsAndCounts()
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/hotstrings/import/preview", new PreviewHotstringImportRequestDto("::btw::by the way"));

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        HotstringImportPreviewDto? body = await response.Content.ReadFromJsonAsync<HotstringImportPreviewDto>();
        body!.ReadyCount.Should().Be(1);
        body.Rows.Should().ContainSingle();
    }

    [Fact]
    public async Task PostImport_CreatesHotstrings()
    {
        var owner = Guid.NewGuid();
        using HttpClient client = CreateAuthed(owner);

        HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/hotstrings/import", new ImportHotstringsRequestDto("::btw::by the way\n::omw::on my way"));

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        HotstringImportResultDto? body = await response.Content.ReadFromJsonAsync<HotstringImportResultDto>();
        body!.ImportedCount.Should().Be(2);

        HttpResponseMessage list = await client.GetAsync("/api/v1/hotstrings?pageSize=50");
        (await list.Content.ReadFromJsonAsync<PagedList<HotstringDto>>())!.TotalCount.Should().Be(2);
    }

    [Fact]
    public async Task PostImport_FullyDuplicate_Returns200WithZeroImported()
    {
        var owner = Guid.NewGuid();
        using HttpClient client = CreateAuthed(owner);
        await client.PostAsJsonAsync("/api/v1/hotstrings/import", new ImportHotstringsRequestDto("::btw::x"));

        HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/hotstrings/import", new ImportHotstringsRequestDto("::btw::again"));

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        (await response.Content.ReadFromJsonAsync<HotstringImportResultDto>())!.ImportedCount.Should().Be(0);
    }

    [Fact]
    public async Task PostImport_EmptyScript_Returns400()
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/hotstrings/import", new ImportHotstringsRequestDto(""));

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task PostPreview_Unauthenticated_Returns401()
    {
        using HttpClient client = _factory.CreateClient();

        HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/hotstrings/import/preview", new PreviewHotstringImportRequestDto("::btw::x"));

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `dotnet test tests/AHKFlowApp.API.Tests --filter "FullyQualifiedName~HotstringImportEndpointsTests"`
Expected: FAIL — endpoints return 404 (not yet defined).

- [ ] **Step 3: Add the two ctor dependencies**

In `src/Backend/AHKFlowApp.API/Controllers/HotstringsController.cs`, add these to the primary-constructor parameter list (after `purgeDeletedHotstring`, line 31), and add the `using` for the new commands:

```csharp
    IUseCase<PurgeDeletedHotstringCommand, Result> purgeDeletedHotstring,
    IUseCase<PreviewHotstringImportCommand, Result<HotstringImportPreviewDto>> previewImport,
    IUseCase<ImportHotstringsCommand, Result<HotstringImportResultDto>> importHotstrings) : ControllerBase
```

> `AHKFlowApp.Application.Commands.Hotstrings` and `AHKFlowApp.Application.DTOs` are already imported at the top of the file.

- [ ] **Step 4: Add the two endpoints**

Insert before the closing brace of `HotstringsController` (after the `Purge` action, ~line 165):

```csharp
    /// <summary>Preview which hotstring lines a pasted/uploaded script would import.</summary>
    [HttpPost("import/preview")]
    [ProducesResponseType(typeof(HotstringImportPreviewDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<HotstringImportPreviewDto>> ImportPreview(
        [FromBody] PreviewHotstringImportRequestDto dto,
        CancellationToken ct) =>
        (await previewImport.ExecuteAsync(new PreviewHotstringImportCommand(dto.Script), ct))
            .ToProblemActionResult(this);

    /// <summary>Bulk-create the recognized hotstrings from a script into a profile target.</summary>
    [HttpPost("import")]
    [ProducesResponseType(typeof(HotstringImportResultDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<HotstringImportResultDto>> Import(
        [FromBody] ImportHotstringsRequestDto dto,
        CancellationToken ct) =>
        (await importHotstrings.ExecuteAsync(new ImportHotstringsCommand(dto), ct))
            .ToProblemActionResult(this);
```

- [ ] **Step 5: Run to verify it passes**

Run: `dotnet test tests/AHKFlowApp.API.Tests --filter "FullyQualifiedName~HotstringImportEndpointsTests"`
Expected: PASS — 5 tests green.

- [ ] **Step 6: Commit**

```bash
git add src/Backend/AHKFlowApp.API/Controllers/HotstringsController.cs \
        tests/AHKFlowApp.API.Tests/Hotstrings/HotstringImportEndpointsTests.cs
git commit -m "feat: hotstring import endpoints"
```

---

### Task 6: UI DTOs + API client methods

**Files:**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HotstringImportDtos.cs`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Services/IHotstringsApiClient.cs`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Services/HotstringsApiClient.cs`
- Test: modify `tests/AHKFlowApp.UI.Blazor.Tests/Services/HotstringsApiClientTests.cs`

**Interfaces:**
- Produces (UI namespace `AHKFlowApp.UI.Blazor.DTOs`): `HotstringImportRowStatus`, `HotstringImportRowDto`, `HotstringImportPreviewDto`, `ImportHotstringsRequestDto`, `HotstringImportResultDto` — field-for-field mirrors of the backend records.
- Produces: `IHotstringsApiClient.PreviewImportAsync(string script, CancellationToken)` → `ApiResult<HotstringImportPreviewDto>`.
- Produces: `IHotstringsApiClient.ImportAsync(ImportHotstringsRequestDto request, CancellationToken)` → `ApiResult<HotstringImportResultDto>`.

> DTO records are trivial (no logic) — no DTO tests. The client methods carry real routes/payloads, so they get focused route tests in the existing `HotstringsApiClientTests` (which already asserts exact URLs via `StubHttpMessageHandler`).

- [ ] **Step 1: Mirror the DTOs**

`src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HotstringImportDtos.cs`:

```csharp
namespace AHKFlowApp.UI.Blazor.DTOs;

public enum HotstringImportRowStatus
{
    Ready,
    Warning,
    Duplicate,
    Invalid,
}

public sealed record HotstringImportRowDto(
    int LineNumber,
    string Trigger,
    string Replacement,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord,
    string[] IgnoredFlags,
    HotstringImportRowStatus Status,
    string? Reason);

public sealed record HotstringImportPreviewDto(
    HotstringImportRowDto[] Rows,
    int ReadyCount,
    int WarningCount,
    int DuplicateCount,
    int InvalidCount);

public sealed record ImportHotstringsRequestDto(
    string Script,
    bool AppliesToAllProfiles = true,
    Guid[]? ProfileIds = null);

public sealed record HotstringImportResultDto(
    int ImportedCount,
    int WarningCount,
    HotstringImportRowDto[] Rows);
```

- [ ] **Step 2: Extend the client interface**

Add to `src/Frontend/AHKFlowApp.UI.Blazor/Services/IHotstringsApiClient.cs` (before the closing brace):

```csharp
    Task<ApiResult<HotstringImportPreviewDto>> PreviewImportAsync(string script, CancellationToken ct = default);
    Task<ApiResult<HotstringImportResultDto>> ImportAsync(ImportHotstringsRequestDto request, CancellationToken ct = default);
```

- [ ] **Step 3: Implement the client methods**

Add to `src/Frontend/AHKFlowApp.UI.Blazor/Services/HotstringsApiClient.cs` (before the private `Add` helper):

```csharp
    public Task<ApiResult<HotstringImportPreviewDto>> PreviewImportAsync(string script, CancellationToken ct = default) =>
        SendAsync<HotstringImportPreviewDto>(
            HttpMethod.Post,
            $"{BasePath}/import/preview",
            JsonContent.Create(new { script }),
            ct);

    public Task<ApiResult<HotstringImportResultDto>> ImportAsync(ImportHotstringsRequestDto request, CancellationToken ct = default) =>
        SendAsync<HotstringImportResultDto>(
            HttpMethod.Post,
            $"{BasePath}/import",
            JsonContent.Create(request),
            ct);
```

- [ ] **Step 4: Add route tests to the existing client test class**

Append to `tests/AHKFlowApp.UI.Blazor.Tests/Services/HotstringsApiClientTests.cs` (same `ClientWith` + `StubHttpMessageHandler` helpers as the surrounding tests):

```csharp
    [Fact]
    public async Task PreviewImportAsync_PostsScriptToPreviewRoute()
    {
        HotstringImportPreviewDto dto = new([], 0, 0, 0, 0);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, dto);

        ApiResult<HotstringImportPreviewDto> result =
            await ClientWith(handler).PreviewImportAsync("::btw::by the way");

        result.IsSuccess.Should().BeTrue();
        handler.LastRequest!.Method.Should().Be(HttpMethod.Post);
        handler.LastRequest.RequestUri!.ToString().Should().Be("http://localhost/api/v1/hotstrings/import/preview");
        (await handler.LastRequest.Content!.ReadAsStringAsync()).Should().Contain("::btw::by the way");
    }

    [Fact]
    public async Task ImportAsync_PostsRequestToImportRoute()
    {
        HotstringImportResultDto dto = new(1, 0, []);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, dto);

        ApiResult<HotstringImportResultDto> result = await ClientWith(handler)
            .ImportAsync(new ImportHotstringsRequestDto("::btw::x", AppliesToAllProfiles: false, ProfileIds: [Guid.NewGuid()]));

        result.IsSuccess.Should().BeTrue();
        result.Value!.ImportedCount.Should().Be(1);
        handler.LastRequest!.Method.Should().Be(HttpMethod.Post);
        handler.LastRequest.RequestUri!.ToString().Should().Be("http://localhost/api/v1/hotstrings/import");
    }
```

- [ ] **Step 5: Run the client tests**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HotstringsApiClientTests"`
Expected: PASS — existing tests plus the 2 new ones green.

- [ ] **Step 6: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HotstringImportDtos.cs \
        src/Frontend/AHKFlowApp.UI.Blazor/Services/IHotstringsApiClient.cs \
        src/Frontend/AHKFlowApp.UI.Blazor/Services/HotstringsApiClient.cs \
        tests/AHKFlowApp.UI.Blazor.Tests/Services/HotstringsApiClientTests.cs
git commit -m "feat: hotstring import UI dtos + api client"
```

---

### Task 7: Import dialog component + bUnit tests

**Files:**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringImportDialog.razor`
- Test: `tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotstrings/HotstringImportDialogTests.cs`

**Interfaces:**
- Consumes: `IHotstringsApiClient.PreviewImportAsync` / `.ImportAsync` (Task 6), `EntityMultiSelect`, `EntityOption`, `ProfileDto`, `ApiErrorMessageFactory`, `ISnackbar`, `IMudDialogInstance`.
- Produces: `HotstringImportDialog` with `[Parameter] IReadOnlyList<ProfileDto> Profiles`. Closes with `DialogResult.Ok(int importedCount)` on success; `Dialog.Cancel()` otherwise.

> **MudBlazor API note:** before finalizing markup, verify `MudFileUpload<IBrowserFile>`, `MudTable`, and `MudChip` parameters against the MudMCP server (`mcp__mudblazor__get_component_parameters`) per `src/Frontend/AHKFlowApp.UI.Blazor/CLAUDE.md`. The markup below targets MudBlazor 9.x.

- [ ] **Step 1: Write the dialog component**

`src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringImportDialog.razor`:

```razor
@using AHKFlowApp.UI.Blazor.DTOs
@using AHKFlowApp.UI.Blazor.Services
@using AHKFlowApp.UI.Blazor.Validation
@using Microsoft.AspNetCore.Components.Forms
@using MudBlazor
@implements IDisposable

<MudDialog Class="hotstring-import-dialog">
    <TitleContent>
        <MudStack Row="true" AlignItems="AlignItems.Center" Justify="Justify.SpaceBetween" Class="flex-grow-1">
            <MudIconButton Class="cancel-import" Icon="@Icons.Material.Filled.ArrowBack" OnClick="Cancel" />
            <MudText Typo="Typo.h6">Import hotstrings</MudText>
            <MudButton Class="confirm-import" Color="Color.Primary" Variant="Variant.Filled"
                       Disabled="@(_preview is null || _importableCount == 0 || _busy)"
                       OnClick="ConfirmAsync">
                Import @_importableCount
            </MudButton>
        </MudStack>
    </TitleContent>
    <DialogContent>
        <MudStack Spacing="3" Class="pa-2">
            <MudTextField T="string" @bind-Value="_script" @bind-Value:after="OnScriptChanged"
                          Label="Paste your .ahk script" Lines="8"
                          Variant="Variant.Outlined" Immediate="true"
                          UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "import-script" })" />

            <MudFileUpload T="IBrowserFile" Accept=".ahk,.txt" FilesChanged="OnFileSelectedAsync">
                <ActivatorContent>
                    <MudButton Class="import-upload" Variant="Variant.Outlined"
                               StartIcon="@Icons.Material.Filled.UploadFile">
                        Upload .ahk / .txt
                    </MudButton>
                </ActivatorContent>
            </MudFileUpload>

            <MudCheckBox T="bool" @bind-Value="_appliesToAllProfiles" Label="Apply to all profiles" />
            @if (!_appliesToAllProfiles)
            {
                <EntityMultiSelect Options="_profileOptions" Label="Profiles"
                                   SelectedIds="_profileIds"
                                   SelectedIdsChanged="ids => _profileIds = [.. ids]"
                                   DataTest="import-profile-select" />
            }

            <MudButton Class="preview-import" Variant="Variant.Filled" Color="Color.Secondary"
                       StartIcon="@Icons.Material.Filled.Visibility"
                       Disabled="@(string.IsNullOrWhiteSpace(_script) || _busy)"
                       OnClick="PreviewAsync">
                Preview
            </MudButton>

            @if (_error is not null)
            {
                <MudAlert Severity="Severity.Error">@_error</MudAlert>
            }

            @if (_preview is not null)
            {
                <MudText Typo="Typo.body2" Class="import-summary">
                    @_preview.ReadyCount ready, @_preview.WarningCount with warnings,
                    @_preview.DuplicateCount duplicates skipped, @_preview.InvalidCount invalid
                </MudText>

                <MudTable Items="_preview.Rows" Dense="true" Hover="true" Class="import-preview-table">
                    <HeaderContent>
                        <MudTh>Line</MudTh>
                        <MudTh>Trigger</MudTh>
                        <MudTh>Replacement</MudTh>
                        <MudTh>Status</MudTh>
                    </HeaderContent>
                    <RowTemplate>
                        <MudTd>@context.LineNumber</MudTd>
                        <MudTd><code>@context.Trigger</code></MudTd>
                        <MudTd>@context.Replacement</MudTd>
                        <MudTd>
                            <MudChip T="string" Size="Size.Small" Color="@StatusColor(context.Status)">
                                @StatusLabel(context)
                            </MudChip>
                        </MudTd>
                    </RowTemplate>
                </MudTable>
            }
        </MudStack>
    </DialogContent>
</MudDialog>

@code {
    [CascadingParameter] private IMudDialogInstance Dialog { get; set; } = default!;
    [Inject] private IHotstringsApiClient Api { get; set; } = default!;
    [Inject] private ISnackbar Snackbar { get; set; } = default!;

    [Parameter] public IReadOnlyList<ProfileDto> Profiles { get; set; } = [];

    private string _script = "";
    private bool _appliesToAllProfiles = true;
    private List<Guid> _profileIds = [];
    private HotstringImportPreviewDto? _preview;
    private string? _error;
    private bool _busy;
    private IReadOnlyList<EntityOption> _profileOptions = [];
    private readonly CancellationTokenSource _cts = new();

    private int _importableCount => _preview is null ? 0 : _preview.ReadyCount + _preview.WarningCount;

    protected override void OnParametersSet() =>
        _profileOptions = [.. Profiles.Select(p => new EntityOption(p.Id, p.Name))];

    private void Cancel() => Dialog.Cancel();

    // Any script change invalidates the preview — confirm stays disabled until re-previewed,
    // so the "Import N" count can never refer to stale content.
    private void OnScriptChanged() => _preview = null;

    private async Task OnFileSelectedAsync(IBrowserFile? file)
    {
        if (file is null)
            return;

        // 1 MB payload cap mirrors the server bound.
        using StreamReader reader = new(file.OpenReadStream(maxAllowedSize: 1_048_576));
        _script = await reader.ReadToEndAsync(_cts.Token);
        OnScriptChanged();
    }

    private async Task PreviewAsync()
    {
        _busy = true;
        _error = null;
        try
        {
            ApiResult<HotstringImportPreviewDto> result = await Api.PreviewImportAsync(_script, _cts.Token);
            if (result.IsSuccess)
                _preview = result.Value;
            else
                _error = ApiErrorMessageFactory.Build(result.Status, result.Problem);
        }
        finally
        {
            _busy = false;
        }
    }

    private async Task ConfirmAsync()
    {
        if (_importableCount == 0)
            return;

        _busy = true;
        _error = null;
        try
        {
            ImportHotstringsRequestDto request = new(
                _script, _appliesToAllProfiles, _appliesToAllProfiles ? null : [.. _profileIds]);

            ApiResult<HotstringImportResultDto> result = await Api.ImportAsync(request, _cts.Token);
            if (!result.IsSuccess)
            {
                _error = ApiErrorMessageFactory.Build(result.Status, result.Problem);
                return;
            }

            int imported = result.Value!.ImportedCount;
            int duplicates = result.Value.Rows.Count(r => r.Status == HotstringImportRowStatus.Duplicate);
            int invalid = result.Value.Rows.Count(r => r.Status == HotstringImportRowStatus.Invalid);
            Snackbar.Add(
                $"Imported {imported} hotstring(s); skipped {duplicates} duplicate(s), {invalid} invalid.",
                Severity.Success);
            Dialog.Close(DialogResult.Ok(imported));
        }
        finally
        {
            _busy = false;
        }
    }

    private static Color StatusColor(HotstringImportRowStatus status) => status switch
    {
        HotstringImportRowStatus.Ready => Color.Success,
        HotstringImportRowStatus.Warning => Color.Warning,
        HotstringImportRowStatus.Duplicate => Color.Default,
        _ => Color.Error,
    };

    private static string StatusLabel(HotstringImportRowDto row) => row.Status switch
    {
        HotstringImportRowStatus.Ready => "Ready",
        HotstringImportRowStatus.Warning => $"Warning: dropped {string.Join(", ", row.IgnoredFlags)}",
        HotstringImportRowStatus.Duplicate => "Duplicate",
        _ => $"Invalid: {row.Reason}",
    };

    public void Dispose() { _cts.Cancel(); _cts.Dispose(); }
}
```

- [ ] **Step 2: Write the failing bUnit tests**

`tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotstrings/HotstringImportDialogTests.cs`:

```csharp
using AHKFlowApp.UI.Blazor.Components.Hotstrings;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using Bunit;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Components.Hotstrings;

public sealed class HotstringImportDialogTests : BunitContext, IAsyncLifetime
{
    private readonly IHotstringsApiClient _api = Substitute.For<IHotstringsApiClient>();

    public HotstringImportDialogTests()
    {
        Services.AddSingleton(_api);
        Services.AddSingleton(Substitute.For<ISnackbar>());
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;
    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    private async Task<IRenderedComponent<MudDialogProvider>> OpenDialogAsync()
    {
        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            await dialogService.ShowAsync<HotstringImportDialog>("Import",
                new DialogParameters
                {
                    [nameof(HotstringImportDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                },
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        return provider;
    }

    [Fact]
    public async Task Confirm_DisabledBeforePreview()
    {
        IRenderedComponent<MudDialogProvider> provider = await OpenDialogAsync();

        provider.WaitForAssertion(() =>
            provider.Find("button.confirm-import").HasAttribute("disabled").Should().BeTrue());
    }

    [Fact]
    public async Task PreviewThenConfirm_CallsImportAndClosesDialog()
    {
        _api.PreviewImportAsync(Arg.Any<string>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringImportPreviewDto>.Ok(new HotstringImportPreviewDto(
                [new HotstringImportRowDto(1, "btw", "by the way", true, false, [], HotstringImportRowStatus.Ready, null)],
                ReadyCount: 1, WarningCount: 0, DuplicateCount: 0, InvalidCount: 0)));
        _api.ImportAsync(Arg.Any<ImportHotstringsRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringImportResultDto>.Ok(new HotstringImportResultDto(
                ImportedCount: 1, WarningCount: 0,
                Rows: [new HotstringImportRowDto(1, "btw", "by the way", true, false, [], HotstringImportRowStatus.Ready, null)])));

        IRenderedComponent<MudDialogProvider> provider = await OpenDialogAsync();

        provider.Find("textarea[data-test=\"import-script\"]").Input("::btw::by the way");
        await provider.InvokeAsync(() => provider.Find("button.preview-import").Click());
        provider.WaitForAssertion(() =>
            provider.Find("button.confirm-import").HasAttribute("disabled").Should().BeFalse());

        await provider.InvokeAsync(() => provider.Find("button.confirm-import").Click());

        await _api.Received(1).ImportAsync(Arg.Any<ImportHotstringsRequestDto>(), Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task EditingScriptAfterPreview_DisablesConfirmUntilRePreviewed()
    {
        _api.PreviewImportAsync(Arg.Any<string>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringImportPreviewDto>.Ok(new HotstringImportPreviewDto(
                [new HotstringImportRowDto(1, "btw", "by the way", true, false, [], HotstringImportRowStatus.Ready, null)],
                ReadyCount: 1, WarningCount: 0, DuplicateCount: 0, InvalidCount: 0)));

        IRenderedComponent<MudDialogProvider> provider = await OpenDialogAsync();

        provider.Find("textarea[data-test=\"import-script\"]").Input("::btw::by the way");
        await provider.InvokeAsync(() => provider.Find("button.preview-import").Click());
        provider.WaitForAssertion(() =>
            provider.Find("button.confirm-import").HasAttribute("disabled").Should().BeFalse());

        provider.Find("textarea[data-test=\"import-script\"]").Input("::btw::changed content");

        provider.WaitForAssertion(() =>
            provider.Find("button.confirm-import").HasAttribute("disabled").Should().BeTrue());
    }
}
```

- [ ] **Step 3: Run to verify it fails, then passes**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HotstringImportDialogTests"`
Expected: FAIL first (component/selectors missing) → after the component compiles, PASS — 3 tests green. If a MudBlazor selector differs from the markup, verify parameters via MudMCP and adjust the component or the selector.

- [ ] **Step 4: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringImportDialog.razor \
        tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotstrings/HotstringImportDialogTests.cs
git commit -m "feat: hotstring import dialog"
```

---

### Task 8: Wire entry points into the Hotstrings page

**Files:**
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor.css`

**Interfaces:**
- Consumes: `HotstringImportDialog` (Task 7), the page's existing `_profiles`, `_dialogOpen`, `ReloadAllAsync`, `DialogService`, `Snackbar`.
- Produces: `OpenImportDialogAsync()` — opens the import dialog full-screen, refreshes the list on a non-canceled result.

> A page-level bUnit test would require mocking six injected services plus auth state and is disproportionate for a wiring change; the dialog itself is covered in Task 7. Verify the entry points render and open the dialog by manual smoke check (Step 4). The `_dialogOpen` guard and `OpenCreateDialogAsync` pattern are copied verbatim from the existing create flow.

- [ ] **Step 1: Add the import handler method**

In the `@code` block of `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor`, add next to `OpenCreateDialogAsync` (~line 651):

```csharp
    private async Task OpenImportDialogAsync()
    {
        if (_dialogOpen)
            return;

        _dialogOpen = true;
        try
        {
            DialogParameters parameters = new()
            {
                [nameof(HotstringImportDialog.Profiles)] = _profiles,
            };

            IDialogReference dialog = await DialogService.ShowAsync<HotstringImportDialog>(
                "Import hotstrings", parameters,
                new DialogOptions { FullScreen = true, CloseButton = false });

            DialogResult? result = await dialog.Result;
            if (result?.Canceled == false)
                await ReloadAllAsync();
        }
        finally
        {
            _dialogOpen = false;
        }
    }
```

- [ ] **Step 2: Add the desktop toolbar button**

In the desktop `.desktop-branch` toolbar, after the `Reload` button (~line 26), add:

```razor
            <MudButton Class="import-hotstrings" Variant="Variant.Filled" Color="Color.Tertiary"
                       StartIcon="@Icons.Material.Filled.UploadFile" OnClick="OpenImportDialogAsync"
                       Disabled="@(!_isAuthenticated || _dialogOpen)">
                Import
            </MudButton>
```

- [ ] **Step 3: Add the mobile import FAB**

In the `.mobile-branch`, add a second FAB just before the existing `add-hotstring-fab` (~line 216):

```razor
            <MudFab Class="import-hotstring-fab" Color="Color.Tertiary"
                    StartIcon="@Icons.Material.Filled.UploadFile"
                    OnClick="OpenImportDialogAsync" />
```

- [ ] **Step 4: Position the import FAB above the add FAB**

Append to `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor.css`:

```css
.import-hotstring-fab {
    position: fixed;
    right: 16px;
    bottom: 84px;
    z-index: 100;
}
```

- [ ] **Step 5: Build the frontend and verify no regressions**

Run: `dotnet build src/Frontend/AHKFlowApp.UI.Blazor --configuration Release`
Then: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --configuration Release`
Expected: Build succeeded; all bUnit tests green.

- [ ] **Step 6: Visual smoke check of the mobile FAB stack**

Use the `playwright-cli` skill (per project CLAUDE.md) against the locally running app: open `/hotstrings`, set viewport to 400×800 (mobile branch), and screenshot. Verify the import FAB sits cleanly above the add FAB (no overlap at `bottom: 84px`) and that tapping each opens the correct dialog. Adjust the CSS offset if they collide.

- [ ] **Step 7: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor \
        src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor.css
git commit -m "feat: import entry points on hotstrings page"
```

---

### Task 9: Full verification + docs status update

**Files:**
- Modify: `docs/superpowers/specs/2026-07-05-ahk-hotstring-import-design.md`
- Modify: `docs/superpowers/specs/2026-07-04-first-release-feature-shortlist.md`

- [ ] **Step 1: Run the full build and test suite**

Run:
```bash
dotnet build --configuration Release
dotnet test --configuration Release --no-build
dotnet format --verify-no-changes
```
Expected: Build succeeded; all tests green; format clean. Fix anything that fails before continuing.

- [ ] **Step 2: Mark the design spec built**

In `docs/superpowers/specs/2026-07-05-ahk-hotstring-import-design.md`, change the status line:

```markdown
**Status:** Implemented 2026-07-05 — see [plan](../plans/2026-07-05-ahk-hotstring-import.md)
```

- [ ] **Step 3: Update the shortlist status**

In `docs/superpowers/specs/2026-07-04-first-release-feature-shortlist.md`, update row #2 of the "Ranked shortlist" table:

```markdown
| 2 | Import existing `.ahk` hotstrings | High — killer onboarding for existing AHK users | M-L | Feature | **Built 2026-07-05** — [design](2026-07-05-ahk-hotstring-import-design.md) + [plan](../plans/2026-07-05-ahk-hotstring-import.md) |
```

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-07-05-ahk-hotstring-import-design.md \
        docs/superpowers/specs/2026-07-04-first-release-feature-shortlist.md
git commit -m "docs: mark ahk hotstring import built"
```

---

## Self-review notes

- **Spec coverage:** parser behaviors (Task 1), duplicate/in-file classification (Tasks 2–4), preview counts (Task 3), commit with detach/retry race net (Task 4), profile target all/specific (Task 4), 1000-row cap + 1 MB + profile rules (Tasks 3–4), both endpoints + auth + 400 + fully-duplicate 200 (Task 5), UI DTO mirror + client (Task 6), dialog input→preview→confirm + disabled-at-0 (Task 7), desktop + mobile entry points (Task 8). Out-of-scope items (CLI, multi-line, flag fidelity, hotkey/overwrite) are intentionally excluded.
- **Type consistency:** `HotstringImportRowDto`, `HotstringImportPreviewDto`, `ImportHotstringsRequestDto`, `HotstringImportResultDto`, and `HotstringImportRowStatus` share identical shapes across backend (`AHKFlowApp.Application.DTOs`) and UI (`AHKFlowApp.UI.Blazor.DTOs`). `PreviewHotstringImportRequestDto` is backend-only (the UI client posts `new { script }`, matching the `BulkDelete` `new { ids }` idiom).
- **Deviation flagged:** commit-path existing-duplicate detection folded into the detach/retry (documented above) for deterministic testability and preview parity.

## Resolved questions (review 2026-07-05)

- Mobile import affordance: stacked 2nd FAB, confirmed — visually smoke-checked in Task 8 step 6.
- Warning chip shows exact dropped-flag tokens (parser preserves `B0`/`K5`/`SI` verbatim).
- Snackbar splits skipped counts into duplicates and invalids.
