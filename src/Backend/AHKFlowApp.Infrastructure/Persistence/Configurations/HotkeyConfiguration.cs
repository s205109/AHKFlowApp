using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace AHKFlowApp.Infrastructure.Persistence.Configurations;

internal sealed class HotkeyConfiguration : IEntityTypeConfiguration<Hotkey>
{
    public void Configure(EntityTypeBuilder<Hotkey> builder)
    {
        builder.HasKey(x => x.Id);

        builder.Property(x => x.OwnerOid).IsRequired();
        builder.HasIndex(x => x.OwnerOid);

        builder.Property(x => x.ProfileId);

        builder.Property(x => x.Trigger)
            .IsRequired()
            .HasMaxLength(100);

        builder.Property(x => x.Action)
            .IsRequired()
            .HasMaxLength(4000);

        builder.Property(x => x.Description)
            .HasMaxLength(200);

        builder.Property(x => x.CreatedAt).IsRequired();
        builder.Property(x => x.UpdatedAt).IsRequired();

        // SQL Server treats NULLs as distinct for uniqueness — two filtered indexes
        // cover both the profile-scoped case and the profile-less case per owner.
        builder.HasIndex(x => new { x.OwnerOid, x.ProfileId, x.Trigger })
            .IsUnique()
            .HasFilter("[ProfileId] IS NOT NULL")
            .HasDatabaseName("IX_Hotkey_Owner_Profile_Trigger");

        builder.HasIndex(x => new { x.OwnerOid, x.Trigger })
            .IsUnique()
            .HasFilter("[ProfileId] IS NULL")
            .HasDatabaseName("IX_Hotkey_Owner_Trigger_NoProfile");
    }
}
