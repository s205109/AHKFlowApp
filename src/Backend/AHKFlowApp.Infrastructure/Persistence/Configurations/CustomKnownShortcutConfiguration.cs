using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace AHKFlowApp.Infrastructure.Persistence.Configurations;

internal sealed class CustomKnownShortcutConfiguration : IEntityTypeConfiguration<CustomKnownShortcut>
{
    public void Configure(EntityTypeBuilder<CustomKnownShortcut> builder)
    {
        builder.HasKey(x => x.Id);

        builder.Property(x => x.OwnerOid).IsRequired();
        builder.Property(x => x.Key).IsRequired().HasMaxLength(50);
        builder.Property(x => x.UsedBy).IsRequired().HasMaxLength(60);
        builder.Property(x => x.Does).IsRequired().HasMaxLength(200);
        builder.Property(x => x.Protection).IsRequired();
        builder.Property(x => x.Scope).IsRequired();
        builder.Property(x => x.CreatedAt).IsRequired();
        builder.Property(x => x.UpdatedAt).IsRequired();

        // One label per combination per owner. Two labels on one combination are allowed and
        // expected — that is how a combination gains a second use.
        builder.HasIndex(x => new { x.OwnerOid, x.Key, x.Ctrl, x.Alt, x.Shift, x.Win, x.UsedBy })
            .IsUnique()
            .HasDatabaseName("IX_CustomKnownShortcut_Owner_Combo_UsedBy");
    }
}
