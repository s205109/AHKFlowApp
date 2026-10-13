using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AHKFlowApp.Infrastructure.Migrations;

/// <inheritdoc />
public partial class BackfillEmptyProfileHeaders : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        // Every profile an owner created in the web UI before backlog 165 stored an empty header,
        // so its generated script carried none of the directives the seeded Default profile emits.
        // This fills those rows in once.
        //
        // The header text below is a frozen copy of DefaultProfileTemplates.Header as it stood
        // when this migration shipped. A migration must keep doing the same thing forever, so it
        // must not read a constant somebody may change later.
        //
        // Two details are deliberate:
        //   DATALENGTH, not = N''. SQL Server pads strings before it compares them, so N'  ' = N''
        //   is true. An equality test would overwrite a header holding only spaces, which is text
        //   the owner wrote.
        //   NCHAR(8212), not a literal em dash. It keeps this file pure ASCII, so no editor and no
        //   encoding setting can change the bytes that reach the database.
        migrationBuilder.Sql("""
            DECLARE @crlf nchar(2) = NCHAR(13) + NCHAR(10);
            DECLARE @header nvarchar(max) =
                    N'; {ProfileName} ' + NCHAR(8212) + N' AHKFlowApp v{AppVersion}' + @crlf
                  + N'; {HotstringCount} hotstrings, {HotkeyCount} hotkeys' + @crlf
                  + N'; Generated {GeneratedAt:yyyy-MM-dd HH:mm}Z' + @crlf
                  + @crlf
                  + N'#Requires AutoHotkey v2.0' + @crlf
                  + N'#SingleInstance Force' + @crlf
                  + N'#Warn All, Off' + @crlf
                  + N'SendMode "Input"' + @crlf
                  + N'SetWorkingDir A_ScriptDir' + @crlf
                  + N'SetTitleMatchMode 2' + @crlf;

            UPDATE [Profiles]
            SET [HeaderTemplate] = @header
            WHERE DATALENGTH([HeaderTemplate]) = 0;
            """);
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        // Nothing to undo. This migration changes no schema, and emptying those headers again
        // would delete text the owner may have edited since. Rolling back past this point is
        // therefore allowed and simply leaves the repaired headers in place.
    }
}
