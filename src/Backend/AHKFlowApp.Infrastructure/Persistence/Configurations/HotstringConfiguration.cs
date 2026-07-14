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

        // nvarchar(max): a Raw definition embeds the trigger line and brace wrapper around a body
        // that could already be near the old 4,000 limit, so the column must not hard-truncate.
        // Validation (RawDefinitionMaxLength) keeps user input bounded; this only removes the cap.
        builder.Property(x => x.Replacement)
            .IsRequired()
            .HasColumnType("nvarchar(max)");

        builder.Property(x => x.Description)
            .HasMaxLength(200);

        builder.Property(x => x.AppliesToAllProfiles).IsRequired();
        builder.Property(x => x.IsEndingCharacterRequired).IsRequired();
        builder.Property(x => x.IsTriggerInsideWord).IsRequired();

        // Persist enum as int (default for EF, made explicit here for clarity).
        builder.Property(x => x.Kind)
            .IsRequired()
            .HasConversion<int>();

        builder.Property(x => x.IsCaseSensitive).IsRequired();
        builder.Property(x => x.OmitEndingCharacter).IsRequired();

        builder.Property(x => x.DateTimeFormat)
            .HasMaxLength(50);

        // Persist enum as int (default for EF, made explicit here for clarity).
        builder.Property(x => x.DateOffsetUnit)
            .HasConversion<int>();

        // Persist enum as int (default for EF, made explicit here for clarity).
        builder.Property(x => x.ContextMatchType)
            .HasConversion<int>();

        builder.Property(x => x.ContextValue)
            .HasMaxLength(200);

        builder.Property(x => x.CreatedAt).IsRequired();
        builder.Property(x => x.UpdatedAt).IsRequired();

        // One trigger per owner per context — a trigger may have one global (null context) row
        // plus one row per distinct window-context value. Profiles are tracked in the junction table.
        // HasFilter(null) overrides EF's default SQL Server convention of adding an "IS NOT NULL"
        // filter to unique indexes with nullable columns: we want SQL Server's native unique-index
        // semantics, where two rows with NULL in every indexed nullable column are treated as
        // duplicates, so only one global (null-context) row per (OwnerOid, Trigger) is allowed.
        builder.HasIndex(x => new { x.OwnerOid, x.Trigger, x.ContextMatchType, x.ContextValue })
            .IsUnique()
            .HasFilter(null)
            .HasDatabaseName("IX_Hotstring_Owner_Trigger_Context");
    }
}
