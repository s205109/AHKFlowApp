using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AHKFlowApp.Infrastructure.Migrations;

/// <inheritdoc />
public partial class AddEntityHistory : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.CreateTable(
            name: "EntityHistories",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                OwnerOid = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                EntityType = table.Column<int>(type: "int", nullable: false),
                EntityId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                Version = table.Column<int>(type: "int", nullable: false),
                ChangeType = table.Column<int>(type: "int", nullable: false),
                SchemaVersion = table.Column<int>(type: "int", nullable: false),
                CapturedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false),
                SnapshotJson = table.Column<string>(type: "nvarchar(max)", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_EntityHistories", x => x.Id);
            });

        migrationBuilder.CreateIndex(
            name: "IX_EntityHistory_Owner_Type_Entity_Version",
            table: "EntityHistories",
            columns: new[] { "OwnerOid", "EntityType", "EntityId", "Version" },
            unique: true);
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(
            name: "EntityHistories");
    }
}
