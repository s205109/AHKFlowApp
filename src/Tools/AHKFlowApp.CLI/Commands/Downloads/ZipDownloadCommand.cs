using System.CommandLine;
using AHKFlowApp.CLI.Services;
using Microsoft.Extensions.DependencyInjection;

namespace AHKFlowApp.CLI.Commands.Downloads;

public static class ZipDownloadCommand
{
    public static Command Build(IServiceProvider services)
    {
        Option<string?> output = new("--output", "-o")
        {
            Description = "Output path. Default: ahkflow_scripts.zip in current directory. '-' writes to stdout.",
        };

        Command cmd = new("zip", "Download a zip of every profile's generated .ahk.") { output };

        cmd.SetAction(async (ParseResult parse, CancellationToken ct) =>
        {
            IDownloadsApiClient downloads = services.GetRequiredService<IDownloadsApiClient>();
            string? outputOption = parse.GetValue(output);

            return await DownloadCommandRunner.RunAsync(
                parse, services, outputOption,
                token => downloads.GetAllProfileScriptsZipAsync(token),
                ct);
        });

        return cmd;
    }
}
