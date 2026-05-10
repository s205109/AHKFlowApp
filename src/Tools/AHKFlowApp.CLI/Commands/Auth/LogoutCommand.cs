using System.CommandLine;
using AHKFlowApp.CLI.Exceptions;
using AHKFlowApp.CLI.Services;
using Microsoft.Extensions.DependencyInjection;

namespace AHKFlowApp.CLI.Commands.Auth;

public static class LogoutCommand
{
    public static Command Build(IServiceProvider services)
    {
        Command cmd = new("logout", "Sign out of AHKFlowApp.");

        cmd.SetAction(async (ParseResult parse, CancellationToken ct) =>
        {
            TextWriter stdout = parse.InvocationConfiguration.Output;
            TextWriter stderr = parse.InvocationConfiguration.Error;
            IAuthTokenProvider auth = services.GetRequiredService<IAuthTokenProvider>();

            try
            {
                await auth.LogoutAsync(ct);
                await stdout.WriteLineAsync("Signed out");
                return 0;
            }
            catch (AuthConfigurationException ex)
            {
                await stderr.WriteLineAsync(ex.Message);
                return 1;
            }
            catch (HttpRequestException ex)
            {
                await stderr.WriteLineAsync(ex.Message);
                return 1;
            }
        });

        return cmd;
    }
}
