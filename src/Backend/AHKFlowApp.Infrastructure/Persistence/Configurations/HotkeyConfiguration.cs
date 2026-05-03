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

        builder.Property(x => x.Description)
            .IsRequired()
            .HasMaxLength(200);

        builder.Property(x => x.Key)
            .IsRequired()
            .HasMaxLength(20);

        builder.Property(x => x.Ctrl).IsRequired();
        builder.Property(x => x.Alt).IsRequired();
        builder.Property(x => x.Shift).IsRequired();
        builder.Property(x => x.Win).IsRequired();

        // Persist enum as int (default for EF, made explicit here for clarity).
        builder.Property(x => x.Action)
            .IsRequired()
            .HasConversion<int>();

        builder.Property(x => x.Parameters)
            .IsRequired()
            .HasMaxLength(4000);

        builder.Property(x => x.AppliesToAllProfiles).IsRequired();
        builder.Property(x => x.CreatedAt).IsRequired();
        builder.Property(x => x.UpdatedAt).IsRequired();

        // One mapping per modifier-combo per user.
        builder.HasIndex(x => new { x.OwnerOid, x.Key, x.Ctrl, x.Alt, x.Shift, x.Win })
            .IsUnique()
            .HasDatabaseName("IX_Hotkey_Owner_Modifiers");
    }
}
