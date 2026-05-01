using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace AHKFlowApp.Infrastructure.Persistence.Configurations;

internal sealed class HotstringProfileConfiguration : IEntityTypeConfiguration<HotstringProfile>
{
    public void Configure(EntityTypeBuilder<HotstringProfile> builder)
    {
        builder.HasKey(x => new { x.HotstringId, x.ProfileId });

        builder.HasOne<Hotstring>()
            .WithMany(h => h.Profiles)
            .HasForeignKey(x => x.HotstringId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasOne<Profile>()
            .WithMany()
            .HasForeignKey(x => x.ProfileId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
