using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace AHKFlowApp.Infrastructure.Persistence.Configurations;

internal sealed class UserPreferenceConfiguration : IEntityTypeConfiguration<UserPreference>
{
    public void Configure(EntityTypeBuilder<UserPreference> builder)
    {
        builder.HasKey(x => x.OwnerOid);

        builder.Property(x => x.RowsPerPage).IsRequired();
        builder.Property(x => x.DarkMode).IsRequired();
        builder.Property(x => x.UpdatedAt).IsRequired();
    }
}
