using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Infrastructure.Persistence;

public sealed class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options), IAppDbContext
{
    public DbSet<TestMessage> TestMessages => Set<TestMessage>();
    public DbSet<Hotstring> Hotstrings => Set<Hotstring>();
    public DbSet<HotstringProfile> HotstringProfiles => Set<HotstringProfile>();
    public DbSet<Hotkey> Hotkeys => Set<Hotkey>();
    public DbSet<HotkeyProfile> HotkeyProfiles => Set<HotkeyProfile>();
    public DbSet<Profile> Profiles => Set<Profile>();
    public DbSet<UserPreference> UserPreferences => Set<UserPreference>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);
        base.OnModelCreating(modelBuilder);
    }
}
