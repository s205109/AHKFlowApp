using System.CommandLine;

namespace AHKFlowApp.CLI.Commands.Hotstrings;

public static class HotstringCommand
{
    public static Command Build(IServiceProvider services)
    {
        Command cmd = new("hotstring", "Manage hotstrings.")
        {
            NewHotstringCommand.Build(services),
            ListHotstringCommand.Build(services),
        };
        return cmd;
    }
}
