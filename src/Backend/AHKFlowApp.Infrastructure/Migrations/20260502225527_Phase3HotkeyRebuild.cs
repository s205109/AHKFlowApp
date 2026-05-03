using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AHKFlowApp.Infrastructure.Migrations;

/// <inheritdoc />
public partial class Phase3HotkeyRebuild : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropIndex(
            name: "IX_Hotkey_Owner_Profile_Trigger",
            table: "Hotkeys");

        migrationBuilder.DropIndex(
            name: "IX_Hotkey_Owner_Trigger_NoProfile",
            table: "Hotkeys");

        migrationBuilder.DropColumn(
            name: "ProfileId",
            table: "Hotkeys");

        migrationBuilder.DropColumn(
            name: "Trigger",
            table: "Hotkeys");

        migrationBuilder.AlterColumn<string>(
            name: "Description",
            table: "Hotkeys",
            type: "nvarchar(200)",
            maxLength: 200,
            nullable: false,
            defaultValue: "",
            oldClrType: typeof(string),
            oldType: "nvarchar(200)",
            oldMaxLength: 200,
            oldNullable: true);

        migrationBuilder.DropColumn(
            name: "Action",
            table: "Hotkeys");

        migrationBuilder.AddColumn<int>(
            name: "Action",
            table: "Hotkeys",
            type: "int",
            nullable: false,
            defaultValue: 0);

        migrationBuilder.AddColumn<bool>(
            name: "Alt",
            table: "Hotkeys",
            type: "bit",
            nullable: false,
            defaultValue: false);

        migrationBuilder.AddColumn<bool>(
            name: "AppliesToAllProfiles",
            table: "Hotkeys",
            type: "bit",
            nullable: false,
            defaultValue: false);

        migrationBuilder.AddColumn<bool>(
            name: "Ctrl",
            table: "Hotkeys",
            type: "bit",
            nullable: false,
            defaultValue: false);

        migrationBuilder.AddColumn<string>(
            name: "Key",
            table: "Hotkeys",
            type: "nvarchar(20)",
            maxLength: 20,
            nullable: false,
            defaultValue: "");

        migrationBuilder.AddColumn<string>(
            name: "Parameters",
            table: "Hotkeys",
            type: "nvarchar(4000)",
            maxLength: 4000,
            nullable: false,
            defaultValue: "");

        migrationBuilder.AddColumn<bool>(
            name: "Shift",
            table: "Hotkeys",
            type: "bit",
            nullable: false,
            defaultValue: false);

        migrationBuilder.AddColumn<bool>(
            name: "Win",
            table: "Hotkeys",
            type: "bit",
            nullable: false,
            defaultValue: false);

        migrationBuilder.CreateTable(
            name: "HotkeyProfiles",
            columns: table => new
            {
                HotkeyId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                ProfileId = table.Column<Guid>(type: "uniqueidentifier", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_HotkeyProfiles", x => new { x.HotkeyId, x.ProfileId });
                table.ForeignKey(
                    name: "FK_HotkeyProfiles_Hotkeys_HotkeyId",
                    column: x => x.HotkeyId,
                    principalTable: "Hotkeys",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_HotkeyProfiles_Profiles_ProfileId",
                    column: x => x.ProfileId,
                    principalTable: "Profiles",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex(
            name: "IX_Hotkey_Owner_Modifiers",
            table: "Hotkeys",
            columns: new[] { "OwnerOid", "Key", "Ctrl", "Alt", "Shift", "Win" },
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_HotkeyProfiles_ProfileId",
            table: "HotkeyProfiles",
            column: "ProfileId");
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(
            name: "HotkeyProfiles");

        migrationBuilder.DropIndex(
            name: "IX_Hotkey_Owner_Modifiers",
            table: "Hotkeys");

        migrationBuilder.DropColumn(
            name: "Alt",
            table: "Hotkeys");

        migrationBuilder.DropColumn(
            name: "AppliesToAllProfiles",
            table: "Hotkeys");

        migrationBuilder.DropColumn(
            name: "Ctrl",
            table: "Hotkeys");

        migrationBuilder.DropColumn(
            name: "Key",
            table: "Hotkeys");

        migrationBuilder.DropColumn(
            name: "Parameters",
            table: "Hotkeys");

        migrationBuilder.DropColumn(
            name: "Shift",
            table: "Hotkeys");

        migrationBuilder.DropColumn(
            name: "Win",
            table: "Hotkeys");

        migrationBuilder.AlterColumn<string>(
            name: "Description",
            table: "Hotkeys",
            type: "nvarchar(200)",
            maxLength: 200,
            nullable: true,
            oldClrType: typeof(string),
            oldType: "nvarchar(200)",
            oldMaxLength: 200);

        migrationBuilder.DropColumn(
            name: "Action",
            table: "Hotkeys");

        migrationBuilder.AddColumn<string>(
            name: "Action",
            table: "Hotkeys",
            type: "nvarchar(4000)",
            maxLength: 4000,
            nullable: false,
            defaultValue: "");

        migrationBuilder.AddColumn<Guid>(
            name: "ProfileId",
            table: "Hotkeys",
            type: "uniqueidentifier",
            nullable: true);

        migrationBuilder.AddColumn<string>(
            name: "Trigger",
            table: "Hotkeys",
            type: "nvarchar(100)",
            maxLength: 100,
            nullable: false,
            defaultValue: "");

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
    }
}
