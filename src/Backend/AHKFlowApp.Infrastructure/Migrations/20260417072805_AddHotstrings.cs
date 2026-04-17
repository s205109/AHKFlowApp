using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AHKFlowApp.Infrastructure.Migrations;

/// <inheritdoc />
public partial class AddHotstrings : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.CreateTable(
            name: "Hotstrings",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                OwnerOid = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                ProfileId = table.Column<Guid>(type: "uniqueidentifier", nullable: true),
                Trigger = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: false),
                Replacement = table.Column<string>(type: "nvarchar(4000)", maxLength: 4000, nullable: false),
                IsEndingCharacterRequired = table.Column<bool>(type: "bit", nullable: false),
                IsTriggerInsideWord = table.Column<bool>(type: "bit", nullable: false),
                CreatedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false),
                UpdatedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_Hotstrings", x => x.Id);
            });

        migrationBuilder.CreateIndex(
            name: "IX_Hotstring_Owner_Profile_Trigger",
            table: "Hotstrings",
            columns: ["OwnerOid", "ProfileId", "Trigger"],
            unique: true,
            filter: "[ProfileId] IS NOT NULL");

        migrationBuilder.CreateIndex(
            name: "IX_Hotstring_Owner_Trigger_NoProfile",
            table: "Hotstrings",
            columns: ["OwnerOid", "Trigger"],
            unique: true,
            filter: "[ProfileId] IS NULL");

        migrationBuilder.CreateIndex(
            name: "IX_Hotstrings_OwnerOid",
            table: "Hotstrings",
            column: "OwnerOid");
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(
            name: "Hotstrings");
    }
}
