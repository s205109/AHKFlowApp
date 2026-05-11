using System.CommandLine;
using AHKFlowApp.CLI.Exceptions;
using AHKFlowApp.CLI.Services;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Identity.Client;

namespace AHKFlowApp.CLI.Commands.Auth;

public static class LoginCommand
{
    public static Command Build(IServiceProvider services)
    {
        Command cmd = new("login", "Sign in to AHKFlowApp.");

        cmd.SetAction(async (ParseResult parse, CancellationToken ct) =>
        {
            TextWriter stdout = parse.InvocationConfiguration.Output;
            TextWriter stderr = parse.InvocationConfiguration.Error;
            IAuthTokenProvider auth = services.GetRequiredService<IAuthTokenProvider>();

            try
            {
                LoginResult result = await auth.LoginAsync(ct);
                string prefix = result.WasAlreadySignedIn ? "Already signed in as" : "Signed in as";
                await stdout.WriteLineAsync($"{prefix} {result.Username}");
                return 0;
            }
            catch (NotAuthenticatedException ex)
            {
                await stderr.WriteLineAsync(ex.Message);
                return 3;
            }
            catch (AuthConfigurationException ex)
            {
                await stderr.WriteLineAsync(ex.Message);
                return 1;
            }
            catch (MsalException ex)
            {
                await stderr.WriteLineAsync($"Authentication error: {ex.Message}");
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
