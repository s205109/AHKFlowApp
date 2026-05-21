using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AHKFlowApp.Infrastructure.Migrations;

/// <inheritdoc />
public partial class SchemaPolish : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<string>(
            name: "Description",
            table: "Hotstrings",
            type: "nvarchar(200)",
            maxLength: 200,
            nullable: true);

        // Backfill 1: remove junction rows for hotstrings flagged AppliesToAllProfiles = 1.
        // The boolean flag is authoritative; such junction rows are historical inconsistency.
        migrationBuilder.Sql("""
            DELETE FROM HotstringProfiles
            WHERE HotstringId IN (SELECT Id FROM Hotstrings WHERE AppliesToAllProfiles = 1);
            """);

        // Backfill 2: same for hotkeys.
        migrationBuilder.Sql("""
            DELETE FROM HotkeyProfiles
            WHERE HotkeyId IN (SELECT Id FROM Hotkeys WHERE AppliesToAllProfiles = 1);
            """);

        // Backfill 3: any hotstring with AppliesToAllProfiles = 0 and no junction rows is an orphan;
        // flip it to AppliesToAllProfiles = 1 to preserve visibility.
        migrationBuilder.Sql("""
            UPDATE Hotstrings
            SET AppliesToAllProfiles = 1,
                UpdatedAt = TODATETIMEOFFSET(SYSUTCDATETIME(), '+00:00')
            WHERE AppliesToAllProfiles = 0
              AND NOT EXISTS (SELECT 1 FROM HotstringProfiles hp WHERE hp.HotstringId = Hotstrings.Id);
            """);

        // Backfill 4: same for hotkeys.
        migrationBuilder.Sql("""
            UPDATE Hotkeys
            SET AppliesToAllProfiles = 1,
                UpdatedAt = TODATETIMEOFFSET(SYSUTCDATETIME(), '+00:00')
            WHERE AppliesToAllProfiles = 0
              AND NOT EXISTS (SELECT 1 FROM HotkeyProfiles hp WHERE hp.HotkeyId = Hotkeys.Id);
            """);
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropColumn(
            name: "Description",
            table: "Hotstrings");
    }
}
