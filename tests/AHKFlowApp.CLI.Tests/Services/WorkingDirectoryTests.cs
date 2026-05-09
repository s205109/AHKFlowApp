using AHKFlowApp.CLI.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Services;

public sealed class WorkingDirectoryTests
{
    [Fact]
    public void Get_WithCustomFactory_ReturnsFactoryValue()
    {
        WorkingDirectory sut = new(() => "/tmp/test");

        sut.Get().Should().Be("/tmp/test");
    }

    [Fact]
    public void Get_DefaultFactory_ReturnsEnvironmentCurrentDirectory()
    {
        WorkingDirectory sut = new();

        sut.Get().Should().Be(Environment.CurrentDirectory);
    }
}
