using FluentAssertions;
using Xunit;
using FrontendTemplates = AHKFlowApp.UI.Blazor.Constants.DefaultProfileTemplates;
using ServerTemplates = AHKFlowApp.Domain.Constants.DefaultProfileTemplates;

namespace AHKFlowApp.UI.Blazor.Tests.Constants;

/// <summary>
/// The Blazor project references no backend project, so it keeps its own copy of the default
/// profile templates. These tests fail the build when the two copies stop matching. They compare
/// the text exactly, including line endings, because the copy is what a new profile stores.
/// </summary>
public sealed class DefaultProfileTemplatesParityTests
{
    [Fact]
    public void Header_MatchesTheServerCopy_Exactly()
    {
        FrontendTemplates.Header.Should().Be(ServerTemplates.Header);
    }

    [Fact]
    public void Footer_MatchesTheServerCopy_Exactly()
    {
        FrontendTemplates.Footer.Should().Be(ServerTemplates.Footer);
    }

    [Theory]
    [InlineData("#Requires AutoHotkey v2.0")]
    [InlineData("#SingleInstance Force")]
    [InlineData("SendMode \"Input\"")]
    [InlineData("SetTitleMatchMode 2")]
    public void Header_CarriesTheDirectiveTheItemNames(string directive)
    {
        FrontendTemplates.Header.Should().Contain(directive);
    }
}
