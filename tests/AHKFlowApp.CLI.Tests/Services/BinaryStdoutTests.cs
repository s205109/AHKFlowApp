using AHKFlowApp.CLI.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Services;

public sealed class BinaryStdoutTests
{
    [Fact]
    public void Open_WithCustomFactory_ReturnsFactoryStream()
    {
        using MemoryStream ms = new();
        BinaryStdout sut = new(() => ms);

        Stream result = sut.Open();

        result.Should().BeSameAs(ms);
    }

    [Fact]
    public void Open_DefaultFactory_ReturnsConsoleStdout()
    {
        BinaryStdout sut = new();

        Stream result = sut.Open();

        result.Should().NotBeNull();
        result.CanWrite.Should().BeTrue();
    }
}
