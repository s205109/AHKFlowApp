using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AHKFlowApp.Infrastructure.Migrations;

/// <inheritdoc />
public partial class AddHotstringDateTimeFields : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<int>(
            name: "DateOffsetAmount",
            table: "Hotstrings",
            type: "int",
            nullable: true);

        migrationBuilder.AddColumn<int>(
            name: "DateOffsetUnit",
            table: "Hotstrings",
            type: "int",
            nullable: true);

        migrationBuilder.AddColumn<string>(
            name: "DateTimeFormat",
            table: "Hotstrings",
            type: "nvarchar(50)",
            maxLength: 50,
            nullable: true);
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropColumn(
            name: "DateOffsetAmount",
            table: "Hotstrings");

        migrationBuilder.DropColumn(
            name: "DateOffsetUnit",
            table: "Hotstrings");

        migrationBuilder.DropColumn(
            name: "DateTimeFormat",
            table: "Hotstrings");
    }
}
