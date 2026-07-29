using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace AHKFlowApp.Infrastructure.Persistence.Configurations;

internal sealed class IgnoredKnownShortcutConfiguration : IEntityTypeConfiguration<IgnoredKnownShortcut>
{
    public void Configure(EntityTypeBuilder<IgnoredKnownShortcut> builder)
    {
        builder.HasKey(x => x.Id);

        builder.Property(x => x.OwnerOid).IsRequired();
        builder.Property(x => x.ShortcutId).IsRequired().HasMaxLength(100);
        builder.Property(x => x.UsedBy).IsRequired().HasMaxLength(60);
        builder.Property(x => x.CreatedAt).IsRequired();

        builder.HasIndex(x => new { x.OwnerOid, x.ShortcutId, x.UsedBy })
            .IsUnique()
            .HasDatabaseName("IX_IgnoredKnownShortcut_Owner_Shortcut_UsedBy");
    }
}
