using System.Diagnostics.CodeAnalysis;
using System.Text.RegularExpressions;
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
    // Error 2601 quotes the object first and the index second. The duplicate key value, which can hold
    // user text such as a profile name, comes after both. So only the second quoted token is the index.
    [ExcludeFromCodeCoverage]
    internal static bool IsUniqueIndexViolation(this DbUpdateException ex, string indexName)
    {
        if (!ex.IsDuplicateKeyViolation() || ex.InnerException is null)
            return false;

        Match quoted = ObjectThenIndex.Match(ex.InnerException.Message);
        return quoted.Success && string.Equals(quoted.Groups["index"].Value, indexName, StringComparison.Ordinal);
    }

    private static readonly Regex ObjectThenIndex = new("^[^']*'[^']*'[^']*'(?<index>[^']*)'", RegexOptions.None, TimeSpan.FromSeconds(1));
}
