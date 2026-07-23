using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AHKFlowApp.Infrastructure.Migrations;

/// <inheritdoc />
public partial class DropLegacyHotkeyAction : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        // Wave 1 contract phase. The typed action columns added by HotkeyTypedActions (Migration A)
        // were back-filled from this pair and every read path now uses them, so the legacy pair goes.
        migrationBuilder.DropColumn(
            name: "Action",
            table: "Hotkeys");

        migrationBuilder.DropColumn(
            name: "Parameters",
            table: "Hotkeys");
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        // Structural revert only — the dropped values are unrecoverable. The columns come back
        // nullable so restored rows read as NULL ("lost") rather than as a plausible-looking
        // Send/"" pair that older code would treat as real data. A true rollback restores from a
        // database backup taken before Up ran.
        migrationBuilder.AddColumn<int>(
            name: "Action",
            table: "Hotkeys",
            type: "int",
            nullable: true);

        migrationBuilder.AddColumn<string>(
            name: "Parameters",
            table: "Hotkeys",
            type: "nvarchar(4000)",
            maxLength: 4000,
            nullable: true);
    }
}
