using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Common;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using Microsoft.EntityFrameworkCore.Storage;
using Xunit;

namespace AHKFlowApp.Application.Tests.History;

[Collection("HistoryDb")]
[Trait("Category", "Integration")]
public sealed class HistorySaveRetryTests(HistoryDbFixture fx)
{
    [Fact]
    public async Task SaveWithHistoryRetryAsync_VersionCollision_BumpsVersionAndSaves()
    {
        var owner = Guid.NewGuid();
        var entityId = Guid.NewGuid();

        await using AppDbContext db = fx.CreateContext();
        var entry = EntityHistory.Create(
            owner, TrackedEntityType.Hotstring, entityId, 1, HistoryChangeType.Edit, 1, "{}", TimeProvider.System);
        db.EntityHistories.Add(entry);

        await using (AppDbContext rival = fx.CreateContext())
        {
            rival.EntityHistories.Add(EntityHistory.Create(
                owner, TrackedEntityType.Hotstring, entityId, 1, HistoryChangeType.Edit, 1, "{}", TimeProvider.System));
            await rival.SaveChangesAsync();
        }

        await db.SaveWithHistoryRetryAsync(entry, default);

        entry.Version.Should().Be(2);
        (await db.EntityHistories.CountAsync(h => h.EntityId == entityId)).Should().Be(2);
    }

    [Fact]
    public async Task SaveWithHistoryRetryAsync_VersionCollision_IgnoresOtherOwnersVersions()
    {
        var owner = Guid.NewGuid();
        var otherOwner = Guid.NewGuid();
        var entityId = Guid.NewGuid();

        await using AppDbContext db = fx.CreateContext();
        var entry = EntityHistory.Create(
            owner, TrackedEntityType.Hotstring, entityId, 1, HistoryChangeType.Edit, 1, "{}", TimeProvider.System);
        db.EntityHistories.Add(entry);

        await using (AppDbContext rival = fx.CreateContext())
        {
            rival.EntityHistories.Add(EntityHistory.Create(
                owner, TrackedEntityType.Hotstring, entityId, 1, HistoryChangeType.Edit, 1, "{}", TimeProvider.System));
            rival.EntityHistories.Add(EntityHistory.Create(
                otherOwner, TrackedEntityType.Hotstring, entityId, 10, HistoryChangeType.Edit, 1, "{}", TimeProvider.System));
            await rival.SaveChangesAsync();
        }

        await db.SaveWithHistoryRetryAsync(entry, default);

        entry.Version.Should().Be(2);
    }

    [Fact]
    public async Task SaveWithHistoryRetryAsync_SecondVersionCollision_RetriesUntilAvailableVersion()
    {
        var owner = Guid.NewGuid();
        var entityId = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.EntityHistories.Add(EntityHistory.Create(
                owner, TrackedEntityType.Hotstring, entityId, 1, HistoryChangeType.Edit, 1, "{}", TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var entry = EntityHistory.Create(
            owner, TrackedEntityType.Hotstring, entityId, 1, HistoryChangeType.Edit, 1, "{}", TimeProvider.System);
        db.EntityHistories.Add(entry);

        bool insertedSecondCollision = false;
        InsertBeforeSecondSaveDbContext retryDb = new(db, async ct =>
        {
            if (insertedSecondCollision)
                return;

            insertedSecondCollision = true;
            await using AppDbContext rival = fx.CreateContext();
            rival.EntityHistories.Add(EntityHistory.Create(
                owner, TrackedEntityType.Hotstring, entityId, 2, HistoryChangeType.Edit, 1, "{}", TimeProvider.System));
            await rival.SaveChangesAsync(ct);
        });

        await retryDb.SaveWithHistoryRetryAsync(entry, default);

        entry.Version.Should().Be(3);
        (await db.EntityHistories.CountAsync(h => h.OwnerOid == owner && h.EntityId == entityId)).Should().Be(3);
    }

    [Fact]
    public async Task SaveWithHistoryRetryAsync_NoCollision_SavesNormally()
    {
        var owner = Guid.NewGuid();
        var entityId = Guid.NewGuid();

        await using AppDbContext db = fx.CreateContext();
        var entry = EntityHistory.Create(
            owner, TrackedEntityType.Hotstring, entityId, 1, HistoryChangeType.Edit, 1, "{}", TimeProvider.System);
        db.EntityHistories.Add(entry);

        await db.SaveWithHistoryRetryAsync(entry, default);

        entry.Version.Should().Be(1);
    }

    private sealed class InsertBeforeSecondSaveDbContext(
        AppDbContext inner,
        Func<CancellationToken, Task> insertBeforeSecondSave)
        : IAppDbContext
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
            if (_saveCount == 2)
                await insertBeforeSecondSave(cancellationToken);

            return await inner.SaveChangesAsync(cancellationToken);
        }

        public EntityEntry<TEntity> Entry<TEntity>(TEntity entity) where TEntity : class
            => inner.Entry(entity);

        public Task<IDbContextTransaction> BeginTransactionAsync(CancellationToken cancellationToken = default)
            => inner.BeginTransactionAsync(cancellationToken);

        public IExecutionStrategy CreateExecutionStrategy()
            => inner.CreateExecutionStrategy();
    }
}
