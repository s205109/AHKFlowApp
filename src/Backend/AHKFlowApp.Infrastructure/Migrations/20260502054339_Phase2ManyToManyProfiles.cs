using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AHKFlowApp.Infrastructure.Migrations;

/// <inheritdoc />
public partial class Phase2ManyToManyProfiles : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropIndex(
            name: "IX_Hotstring_Owner_Profile_Trigger",
            table: "Hotstrings");

        migrationBuilder.DropIndex(
            name: "IX_Hotstring_Owner_Trigger_NoProfile",
            table: "Hotstrings");

        migrationBuilder.DropColumn(
            name: "ProfileId",
            table: "Hotstrings");

        // Default true preserves prior "ProfileId IS NULL = global" semantics for any existing rows.
        migrationBuilder.AddColumn<bool>(
            name: "AppliesToAllProfiles",
            table: "Hotstrings",
            type: "bit",
            nullable: false,
            defaultValue: true);

        migrationBuilder.CreateTable(
            name: "HotstringProfiles",
            columns: table => new
            {
                HotstringId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                ProfileId = table.Column<Guid>(type: "uniqueidentifier", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_HotstringProfiles", x => new { x.HotstringId, x.ProfileId });
                table.ForeignKey(
                    name: "FK_HotstringProfiles_Hotstrings_HotstringId",
                    column: x => x.HotstringId,
                    principalTable: "Hotstrings",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_HotstringProfiles_Profiles_ProfileId",
                    column: x => x.ProfileId,
                    principalTable: "Profiles",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex(
            name: "IX_Hotstring_Owner_Trigger",
            table: "Hotstrings",
            columns: new[] { "OwnerOid", "Trigger" },
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_HotstringProfiles_ProfileId",
            table: "HotstringProfiles",
            column: "ProfileId");
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(
            name: "HotstringProfiles");

        migrationBuilder.DropIndex(
            name: "IX_Hotstring_Owner_Trigger",
            table: "Hotstrings");

        migrationBuilder.DropColumn(
            name: "AppliesToAllProfiles",
            table: "Hotstrings");

        migrationBuilder.AddColumn<Guid>(
            name: "ProfileId",
            table: "Hotstrings",
            type: "uniqueidentifier",
            nullable: true);

        migrationBuilder.CreateIndex(
            name: "IX_Hotstring_Owner_Profile_Trigger",
            table: "Hotstrings",
            columns: new[] { "OwnerOid", "ProfileId", "Trigger" },
            unique: true,
            filter: "[ProfileId] IS NOT NULL");

        migrationBuilder.CreateIndex(
            name: "IX_Hotstring_Owner_Trigger_NoProfile",
            table: "Hotstrings",
            columns: new[] { "OwnerOid", "Trigger" },
            unique: true,
            filter: "[ProfileId] IS NULL");
    }
}
