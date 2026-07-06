# v1 Code-Body & Multi-Line Hotstring Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Import AHK v1 code-body and multi-line (continuation-section) hotstrings — convert static Send-only bodies and canonical `( ... )` blocks into multi-line replacements, reject logic bodies with honest granular reasons, and make the generator escape replacements so export→import→export is lossless (also fixing the latent multi-line-replacement generator bug).

**Architecture:** All logic changes live in the Application layer: `AhkScriptGenerator` (escaping) and `AhkHotstringParser` (decoding, continuation sections, code-body scanning, Send conversion). The parser stays `internal static partial class`; all new helpers are `private static`. One one-line CSS polish in `HotstringImportDialog.razor`. No DTO, domain, validation, API, or UI-form changes.

**Tech Stack:** .NET 10, C# 14 (file-scoped namespaces, collection expressions, switch expressions, `GeneratedRegex`), xUnit + FluentAssertions, bUnit (Task 7 only).

**Spec:** `docs/superpowers/specs/2026-07-06-v1-codebody-hotstring-import-design.md`

## Global Constraints

**From the spec (exact values — do not deviate):**

- **Generator escape set & order** (backtick first so nothing is double-escaped; output is one physical line per hotstring):
  1. `` ` `` → ` `` `
  2. LF (`\n`) → `` `n ``
  3. CR (`\r`) → `` `r ``
  4. TAB (`\t`) → `` `t ``
  5. `;` → `` `; `` (added per the spec's resolved item: AHK v2 treats a space/tab-preceded `;` as an end-of-line comment even on hotstring lines — see `https://www.autohotkey.com/docs/v2/misc/EscapeChar.htm`; escaping every `;` is safe because the decoder normalises `` `; `` back to `;`)
- **Decode algorithm** (single left-to-right pass over the single-line replacement captured after `::`, applied AFTER the regex splits trigger/replacement): non-backtick chars emit verbatim; on backtick look at next char x — `` ` ``→`` ` `` (doubled, consume both), `n`→LF, `r`→CR, `t`→TAB, `s`→space, `;`→`;`, any other char → emit x verbatim; a trailing lone backtick is dropped. `` ``n `` decodes to literal backtick + `n`, never a newline. Continuation-section lines are NOT escape-decoded.
- **Send-family regex:** `^\s*(SendInput|SendText|SendRaw|SendEvent|SendPlay|Send)\b\s*,?\s*(.*)$`, case-insensitive (longest alternatives first so `Send` cannot shadow `SendInput`).
- **v1 Send arg rules:** strip one optional leading `,` plus leading whitespace (the regex does this); keep internal and trailing spaces; unescaped `;` preceded by whitespace/tab (or at arg start) → reject whole body `"Inline comment in Send — not imported."`; only `` `; `` is a literal semicolon; reject `%...%` in ALL send families; interpreting sends (`Send`/`SendInput`/`SendEvent`/`SendPlay`) reject bare `^ ! + #` and any `{...}` token except `{Enter}`/`{Return}`→`\n` and `{Tab}`→`\t`; literal sends (`SendText`/`SendRaw`) keep braces/modifiers literal; concatenate converted sends in order with NO separator.
- **Code-body scan hard boundaries** (priority order): (1) a line matching the hotstring pattern before any `return` → Invalid `"Unterminated code body (no `return` before next hotstring)."` and DO NOT consume that line; (2) a lone `(` opens a nested continuation block — ignore `return`/`)`-lookalikes/hotstring-looking lines until the matching lone `)`; (3) a trimmed `return` (case-insensitive) outside a nested block → consume it, body is terminated; (4) EOF before `return` → Invalid `"Unterminated code body (no `return`)."`. Blank and `;`-comment lines inside the body are skipped, never terminators.
- **Exact reject/error strings:**
  - `"Unterminated continuation section."`
  - ``"Unterminated code body (no `return` before next hotstring)."``
  - ``"Unterminated code body (no `return`)."``
  - `"Inline comment in Send — not imported."`
  - `"Code-body hotstrings that run logic aren't supported (found: {construct})."` (granular; name the construct)
  - `"Code-body hotstrings that run logic aren't supported."` (generic fallback only when nothing specific is known)
- **Continuation sections:** lone `(` after an empty-replacement hotstring line … lone `)`; join inner lines with `\n`, trim per-line leading whitespace (AHK v2 defaults — verify at `https://www.autohotkey.com/docs/v2/Scripts.htm#continuation`); EOF before `)` → Invalid `"Unterminated continuation section."`.
- **Unchanged:** status enum, DTOs, duplicate detection (`HotstringImportClassifier.MarkDuplicates`), domain/validation (`Trigger` ≤ 50, `Replacement` ≤ 4000, `\n` allowed), UI edit form. Conversion is total: every row is Ready/Warning/Invalid — never a throw.

**Project rules:**

- .NET 10; all tests xUnit + FluentAssertions; test naming `MethodName_Scenario_ExpectedResult`; AAA with blank-line separation.
- File-scoped namespaces, Allman braces, `private static` helpers, records for DTOs.
- No `UseInMemoryDatabase` (not needed here — all tests are pure unit/bUnit tests).
- Conventional commits, extremely concise, each ending with:
  `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
- All commands run from the repo root `C:\Dev\segocom-github\AHKFlowApp\.claude\worktrees\feature-first-release-feature-shortlist`.
- Do not commit to `main`; work stays on the current feature branch.

---

### Task 1: Generator escapes replacements onto one physical line

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs`
- Test: `tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorTests.cs`

**Interfaces:**
- Consumes: `Hotstring.Replacement` (string), existing `private static string FormatHotstring(Hotstring hs)`.
- Produces: `private static string EscapeReplacement(string replacement)` in `AhkScriptGenerator`.

**Steps:**

- [ ] Verify the `;` claim against AHK v2 docs (`https://www.autohotkey.com/docs/v2/misc/EscapeChar.htm`): `` `; `` "is necessary only if the semicolon has a space or tab to its left" — i.e. space-preceded semicolons start comments even on hotstring lines, so the generator must escape `;`. This plan escapes every `;` unconditionally (simpler, decoder normalises it back). If the docs contradict this, keep the escape anyway — it is harmless and lossless.
- [ ] Write the failing test — append to `tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorTests.cs` (inside the existing `AhkScriptGeneratorTests` class):

```csharp
    [Theory]
    [InlineData("line one\nline two", "::sig::line one`nline two")]
    [InlineData("a\rb", "::sig::a`rb")]
    [InlineData("a\tb", "::sig::a`tb")]
    [InlineData("a\r\nb", "::sig::a`r`nb")]
    [InlineData("back`tick", "::sig::back``tick")]
    [InlineData("literal `n stays\n", "::sig::literal ``n stays`n")]
    [InlineData("a ; b", "::sig::a `; b")]
    public void Generate_HotstringWithSpecialChars_EscapesOntoSinglePhysicalLine(
        string replacement, string expectedLine)
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("sig")
            .WithReplacement(replacement)
            .WithEndingCharacterRequired(true)
            .WithTriggerInsideWord(false)
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Be(
            "H\n" +
            "; --- Hotstrings ---\n" +
            expectedLine + "\n" +
            "; --- Hotkeys ---\n" +
            "F");
    }
```

- [ ] Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~AhkScriptGeneratorTests.Generate_HotstringWithSpecialChars_EscapesOntoSinglePhysicalLine"` — expect FAIL (raw newlines break the output; no escaping exists yet).
- [ ] Implement — in `src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs`, replace `FormatHotstring` and add `EscapeReplacement` directly below it:

```csharp
    private static string FormatHotstring(Hotstring hs)
    {
        string options = "";
        if (!hs.IsEndingCharacterRequired) options += "*";
        if (hs.IsTriggerInsideWord) options += "?";
        return $":{options}:{hs.Trigger}::{EscapeReplacement(hs.Replacement)}";
    }

    // Keeps every hotstring on one physical line. Backtick first so nothing is
    // double-escaped. ';' is always escaped because AHK v2 treats a semicolon with
    // a space/tab to its left as an end-of-line comment, even on hotstring lines.
    // The emitted set is a subset of what AhkHotstringParser.DecodeEscapes accepts,
    // so generate -> parse -> generate is lossless.
    private static string EscapeReplacement(string replacement) =>
        replacement
            .Replace("`", "``")
            .Replace("\n", "`n")
            .Replace("\r", "`r")
            .Replace("\t", "`t")
            .Replace(";", "`;");
```

- [ ] Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~AhkScriptGeneratorTests"` — expect PASS (new theory green, all pre-existing generator tests still green — their replacements contain no escaped chars).
- [ ] Commit:

```bash
git add src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorTests.cs
git commit -m "feat: escape hotstring replacements in generated scripts" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Parser decodes escape sequences in single-line replacements

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Services/AhkHotstringParser.cs`
- Test: `tests/AHKFlowApp.Application.Tests/Hotstrings/AhkHotstringParserTests.cs`

**Interfaces:**
- Consumes: `Match.Groups[3].Value` (raw replacement text after the regex split).
- Produces: `private static string DecodeEscapes(string value)` in `AhkHotstringParser`.

**Steps:**

- [ ] Write the failing tests — append to `tests/AHKFlowApp.Application.Tests/Hotstrings/AhkHotstringParserTests.cs` (inside the existing `AhkHotstringParserTests` class):

```csharp
    [Theory]
    [InlineData("::sig::line one`nline two", "line one\nline two")]
    [InlineData("::sig::a`rb", "a\rb")]
    [InlineData("::sig::a`tb", "a\tb")]
    [InlineData("::sig::back``tick", "back`tick")]
    [InlineData("::sig::a`sb", "a b")]
    [InlineData("::sig::a`;b", "a;b")]
    public void Parse_EscapedReplacement_DecodesEscapeSequences(string line, string expected)
    {
        HotstringImportRowDto row = AhkHotstringParser.Parse(line)[0];

        row.Replacement.Should().Be(expected);
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_DoubledBacktickBeforeN_KeepsLiteralBacktickAndN()
    {
        HotstringImportRowDto row = AhkHotstringParser.Parse("::sig::keep ``n literal")[0];

        row.Replacement.Should().Be("keep `n literal");
    }

    [Fact]
    public void Parse_UnknownEscape_EmitsEscapedCharVerbatim()
    {
        HotstringImportRowDto row = AhkHotstringParser.Parse("::sig::a`qb")[0];

        row.Replacement.Should().Be("aqb");
    }

    [Fact]
    public void Parse_TrailingLoneBacktick_IsDropped()
    {
        HotstringImportRowDto row = AhkHotstringParser.Parse("::sig::abc`")[0];

        row.Replacement.Should().Be("abc");
    }
```

- [ ] Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~AhkHotstringParserTests.Parse_EscapedReplacement_DecodesEscapeSequences"` — expect FAIL (replacement kept verbatim today).
- [ ] Implement — in `src/Backend/AHKFlowApp.Application/Services/AhkHotstringParser.cs`: add `using System.Text;` as the first using directive, change the replacement capture line in `Parse`, and add `DecodeEscapes`. Full `Parse` after this task (only the `DecodeEscapes(...)` line changed from current source):

```csharp
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
            string replacement = DecodeEscapes(match.Groups[3].Value);
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
```

  And add this private method (below `Parse`, above `ParseOptions`):

```csharp
    // AHK v2 escape semantics: backtick escapes the SINGLE next character. Doubled
    // backticks are handled inline in the same pass, so "``n" decodes to a literal
    // backtick followed by 'n' — never a newline. No backtick survives decoding,
    // which makes re-generation deterministic. Exotic escapes with no text meaning
    // (`a `b `f `v) decode to the literal letter — documented limitation, not a bug.
    private static string DecodeEscapes(string value)
    {
        if (!value.Contains('`'))
            return value;

        StringBuilder sb = new(value.Length);
        for (int i = 0; i < value.Length; i++)
        {
            char c = value[i];
            if (c != '`')
            {
                sb.Append(c);
                continue;
            }

            if (i + 1 >= value.Length)
                break; // trailing lone backtick — dropped

            char next = value[++i];
            sb.Append(next switch
            {
                '`' => '`',
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                's' => ' ',
                ';' => ';',
                _ => next, // unknown escape — AHK emits the next char verbatim
            });
        }

        return sb.ToString();
    }
```

- [ ] Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~AhkHotstringParserTests"` — expect PASS (all four new tests green; every pre-existing parser test unaffected — their inputs contain no backticks).
- [ ] Commit:

```bash
git add src/Backend/AHKFlowApp.Application/Services/AhkHotstringParser.cs tests/AHKFlowApp.Application.Tests/Hotstrings/AhkHotstringParserTests.cs
git commit -m "feat: decode backtick escapes in hotstring import" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Continuation sections convert to multi-line replacements

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Services/AhkHotstringParser.cs`
- Test: `tests/AHKFlowApp.Application.Tests/Hotstrings/AhkHotstringParserTests.cs`

**Interfaces:**
- Produces:
  - `private static HotstringImportRowDto BuildRow(int lineNumber, string trigger, string replacement, bool endingRequired, bool insideWord, string[] ignoredFlags)`
  - `private static HotstringImportRowDto ParseContinuationSection(string[] lines, ref int i, int lineNumber, string trigger, bool endingRequired, bool insideWord, string[] ignoredFlags)`
- Consumes: `ValidateTrigger`, `ValidateReplacement` (existing).

**Steps:**

- [ ] Update the existing test — in `tests/AHKFlowApp.Application.Tests/Hotstrings/AhkHotstringParserTests.cs`, REPLACE the whole `Parse_MultiLineContinuation_IsInvalidAndConsumesInnerLines` method with:

```csharp
    [Fact]
    public void Parse_MultiLineContinuation_ConvertsToMultiLineReplacement()
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
        rows[0].Trigger.Should().Be("sig");
        rows[0].Replacement.Should().Be("line one\nline two");
        rows[0].Status.Should().Be(HotstringImportRowStatus.Ready);
        rows[1].Trigger.Should().Be("btw");
        rows[1].Status.Should().Be(HotstringImportRowStatus.Ready);
    }
```

- [ ] Add the new failing tests to the same class:

```csharp
    [Fact]
    public void Parse_IndentedContinuationLines_TrimLeadingWhitespacePerLine()
    {
        string script = string.Join('\n',
            "::sig::",
            "(",
            "    indented one",
            "\tindented two",
            ")");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Replacement.Should().Be("indented one\nindented two");
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_ContinuationLines_AreNotEscapeDecoded()
    {
        string script = string.Join('\n',
            "::sig::",
            "(",
            "literal `n stays",
            ")");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Replacement.Should().Be("literal `n stays");
    }

    [Fact]
    public void Parse_UnterminatedContinuation_IsInvalid()
    {
        string script = string.Join('\n',
            "::sig::",
            "(",
            "line one");

        IReadOnlyList<HotstringImportRowDto> rows = AhkHotstringParser.Parse(script);

        rows.Should().ContainSingle();
        rows[0].Status.Should().Be(HotstringImportRowStatus.Invalid);
        rows[0].Reason.Should().Be("Unterminated continuation section.");
    }
```

- [ ] Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~AhkHotstringParserTests"` — expect FAIL (continuation branch still emits "Multi-line replacements are not supported.").
- [ ] Implement — replace `Parse` with the version below (continuation branch delegated; validation tail extracted into `BuildRow`) and add the two new private methods below `Parse`:

```csharp
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
            string replacement = DecodeEscapes(match.Groups[3].Value);
            (bool endingRequired, bool insideWord, string[] ignoredFlags) = ParseOptions(match.Groups[1].Value);

            // "::trigger::" immediately followed by a lone "(" opens a continuation section.
            if (replacement.Length == 0 && i + 1 < lines.Length && lines[i + 1].Trim() == "(")
            {
                rows.Add(ParseContinuationSection(
                    lines, ref i, lineNumber, trigger, endingRequired, insideWord, ignoredFlags));
                continue;
            }

            rows.Add(BuildRow(lineNumber, trigger, replacement, endingRequired, insideWord, ignoredFlags));
        }

        return rows;
    }

    private static HotstringImportRowDto BuildRow(
        int lineNumber, string trigger, string replacement,
        bool endingRequired, bool insideWord, string[] ignoredFlags)
    {
        string? reason = ValidateTrigger(trigger) ?? ValidateReplacement(replacement);
        HotstringImportRowStatus status = reason is not null
            ? HotstringImportRowStatus.Invalid
            : ignoredFlags.Length > 0
                ? HotstringImportRowStatus.Warning
                : HotstringImportRowStatus.Ready;

        return new HotstringImportRowDto(
            lineNumber, trigger, replacement, endingRequired, insideWord, ignoredFlags, status, reason);
    }

    // AHK v2 continuation defaults: inner lines joined with LF, per-line leading
    // whitespace trimmed. Continuation lines are literal text — no escape decoding.
    private static HotstringImportRowDto ParseContinuationSection(
        string[] lines, ref int i, int lineNumber, string trigger,
        bool endingRequired, bool insideWord, string[] ignoredFlags)
    {
        i++; // consume "("
        List<string> inner = [];

        while (i + 1 < lines.Length)
        {
            i++;
            if (lines[i].Trim() == ")")
                return BuildRow(lineNumber, trigger, string.Join('\n', inner),
                    endingRequired, insideWord, ignoredFlags);

            inner.Add(lines[i].TrimStart());
        }

        return new HotstringImportRowDto(
            lineNumber, trigger, "", endingRequired, insideWord, ignoredFlags,
            HotstringImportRowStatus.Invalid, "Unterminated continuation section.");
    }
```

- [ ] Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~AhkHotstringParserTests"` — expect PASS.
- [ ] Commit:

```bash
git add src/Backend/AHKFlowApp.Application/Services/AhkHotstringParser.cs tests/AHKFlowApp.Application.Tests/Hotstrings/AhkHotstringParserTests.cs
git commit -m "feat: import continuation-section hotstrings as multi-line" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Code-body scanning with hard boundaries

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Services/AhkHotstringParser.cs`
- Test: `tests/AHKFlowApp.Application.Tests/Hotstrings/AhkHotstringParserTests.cs`

**Interfaces:**
- Produces:
  - `private static bool HasCodeBody(string[] lines, int index)`
  - `private static HotstringImportRowDto ParseCodeBody(string[] lines, ref int i, int lineNumber, string trigger, bool endingRequired, bool insideWord, string[] ignoredFlags)`
  - `private static bool TryConvertSendBody(IReadOnlyList<string> bodyLines, out string replacement, out string reason)` — minimal reject-all version in this task; Task 5 supplies the real conversion behind the SAME signature.
- Consumes: `HotstringLine()` regex, `BuildRow` (Task 3).

**Steps:**

- [ ] Write the failing tests — append to `AhkHotstringParserTests`:

```csharp
    [Fact]
    public void Parse_CodeBodyWithoutReturnBeforeNextHotstring_IsInvalidAndNextRowParses()
    {
        string script = string.Join('\n',
            "::bad::",
            "Send hello",
            "::btw::by the way");

        IReadOnlyList<HotstringImportRowDto> rows = AhkHotstringParser.Parse(script);

        rows.Should().HaveCount(2);
        rows[0].Status.Should().Be(HotstringImportRowStatus.Invalid);
        rows[0].Reason.Should().Be("Unterminated code body (no `return` before next hotstring).");
        rows[1].Trigger.Should().Be("btw");
        rows[1].Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_CodeBodyWithoutReturnAtEof_IsInvalid()
    {
        string script = string.Join('\n',
            "::bad::",
            "MsgBox hi");

        IReadOnlyList<HotstringImportRowDto> rows = AhkHotstringParser.Parse(script);

        rows.Should().ContainSingle();
        rows[0].Status.Should().Be(HotstringImportRowStatus.Invalid);
        rows[0].Reason.Should().Be("Unterminated code body (no `return`).");
    }

    [Fact]
    public void Parse_TerminatedLogicBody_IsInvalidWithHonestReason()
    {
        string script = string.Join('\n',
            "::d::",
            "FormatTime, X,, yyyy",
            "return",
            "::btw::by the way");

        IReadOnlyList<HotstringImportRowDto> rows = AhkHotstringParser.Parse(script);

        rows.Should().HaveCount(2);
        rows[0].Status.Should().Be(HotstringImportRowStatus.Invalid);
        rows[0].Reason.Should().Contain("aren't supported");
        rows[1].Trigger.Should().Be("btw");
        rows[1].Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_CodeBodyBlankAndCommentLines_AreSkippedNotTerminators()
    {
        string script = string.Join('\n',
            "::bad::",
            "MsgBox hi",
            "",
            "; a comment",
            "return");

        IReadOnlyList<HotstringImportRowDto> rows = AhkHotstringParser.Parse(script);

        rows.Should().ContainSingle();
        rows[0].Status.Should().Be(HotstringImportRowStatus.Invalid);
        rows[0].Reason.Should().Contain("aren't supported");
    }

    [Fact]
    public void Parse_NestedContinuationBlockInBody_IgnoresReturnAndHotstringLines()
    {
        string script = string.Join('\n',
            "::bad::",
            "x := 1",
            "(",
            "return",
            "::fake::not a new row",
            ")",
            "return",
            "::btw::by the way");

        IReadOnlyList<HotstringImportRowDto> rows = AhkHotstringParser.Parse(script);

        rows.Should().HaveCount(2);
        rows[0].Status.Should().Be(HotstringImportRowStatus.Invalid);
        rows[0].Reason.Should().Contain("aren't supported");
        rows[1].Trigger.Should().Be("btw");
    }

    [Fact]
    public void Parse_EmptyHotstringFollowedByHotstring_IsReplacementRequired()
    {
        string script = string.Join('\n',
            "::x::",
            "::btw::by the way");

        IReadOnlyList<HotstringImportRowDto> rows = AhkHotstringParser.Parse(script);

        rows.Should().HaveCount(2);
        rows[0].Reason.Should().Be("Replacement is required.");
        rows[1].Status.Should().Be(HotstringImportRowStatus.Ready);
    }
```

- [ ] Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~AhkHotstringParserTests"` — expect FAIL (empty-replacement rows report "Replacement is required." and body lines are skipped as non-hotstring lines today).
- [ ] Implement — in `AhkHotstringParser.cs`, insert the code-body branch into `Parse` (full method shown) and add the three private methods below `ParseContinuationSection`:

```csharp
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
            string replacement = DecodeEscapes(match.Groups[3].Value);
            (bool endingRequired, bool insideWord, string[] ignoredFlags) = ParseOptions(match.Groups[1].Value);

            // "::trigger::" immediately followed by a lone "(" opens a continuation section.
            if (replacement.Length == 0 && i + 1 < lines.Length && lines[i + 1].Trim() == "(")
            {
                rows.Add(ParseContinuationSection(
                    lines, ref i, lineNumber, trigger, endingRequired, insideWord, ignoredFlags));
                continue;
            }

            // "::trigger::" followed by non-hotstring code is a v1 code-body hotstring.
            if (replacement.Length == 0 && HasCodeBody(lines, i))
            {
                rows.Add(ParseCodeBody(
                    lines, ref i, lineNumber, trigger, endingRequired, insideWord, ignoredFlags));
                continue;
            }

            rows.Add(BuildRow(lineNumber, trigger, replacement, endingRequired, insideWord, ignoredFlags));
        }

        return rows;
    }

    // Peek past blank/comment lines: a following non-hotstring line means a v1 code
    // body; another hotstring (or nothing) means a genuinely empty hotstring.
    private static bool HasCodeBody(string[] lines, int index)
    {
        for (int j = index + 1; j < lines.Length; j++)
        {
            string trimmed = lines[j].Trim();
            if (trimmed.Length == 0 || trimmed.StartsWith(';'))
                continue;

            return !HotstringLine().IsMatch(lines[j]);
        }

        return false;
    }

    private static HotstringImportRowDto ParseCodeBody(
        string[] lines, ref int i, int lineNumber, string trigger,
        bool endingRequired, bool insideWord, string[] ignoredFlags)
    {
        List<string> body = [];
        int nestedDepth = 0;
        bool terminated = false;

        while (i + 1 < lines.Length)
        {
            string next = lines[i + 1];
            string trimmed = next.Trim();

            if (nestedDepth == 0)
            {
                // Hard boundary: a new hotstring before `return` ends the scan WITHOUT
                // consuming the line — the main loop re-processes it as its own row.
                if (HotstringLine().IsMatch(next))
                    return new HotstringImportRowDto(
                        lineNumber, trigger, "", endingRequired, insideWord, ignoredFlags,
                        HotstringImportRowStatus.Invalid,
                        "Unterminated code body (no `return` before next hotstring).");

                i++; // consume the body line

                if (trimmed.Length == 0 || trimmed.StartsWith(';'))
                    continue; // blank/comment lines are skipped, never terminators

                if (string.Equals(trimmed, "return", StringComparison.OrdinalIgnoreCase))
                {
                    terminated = true;
                    break;
                }

                if (trimmed == "(")
                    nestedDepth++;

                body.Add(next);
            }
            else
            {
                // Inside a lone-( ... lone-) block everything is literal: ignore return,
                // hotstring-looking lines, and comments until the matching lone ")".
                i++;
                if (trimmed == "(")
                    nestedDepth++;
                else if (trimmed == ")")
                    nestedDepth--;

                body.Add(next);
            }
        }

        if (!terminated)
            return new HotstringImportRowDto(
                lineNumber, trigger, "", endingRequired, insideWord, ignoredFlags,
                HotstringImportRowStatus.Invalid, "Unterminated code body (no `return`).");

        return TryConvertSendBody(body, out string converted, out string reason)
            ? BuildRow(lineNumber, trigger, converted, endingRequired, insideWord, ignoredFlags)
            : new HotstringImportRowDto(
                lineNumber, trigger, "", endingRequired, insideWord, ignoredFlags,
                HotstringImportRowStatus.Invalid, reason);
    }

    // Conservative default: every terminated body is rejected. Real Send-family
    // conversion replaces this method body behind the same signature.
    private static bool TryConvertSendBody(
        IReadOnlyList<string> bodyLines, out string replacement, out string reason)
    {
        replacement = "";
        reason = "Code-body hotstrings that run logic aren't supported.";
        return false;
    }
```

- [ ] Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~AhkHotstringParserTests"` — expect PASS (all six new tests green; `Parse_EmptyReplacement_IsInvalid` still green — no following line means no code body).
- [ ] Commit:

```bash
git add src/Backend/AHKFlowApp.Application/Services/AhkHotstringParser.cs tests/AHKFlowApp.Application.Tests/Hotstrings/AhkHotstringParserTests.cs
git commit -m "feat: scan v1 code bodies with hard boundaries on import" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Convert literal Send-family bodies (`TryConvertSendBody`)

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Services/AhkHotstringParser.cs`
- Test: `tests/AHKFlowApp.Application.Tests/Hotstrings/AhkHotstringParserTests.cs`

**Interfaces:**
- Consumes: `TryConvertSendBody` call site in `ParseCodeBody` (Task 4 — unchanged).
- Produces (replacing the Task 4 stub, same signature):
  - `private static bool TryConvertSendBody(IReadOnlyList<string> bodyLines, out string replacement, out string reason)`
  - `private static bool TryConvertSendArg(string arg, bool literalMode, out string converted, out string reason)`
  - `private static string FirstToken(string line)`
  - `[GeneratedRegex(@"^\s*(SendInput|SendText|SendRaw|SendEvent|SendPlay|Send)\b\s*,?\s*(.*)$", RegexOptions.IgnoreCase)] private static partial Regex SendCommand();`

**Steps:**

- [ ] Write the failing tests — append to `AhkHotstringParserTests` (the spec's motivating examples appear verbatim):

```csharp
    [Fact]
    public void Parse_MvgpSendBody_ConvertsToTwoLineReplacement()
    {
        string script = string.Join('\n',
            "::mvgp::",
            "send Met vriendelijke Groet,{Return}",
            "send Bart Segers",
            "return");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Replacement.Should().Be("Met vriendelijke Groet,\nBart Segers");
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_DbgSendBody_ConvertsToLiteralText()
    {
        string script = string.Join('\n',
            "::dbg::",
            "send mocha --debug-brk",
            "return");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Replacement.Should().Be("mocha --debug-brk");
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_DTimeBody_IsRejectedNamingFormatTime()
    {
        string script = string.Join('\n',
            "::d-time::",
            "FormatTime, CurrentDateTime,, dd/MM/yyyy HH:mm",
            "SendInput %CurrentDateTime%",
            "return");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Status.Should().Be(HotstringImportRowStatus.Invalid);
        row.Reason.Should().Be("Code-body hotstrings that run logic aren't supported (found: FormatTime).");
    }

    [Fact]
    public void Parse_LiClipboardBody_IsRejectedNamingFirstConstruct()
    {
        string script = string.Join('\n',
            "::li::",
            "clipsaved := ClipboardAll",
            "clipboard := \"[li]\"",
            "Send ^v",
            "clipboard := clipsaved",
            "return");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Status.Should().Be(HotstringImportRowStatus.Invalid);
        row.Reason.Should().Be("Code-body hotstrings that run logic aren't supported (found: clipsaved).");
    }

    [Fact]
    public void Parse_SendWithInlineComment_RejectsWholeBody()
    {
        string script = string.Join('\n',
            "::x::",
            "Send, hello ; note",
            "return");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Status.Should().Be(HotstringImportRowStatus.Invalid);
        row.Reason.Should().Be("Inline comment in Send — not imported.");
    }

    [Fact]
    public void Parse_SendWithEscapedSemicolon_KeepsLiteralSemicolon()
    {
        string script = string.Join('\n',
            "::x::",
            "Send, a`;b",
            "return");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Replacement.Should().Be("a;b");
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_SendCommaArg_TrimsLeadingWhitespaceKeepsTrailing()
    {
        string script = string.Join('\n',
            "::x::",
            "Send,   hello world ",
            "return");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Replacement.Should().Be("hello world ");
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_SendWithPercentVariable_IsRejected()
    {
        string script = string.Join('\n',
            "::x::",
            "SendInput %CurrentDateTime%",
            "return");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Status.Should().Be(HotstringImportRowStatus.Invalid);
        row.Reason.Should().Be("Code-body hotstrings that run logic aren't supported (found: %variable%).");
    }

    [Fact]
    public void Parse_SendWithModifierKeystroke_IsRejected()
    {
        string script = string.Join('\n',
            "::x::",
            "Send ^v",
            "return");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Status.Should().Be(HotstringImportRowStatus.Invalid);
        row.Reason.Should().Be("Code-body hotstrings that run logic aren't supported (found: modifier ^).");
    }

    [Fact]
    public void Parse_SendWithUnsupportedBraceToken_IsRejected()
    {
        string script = string.Join('\n',
            "::x::",
            "Send {F5}",
            "return");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Status.Should().Be(HotstringImportRowStatus.Invalid);
        row.Reason.Should().Be("Code-body hotstrings that run logic aren't supported (found: {F5}).");
    }

    [Fact]
    public void Parse_SendEnterAndTabTokens_ConvertToNewlineAndTab()
    {
        string script = string.Join('\n',
            "::x::",
            "Send a{Enter}b{Tab}c",
            "return");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Replacement.Should().Be("a\nb\tc");
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_SendRawBody_KeepsBracesAndModifiersLiteral()
    {
        string script = string.Join('\n',
            "::x::",
            "SendRaw {Home}^+!",
            "return");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Replacement.Should().Be("{Home}^+!");
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_SendTextWithPercentVariable_IsRejected()
    {
        string script = string.Join('\n',
            "::x::",
            "SendText %x%",
            "return");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Status.Should().Be(HotstringImportRowStatus.Invalid);
        row.Reason.Should().Be("Code-body hotstrings that run logic aren't supported (found: %variable%).");
    }

    [Fact]
    public void Parse_MultipleSends_ConcatenateWithNoSeparator()
    {
        string script = string.Join('\n',
            "::x::",
            "Send abc",
            "Send def",
            "return");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Replacement.Should().Be("abcdef");
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
    }
```

- [ ] Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~AhkHotstringParserTests"` — expect FAIL (the Task 4 stub rejects everything with the generic reason).
- [ ] Implement — in `AhkHotstringParser.cs`: add the `SendCommand` regex below the existing `HotstringLine` regex, then REPLACE the Task 4 `TryConvertSendBody` stub with the full implementation and add `TryConvertSendArg` and `FirstToken` below it:

```csharp
    // Longest alternatives first so "Send" cannot shadow "SendInput" etc.
    // Strips one optional leading ',' and the leading whitespace of the first
    // parameter (v1 semantics); internal and trailing spaces stay in group 2.
    [GeneratedRegex(@"^\s*(SendInput|SendText|SendRaw|SendEvent|SendPlay|Send)\b\s*,?\s*(.*)$", RegexOptions.IgnoreCase)]
    private static partial Regex SendCommand();
```

```csharp
    // A body converts only if EVERY line is a Send-family command sending literal
    // text. Converted sends concatenate in order with NO separator — only
    // {Enter}/{Return} introduce newlines. Anything else rejects the whole body
    // with a reason naming the first offending construct.
    private static bool TryConvertSendBody(
        IReadOnlyList<string> bodyLines, out string replacement, out string reason)
    {
        replacement = "";
        reason = "Code-body hotstrings that run logic aren't supported.";

        StringBuilder text = new();
        foreach (string line in bodyLines)
        {
            Match match = SendCommand().Match(line);
            if (!match.Success)
            {
                string token = FirstToken(line);
                if (token.Length > 0)
                    reason = $"Code-body hotstrings that run logic aren't supported (found: {token}).";
                return false;
            }

            string command = match.Groups[1].Value;
            bool literalMode = command.Equals("SendText", StringComparison.OrdinalIgnoreCase)
                || command.Equals("SendRaw", StringComparison.OrdinalIgnoreCase);

            if (!TryConvertSendArg(match.Groups[2].Value, literalMode, out string converted, out reason))
                return false;

            text.Append(converted);
        }

        replacement = text.ToString();
        return true;
    }

    private static bool TryConvertSendArg(
        string arg, bool literalMode, out string converted, out string reason)
    {
        converted = "";
        reason = "";

        if (arg.Trim() == "(")
        {
            reason = "Code-body hotstrings that run logic aren't supported (found: continuation section in Send).";
            return false;
        }

        StringBuilder sb = new(arg.Length);
        for (int i = 0; i < arg.Length; i++)
        {
            char c = arg[i];

            if (c == '`')
            {
                if (i + 1 >= arg.Length)
                    break; // trailing lone backtick — dropped (mirrors DecodeEscapes)

                char next = arg[++i];
                sb.Append(next switch
                {
                    '`' => '`',
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    's' => ' ',
                    ';' => ';',
                    _ => next,
                });
                continue;
            }

            if (c == ';' && (i == 0 || arg[i - 1] is ' ' or '\t'))
            {
                // v1 comment start: unescaped ';' with whitespace to its left (or at
                // the arg start, where the stripped separator preceded it) — ambiguous.
                reason = "Inline comment in Send — not imported.";
                return false;
            }

            if (c == '%')
            {
                reason = "Code-body hotstrings that run logic aren't supported (found: %variable%).";
                return false;
            }

            if (!literalMode && c is '^' or '!' or '+' or '#')
            {
                reason = $"Code-body hotstrings that run logic aren't supported (found: modifier {c}).";
                return false;
            }

            if (!literalMode && c == '{')
            {
                int close = arg.IndexOf('}', i + 1);
                if (close < 0)
                {
                    reason = "Code-body hotstrings that run logic aren't supported (found: unclosed { token).";
                    return false;
                }

                string token = arg[(i + 1)..close];
                if (token.Equals("Enter", StringComparison.OrdinalIgnoreCase)
                    || token.Equals("Return", StringComparison.OrdinalIgnoreCase))
                {
                    sb.Append('\n');
                }
                else if (token.Equals("Tab", StringComparison.OrdinalIgnoreCase))
                {
                    sb.Append('\t');
                }
                else
                {
                    reason = $"Code-body hotstrings that run logic aren't supported (found: {{{token}}}).";
                    return false;
                }

                i = close;
                continue;
            }

            if (!literalMode && c == '}')
            {
                reason = "Code-body hotstrings that run logic aren't supported (found: stray }).";
                return false;
            }

            sb.Append(c);
        }

        converted = sb.ToString();
        return true;
    }

    private static string FirstToken(string line)
    {
        string trimmed = line.Trim();
        int end = trimmed.IndexOfAny([' ', '\t', ',']);
        return end < 0 ? trimmed : trimmed[..end];
    }
```

- [ ] Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~AhkHotstringParserTests"` — expect PASS. Task 4's terminated-body tests stay green: their reasons became granular (`found: FormatTime` / `found: x`) but still contain "aren't supported".
- [ ] Run the whole Application test project as a guard: `dotnet test tests/AHKFlowApp.Application.Tests` — expect PASS.
- [ ] Commit:

```bash
git add src/Backend/AHKFlowApp.Application/Services/AhkHotstringParser.cs tests/AHKFlowApp.Application.Tests/Hotstrings/AhkHotstringParserTests.cs
git commit -m "feat: convert literal Send bodies to replacements on import" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Generator↔parser round-trip integration test

**Files:**
- Create: `tests/AHKFlowApp.Application.Tests/Hotstrings/AhkHotstringRoundTripTests.cs`

**Interfaces:**
- Consumes: `AhkScriptGenerator.Generate(Profile, IEnumerable<Hotstring>, IEnumerable<Hotkey>)`, `AhkHotstringParser.Parse(string)`, `ProfileBuilder`, `HotstringBuilder` (TestUtilities).
- Produces: test class only — no production code.

**Steps:**

- [ ] Write the test — create `tests/AHKFlowApp.Application.Tests/Hotstrings/AhkHotstringRoundTripTests.cs` with this exact content:

```csharp
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.TestUtilities.Builders;
using FluentAssertions;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

[Trait("Category", "Unit")]
public sealed class AhkHotstringRoundTripTests
{
    private static AhkScriptGenerator Generator()
    {
        IAppVersionProvider version = Substitute.For<IAppVersionProvider>();
        version.GetVersion().Returns("0.0.0");
        return new AhkScriptGenerator(new HeaderTokenRenderer(), TimeProvider.System, version);
    }

    [Fact]
    public void GenerateParseGenerate_BacktickNewlineTabReplacement_IsUnchanged()
    {
        string replacement = "a `b ; c\n\td\r\ne";
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring original = new HotstringBuilder()
            .WithTrigger("sig")
            .WithReplacement(replacement)
            .WithEndingCharacterRequired(true)
            .WithTriggerInsideWord(false)
            .Build();

        string firstScript = Generator().Generate(profile, [original], []);
        HotstringImportRowDto row = AhkHotstringParser.Parse(firstScript).Single();
        Hotstring reimported = new HotstringBuilder()
            .WithTrigger(row.Trigger)
            .WithReplacement(row.Replacement)
            .WithEndingCharacterRequired(row.IsEndingCharacterRequired)
            .WithTriggerInsideWord(row.IsTriggerInsideWord)
            .Build();
        string secondScript = Generator().Generate(profile, [reimported], []);

        firstScript.Should().Contain("::sig::a ``b `; c`n`td`r`ne");
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
        row.Replacement.Should().Be(replacement);
        secondScript.Should().Be(firstScript);
    }
}
```

- [ ] Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~AhkHotstringRoundTripTests"` — expect PASS immediately (Tasks 1–2 already implemented both sides; this test locks the ordering contract so neither side regresses independently). If it FAILS, stop and fix the escape/decode ordering — do not adjust the test.
- [ ] Commit:

```bash
git add tests/AHKFlowApp.Application.Tests/Hotstrings/AhkHotstringRoundTripTests.cs
git commit -m "test: lock generator-parser hotstring round-trip" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: UI polish — `white-space: pre-wrap` on the preview replacement cell

**Files:**
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringImportDialog.razor`
- Test: `tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotstrings/HotstringImportDialogTests.cs`

**Interfaces:**
- Consumes: existing `MudTd` in the preview table `RowTemplate`; `MudTd.Style` parameter (inherited from `MudComponentBase`).
- Produces: markup change only — no code API.

The existing test file already renders the preview table (see `PreviewThenConfirm_CallsImportAndClosesDialog`), so per the spec's resolved item a bUnit assertion is added.

**Steps:**

- [ ] Write the failing test — append to `HotstringImportDialogTests`:

```csharp
    [Fact]
    public async Task Preview_ReplacementCell_UsesPreWrapWhitespace()
    {
        _api.PreviewImportAsync(Arg.Any<string>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringImportPreviewDto>.Ok(new HotstringImportPreviewDto(
                [new HotstringImportRowDto(1, "sig", "line one\nline two", true, false, [], HotstringImportRowStatus.Ready, null)],
                ReadyCount: 1, WarningCount: 0, DuplicateCount: 0, InvalidCount: 0)));

        IRenderedComponent<MudDialogProvider> provider = await OpenDialogAsync();

        provider.Find("textarea[data-test=\"import-script\"]").Input("::sig::line one`nline two");
        await provider.InvokeAsync(() => provider.Find("button.preview-import").Click());

        provider.WaitForAssertion(() =>
            provider.FindAll("td[style*='white-space: pre-wrap']").Should().NotBeEmpty());
    }
```

- [ ] Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HotstringImportDialogTests.Preview_ReplacementCell_UsesPreWrapWhitespace"` — expect FAIL (no styled cell yet).
- [ ] Implement — in `HotstringImportDialog.razor`, change the replacement cell in the `RowTemplate` from:

```razor
                        <MudTd>@context.Replacement</MudTd>
```

  to:

```razor
                        <MudTd Style="white-space: pre-wrap">@context.Replacement</MudTd>
```

- [ ] Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HotstringImportDialogTests"` — expect PASS (new test green, existing four tests unaffected).
- [ ] Commit:

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringImportDialog.razor tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotstrings/HotstringImportDialogTests.cs
git commit -m "feat: pre-wrap replacement cell in import preview" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Final verification

**Files:**
- Create: none
- Modify: none (unless `dotnet format` reports drift)
- Test: full solution

**Interfaces:** none — verification only.

**Steps:**

- [ ] `dotnet restore && dotnet build --configuration Release --no-restore` — expect zero errors/warnings introduced by this feature.
- [ ] `dotnet test --configuration Release --no-build --verbosity normal` — expect ALL projects green (Application, Domain, Infrastructure, API, UI.Blazor tests).
- [ ] `dotnet format --verify-no-changes` — if it fails, run `dotnet format`, re-verify, then:

```bash
git add -A
git commit -m "chore: format" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] Optional end-to-end smoke (spec's Testing section; needs the local stack running — API + Blazor): use the `playwright-cli` skill to open the import dialog and paste the script below; confirm mvgp Ready with a two-line replacement rendered on two lines, first dbg Ready, second dbg Duplicate, d-time and li Invalid with reasons naming FormatTime / clipsaved; import, download the profile script, re-import it cleanly (all rows Duplicate).

```
::mvgp::
send Met vriendelijke Groet,{Return}
send Bart Segers
return

::dbg::
send mocha --debug-brk
return

::dbg::
send mocha --debug-brk
return

::d-time::
FormatTime, CurrentDateTime,, dd/MM/yyyy HH:mm
SendInput %CurrentDateTime%
return

::li::
clipsaved := ClipboardAll
Send ^v
clipboard := clipsaved
return
```

---

## Spec Coverage Map

| Spec section | Task(s) |
|---|---|
| Part 1 — generator escaping (+ latent multi-line bug) | 1 |
| Escape grammar & decoding contract | 1, 2, 6 |
| Part 2 — decode escapes | 2 |
| Part 2 — continuation-section conversion (+ unterminated) | 3 |
| Part 3 step 1–2 — code-body detection, hard boundaries, nested blocks, EOF | 4 |
| Part 3 step 3 — `TryConvertSendBody`, v1 arg rules, granular reasons | 5 |
| Motivating examples (mvgp, dbg, d-time, li) | 5 (unit), 8 (E2E; dbg Duplicate is classifier-side, already implemented) |
| Negative/adversarial tests (escape decode, round-trip, Send arg, scan boundary) | 2, 4, 5, 6 |
| Round-trip integration test | 6 |
| Resolved item — preview `white-space: pre-wrap` | 7 |
| Resolved items — `;` literal claim, continuation defaults (doc verification) | 1, 3 |
| Error handling (total, never throws) | 4, 5 (all paths return a row) |
| Unchanged: DTOs, duplicate detection, domain/validation, edit form | — (no task touches them) |

## Unresolved Questions

- `;` escaped unconditionally in generator (spec allowed leaving it literal pending doc check; AHK v2 docs indicate space-preceded `;` comments apply) — OK?
- Playwright E2E left as optional manual step in Task 8, not an automated `AHKFlowApp.E2E.Tests` case — OK?
- Code-body peek skips comment lines as well as blank lines (spec said "next non-blank") — OK?
- Send arg starting with `;` (e.g. `Send, ;x`) rejected as inline comment — conservative — OK?
