using System.Globalization;
using System.Threading;
using AHKFlowApp.Application.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Services;

public sealed class HeaderTokenRendererTests
{
    private static readonly DateTimeOffset s_fixedTime =
        DateTimeOffset.Parse("2026-05-19T14:35:42Z", CultureInfo.InvariantCulture);

    private static HeaderTokenRenderer NewSut() => new();

    private static HeaderTokenRenderer.Context Ctx(
        string profileName = "Work",
        string appVersion = "1.2.3",
        int hotstrings = 12,
        int hotkeys = 12,
        DateTimeOffset? generatedAt = null) =>
        new(profileName, appVersion, hotstrings, hotkeys, generatedAt ?? s_fixedTime);

    [Fact]
    public void Substitutes_ProfileName()
    {
        NewSut().Render("Hello {ProfileName}", Ctx()).Should().Be("Hello Work");
    }

    [Fact]
    public void Substitutes_AppVersion()
    {
        NewSut().Render("v{AppVersion}", Ctx(appVersion: "9.9.9")).Should().Be("v9.9.9");
    }

    [Fact]
    public void Substitutes_HotstringCount_HotkeyCount()
    {
        NewSut().Render("{HotstringCount}h {HotkeyCount}k", Ctx(hotstrings: 7, hotkeys: 4))
            .Should().Be("7h 4k");
    }

    [Fact]
    public void Substitutes_GeneratedAt_DefaultFormat_o()
    {
        string expected = s_fixedTime.ToString("o", CultureInfo.InvariantCulture);
        NewSut().Render("at {GeneratedAt}", Ctx()).Should().Be($"at {expected}");
    }

    [Fact]
    public void Substitutes_GeneratedAt_CustomFormat()
    {
        NewSut().Render("{GeneratedAt:yyyy-MM-dd HH:mm}", Ctx())
            .Should().Be("2026-05-19 14:35");
    }

    [Fact]
    public void Preserves_UnknownTokens()
    {
        NewSut().Render("{Nope} {ProfileName}", Ctx()).Should().Be("{Nope} Work");
    }

    [Fact]
    public void EscapesLiteralBraces_DoubledOpenAndClose()
    {
        NewSut().Render("{{not a token}}", Ctx()).Should().Be("{not a token}");
    }

    [Fact]
    public void EscapeAdjacentToToken()
    {
        NewSut().Render("{{ {ProfileName} }}", Ctx()).Should().Be("{ Work }");
    }

    [Fact]
    public void Empty_ReturnsEmpty()
    {
        NewSut().Render("", Ctx()).Should().Be("");
    }

    [Fact]
    public void Renders_Multiline_Header()
    {
        string template = """
            ; {ProfileName} v{AppVersion}
            ; {HotstringCount} hotstrings
            ; {GeneratedAt:yyyy-MM-dd}
            """;
        string expected = """
            ; Work v1.2.3
            ; 12 hotstrings
            ; 2026-05-19
            """;
        NewSut().Render(template, Ctx()).Should().Be(expected);
    }

    [Fact]
    public void Uses_InvariantCulture_For_GeneratedAt()
    {
        CultureInfo original = Thread.CurrentThread.CurrentCulture;
        try
        {
            Thread.CurrentThread.CurrentCulture = new CultureInfo("de-DE");
            string rendered = NewSut().Render("{GeneratedAt:dd MMMM yyyy}", Ctx());
            // German would render "Mai"; invariant must render "May".
            rendered.Should().Be("19 May 2026");
        }
        finally
        {
            Thread.CurrentThread.CurrentCulture = original;
        }
    }

    [Fact]
    public void Renders_When_NoBraces_AtAll()
    {
        NewSut().Render("plain content", Ctx()).Should().Be("plain content");
    }

    [Fact]
    public void SubstitutedValue_ContainingDoubleBraces_IsNotCollapsed()
    {
        // ProfileName contains {{ — pass-2-style post-processing would corrupt it.
        NewSut().Render("{ProfileName}", Ctx(profileName: "A{{B}}C")).Should().Be("A{{B}}C");
    }
}
