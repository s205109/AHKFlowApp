namespace AHKFlowApp.CLI.Services;

public sealed class LocalAppDataAuthCachePathProvider : IAuthCachePathProvider
{
    private const string CacheFileName = "msal-cache.bin3";
    private const string CacheDirectoryName = "AHKFlowApp";

    public string GetCacheFilePath()
    {
        string root = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        if (string.IsNullOrWhiteSpace(root))
        {
            root = Environment.CurrentDirectory;
        }

        string directory = Path.Combine(root, CacheDirectoryName);
        Directory.CreateDirectory(directory);
        return Path.Combine(directory, CacheFileName);
    }
}
