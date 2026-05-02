using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace AHKFlowApp.Infrastructure.Persistence.Configurations;

internal sealed class ProfileConfiguration : IEntityTypeConfiguration<Profile>
{
    public void Configure(EntityTypeBuilder<Profile> builder)
    {
        builder.HasKey(x => x.Id);

        builder.Property(x => x.OwnerOid).IsRequired();
        builder.HasIndex(x => x.OwnerOid);

        builder.Property(x => x.Name)
            .IsRequired()
            .HasMaxLength(100);

        builder.Property(x => x.IsDefault).IsRequired();

        builder.Property(x => x.HeaderTemplate)
            .IsRequired()
            .HasMaxLength(8000);

        builder.Property(x => x.FooterTemplate)
            .IsRequired()
            .HasMaxLength(4000);

        builder.Property(x => x.CreatedAt).IsRequired();
        builder.Property(x => x.UpdatedAt).IsRequired();

        // Name unique per owner.
        builder.HasIndex(x => new { x.OwnerOid, x.Name })
            .IsUnique()
            .HasDatabaseName("IX_Profile_Owner_Name");

        // At most one default profile per owner (filtered unique index).
        builder.HasIndex(x => new { x.OwnerOid, x.IsDefault })
            .IsUnique()
            .HasFilter("[IsDefault] = 1")
            .HasDatabaseName("IX_Profile_Owner_DefaultOnly");
    }
}
