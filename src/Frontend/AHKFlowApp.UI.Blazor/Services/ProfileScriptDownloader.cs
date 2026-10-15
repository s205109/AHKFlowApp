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
/// Fetches a profile's generated script and saves it under the name the API chose. The Profiles
/// page and the Downloads page both call this. The API's stem rule is the only one, so a profile
/// gets the same stem here as inside the zip. It raises no snackbar, so each page keeps its own
/// wording.
/// </summary>
internal sealed class ProfileScriptDownloader(
    IDownloadsApiClient downloadsApi,
    IFileSaver fileSaver,
    TimeProvider clock)
{
    /// <summary>
    /// Saves the profile's script as <c>{timestamp}_{API file name}</c>, for example
    /// <c>20260726_140509_ahkflow_Work.ahk</c>.
    /// </summary>
    /// <remarks>
    /// The API sends its file name in the <c>Content-Disposition</c> header. When the response has
    /// no readable header, the API client falls back to <c>ahkflow_profile.ahk</c>.
    /// Cancellation is not caught here. Every caller must catch
    /// <see cref="OperationCanceledException"/> and show no message. An exception from
    /// <see cref="IFileSaver.SaveAsync"/> also travels out unchanged.
    /// </remarks>
    internal async Task<DownloadOutcome> DownloadAsync(Guid profileId, CancellationToken ct)
    {
        ApiResult<FileDownload> result = await downloadsApi.GetProfileScriptAsync(profileId, ct);

        if (!result.IsSuccess)
        {
            return DownloadOutcome.Failure(ApiErrorMessageFactory.Build(result.Status, result.Problem));
        }

        string fileName = $"{DownloadFileNames.Timestamp(clock)}_{result.Value!.FileName}";
        await fileSaver.SaveAsync(fileName, result.Value.ContentType, result.Value.Content);
        return DownloadOutcome.Success(fileName);
    }
}
