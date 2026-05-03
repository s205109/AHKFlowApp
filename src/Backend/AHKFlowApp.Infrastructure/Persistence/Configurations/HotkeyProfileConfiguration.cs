using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace AHKFlowApp.Infrastructure.Persistence.Configurations;

internal sealed class HotkeyProfileConfiguration : IEntityTypeConfiguration<HotkeyProfile>
{
    public void Configure(EntityTypeBuilder<HotkeyProfile> builder)
    {
        builder.HasKey(x => new { x.HotkeyId, x.ProfileId });

        builder.HasOne<Hotkey>()
            .WithMany(h => h.Profiles)
            .HasForeignKey(x => x.HotkeyId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasOne<Profile>()
            .WithMany()
            .HasForeignKey(x => x.ProfileId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
