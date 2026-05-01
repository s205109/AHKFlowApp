using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AHKFlowApp.Infrastructure.Migrations;

/// <inheritdoc />
public partial class AddHotkeys : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.CreateTable(
            name: "Hotkeys",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                OwnerOid = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                ProfileId = table.Column<Guid>(type: "uniqueidentifier", nullable: true),
                Trigger = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false),
                Action = table.Column<string>(type: "nvarchar(4000)", maxLength: 4000, nullable: false),
                Description = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: true),
                CreatedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false),
                UpdatedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_Hotkeys", x => x.Id);
            });

        migrationBuilder.CreateIndex(
            name: "IX_Hotkey_Owner_Profile_Trigger",
            table: "Hotkeys",
            columns: new[] { "OwnerOid", "ProfileId", "Trigger" },
            unique: true,
            filter: "[ProfileId] IS NOT NULL");

        migrationBuilder.CreateIndex(
            name: "IX_Hotkey_Owner_Trigger_NoProfile",
            table: "Hotkeys",
            columns: new[] { "OwnerOid", "Trigger" },
            unique: true,
            filter: "[ProfileId] IS NULL");

        migrationBuilder.CreateIndex(
            name: "IX_Hotkeys_OwnerOid",
            table: "Hotkeys",
            column: "OwnerOid");
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(
            name: "Hotkeys");
    }
}
