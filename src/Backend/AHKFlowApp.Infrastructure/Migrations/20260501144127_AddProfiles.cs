using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AHKFlowApp.Infrastructure.Migrations;

/// <inheritdoc />
public partial class AddProfiles : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.CreateTable(
            name: "Profiles",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                OwnerOid = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                Name = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false),
                IsDefault = table.Column<bool>(type: "bit", nullable: false),
                HeaderTemplate = table.Column<string>(type: "nvarchar(max)", maxLength: 8000, nullable: false),
                FooterTemplate = table.Column<string>(type: "nvarchar(4000)", maxLength: 4000, nullable: false),
                CreatedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false),
                UpdatedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_Profiles", x => x.Id);
            });

        migrationBuilder.CreateIndex(
            name: "IX_Profile_Owner_DefaultOnly",
            table: "Profiles",
            columns: new[] { "OwnerOid", "IsDefault" },
            unique: true,
            filter: "[IsDefault] = 1");

        migrationBuilder.CreateIndex(
            name: "IX_Profile_Owner_Name",
            table: "Profiles",
            columns: new[] { "OwnerOid", "Name" },
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_Profiles_OwnerOid",
            table: "Profiles",
            column: "OwnerOid");
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(
            name: "Profiles");
    }
}
