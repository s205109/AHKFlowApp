using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AHKFlowApp.Infrastructure.Migrations;

/// <inheritdoc />
public partial class AddLazySeedMarkers : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<DateTimeOffset>(
            name: "HotkeysSeededAt",
            table: "UserPreferences",
            type: "datetimeoffset",
            nullable: true);

        migrationBuilder.AddColumn<DateTimeOffset>(
            name: "HotstringsSeededAt",
            table: "UserPreferences",
            type: "datetimeoffset",
            nullable: true);
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropColumn(
            name: "HotkeysSeededAt",
            table: "UserPreferences");

        migrationBuilder.DropColumn(
            name: "HotstringsSeededAt",
            table: "UserPreferences");
    }
}
