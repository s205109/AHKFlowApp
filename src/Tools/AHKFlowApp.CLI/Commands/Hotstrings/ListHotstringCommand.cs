using System.CommandLine;
using AHKFlowApp.CLI.Exceptions;
using AHKFlowApp.CLI.Output;
using AHKFlowApp.CLI.Services;
using Microsoft.Extensions.DependencyInjection;
using Polly.Timeout;

namespace AHKFlowApp.CLI.Commands.Hotstrings;

public static class ListHotstringCommand
{
    public static Command Build(IServiceProvider services)
    {
        Option<string?> profile = new("--profile", "-p") { Description = "Filter by profile name." };
        Option<string?> search = new("--search", "-s", "--grep", "-g")
        {
            Description = "Search trigger / replacement (case-insensitive).",
        };
        Option<int> page = new("--page") { Description = "Page (1-indexed).", DefaultValueFactory = _ => 1 };
        Option<int> pageSize = new("--page-size") { Description = "Items per page (1-200).", DefaultValueFactory = _ => 50 };
        Option<bool> json = new("--json") { Description = "Emit JSON instead of human table." };

        Command cmd = new("list", "List hotstrings.") { profile, search, page, pageSize, json };

        cmd.SetAction(async (ParseResult parse, CancellationToken ct) =>
        {
            TextWriter stdout = parse.InvocationConfiguration.Output;
            TextWriter stderr = parse.InvocationConfiguration.Error;
            IHotstringsApiClient hotstrings = services.GetRequiredService<IHotstringsApiClient>();
            IProfilesApiClient profilesClient = services.GetRequiredService<IProfilesApiClient>();

            string? profileName = parse.GetValue(profile);
            bool wantJson = parse.GetValue(json);

            try
            {
                Guid? profileId = null;
                IReadOnlyDictionary<Guid, string> idToName =
                    System.Collections.Frozen.FrozenDictionary<Guid, string>.Empty;

                if (profileName is not null)
                {
                    IReadOnlyList<ProfileSummary> all = await profilesClient.ListAsync(ct);
                    idToName = all.ToDictionary(p => p.Id, p => p.Name);

                    ProfileSummary? match = all.FirstOrDefault(p =>
                        string.Equals(p.Name, profileName, StringComparison.OrdinalIgnoreCase));
                    if (match is null)
                    {
                        string available = string.Join(", ", all.Select(a => a.Name));
                        await stderr.WriteLineAsync(
                            $"Profile '{profileName}' not found. Available: {available}");
                        return 2;
                    }
                    profileId = match.Id;
                }

                PagedList<HotstringDto> result = await hotstrings.ListAsync(
                    profileId,
                    parse.GetValue(search),
                    parse.GetValue(page),
                    parse.GetValue(pageSize),
                    ct);

                if (wantJson)
                {
                    HotstringJsonFormatter.WritePage(stdout, result);
                }
                else
                {
                    if (profileName is null
                        && result.Items.Any(h => !h.AppliesToAllProfiles && h.ProfileIds.Length > 0))
                    {
                        IReadOnlyList<ProfileSummary> all = await profilesClient.ListAsync(ct);
                        idToName = all.ToDictionary(p => p.Id, p => p.Name);
                    }
                    HotstringTableFormatter.Write(stdout, result, idToName);
                }
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
            catch (ApiException ex) when (ex.StatusCode is 400 or 409)
            {
                await stderr.WriteLineAsync(ex.Body ?? ex.Message);
                return 2;
            }
            catch (ApiException ex) when (ex.StatusCode == 401)
            {
                await stderr.WriteLineAsync(AuthMessages.AuthenticationFailed);
                return 3;
            }
            catch (ApiException ex) when (CliApiFailureDetector.IsStoppedWebAppResponse(ex))
            {
                await stderr.WriteLineAsync(ApiMessages.WebAppUnavailable);
                return 1;
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
            catch (TimeoutRejectedException)
            {
                await stderr.WriteLineAsync(ApiMessages.RequestTimedOut);
                return 1;
            }
        });

        return cmd;
    }
}
