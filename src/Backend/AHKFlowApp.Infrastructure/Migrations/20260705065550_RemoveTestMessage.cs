using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AHKFlowApp.Infrastructure.Migrations;

/// <inheritdoc />
public partial class RemoveTestMessage : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(
            name: "TestMessages");
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.CreateTable(
            name: "TestMessages",
            columns: table => new
            {
                Id = table.Column<int>(type: "int", nullable: false)
                    .Annotation("SqlServer:Identity", "1, 1"),
                CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false),
                Message = table.Column<string>(type: "nvarchar(500)", maxLength: 500, nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_TestMessages", x => x.Id);
            });

        migrationBuilder.InsertData(
            table: "TestMessages",
            columns: new[] { "Id", "CreatedAt", "Message" },
            values: new object[] { 1, new DateTime(2025, 1, 1, 0, 0, 0, 0, DateTimeKind.Utc), "hello test record" });
    }
}
