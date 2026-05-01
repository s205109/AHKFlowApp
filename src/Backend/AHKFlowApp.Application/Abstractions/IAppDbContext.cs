using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Abstractions;

public interface IAppDbContext
{
    DbSet<Hotstring> Hotstrings { get; }
    DbSet<HotstringProfile> HotstringProfiles { get; }
    DbSet<Hotkey> Hotkeys { get; }
    DbSet<Profile> Profiles { get; }
    DbSet<UserPreference> UserPreferences { get; }

    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}
