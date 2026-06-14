using AHKFlowApp.Launcher;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Launcher;

public sealed class DockerSqlControlTests
{
    [Fact]
    public void BuildStopArguments_ProducesComposeStopForProject()
    {
        IReadOnlyList<string> arguments = DockerSqlControl.BuildStopArguments(
            repoRoot: @"C:\repo",
            composeProject: "ahkflowapp");

        arguments.Should().Equal(
            "compose",
            "-f", Path.Combine(@"C:\repo", "docker-compose.yml"),
            "-p", "ahkflowapp",
            "stop");
    }
}
