using System.CommandLine;
using AHKFlowApp.CLI.Exceptions;
using AHKFlowApp.CLI.Services;
using Microsoft.Extensions.DependencyInjection;

namespace AHKFlowApp.CLI.Commands.Downloads;

public static class AhkDownloadCommand
{
    public static Command Build(IServiceProvider services)
    {
        Option<string> profile = new("--profile", "-p")
        {
            Description = "Profile name (case-insensitive).",
            Required = true,
        };
        Option<string?> output = new("--output", "-o")
        {
            Description = "Output path. Default: server-named file in current directory. '-' writes to stdout.",
        };

        Command cmd = new("ahk", "Download the generated .ahk for a single profile.") { profile, output };

        cmd.SetAction(async (ParseResult parse, CancellationToken ct) =>
        {
            IDownloadsApiClient downloads = services.GetRequiredService<IDownloadsApiClient>();
            IProfilesApiClient profilesClient = services.GetRequiredService<IProfilesApiClient>();

            string profileName = parse.GetValue(profile)!;
            string? outputOption = parse.GetValue(output);

            return await DownloadCommandRunner.RunAsync(
                parse, services, outputOption,
                async token =>
                {
                    IReadOnlyList<ProfileSummary> all = await profilesClient.ListAsync(token);
                    ProfileSummary? match = all.FirstOrDefault(p =>
                        string.Equals(p.Name, profileName, StringComparison.OrdinalIgnoreCase));
                    if (match is null)
                    {
                        string available = string.Join(", ", all.Select(a => a.Name));
                        throw new ProfileNotFoundException(profileName, available);
                    }
                    return await downloads.GetProfileScriptAsync(match.Id, token);
                },
                ct);
        });

        return cmd;
    }
}
