using AHKFlowApp.Application.Constants;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Application.Validation;
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

    /// <summary>A lone C1 control character (U+0085), written as an escape so the source file
    /// stays plain ASCII — U+0085 is a Unicode line break that editors rewrite in place.</summary>
    private const string LoneC1 = "\u0085";

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
        // char.IsControl also rejects the C1 block U+0080-U+009F, which a naked `UNICODE(@key) >= 32`
        // test in T-SQL accepts. ValidParameters blocks these at the API boundary today, so this
        // guards rows that predate that rule rather than anything currently writable.
        new("send-lone-c1-control", HotkeyAction.Send, LoneC1,
            HotkeyActionKind.Raw, null, null, null, null, $"Send(\"{LoneC1}\")"),
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
        // A modifier may appear at most once. C# tracks them in a HashSet, the SQL classifier in a
        // CHARINDEX over an accumulator string — two different mechanisms that must agree, including
        // when the repeat is not adjacent.
        new("send-duplicate-modifier", HotkeyAction.Send, "^^a",
            HotkeyActionKind.Raw, null, null, null, null, "Send(\"^^a\")"),
        new("send-duplicate-modifier-separated", HotkeyAction.Send, "^!^a",
            HotkeyActionKind.Raw, null, null, null, null, "Send(\"^!^a\")"),
        // Modifiers with no key at all: C# returns false on the empty remainder, SQL on @klen = 0.
        new("send-modifiers-only", HotkeyAction.Send, "^!",
            HotkeyActionKind.Raw, null, null, null, null, "Send(\"^!\")"),
        MaximumLengthSendCase(),
        .. EverySendKeysToken(),
    ];

    // The widest legal Parameters value, escaped past the nvarchar(4000) ceiling. Built here rather
    // than pasted so the input and its expectation cannot drift. The migration's back-fill embeds
    // [Parameters] (nvarchar(4000)) in a concatenation: with no large-value operand the whole
    // expression truncates at 4000 nchars *before* it is assigned to the nvarchar(max) Body column,
    // dropping the closing `") and emitting an unterminated AHK string literal. This case fails
    // unless the migration casts to NVARCHAR(MAX) at the innermost REPLACE.
    private static LegacyHotkeyFixture MaximumLengthSendCase()
    {
        // 50 backtick/quote pairs (100 chars, 200 once escaped) then filler to exactly the limit.
        string parameters = string.Concat(Enumerable.Repeat("`\"", 50))
            + new string('x', HotkeyRules.ParametersMaxLength - 100);

        return new("send-maximum-length", HotkeyAction.Send, parameters,
            HotkeyActionKind.Raw, null, null, null, null,
            $"Send(\"{AhkEscaping.EscapeStringLiteral(parameters)}\")");
    }

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

        // The loops above only ever apply `^`. All four Send modifiers are accepted in any order and
        // any combination, braced or bare, so each one needs its own case: the SQL classifier lists
        // them separately and a typo would drop one silently.
        string[] modified = ["!a", "+a", "#a", "!{Volume_Up}", "+{Tab}", "#{F5}", "^!+#{Escape}", "+!5"];
        foreach (string token in modified)
            yield return SendKeysCase(token);

        // vk/sc codes: accepted by TryCanonicalize, not registry names, so no role check applies.
        // Every accepted width (vk 1-2, sc 1-3) and both cases of prefix and digits, since the
        // grammar is width-tolerant and case-insensitive while the SQL side spells one LIKE pattern
        // per width and leans on a CI collation for the case.
        string[] codes = ["vk1", "vk01", "vkFF", "VK1", "sc1", "sc1b", "sc001", "sc01B", "SC01B"];
        foreach (string code in codes)
            yield return SendKeysCase($"{{{code}}}");
    }

    private static LegacyHotkeyFixture SendKeysCase(string token) =>
        new($"send-token-{token}", HotkeyAction.Send, token,
            HotkeyActionKind.SendKeys, null, token, null, null, null);
}
