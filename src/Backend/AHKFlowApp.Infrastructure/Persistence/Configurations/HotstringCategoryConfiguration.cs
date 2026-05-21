using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace AHKFlowApp.Infrastructure.Persistence.Configurations;

internal sealed class HotstringCategoryConfiguration : IEntityTypeConfiguration<HotstringCategory>
{
    public void Configure(EntityTypeBuilder<HotstringCategory> builder)
    {
        builder.HasKey(x => new { x.HotstringId, x.CategoryId });

        builder.HasOne(x => x.Hotstring)
            .WithMany(h => h.Categories)
            .HasForeignKey(x => x.HotstringId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasOne(x => x.Category)
            .WithMany(c => c.Hotstrings)
            .HasForeignKey(x => x.CategoryId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasIndex(x => x.CategoryId);
    }
}
