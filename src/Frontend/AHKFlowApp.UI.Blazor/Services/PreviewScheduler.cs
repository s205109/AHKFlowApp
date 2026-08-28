namespace AHKFlowApp.UI.Blazor.Services;

/// <summary>
/// Runs one live preview at a time for an edit dialog. Owns the cancellation source, the
/// generation counter that discards superseded responses, the pending flag the UI shows as a
/// spinner, and the exception boundary that keeps a fire-and-forget task from faulting.
/// </summary>
/// <remarks>
/// What triggers a preview stays with the caller: the hotstring dialog diffs its request after
/// each render, the hotkey dialog calls <see cref="Schedule"/> from each field handler. Only the
/// running of it is shared.
/// </remarks>
/// <typeparam name="TRequest">The preview request the API client takes.</typeparam>
/// <typeparam name="TResult">The preview payload the API client returns.</typeparam>
/// <param name="fetchAsync">Calls the API. Receives the request and a token cancelled on supersede.</param>
/// <param name="onResult">Applies a result that is still current.</param>
/// <param name="onUnexpectedError">
/// Reports an exception the fetch did not handle. The <see cref="bool"/> is true when the failure
/// is still the current generation. Callers log regardless and change state only when it is true.
/// </param>
/// <param name="stateHasChanged">Asks the owning component to re-render.</param>
internal sealed class PreviewScheduler<TRequest, TResult>(
    Func<TRequest, CancellationToken, Task<ApiResult<TResult>>> fetchAsync,
    Action<ApiResult<TResult>> onResult,
    Action<Exception, bool> onUnexpectedError,
    Action stateHasChanged) : IDisposable
{
    private CancellationTokenSource? _cts;
    private int _generation;
    private bool _disposed;

    /// <summary>True while a preview is in flight. Drives the spinner and the stale styling.</summary>
    public bool Pending { get; private set; }

    /// <summary>
    /// The run started by the most recent <see cref="Schedule"/> call. A test awaits it to know
    /// that a response has been handled, including a superseded one the scheduler discards.
    /// Capture it while its generation is still current; the next <see cref="Schedule"/> call
    /// replaces it.
    /// </summary>
    internal Task? LastRun { get; private set; }

    /// <summary>
    /// Supersedes any in-flight preview and starts a new one. When <paramref name="debounce"/> is
    /// greater than zero the fetch waits that long first, so a burst of keystrokes costs one call.
    /// </summary>
    public void Schedule(TRequest request, TimeSpan debounce)
    {
        Cancel();
        CancellationTokenSource cts = new();
        _cts = cts;
        int generation = ++_generation;
        Pending = true;

        // Fire-and-forget: RunAsync handles every exception it can raise (including unexpected
        // ones), so the task never faults. The handle is kept only so a test can await the run
        // and know a superseded response has been handled. Nothing here reads it.
        LastRun = RunAsync(request, cts.Token, generation, debounce);

        stateHasChanged();
    }

    /// <summary>Discards any in-flight preview and clears the pending flag.</summary>
    public void Cancel()
    {
        // Bumping the generation (not just cancelling) also discards in-flight responses
        // whose transport ignores cancellation and completes successfully afterwards.
        _generation++;
        Pending = false;
        _cts?.Cancel();
        _cts?.Dispose();
        _cts = null;
    }

    public void Dispose()
    {
        _disposed = true;
        Cancel();
    }

    private async Task RunAsync(TRequest request, CancellationToken ct, int generation, TimeSpan debounce)
    {
        try
        {
            if (debounce > TimeSpan.Zero)
                await Task.Delay(debounce, ct);

            ApiResult<TResult> result = await fetchAsync(request, ct);

            if (generation != _generation || _disposed)
                return;

            Pending = false;
            onResult(result);
            stateHasChanged();
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            // A cancelled preview (superseded input, panel collapsed, dialog disposed) is
            // silently ignored — never surfaced as an error.
            //
            // The token check is what makes this arm safe. HttpClient reports its own timeout as
            // a TaskCanceledException, which is an OperationCanceledException even though nobody
            // asked this preview to stop. Catching that here too would leave the spinner running,
            // the snippet dimmed and the copy button disabled with no way back, so it falls
            // through to the failure arm below instead.
        }
        catch (Exception ex)
        {
            // Boundary for a fire-and-forget background task: successful-response
            // deserialization (or anything else) can throw after ApiClientBase's
            // HttpRequestException handling. The caller logs it and surfaces a friendly message
            // instead of leaving the spinner stuck forever.
            bool isCurrent = generation == _generation && !_disposed;
            onUnexpectedError(ex, isCurrent);

            if (!isCurrent)
                return;

            Pending = false;
            stateHasChanged();
        }
    }
}
