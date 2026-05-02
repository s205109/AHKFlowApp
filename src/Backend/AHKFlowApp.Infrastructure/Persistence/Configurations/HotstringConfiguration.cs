using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace AHKFlowApp.Infrastructure.Persistence.Configurations;

internal sealed class HotstringConfiguration : IEntityTypeConfiguration<Hotstring>
{
    public void Configure(EntityTypeBuilder<Hotstring> builder)
    {
        builder.HasKey(x => x.Id);

        builder.Property(x => x.OwnerOid).IsRequired();
        builder.HasIndex(x => x.OwnerOid);

        builder.Property(x => x.Trigger)
            .IsRequired()
            .HasMaxLength(50);

        builder.Property(x => x.Replacement)
            .IsRequired()
            .HasMaxLength(4000);

        builder.Property(x => x.AppliesToAllProfiles).IsRequired();
        builder.Property(x => x.IsEndingCharacterRequired).IsRequired();
        builder.Property(x => x.IsTriggerInsideWord).IsRequired();

        builder.Property(x => x.CreatedAt).IsRequired();
        builder.Property(x => x.UpdatedAt).IsRequired();

        // One trigger per owner globally — profiles are tracked in the junction table.
        builder.HasIndex(x => new { x.OwnerOid, x.Trigger })
            .IsUnique()
            .HasDatabaseName("IX_Hotstring_Owner_Trigger");
    }
}
