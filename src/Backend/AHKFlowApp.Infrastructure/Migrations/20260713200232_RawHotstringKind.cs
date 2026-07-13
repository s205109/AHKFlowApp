using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AHKFlowApp.Infrastructure.Migrations;

/// <inheritdoc />
public partial class RawHotstringKind : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        // Widen first so embedding a near-limit Script body inside a full definition can't truncate.
        migrationBuilder.AlterColumn<string>(
            name: "Replacement",
            table: "Hotstrings",
            type: "nvarchar(max)",
            nullable: false,
            oldClrType: typeof(string),
            oldType: "nvarchar(4000)",
            oldMaxLength: 4000);

        // Rewrite legacy Script rows (Kind = 3) to Raw (Kind = 4), replacing the body-only
        // Replacement with the entire verbatim definition. This T-SQL is a hand-written copy of
        // ScriptToRawComposer (BuildOptions X/T never apply to a brace-body kind; Escape does
        // backtick first) — the Infrastructure Testcontainers parity test proves the two agree,
        // so migrated scripts are byte-identical to what the old emitter produced.
        migrationBuilder.Sql(@"
UPDATE [Hotstrings]
SET [Replacement] =
        ':'
        + (CASE WHEN [IsEndingCharacterRequired] = 0 THEN '*' ELSE '' END)
        + (CASE WHEN [IsTriggerInsideWord] = 1 THEN '?' ELSE '' END)
        + (CASE WHEN [IsCaseSensitive] = 1 THEN 'C' ELSE '' END)
        + (CASE WHEN [OmitEndingCharacter] = 1 AND [IsEndingCharacterRequired] = 1 THEN 'O' ELSE '' END)
        + ':'
        + REPLACE(REPLACE(REPLACE(REPLACE(REPLACE([Trigger],
              '`', '``'),
              CHAR(10), '`n'),
              CHAR(13), '`r'),
              CHAR(9), '`t'),
              ';', '`;')
        + '::' + CHAR(10) + '{' + CHAR(10) + [Replacement] + CHAR(10) + '}',
    [Kind] = 4
WHERE [Kind] = 3;");
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        // Down-migration is unsupported: the Script→Raw data rewrite is lossy in reverse (the
        // composed brace wrapper and option flags cannot be reliably decomposed) and reverting
        // the column to nvarchar(4000) would truncate Raw rows that legitimately exceed 4,000
        // characters. Restore from backup instead of rolling this migration back.
        throw new System.NotSupportedException(
            "The RawHotstringKind migration cannot be reverted. Restore from a database backup instead.");
    }
}
