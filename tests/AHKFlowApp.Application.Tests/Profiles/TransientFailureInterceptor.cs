using System.Data.Common;
using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;

namespace AHKFlowApp.Application.Tests.Profiles;

/// <summary>
/// Fails the first save that sets a default on an existing profile with a SQL error the
/// retrying context treats as transient. In the update handler that is save 2 of attempt 1.
/// </summary>
internal sealed class TransientFailureInterceptor : DbCommandInterceptor
{
    public const int ErrorNumber = 51000;

    public int FailuresInjected { get; private set; }

    public override ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(
        DbCommand command,
        CommandEventData eventData,
        InterceptionResult<DbDataReader> result,
        CancellationToken cancellationToken = default)
    {
        bool setsDefault = eventData.CommandSource == CommandSource.SaveChanges
            && eventData.Context!.ChangeTracker.Entries<Profile>()
                .Any(e => e.State == EntityState.Modified && e.Entity.IsDefault);
        if (FailuresInjected == 0 && setsDefault)
        {
            FailuresInjected++;
            command.CommandText = $"THROW {ErrorNumber}, 'Simulated transient failure.', 1;";
        }

        return new ValueTask<InterceptionResult<DbDataReader>>(result);
    }
}
