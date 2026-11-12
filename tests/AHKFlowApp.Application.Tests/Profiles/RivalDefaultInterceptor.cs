using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;

namespace AHKFlowApp.Application.Tests.Profiles;

/// <summary>
/// Simulates a concurrent request: just before the first save that sets a default, it moves
/// the owner's default to a new profile named "Rival", on the handler's own connection.
/// </summary>
internal sealed class RivalDefaultInterceptor(Guid ownerOid) : SaveChangesInterceptor
{
    private bool _inserted;

    public override async ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData eventData,
        InterceptionResult<int> result,
        CancellationToken cancellationToken = default)
    {
        bool setsDefault = eventData.Context!.ChangeTracker.Entries<Profile>()
            .Any(e => e.Entity.IsDefault && e.State is EntityState.Added or EntityState.Modified);
        if (!_inserted && setsDefault)
        {
            _inserted = true;
            DateTimeOffset now = DateTimeOffset.UnixEpoch;
            await eventData.Context.Database.ExecuteSqlAsync(
                $"""
                UPDATE [Profiles] SET [IsDefault] = 0 WHERE [OwnerOid] = {ownerOid} AND [IsDefault] = 1;
                INSERT INTO [Profiles] ([Id], [OwnerOid], [Name], [IsDefault], [HeaderTemplate], [FooterTemplate], [CreatedAt], [UpdatedAt]) VALUES ({Guid.NewGuid()}, {ownerOid}, {"Rival"}, {true}, {""}, {""}, {now}, {now});
                """,
                cancellationToken);
        }

        return result;
    }
}
