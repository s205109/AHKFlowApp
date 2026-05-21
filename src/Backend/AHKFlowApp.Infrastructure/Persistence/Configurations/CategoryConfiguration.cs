using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace AHKFlowApp.Infrastructure.Persistence.Configurations;

internal sealed class CategoryConfiguration : IEntityTypeConfiguration<Category>
{
    public void Configure(EntityTypeBuilder<Category> builder)
    {
        builder.HasKey(x => x.Id);

        builder.Property(x => x.OwnerOid).IsRequired();
        builder.HasIndex(x => x.OwnerOid);

        builder.Property(x => x.Name)
            .IsRequired()
            .HasMaxLength(30);

        builder.Property(x => x.CreatedAt).IsRequired();
        builder.Property(x => x.UpdatedAt).IsRequired();

        // Case-insensitive uniqueness per owner. The Name column uses the default
        // SQL Server collation which is case-insensitive; combined with a unique
        // index this gives "Email" / "EMAIL" conflict at the DB level without LOWER().
        builder.HasIndex(x => new { x.OwnerOid, x.Name })
            .IsUnique()
            .HasDatabaseName("IX_Category_Owner_Name");
    }
}
