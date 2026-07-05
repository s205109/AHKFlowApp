using System.Linq.Expressions;
using Ardalis.Result;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Common;

internal static class OwnedIdsValidation
{
    /// <summary>
    /// Verifies that every id in <paramref name="distinctIds"/> matches an entity in
    /// <paramref name="set"/> per <paramref name="ownedWithIds"/> (owner + id filter,
    /// built by the caller since Profile/Category share no interface).
    /// </summary>
    /// <returns>
    /// null when all ids exist for the owner; otherwise a <see cref="ValidationError"/>
    /// with Identifier "Input.{fieldName}" bindable to the request field.
    /// </returns>
    public static async Task<ValidationError?> CheckOwnedIdsAsync<TEntity>(
        IQueryable<TEntity> set,
        Expression<Func<TEntity, bool>> ownedWithIds,
        Guid[] distinctIds,
        string fieldName,
        CancellationToken ct)
    {
        if (distinctIds.Length == 0)
            return null;

        int validCount = await set.CountAsync(ownedWithIds, ct);
        return validCount == distinctIds.Length
            ? null
            : new ValidationError
            {
                Identifier = $"Input.{fieldName}",
                ErrorMessage = $"One or more {fieldName} do not exist for this user.",
            };
    }
}
