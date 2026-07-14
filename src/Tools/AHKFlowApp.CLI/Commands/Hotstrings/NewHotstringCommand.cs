using System.CommandLine;
using AHKFlowApp.CLI.Exceptions;
using AHKFlowApp.CLI.Output;
using AHKFlowApp.CLI.Services;
using Microsoft.Extensions.DependencyInjection;
using Polly.Timeout;

namespace AHKFlowApp.CLI.Commands.Hotstrings;

public static class NewHotstringCommand
{
    public static Command Build(IServiceProvider services)
    {
        Option<string> trigger = new("--trigger", "-t") { Description = "Abbreviation to expand." };
        Option<string> replacement = new("--replacement", "-r") { Description = "Replacement text." };
        Option<string> raw = new("--raw")
        {
            Description = "Create a Raw hotstring from a full AHK v2 definition, e.g. \":K1000 SE*:ftw::for the win\" (mutually exclusive with --trigger/--replacement).",
        };
        Option<string[]> profile = new("--profile", "-p") { Description = "Profile name (repeatable)." };
        Option<bool> noEndingChar = new("--no-ending-char") { Description = "Don't require an ending character (default: required)." };
        Option<bool> noInsideWord = new("--no-inside-word") { Description = "Don't trigger inside words (default: triggers inside words)." };
        Option<bool> json = new("--json") { Description = "Emit JSON instead of human summary." };

        Command cmd = new("new", "Create a new hotstring.")
        {
            trigger, replacement, raw, profile, noEndingChar, noInsideWord, json,
        };

        cmd.SetAction(async (ParseResult parse, CancellationToken ct) =>
        {
            TextWriter stdout = parse.InvocationConfiguration.Output;
            TextWriter stderr = parse.InvocationConfiguration.Error;
            IHotstringsApiClient hotstrings = services.GetRequiredService<IHotstringsApiClient>();
            IProfilesApiClient profiles = services.GetRequiredService<IProfilesApiClient>();

            try
            {
                string? rawDefinition = parse.GetValue(raw);
                string? triggerValue = parse.GetValue(trigger);
                string? replacementValue = parse.GetValue(replacement);

                // Validate the two mutually-exclusive input modes up front. The server does all
                // Raw parsing/validation; the CLI only relays the definition and ProblemDetails.
                if (rawDefinition is not null)
                {
                    if (triggerValue is not null || replacementValue is not null)
                    {
                        await stderr.WriteLineAsync("--raw cannot be combined with --trigger or --replacement.");
                        return 2;
                    }
                }
                else if (triggerValue is null || replacementValue is null)
                {
                    await stderr.WriteLineAsync("Specify either --raw, or both --trigger and --replacement.");
                    return 2;
                }

                Guid[]? resolvedIds = null;
                bool appliesToAll = true;
                string[]? names = parse.GetValue(profile);
                if (names is { Length: > 0 })
                {
                    IReadOnlyList<ProfileSummary> all = await profiles.ListAsync(ct);
                    Dictionary<string, Guid> byName = new(StringComparer.OrdinalIgnoreCase);
                    foreach (ProfileSummary p in all) byName[p.Name] = p.Id;
                    List<Guid> resolved = [];
                    foreach (string n in names)
                    {
                        if (!byName.TryGetValue(n, out Guid id))
                        {
                            string available = string.Join(", ", all.Select(a => a.Name));
                            await stderr.WriteLineAsync($"Profile '{n}' not found. Available: {available}");
                            return 2;
                        }
                        resolved.Add(id);
                    }
                    resolvedIds = [.. resolved];
                    appliesToAll = false;
                }

                CreateHotstringDto input = rawDefinition is not null
                    ? new CreateHotstringDto(
                        Trigger: string.Empty,
                        Replacement: rawDefinition,
                        ProfileIds: resolvedIds,
                        AppliesToAllProfiles: appliesToAll,
                        Kind: HotstringKind.Raw)
                    : new CreateHotstringDto(
                        Trigger: triggerValue!,
                        Replacement: replacementValue!,
                        ProfileIds: resolvedIds,
                        AppliesToAllProfiles: appliesToAll,
                        IsEndingCharacterRequired: !parse.GetValue(noEndingChar),
                        IsTriggerInsideWord: !parse.GetValue(noInsideWord));

                HotstringDto created = await hotstrings.CreateAsync(input, ct);

                if (parse.GetValue(json))
                    HotstringJsonFormatter.WriteSingle(stdout, created);
                else
                    await stdout.WriteLineAsync(
                        $"Created hotstring {created.Id} ('{created.Trigger}')");
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
