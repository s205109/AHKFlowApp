using System.Security.Cryptography;
using System.Text;
using Microsoft.Data.SqlClient;

namespace AHKFlowApp.TestUtilities.Fixtures;

public static class SqlTestDatabase
{
    private const int MaxSqlIdentifierLength = 128;
    private const int HashLength = 12;
    private const string Prefix = "AHKFlowTest_";

    public static string CreateName(Type fixtureType)
    {
        string qualifiedName = fixtureType.FullName ?? fixtureType.Name;
        string hash = CreateHash(qualifiedName);
        string sanitizedName = Sanitize(qualifiedName);
        int maxSanitizedLength = MaxSqlIdentifierLength - Prefix.Length - 1 - HashLength;
        string trimmedName = sanitizedName.Length > maxSanitizedLength
            ? sanitizedName[..maxSanitizedLength]
            : sanitizedName;

        return $"{Prefix}{trimmedName}_{hash}";
    }

    public static string CreateConnectionString(string baseConnectionString, Type fixtureType)
    {
        var builder = new SqlConnectionStringBuilder(baseConnectionString)
        {
            InitialCatalog = CreateName(fixtureType),
        };

        return builder.ConnectionString;
    }

    private static string CreateHash(string value)
    {
        byte[] hashBytes = SHA256.HashData(Encoding.UTF8.GetBytes(value));
        return Convert.ToHexString(hashBytes)[..HashLength].ToLowerInvariant();
    }

    private static string Sanitize(string value)
    {
        var builder = new StringBuilder(value.Length);

        foreach (char character in value)
        {
            builder.Append(IsAsciiLetterOrDigit(character) ? character : '_');
        }

        return builder.ToString();
    }

    private static bool IsAsciiLetterOrDigit(char value) =>
        value is >= 'A' and <= 'Z'
        || value is >= 'a' and <= 'z'
        || value is >= '0' and <= '9';
}
