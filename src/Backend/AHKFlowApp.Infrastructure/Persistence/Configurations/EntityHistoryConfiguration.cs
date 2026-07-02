using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace AHKFlowApp.Infrastructure.Persistence.Configurations;

internal sealed class EntityHistoryConfiguration : IEntityTypeConfiguration<EntityHistory>
{
    public void Configure(EntityTypeBuilder<EntityHistory> builder)
    {
        builder.HasKey(x => x.Id);

        builder.Property(x => x.OwnerOid).IsRequired();
        builder.Property(x => x.EntityType).IsRequired();
        builder.Property(x => x.EntityId).IsRequired();
        builder.Property(x => x.Version).IsRequired();
        builder.Property(x => x.ChangeType).IsRequired();
        builder.Property(x => x.SchemaVersion).IsRequired();
        builder.Property(x => x.CapturedAt).IsRequired();
        builder.Property(x => x.SnapshotJson).IsRequired();

        builder.HasIndex(x => new { x.OwnerOid, x.EntityType, x.EntityId, x.Version })
            .IsUnique()
            .HasDatabaseName("IX_EntityHistory_Owner_Type_Entity_Version");
    }
}
