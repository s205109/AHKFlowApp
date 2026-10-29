using System.CommandLine;
using System.CommandLine.Parsing;
using AHKFlowApp.CLI.Commands;
using AHKFlowApp.UI.Blazor.Components.Home;
using Bunit;
using FluentAssertions;
using FluentAssertions.Execution;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor.Services;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Pages.Home;

public sealed class CliQuickstartCardTests : BunitContext, IAsyncLifetime
{
    public CliQuickstartCardTests()
    {
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;
    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    [Fact]
    public void Renders_title_and_three_commands()
    {
        IRenderedComponent<CliQuickstartCard> cut = Render<CliQuickstartCard>();

        cut.Markup.Should().Contain("CLI quickstart");
        cut.FindAll(".cli-text").Select(e => e.TextContent).Should().Equal(
            "ahkflow hotstring new --trigger \"yw\" --replacement \"you're welcome\" --profile work",
            "ahkflow hotstring list --profile work --grep \"typo\"",
            "ahkflow download ahk --profile work");
        cut.Find("[data-test=\"cli-profile-hint\"]").TextContent
            .Should().Be("Replace work with an existing profile name.");
    }

    // Backlog 197. The card once printed "ahkflow new" and "ahkflow list", which the CLI does not
    // define. Every printed line must parse against the CLI's own command tree with no error. A
    // group such as "hotstring" alone is an error too, so no error means the line reaches a command
    // with an action. This proves command-tree compatibility only, not that the command succeeds:
    // an action checks some options itself, and sign-in, profiles and the API are outside a parse.
    // Parsing never runs an action, and only actions read services, so an empty provider is enough.
    [Fact]
    public void Every_printed_command_parses_against_the_cli_command_tree()
    {
        IRenderedComponent<CliQuickstartCard> cut = Render<CliQuickstartCard>();
        string[] printed = [.. cut.FindAll(".cli-text").Select(e => e.TextContent)];
        string? executable = typeof(RootCli).Assembly.GetName().Name;
        RootCommand root = RootCli.Build(new ServiceCollection().BuildServiceProvider());

        printed.Should().NotBeEmpty();
        using (new AssertionScope())
        {
            foreach (string line in printed)
            {
                string[] tokens = [.. CommandLineParser.SplitCommandLine(line)];
                tokens.FirstOrDefault().Should().Be(executable, "'{0}' must start with the CLI's name", line);

                string[] args = [.. tokens.Skip(1)];
                ParseResult result = root.Parse(args);
                result.Errors.Select(e => e.Message).Should().BeEmpty("'{0}' must parse against the CLI", line);
                result.CommandResult.Command.Action.Should().NotBeNull("'{0}' must reach a command with an action", line);
            }
        }
    }

    // An owner runs what the button copies, so each line needs its own button, and each button
    // must copy the line it sits beside.
    [Fact]
    public async Task Each_copy_button_copies_the_command_beside_it()
    {
        IRenderedComponent<CliQuickstartCard> cut = Render<CliQuickstartCard>();
        string[] printed = [.. cut.FindAll(".cli-text").Select(e => e.TextContent)];
        printed.Should().NotBeEmpty();
        cut.FindAll("button.cli-copy-btn").Should().HaveCount(printed.Length);

        foreach (int index in Enumerable.Range(0, printed.Length))
        {
            await cut.InvokeAsync(() => cut.FindAll("button.cli-copy-btn")[index].Click());
        }

        JSInterop.VerifyInvoke("navigator.clipboard.writeText", calledTimes: printed.Length);
        JSInterop.Invocations["navigator.clipboard.writeText"]
            .Select(invocation => (string?)invocation.Arguments[0])
            .Should().Equal(printed);
    }
}
