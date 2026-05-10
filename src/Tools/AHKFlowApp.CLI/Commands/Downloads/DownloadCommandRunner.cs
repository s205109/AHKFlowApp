using System.CommandLine;
using AHKFlowApp.CLI.Exceptions;
using AHKFlowApp.CLI.Output;
using AHKFlowApp.CLI.Services;
using Microsoft.Extensions.DependencyInjection;

namespace AHKFlowApp.CLI.Commands.Downloads;

internal static class DownloadCommandRunner
{
    public static async Task<int> RunAsync(
        ParseResult parse,
        IServiceProvider services,
        string? outputOption,
        Func<CancellationToken, Task<DownloadResult>> fetch,
        CancellationToken ct)
    {
        TextWriter stdout = parse.InvocationConfiguration.Output;
        TextWriter stderr = parse.InvocationConfiguration.Error;
        BinaryStdout binaryStdout = services.GetRequiredService<BinaryStdout>();
        WorkingDirectory workingDir = services.GetRequiredService<WorkingDirectory>();

        try
        {
            DownloadResult result = await fetch(ct);
            DownloadTarget target = DownloadDestination.Resolve(outputOption, result.FileName, workingDir.Get());
            await DownloadDestination.WriteAsync(target, result.Bytes, binaryStdout, ct);

            if (target is DownloadTarget.FileTarget file)
                await stdout.WriteLineAsync($"Wrote {file.Path} ({result.Bytes.Length} bytes)");

            return 0;
        }
        catch (ProfileNotFoundException ex)
        {
            await stderr.WriteLineAsync(ex.Message);
            return 2;
        }
        catch (NotAuthenticatedException ex)
        {
            await stderr.WriteLineAsync(ex.Message);
            return 3;
        }
        catch (ApiException ex) when (ex.StatusCode == 401)
        {
            await stderr.WriteLineAsync(AuthMessages.AuthenticationFailed);
            return 3;
        }
        catch (ApiException ex) when (ex.StatusCode is 400 or 404 or 409)
        {
            await stderr.WriteLineAsync(ex.Body ?? ex.Message);
            return 2;
        }
        catch (ApiException ex)
        {
            await stderr.WriteLineAsync(ex.Body ?? $"Server error ({ex.StatusCode}).");
            return 1;
        }
        catch (HttpRequestException ex)
        {
            await stderr.WriteLineAsync(ex.Message);
            return 1;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
            await stderr.WriteLineAsync(ex.Message);
            return 1;
        }
    }
}
