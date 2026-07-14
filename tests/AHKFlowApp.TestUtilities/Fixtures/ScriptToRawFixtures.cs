namespace AHKFlowApp.TestUtilities.Fixtures;

/// <summary>
/// One Script→Raw conversion case: the legacy Script row's fields plus the exact verbatim Raw
/// definition it must convert to (byte-identical to the retired emitter's Script output).
/// </summary>
public sealed record ScriptToRawFixture(
    string Name,
    string Trigger,
    string Body,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord,
    bool IsCaseSensitive,
    bool OmitEndingCharacter,
    string ExpectedRawDefinition);

/// <summary>
/// Shared golden set guarding the three copies of the Script→Raw transform: the C# composer
/// (<c>ScriptToRawComposer</c>), the history restore/revert conversion, and the EF data migration's
/// hand-written T-SQL. Covers the option-flag matrix, triggers with backtick/semicolon, CRLF bodies,
/// blank-edged bodies, and a 4,000-character body (the old column max — proves no truncation).
/// </summary>
public static class ScriptToRawFixtures
{
    public static IReadOnlyList<ScriptToRawFixture> All { get; } = Build();

    private static IReadOnlyList<ScriptToRawFixture> Build()
    {
        string big = new('x', 4000);
        return
        [
            new("no-flags-simple", "rng", "Send foo", true, false, false, false,
                "::rng::\n{\nSend foo\n}"),
            new("star-insideword-case", "x", "b", false, true, true, false,
                ":*?C:x::\n{\nb\n}"),
            new("omit-flag", "y", "c", true, false, false, true,
                ":O:y::\n{\nc\n}"),
            new("omit-ignored-with-star", "z", "d", false, false, false, true,
                ":*:z::\n{\nd\n}"), // O is meaningless with *, so it is not emitted
            new("semicolon-trigger", "a;b", "x", true, false, false, false,
                "::a`;b::\n{\nx\n}"),
            new("backtick-trigger", "c`d", "x", true, false, false, false,
                "::c``d::\n{\nx\n}"),
            new("crlf-body", "t", "l1\r\nl2", true, false, false, false,
                "::t::\n{\nl1\r\nl2\n}"),
            new("blank-edged-body", "t", "\n\nMsgBox 1\n\n", true, false, false, false,
                "::t::\n{\n\n\nMsgBox 1\n\n\n}"),
            new("max-4000-body", "t", big, true, false, false, false,
                "::t::\n{\n" + big + "\n}"),
        ];
    }
}
