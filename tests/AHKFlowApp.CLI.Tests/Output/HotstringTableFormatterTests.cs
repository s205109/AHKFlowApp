using AHKFlowApp.CLI.Output;
using AHKFlowApp.CLI.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Output;

public sealed class HotstringTableFormatterTests
{
    private static readonly DateTimeOffset FixedTime = new(2026, 5, 8, 12, 0, 0, TimeSpan.Zero);
    private static readonly Dictionary<Guid, string> EmptyNames = [];

    private static HotstringDto Hotstring(
        string trigger = "btw",
        string replacement = "by the way",
        Guid[]? profileIds = null,
        bool appliesToAll = true) =>
        new(Guid.NewGuid(),
            profileIds ?? [],
            appliesToAll,
            trigger,
            replacement,
            true,
            true,
            FixedTime,
            FixedTime);

    [Fact]
    public void Write_EmptyPage_WritesPlaceholderOnly()
    {
        StringWriter sw = new();
        PagedList<HotstringDto> page = new([], 1, 50, 0);

        HotstringTableFormatter.Write(sw, page, EmptyNames);

        sw.ToString().Should().Be("No hotstrings found." + Environment.NewLine);
    }

    [Fact]
    public void Write_AppliesToAll_RendersAllInProfilesColumn()
    {
        StringWriter sw = new();
        PagedList<HotstringDto> page = new([Hotstring()], 1, 50, 1);

        HotstringTableFormatter.Write(sw, page, EmptyNames);

        sw.ToString().Should().Contain(" all ");
    }

    [Fact]
    public void Write_ThreeProfilesResolved_JoinedByComma()
    {
        Guid a = Guid.NewGuid(), b = Guid.NewGuid(), c = Guid.NewGuid();
        Dictionary<Guid, string> names = new() { [a] = "Work", [b] = "Home", [c] = "Side" };
        StringWriter sw = new();
        PagedList<HotstringDto> page = new(
            [Hotstring(profileIds: [a, b, c], appliesToAll: false)], 1, 50, 1);

        HotstringTableFormatter.Write(sw, page, names);

        sw.ToString().Should().Contain("Work, Home, Side");
        sw.ToString().Should().NotContain("more");
    }

    [Fact]
    public void Write_FiveProfiles_ShowsThreePlusNMore()
    {
        Guid[] ids = [Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid()];
        var names = ids.Select((g, i) => (g, $"P{i}"))
            .ToDictionary(t => t.g, t => t.Item2);
        StringWriter sw = new();
        PagedList<HotstringDto> page = new(
            [Hotstring(profileIds: ids, appliesToAll: false)], 1, 50, 1);

        HotstringTableFormatter.Write(sw, page, names);

        sw.ToString().Should().Contain("+2 more");
    }

    [Fact]
    public void Write_LongProfilesString_TruncatedWithEllipsis()
    {
        Guid a = Guid.NewGuid(), b = Guid.NewGuid(), c = Guid.NewGuid();
        Dictionary<Guid, string> names = new()
        {
            [a] = "VeryLongProfileNameOne",
            [b] = "VeryLongProfileNameTwo",
            [c] = "VeryLongProfileNameThree",
        };
        StringWriter sw = new();
        PagedList<HotstringDto> page = new(
            [Hotstring(profileIds: [a, b, c], appliesToAll: false)], 1, 50, 1);

        HotstringTableFormatter.Write(sw, page, names);

        sw.ToString().Should().Contain("…");
    }

    [Fact]
    public void Write_LongTrigger_TruncatedWithEllipsis()
    {
        StringWriter sw = new();
        PagedList<HotstringDto> page = new(
            [Hotstring(trigger: new string('x', 40))], 1, 50, 1);

        HotstringTableFormatter.Write(sw, page, EmptyNames);

        sw.ToString().Should().Contain("…");
    }

    [Fact]
    public void Write_SinglePage_OmitsFooter()
    {
        StringWriter sw = new();
        PagedList<HotstringDto> page = new([Hotstring()], 1, 50, 1);

        HotstringTableFormatter.Write(sw, page, EmptyNames);

        sw.ToString().Should().NotContain("Page ");
    }

    [Fact]
    public void Write_MultiplePages_ShowsFooter()
    {
        StringWriter sw = new();
        PagedList<HotstringDto> page = new([Hotstring()], 1, 1, 5);

        HotstringTableFormatter.Write(sw, page, EmptyNames);

        sw.ToString().Should().Contain("Page 1/5");
        sw.ToString().Should().Contain("--page N");
    }

    [Fact]
    public void Write_UpdatedColumn_FormattedAsLocalDateTime()
    {
        StringWriter sw = new();
        PagedList<HotstringDto> page = new([Hotstring()], 1, 50, 1);

        HotstringTableFormatter.Write(sw, page, EmptyNames);

        string expected = FixedTime.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss");
        sw.ToString().Should().Contain(expected);
    }
}
