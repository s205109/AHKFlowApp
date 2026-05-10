using System.CommandLine;
using AHKFlowApp.CLI.Commands.Auth;
using AHKFlowApp.CLI.Commands.Downloads;
using AHKFlowApp.CLI.Commands.Hotstrings;

namespace AHKFlowApp.CLI.Commands;

public static class RootCli
{
    public static readonly Option<bool> VerboseOption = new("--verbose", "-v")
    {
        Description = "Enable Information-level logs to stderr.",
        Recursive = true,
    };

    public static RootCommand Build(IServiceProvider services)
    {
        RootCommand root = new("ahkflow - AHKFlowApp CLI")
        {
            VerboseOption,
            LoginCommand.Build(services),
            LogoutCommand.Build(services),
            HotstringCommand.Build(services),
            DownloadCommand.Build(services),
        };
        return root;
    }
}
