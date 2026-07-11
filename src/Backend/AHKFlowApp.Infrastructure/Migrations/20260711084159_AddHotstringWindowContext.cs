using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AHKFlowApp.Infrastructure.Migrations;

/// <inheritdoc />
public partial class AddHotstringWindowContext : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropIndex(
            name: "IX_Hotstring_Owner_Trigger",
            table: "Hotstrings");

        migrationBuilder.AddColumn<int>(
            name: "ContextMatchType",
            table: "Hotstrings",
            type: "int",
            nullable: true);

        migrationBuilder.AddColumn<string>(
            name: "ContextValue",
            table: "Hotstrings",
            type: "nvarchar(200)",
            maxLength: 200,
            nullable: true);

        migrationBuilder.CreateIndex(
            name: "IX_Hotstring_Owner_Trigger_Context",
            table: "Hotstrings",
            columns: new[] { "OwnerOid", "Trigger", "ContextMatchType", "ContextValue" },
            unique: true);
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropIndex(
            name: "IX_Hotstring_Owner_Trigger_Context",
            table: "Hotstrings");

        migrationBuilder.DropColumn(
            name: "ContextMatchType",
            table: "Hotstrings");

        migrationBuilder.DropColumn(
            name: "ContextValue",
            table: "Hotstrings");

        migrationBuilder.CreateIndex(
            name: "IX_Hotstring_Owner_Trigger",
            table: "Hotstrings",
            columns: new[] { "OwnerOid", "Trigger" },
            unique: true);
    }
}
