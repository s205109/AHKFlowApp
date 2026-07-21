using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.Commands.Dev;

/// <summary>
/// The curated dev seed set. Shared by <c>SeedHotstringsCommandHandler</c> (the explicit
/// <c>POST /dev/hotstrings/seed</c> path) and the lazy auto-seed in <c>ListHotstringsQuery</c>,
/// which previously held byte-identical copies that had to be updated in lockstep.
/// </summary>
internal static class HotstringSeedSamples
{
    /// <param name="Trigger"></param>
    /// <param name="Replacement">
    /// Kind-dependent, matching <see cref="Domain.Entities.HotstringDefinition"/>: literal text for
    /// Text, the token string for Macro, and the entire verbatim <c>:options:trigger::</c> definition
    /// for Raw.
    /// </param>
    /// <param name="Description"></param>
    /// <param name="Ending"></param>
    /// <param name="InsideWord"></param>
    /// <param name="Categories"></param>
    /// <param name="Kind"></param>
    /// <param name="DateTimeFormat"></param>
    internal sealed record Sample(
        string Trigger,
        string Replacement,
        string Description,
        bool Ending,
        bool InsideWord,
        string[] Categories,
        HotstringKind Kind,
        string? DateTimeFormat = null);

    // Raw samples are deliberately single-line: this path constructs HotstringDefinition directly
    // rather than going through RawHotstringDefinitionParser.Prepare, so nothing here normalizes
    // CRLF to LF or checks brace balance. Both use the X (execute) flag, which is the thing no
    // structured kind can express — the honest reason to reach for Raw.
    internal static readonly Sample[] All =
    [
        new("recieve", "receive", "Fixes a common typo.", true, true, ["Autocorrect"], HotstringKind.Text),
        new("btw", "by the way", "Expands a chat abbreviation.", true, false, ["Communication"], HotstringKind.Text),
        new("brb", "be right back", "Expands a chat abbreviation.", true, false, ["Communication"], HotstringKind.Text),
        new("fyi", "for your information", "Expands a chat abbreviation.", true, false, ["Communication"], HotstringKind.Text),
        new("/today", "", "Inserts today's date.", false, false, ["DateTime"], HotstringKind.DateTime, "yyyy-MM-dd"),
        new("/now", "", "Inserts the current time.", false, false, ["DateTime"], HotstringKind.DateTime, "HH:mm"),
        new("@sig", "Example User\nuser@example.com\nExample Company", "Inserts a plain-text email signature.", false, false, ["Email"], HotstringKind.Text),
        new(";arrow", "→", "Inserts a right arrow.", false, false, ["Symbols"], HotstringKind.Text),
        new(";check", "✓", "Inserts a check mark.", false, false, ["Symbols"], HotstringKind.Text),
        new(";shrug", "¯\\_(ツ)_/¯", "Inserts the shrug emoticon.", false, false, ["Symbols"], HotstringKind.Text),
        new(";e:", "ë", "Inserts e with diaeresis.", false, false, ["Symbols"], HotstringKind.Text),
        new(";todo", "TODO(name): ", "Inserts a TODO marker.", false, false, ["Code"], HotstringKind.Text),
        new("htag", "<b>{{cursor}}</b>", "Wraps the cursor in bold tags.", false, false, ["Code"], HotstringKind.Macro),
        new("alink", "<a href=\"{{cursor}}\"></a>", "Inserts an anchor tag with the cursor in the href.", false, false, ["Code"], HotstringKind.Macro),
        new("/user", ":X:/user::SendText(A_UserName)", "Inserts the current Windows username.", false, false, ["Code"], HotstringKind.Raw),
        new("/ghub", ":X:/ghub::Run(\"https://github.com\")", "Opens GitHub in the default browser.", false, false, ["Code"], HotstringKind.Raw),
    ];
}
