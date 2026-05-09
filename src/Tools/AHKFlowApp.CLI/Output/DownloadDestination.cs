namespace AHKFlowApp.CLI.Output;

public abstract record DownloadTarget
{
    public sealed record StdoutTarget : DownloadTarget;
    public sealed record FileTarget(string Path) : DownloadTarget;

    public static readonly DownloadTarget Stdout = new StdoutTarget();
    public static DownloadTarget File(string path) => new FileTarget(path);
}

public static class DownloadDestination
{
    public static DownloadTarget Resolve(string? optionValue, string serverFileName, string baseDirectory)
    {
        if (optionValue is null)
            return DownloadTarget.File(Path.Combine(baseDirectory, serverFileName));

        if (optionValue == "-")
            return DownloadTarget.Stdout;

        bool endsWithSep = Path.EndsInDirectorySeparator(optionValue);
        string normalized = Path.IsPathRooted(optionValue)
            ? optionValue
            : Path.GetFullPath(optionValue, baseDirectory);

        if (endsWithSep || Directory.Exists(normalized))
            return DownloadTarget.File(Path.Combine(normalized, serverFileName));

        return DownloadTarget.File(normalized);
    }
}
