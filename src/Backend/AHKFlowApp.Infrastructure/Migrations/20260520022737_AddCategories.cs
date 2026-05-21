using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AHKFlowApp.Infrastructure.Migrations;

/// <inheritdoc />
public partial class AddCategories : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<DateTimeOffset>(
            name: "CategoriesSeededAt",
            table: "UserPreferences",
            type: "datetimeoffset",
            nullable: true);

        migrationBuilder.CreateTable(
            name: "Categories",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                OwnerOid = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                Name = table.Column<string>(type: "nvarchar(30)", maxLength: 30, nullable: false),
                CreatedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false),
                UpdatedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_Categories", x => x.Id);
            });

        migrationBuilder.CreateTable(
            name: "HotkeyCategories",
            columns: table => new
            {
                HotkeyId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                CategoryId = table.Column<Guid>(type: "uniqueidentifier", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_HotkeyCategories", x => new { x.HotkeyId, x.CategoryId });
                table.ForeignKey(
                    name: "FK_HotkeyCategories_Categories_CategoryId",
                    column: x => x.CategoryId,
                    principalTable: "Categories",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_HotkeyCategories_Hotkeys_HotkeyId",
                    column: x => x.HotkeyId,
                    principalTable: "Hotkeys",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateTable(
            name: "HotstringCategories",
            columns: table => new
            {
                HotstringId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                CategoryId = table.Column<Guid>(type: "uniqueidentifier", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_HotstringCategories", x => new { x.HotstringId, x.CategoryId });
                table.ForeignKey(
                    name: "FK_HotstringCategories_Categories_CategoryId",
                    column: x => x.CategoryId,
                    principalTable: "Categories",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_HotstringCategories_Hotstrings_HotstringId",
                    column: x => x.HotstringId,
                    principalTable: "Hotstrings",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex(
            name: "IX_Categories_OwnerOid",
            table: "Categories",
            column: "OwnerOid");

        migrationBuilder.CreateIndex(
            name: "IX_Category_Owner_Name",
            table: "Categories",
            columns: new[] { "OwnerOid", "Name" },
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_HotkeyCategories_CategoryId",
            table: "HotkeyCategories",
            column: "CategoryId");

        migrationBuilder.CreateIndex(
            name: "IX_HotstringCategories_CategoryId",
            table: "HotstringCategories",
            column: "CategoryId");
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(
            name: "HotkeyCategories");

        migrationBuilder.DropTable(
            name: "HotstringCategories");

        migrationBuilder.DropTable(
            name: "Categories");

        migrationBuilder.DropColumn(
            name: "CategoriesSeededAt",
            table: "UserPreferences");
    }
}
