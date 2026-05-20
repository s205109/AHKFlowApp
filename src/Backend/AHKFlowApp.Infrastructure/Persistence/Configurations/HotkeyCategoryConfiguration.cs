using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace AHKFlowApp.Infrastructure.Persistence.Configurations;

internal sealed class HotkeyCategoryConfiguration : IEntityTypeConfiguration<HotkeyCategory>
{
    public void Configure(EntityTypeBuilder<HotkeyCategory> builder)
    {
        builder.HasKey(x => new { x.HotkeyId, x.CategoryId });

        builder.HasOne(x => x.Hotkey)
            .WithMany(h => h.Categories)
            .HasForeignKey(x => x.HotkeyId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasOne(x => x.Category)
            .WithMany(c => c.Hotkeys)
            .HasForeignKey(x => x.CategoryId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasIndex(x => x.CategoryId);
    }
}
