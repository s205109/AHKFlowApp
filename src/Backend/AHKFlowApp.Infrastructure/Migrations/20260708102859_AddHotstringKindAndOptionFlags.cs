using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AHKFlowApp.Infrastructure.Migrations;

/// <inheritdoc />
public partial class AddHotstringKindAndOptionFlags : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<bool>(
            name: "IsCaseSensitive",
            table: "Hotstrings",
            type: "bit",
            nullable: false,
            defaultValue: false);

        migrationBuilder.AddColumn<int>(
            name: "Kind",
            table: "Hotstrings",
            type: "int",
            nullable: false,
            defaultValue: 0);

        migrationBuilder.AddColumn<bool>(
            name: "OmitEndingCharacter",
            table: "Hotstrings",
            type: "bit",
            nullable: false,
            defaultValue: false);
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropColumn(
            name: "IsCaseSensitive",
            table: "Hotstrings");

        migrationBuilder.DropColumn(
            name: "Kind",
            table: "Hotstrings");

        migrationBuilder.DropColumn(
            name: "OmitEndingCharacter",
            table: "Hotstrings");
    }
}
