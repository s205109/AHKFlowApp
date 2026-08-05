using System.Text;
using AHKFlowApp.UI.Blazor.Helpers;

namespace AHKFlowApp.UI.Blazor.Services;

/// <summary>
/// What a single download attempt ended with. Three free fields would allow contradictory values,
/// such as a saved file that also carries an error. The private constructor and the two factories
/// make those states impossible to build.
/// </summary>
internal sealed record DownloadOutcome
{
    private DownloadOutcome() { }

    internal bool Saved { get; private init; }
    internal string? FileName { get; private init; }
    internal string? Error { get; private init; }

    internal static DownloadOutcome Success(string fileName) =>
        new() { Saved = true, FileName = fileName };

    internal static DownloadOutcome Failure(string error) =>
        new() { Saved = false, Error = error };
}

/// <summary>
/// Fetches a profile's generated script, names the file, and saves it. The Profiles page and the
/// Downloads page both call this, so the same profile can never download under two different
/// names. It raises no snackbar, so each page keeps its own wording.
/// </summary>
internal sealed class ProfileScriptDownloader(
    IDownloadsApiClient downloadsApi,
    IFileSaver fileSaver,
    TimeProvider clock)
{
    /// <summary>
    /// Saves the profile's script as <c>{timestamp}_ahkflow_{stem}.ahk</c>.
    /// </summary>
    /// <remarks>
    /// Cancellation is not caught here. Every caller must catch
    /// <see cref="OperationCanceledException"/> and show no message. An exception from
    /// <see cref="IFileSaver.SaveAsync"/> also travels out unchanged.
    /// </remarks>
    internal async Task<DownloadOutcome> DownloadAsync(
        Guid profileId,
        string profileName,
        CancellationToken ct)
    {
        ApiResult<FileDownload> result = await downloadsApi.GetProfileScriptAsync(profileId, ct);

        if (!result.IsSuccess)
        {
            return DownloadOutcome.Failure(ApiErrorMessageFactory.Build(result.Status, result.Problem));
        }

        string fileName = $"{DownloadFileNames.Timestamp(clock)}_ahkflow_{SafeStem(profileName)}.ahk";
        await fileSaver.SaveAsync(fileName, result.Value!.ContentType, result.Value.Content);
        return DownloadOutcome.Success(fileName);
    }

    /// <summary>
    /// Turns a profile name into a file-name stem. Every run of unsafe characters becomes one
    /// underscore; only ASCII letters, digits, <c>.</c> and <c>-</c> survive.
    /// </summary>
    /// <remarks>
    /// The cut to 64 characters runs before the edge underscores are trimmed. The other order can
    /// leave a trailing underscore: a long name may collapse to text whose 64th character is the
    /// underscore, which the earlier trim never saw.
    /// </remarks>
    private static string SafeStem(string name)
    {
        StringBuilder sb = new(name.Length);
        bool previousWasUnderscore = false;
        foreach (char c in name)
        {
            bool safe = char.IsAsciiLetterOrDigit(c) || c == '.' || c == '-';
            if (safe)
            {
                sb.Append(c);
                previousWasUnderscore = false;
            }
            else if (!previousWasUnderscore)
            {
                sb.Append('_');
                previousWasUnderscore = true;
            }
        }

        string collapsed = sb.ToString();
        string truncated = collapsed.Length > 64 ? collapsed[..64] : collapsed;
        string trimmed = truncated.Trim('_');
        return trimmed.Length == 0 ? "profile" : trimmed;
    }
}
