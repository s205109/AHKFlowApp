using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using Microsoft.EntityFrameworkCore.Storage;

namespace AHKFlowApp.Application.Tests.Dev;

// Test decorator: forwards every IAppDbContext member to a real AppDbContext but runs a
// callback immediately before the Nth SaveChangesAsync. Lets a test commit a competing
// writer at the exact point a handler is about to save, so the save hits a genuine
// duplicate-key violation instead of a synthesized exception.
internal sealed class RunBeforeNthSaveDbContext(AppDbContext inner, int runBeforeCall, Func<Task> beforeSave) : IAppDbContext
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

    public async Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
    {
        _saveCount++;
        if (_saveCount == runBeforeCall)
            await beforeSave();
        return await inner.SaveChangesAsync(cancellationToken);
    }

    public EntityEntry<TEntity> Entry<TEntity>(TEntity entity) where TEntity : class
        => inner.Entry(entity);

    public Task<IDbContextTransaction> BeginTransactionAsync(CancellationToken cancellationToken = default)
        => inner.BeginTransactionAsync(cancellationToken);

    public IExecutionStrategy CreateExecutionStrategy()
        => inner.CreateExecutionStrategy();
}
