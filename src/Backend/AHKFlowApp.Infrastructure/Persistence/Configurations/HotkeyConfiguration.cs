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

        // Persist enum as int (default for EF, made explicit here for clarity).
        builder.Property(x => x.ContextMatchType)
            .HasConversion<int>();

        builder.Property(x => x.ContextValue)
            .HasMaxLength(200);

        builder.Property(x => x.AppliesToAllProfiles).IsRequired();
        builder.Property(x => x.CreatedAt).IsRequired();
        builder.Property(x => x.UpdatedAt).IsRequired();

        // One mapping per modifier-combo per owner per context — a combination may have one global
        // (null context) row plus one row per distinct window-context value. Profiles are tracked in
        // the junction table.
        // HasFilter(null) overrides EF's default SQL Server convention of adding an "IS NOT NULL"
        // filter to unique indexes with nullable columns: we want SQL Server's native unique-index
        // semantics, where two rows with NULL in every indexed nullable column are treated as
        // duplicates, so only one global (null-context) row per combination is allowed.
        builder.HasIndex(x => new
        {
            x.OwnerOid,
            x.Key,
            x.Ctrl,
            x.Alt,
            x.Shift,
            x.Win,
            x.ContextMatchType,
            x.ContextValue,
        })
            .IsUnique()
            .HasFilter(null)
            .HasDatabaseName("IX_Hotkey_Owner_Modifiers_Context");
    }
}
