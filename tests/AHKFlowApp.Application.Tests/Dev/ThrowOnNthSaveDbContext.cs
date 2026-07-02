using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using Microsoft.EntityFrameworkCore.Storage;

namespace AHKFlowApp.Application.Tests.Dev;

// Test decorator: forwards every IAppDbContext member to a real AppDbContext but
// throws on the Nth SaveChangesAsync call. Used to verify SeedAll rollback.
internal sealed class ThrowOnNthSaveDbContext(AppDbContext inner, int failOnCall) : IAppDbContext
{
    private int _saveCount;

    public DbSet<Hotstring> Hotstrings => inner.Hotstrings;
    public DbSet<HotstringProfile> HotstringProfiles => inner.HotstringProfiles;
    public DbSet<Hotkey> Hotkeys => inner.Hotkeys;
    public DbSet<HotkeyProfile> HotkeyProfiles => inner.HotkeyProfiles;
    public DbSet<Profile> Profiles => inner.Profiles;
    public DbSet<UserPreference> UserPreferences => inner.UserPreferences;
    public DbSet<Category> Categories => inner.Categories;
    public DbSet<HotstringCategory> HotstringCategories => inner.HotstringCategories;
    public DbSet<HotkeyCategory> HotkeyCategories => inner.HotkeyCategories;
    public DbSet<EntityHistory> EntityHistories => inner.EntityHistories;

    public Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
    {
        _saveCount++;
        if (_saveCount == failOnCall)
            throw new InvalidOperationException("forced failure");
        return inner.SaveChangesAsync(cancellationToken);
    }

    public EntityEntry<TEntity> Entry<TEntity>(TEntity entity) where TEntity : class
        => inner.Entry(entity);

    public Task<IDbContextTransaction> BeginTransactionAsync(CancellationToken cancellationToken = default)
        => inner.BeginTransactionAsync(cancellationToken);

    public IExecutionStrategy CreateExecutionStrategy()
        => inner.CreateExecutionStrategy();
}
