using AHKFlowApp.CLI.Services;

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

    public static async Task WriteAsync(
        DownloadTarget target, byte[] bytes, BinaryStdout binaryStdout, CancellationToken ct)
    {
        switch (target)
        {
            case DownloadTarget.StdoutTarget:
            {
                Stream stdout = binaryStdout.Open();
                await stdout.WriteAsync(bytes, ct);
                await stdout.FlushAsync(ct);
                break;
            }
            case DownloadTarget.FileTarget file:
            {
                string? dir = Path.GetDirectoryName(file.Path);
                if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
                await File.WriteAllBytesAsync(file.Path, bytes, ct);
                break;
            }
            default:
                throw new InvalidOperationException($"Unhandled download target type: {target.GetType().Name}");
        }
    }
}
