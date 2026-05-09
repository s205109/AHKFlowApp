using System.CommandLine;
using AHKFlowApp.CLI.Exceptions;
using AHKFlowApp.CLI.Output;
using AHKFlowApp.CLI.Services;
using Microsoft.Extensions.DependencyInjection;

namespace AHKFlowApp.CLI.Commands.Hotstrings;

public static class NewHotstringCommand
{
    public static Command Build(IServiceProvider services)
    {
        Option<string> trigger = new("--trigger", "-t") { Description = "Abbreviation to expand.", Required = true };
        Option<string> replacement = new("--replacement", "-r") { Description = "Replacement text.", Required = true };
        Option<string[]> profile = new("--profile", "-p") { Description = "Profile name (repeatable)." };
        Option<bool> noEndingChar = new("--no-ending-char") { Description = "Don't require an ending character (default: required)." };
        Option<bool> noInsideWord = new("--no-inside-word") { Description = "Don't trigger inside words (default: triggers inside words)." };
        Option<bool> json = new("--json") { Description = "Emit JSON instead of human summary." };

        Command cmd = new("new", "Create a new hotstring.")
        {
            trigger, replacement, profile, noEndingChar, noInsideWord, json,
        };

        cmd.SetAction(async (ParseResult parse, CancellationToken ct) =>
        {
            TextWriter stdout = parse.InvocationConfiguration.Output;
            TextWriter stderr = parse.InvocationConfiguration.Error;
            IHotstringsApiClient hotstrings = services.GetRequiredService<IHotstringsApiClient>();
            IProfilesApiClient profiles = services.GetRequiredService<IProfilesApiClient>();

            try
            {
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

                CreateHotstringDto input = new(
                    Trigger: parse.GetValue(trigger)!,
                    Replacement: parse.GetValue(replacement)!,
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
            catch (ApiException ex) when (ex.StatusCode is 400 or 409)
            {
                await stderr.WriteLineAsync(ex.Body ?? ex.Message);
                return 2;
            }
            catch (ApiException ex) when (ex.StatusCode is 401 or 403)
            {
                await stderr.WriteLineAsync(
                    "Not signed in. Set AHKFLOW_TOKEN environment variable to a bearer token.");
                return 3;
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
        });

        return cmd;
    }
}
