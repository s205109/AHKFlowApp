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

        // Typed action columns (Wave 1). The legacy (Action, Parameters) pair was dropped by the
        // contract migration; enums persist as int (EF's default, explicit here for clarity).
        builder.Property(x => x.ActionKind)
            .IsRequired()
            .HasConversion<int>();

        builder.Property(x => x.Text);                                    // nvarchar(max), nullable
        builder.Property(x => x.SendKeysContent).HasMaxLength(100);
        builder.Property(x => x.RunTarget).HasMaxLength(4000);
        builder.Property(x => x.RunTargetKind).HasConversion<int>();      // nullable int
        builder.Property(x => x.WindowOp).HasConversion<int>();           // nullable int
        builder.Property(x => x.RemapDest).HasMaxLength(50);
        builder.Property(x => x.Body);                                    // nvarchar(max), nullable

        builder.Property(x => x.AppliesToAllProfiles).IsRequired();
        builder.Property(x => x.CreatedAt).IsRequired();
        builder.Property(x => x.UpdatedAt).IsRequired();

        // One mapping per modifier-combo per user.
        builder.HasIndex(x => new { x.OwnerOid, x.Key, x.Ctrl, x.Alt, x.Shift, x.Win })
            .IsUnique()
            .HasDatabaseName("IX_Hotkey_Owner_Modifiers");
    }
}
