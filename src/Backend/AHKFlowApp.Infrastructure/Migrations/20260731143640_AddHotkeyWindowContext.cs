using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AHKFlowApp.Infrastructure.Migrations;

/// <summary>
/// Gives a hotkey the same window context a hotstring already has, so one key + modifier
/// combination can mean different things in different windows.
/// </summary>
/// <remarks>
/// <para>
/// Moving forward is safe. The new index covers the same columns as
/// <c>IX_Hotkey_Owner_Modifiers</c> plus two more, so no pair of rows that was unique before can
/// collide now. Existing rows get a NULL context, which means the hotkey fires everywhere.
/// </para>
/// <para>
/// Moving back can fail. Once two rows share a key + modifier combination in different window
/// contexts, <c>Down</c> cannot recreate <c>IX_Hotkey_Owner_Modifiers</c> as unique, because those
/// rows are exactly what the old index forbids. To roll back, first delete or merge the extra rows
/// so each key + modifier combination has one row per owner, then run the rollback again.
/// </para>
/// </remarks>
public partial class AddHotkeyWindowContext : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropIndex(
            name: "IX_Hotkey_Owner_Modifiers",
            table: "Hotkeys");

        migrationBuilder.AddColumn<int>(
            name: "ContextMatchType",
            table: "Hotkeys",
            type: "int",
            nullable: true);

        migrationBuilder.AddColumn<string>(
            name: "ContextValue",
            table: "Hotkeys",
            type: "nvarchar(200)",
            maxLength: 200,
            nullable: true);

        migrationBuilder.CreateIndex(
            name: "IX_Hotkey_Owner_Modifiers_Context",
            table: "Hotkeys",
            columns: new[] { "OwnerOid", "Key", "Ctrl", "Alt", "Shift", "Win", "ContextMatchType", "ContextValue" },
            unique: true);
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropIndex(
            name: "IX_Hotkey_Owner_Modifiers_Context",
            table: "Hotkeys");

        migrationBuilder.DropColumn(
            name: "ContextMatchType",
            table: "Hotkeys");

        migrationBuilder.DropColumn(
            name: "ContextValue",
            table: "Hotkeys");

        migrationBuilder.CreateIndex(
            name: "IX_Hotkey_Owner_Modifiers",
            table: "Hotkeys",
            columns: new[] { "OwnerOid", "Key", "Ctrl", "Alt", "Shift", "Win" },
            unique: true);
    }
}
