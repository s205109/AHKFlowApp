using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AHKFlowApp.Infrastructure.Migrations;

/// <inheritdoc />
public partial class HotkeyTypedActions : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<int>(
            name: "ActionKind",
            table: "Hotkeys",
            type: "int",
            nullable: false,
            defaultValue: 0);

        migrationBuilder.AddColumn<string>(
            name: "Body",
            table: "Hotkeys",
            type: "nvarchar(max)",
            nullable: true);

        migrationBuilder.AddColumn<string>(
            name: "RemapDest",
            table: "Hotkeys",
            type: "nvarchar(50)",
            maxLength: 50,
            nullable: true);

        migrationBuilder.AddColumn<string>(
            name: "RunTarget",
            table: "Hotkeys",
            type: "nvarchar(4000)",
            maxLength: 4000,
            nullable: true);

        migrationBuilder.AddColumn<int>(
            name: "RunTargetKind",
            table: "Hotkeys",
            type: "int",
            nullable: true);

        migrationBuilder.AddColumn<string>(
            name: "SendKeysContent",
            table: "Hotkeys",
            type: "nvarchar(100)",
            maxLength: 100,
            nullable: true);

        migrationBuilder.AddColumn<string>(
            name: "Text",
            table: "Hotkeys",
            type: "nvarchar(max)",
            nullable: true);

        migrationBuilder.AddColumn<int>(
            name: "WindowOp",
            table: "Hotkeys",
            type: "int",
            nullable: true);

        // The SendKeys grammar is awkward inline, so it lives in a scalar function created here and
        // dropped at the end of Up. Frozen at this migration: later waves that add SendToken names do
        // NOT edit this file — the Infrastructure parity test fails loudly instead, which is the
        // signal to decide between a top-up migration and accepting Raw for the new names.
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
        -- ({a} is braced-legal), because the migration never canonicalizes. Generated from
        -- HotkeyKeys, not hand-typed, and frozen once this migration shipped. A subset here would
        -- classify {F5} / {Enter} / {Esc} as Raw in the database while the C# converter — which
        -- consults the whole registry through TryCanonicalize — calls them SendKeys, so a snapshot
        -- restore would disagree with the migrated row for the same value.
        IF @inner COLLATE Latin1_General_CI_AS IN ('0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'Alt', 'AppsKey', 'BS', 'Backspace', 'Break', 'Browser_Back', 'Browser_Favorites', 'Browser_Forward', 'Browser_Home', 'Browser_Refresh', 'Browser_Search', 'Browser_Stop', 'CapsLock', 'Control', 'Ctrl', 'Del', 'Delete', 'Down', 'End', 'Enter', 'Esc', 'Escape', 'F1', 'F10', 'F11', 'F12', 'F13', 'F14', 'F15', 'F16', 'F17', 'F18', 'F19', 'F2', 'F20', 'F21', 'F22', 'F23', 'F24', 'F3', 'F4', 'F5', 'F6', 'F7', 'F8', 'F9', 'Home', 'Ins', 'Insert', 'LAlt', 'LCtrl', 'LShift', 'LWin', 'Launch_Mail', 'Launch_Media', 'Left', 'Media_Next', 'Media_Play_Pause', 'Media_Prev', 'Media_Stop', 'NumLock', 'Numpad0', 'Numpad1', 'Numpad2', 'Numpad3', 'Numpad4', 'Numpad5', 'Numpad6', 'Numpad7', 'Numpad8', 'Numpad9', 'NumpadAdd', 'NumpadDiv', 'NumpadDot', 'NumpadEnter', 'NumpadMult', 'NumpadSub', 'PageDown', 'PageUp', 'Pause', 'PgDn', 'PgDown', 'PgUp', 'PrintScreen', 'RAlt', 'RCtrl', 'RShift', 'RWin', 'Return', 'Right', 'ScrollLock', 'Shift', 'Space', 'Tab', 'Up', 'Volume_Down', 'Volume_Mute', 'Volume_Up', 'Win', 'Windows', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z') RETURN 1;
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

        migrationBuilder.Sql(@"DROP FUNCTION [dbo].[fn_IsSendKeysContent];");
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        // Down-migration is unsupported: the legacy→typed back-fill is lossy in reverse (a migrated
        // Raw body cannot be decomposed back into the exact Parameters it came from), and the typed
        // columns stay in place until the contract migration drops the legacy pair. Restore from a
        // database backup instead of rolling this migration back.
        throw new System.NotSupportedException(
            "The HotkeyTypedActions migration cannot be reverted. Restore from a database backup instead.");
    }
}
