using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AHKFlowApp.Infrastructure.Migrations;

/// <inheritdoc />
public partial class AddKnownShortcuts : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.CreateTable(
            name: "CustomKnownShortcuts",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                OwnerOid = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                Key = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: false),
                Ctrl = table.Column<bool>(type: "bit", nullable: false),
                Alt = table.Column<bool>(type: "bit", nullable: false),
                Shift = table.Column<bool>(type: "bit", nullable: false),
                Win = table.Column<bool>(type: "bit", nullable: false),
                UsedBy = table.Column<string>(type: "nvarchar(60)", maxLength: 60, nullable: false),
                Protection = table.Column<int>(type: "int", nullable: false),
                Scope = table.Column<int>(type: "int", nullable: false),
                Does = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false),
                CreatedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false),
                UpdatedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_CustomKnownShortcuts", x => x.Id);
            });

        migrationBuilder.CreateTable(
            name: "IgnoredKnownShortcuts",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                OwnerOid = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                ShortcutId = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false),
                UsedBy = table.Column<string>(type: "nvarchar(60)", maxLength: 60, nullable: false),
                CreatedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_IgnoredKnownShortcuts", x => x.Id);
            });

        migrationBuilder.CreateIndex(
            name: "IX_CustomKnownShortcut_Owner_Combo_UsedBy",
            table: "CustomKnownShortcuts",
            columns: new[] { "OwnerOid", "Key", "Ctrl", "Alt", "Shift", "Win", "UsedBy" },
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_IgnoredKnownShortcut_Owner_Shortcut_UsedBy",
            table: "IgnoredKnownShortcuts",
            columns: new[] { "OwnerOid", "ShortcutId", "UsedBy" },
            unique: true);
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(
            name: "CustomKnownShortcuts");

        migrationBuilder.DropTable(
            name: "IgnoredKnownShortcuts");
    }
}
