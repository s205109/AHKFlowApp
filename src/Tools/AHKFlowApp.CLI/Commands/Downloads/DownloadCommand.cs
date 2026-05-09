using System.CommandLine;

namespace AHKFlowApp.CLI.Commands.Downloads;

public static class DownloadCommand
{
    public static Command Build(IServiceProvider services)
    {
        Command cmd = new("download", "Download generated AutoHotkey scripts.")
        {
            AhkDownloadCommand.Build(services),
            ZipDownloadCommand.Build(services),
        };
        return cmd;
    }
}
