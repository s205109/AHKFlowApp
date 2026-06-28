using System.Security.Cryptography;
using System.Text;
using Microsoft.Data.SqlClient;

namespace AHKFlowApp.TestUtilities.Fixtures;

public static class SqlTestDatabase
{
    private const int MaxSqlIdentifierLength = 128;
    private const int HashLength = 12;
    private const string Prefix = "AHKFlowTest_";

    public static string CreateName(Type fixtureType) =>
        CreateName(fixtureType.FullName ?? fixtureType.Name);

    public static string CreateName(string discriminator)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(discriminator);

        string hash = CreateHash(discriminator);
        string sanitizedName = Sanitize(discriminator);
        int maxSanitizedLength = MaxSqlIdentifierLength - Prefix.Length - 1 - HashLength;
        string trimmedName = sanitizedName.Length > maxSanitizedLength
            ? sanitizedName[..maxSanitizedLength]
            : sanitizedName;

        return $"{Prefix}{trimmedName}_{hash}";
    }

    public static string CreateConnectionString(string baseConnectionString, Type fixtureType) =>
        CreateConnectionString(baseConnectionString, fixtureType.FullName ?? fixtureType.Name);

    public static string CreateConnectionString(string baseConnectionString, string discriminator)
    {
        var builder = new SqlConnectionStringBuilder(baseConnectionString)
        {
            InitialCatalog = CreateName(discriminator),
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
