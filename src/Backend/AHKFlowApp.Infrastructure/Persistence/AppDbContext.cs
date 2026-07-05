using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;

namespace AHKFlowApp.Infrastructure.Persistence;

public sealed class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options), IAppDbContext
{
    public DbSet<Hotstring> Hotstrings => Set<Hotstring>();
    public DbSet<HotstringProfile> HotstringProfiles => Set<HotstringProfile>();
    public DbSet<Hotkey> Hotkeys => Set<Hotkey>();
    public DbSet<HotkeyProfile> HotkeyProfiles => Set<HotkeyProfile>();
    public DbSet<Profile> Profiles => Set<Profile>();
    public DbSet<UserPreference> UserPreferences => Set<UserPreference>();
    public DbSet<Category> Categories => Set<Category>();
    public DbSet<HotstringCategory> HotstringCategories => Set<HotstringCategory>();
    public DbSet<HotkeyCategory> HotkeyCategories => Set<HotkeyCategory>();
    public DbSet<EntityHistory> EntityHistories => Set<EntityHistory>();

    public Task<IDbContextTransaction> BeginTransactionAsync(CancellationToken cancellationToken = default)
        => Database.BeginTransactionAsync(cancellationToken);

    public IExecutionStrategy CreateExecutionStrategy()
        => Database.CreateExecutionStrategy();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);
        base.OnModelCreating(modelBuilder);
    }
}
