using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Abstractions;

public interface IAppDbContext
{
    DbSet<Hotstring> Hotstrings { get; }
    DbSet<Hotkey> Hotkeys { get; }
    DbSet<UserPreference> UserPreferences { get; }

    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}
