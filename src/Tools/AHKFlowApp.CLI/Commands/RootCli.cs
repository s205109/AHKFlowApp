using System.CommandLine;
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
            HotstringCommand.Build(services),
            DownloadCommand.Build(services),
        };
        // Subcommands wired in subsequent phases:
        //   root.Subcommands.Add(LoginCommand.Build(services));
        //   root.Subcommands.Add(LogoutCommand.Build(services));
        return root;
    }
}
