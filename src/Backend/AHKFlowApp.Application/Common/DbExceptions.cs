using System.Diagnostics.CodeAnalysis;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Common;

internal static class DbExceptions
{
    // Checks SQL Server unique-constraint error codes (2601/2627) without importing Microsoft.Data.SqlClient,
    // which would couple the Application layer to an infrastructure concern.
    [ExcludeFromCodeCoverage]
    internal static bool IsDuplicateKeyViolation(this DbUpdateException ex) =>
        ex.InnerException?.GetType().GetProperty("Number")?.GetValue(ex.InnerException) is int n &&
        n is 2601 or 2627;

    // Reads the index name from the SQL Server message, so callers can tell unique indexes apart.
    [ExcludeFromCodeCoverage]
    internal static bool IsUniqueIndexViolation(this DbUpdateException ex, string indexName) =>
        ex.IsDuplicateKeyViolation() &&
        ex.InnerException?.Message.Contains($"'{indexName}'", StringComparison.Ordinal) == true;
}
