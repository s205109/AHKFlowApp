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

    private static HotstringDto DateTimeHotstring(
        string? dateTimeFormat = "yyyy-MM-dd",
        int? dateOffsetAmount = null,
        DateOffsetUnit? dateOffsetUnit = null,
        string trigger = "ddate") =>
        new(Guid.NewGuid(),
            [],
            true,
            trigger,
            string.Empty,
            true,
            true,
            FixedTime,
            FixedTime,
            HotstringKind.DateTime,
            DateTimeFormat: dateTimeFormat,
            DateOffsetAmount: dateOffsetAmount,
            DateOffsetUnit: dateOffsetUnit);

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

    [Fact]
    public void Write_RendersKindColumn()
    {
        StringWriter sw = new();
        PagedList<HotstringDto> page = new([Hotstring()], 1, 50, 1);

        HotstringTableFormatter.Write(sw, page, new Dictionary<Guid, string>());

        sw.ToString().Should().Contain("Kind");
        sw.ToString().Should().Contain("Text");
    }

    [Fact]
    public void Write_DateTimeRow_NoOffset_RendersRawFormat()
    {
        StringWriter sw = new();
        PagedList<HotstringDto> page = new([DateTimeHotstring(dateTimeFormat: "yyyy-MM-dd")], 1, 50, 1);

        HotstringTableFormatter.Write(sw, page, EmptyNames);

        sw.ToString().Should().Contain("yyyy-MM-dd");
    }

    [Fact]
    public void Write_DateTimeRow_PositiveOffset_RendersPluralWithSign()
    {
        StringWriter sw = new();
        PagedList<HotstringDto> page = new(
            [DateTimeHotstring(dateTimeFormat: "yyyy-MM-dd", dateOffsetAmount: 7, dateOffsetUnit: DateOffsetUnit.Days)],
            1, 50, 1);

        HotstringTableFormatter.Write(sw, page, EmptyNames);

        sw.ToString().Should().Contain("yyyy-MM-dd (+7 days)");
    }

    [Fact]
    public void Write_DateTimeRow_NegativeOffset_RendersPluralWithSign()
    {
        StringWriter sw = new();
        PagedList<HotstringDto> page = new(
            [DateTimeHotstring(dateTimeFormat: "dddd d MMMM yyyy", dateOffsetAmount: -2, dateOffsetUnit: DateOffsetUnit.Hours)],
            1, 50, 1);

        HotstringTableFormatter.Write(sw, page, EmptyNames);

        sw.ToString().Should().Contain("dddd d MMMM yyyy (-2 hours)");
    }

    [Theory]
    [InlineData(1, "day")]
    [InlineData(-1, "hour")]
    public void Write_DateTimeRow_SingularOffset_RendersSingularUnit(int amount, string expectedUnit)
    {
        DateOffsetUnit unit = expectedUnit.Contains("day")
            ? DateOffsetUnit.Days
            : DateOffsetUnit.Hours;
        StringWriter sw = new();
        PagedList<HotstringDto> page = new(
            [DateTimeHotstring(dateTimeFormat: "yyyy-MM-dd", dateOffsetAmount: amount, dateOffsetUnit: unit)],
            1, 50, 1);

        HotstringTableFormatter.Write(sw, page, EmptyNames);

        string sign = amount < 0 ? "-" : "+";
        sw.ToString().Should().Contain($"({sign}{Math.Abs(amount)} {expectedUnit})");
    }

    [Fact]
    public void Write_DateTimeRow_ZeroOffset_RendersPluralNotSingular()
    {
        StringWriter sw = new();
        PagedList<HotstringDto> page = new(
            [DateTimeHotstring(dateTimeFormat: "yyyy-MM-dd", dateOffsetAmount: 0, dateOffsetUnit: DateOffsetUnit.Days)],
            1, 50, 1);

        HotstringTableFormatter.Write(sw, page, EmptyNames);

        sw.ToString().Should().Contain("(+0 days)");
    }

    [Fact]
    public void Write_DateTimeRow_NullFormat_RendersEmDash()
    {
        StringWriter sw = new();
        PagedList<HotstringDto> page = new([DateTimeHotstring(dateTimeFormat: null)], 1, 50, 1);

        HotstringTableFormatter.Write(sw, page, EmptyNames);

        sw.ToString().Should().Contain("—");
    }

    [Fact]
    public void Write_TextRow_UnchangedReplacementRendering()
    {
        StringWriter sw = new();
        PagedList<HotstringDto> page = new([Hotstring(replacement: "by the way")], 1, 50, 1);

        HotstringTableFormatter.Write(sw, page, EmptyNames);

        sw.ToString().Should().Contain("by the way");
    }

    [Theory]
    [InlineData(DateOffsetUnit.Seconds, "seconds")]
    [InlineData(DateOffsetUnit.Minutes, "minutes")]
    [InlineData(DateOffsetUnit.Hours, "hours")]
    [InlineData(DateOffsetUnit.Days, "days")]
    public void Write_DateTimeRow_AllUnits_RenderLowercaseName(DateOffsetUnit unit, string expected)
    {
        StringWriter sw = new();
        PagedList<HotstringDto> page = new(
            [DateTimeHotstring(dateTimeFormat: "yyyy-MM-dd", dateOffsetAmount: 3, dateOffsetUnit: unit)],
            1, 50, 1);

        HotstringTableFormatter.Write(sw, page, EmptyNames);

        sw.ToString().Should().Contain($"3 {expected}");
    }

    [Fact]
    public void Write_MacroRow_RendersKindLabelAndRawTruncatedTokenReplacement()
    {
        // Pinning test: Macro kind has no special formatter handling — it falls through to the
        // same raw Truncate(...) path as Text (FormatReplacementColumn only special-cases DateTime).
        // The 41-char input exceeds ReplacementWidth (40), so Truncate cuts to 39 chars + "…".
        const string macroReplacement = "<b>{{cursor}}</b>{{key:Enter}}{{key:Tab}}";
        const string expectedTruncated = "<b>{{cursor}}</b>{{key:Enter}}{{key:Tab…";
        StringWriter sw = new();
        PagedList<HotstringDto> page = new(
            [Hotstring(trigger: "htag", replacement: macroReplacement) with { Kind = HotstringKind.Macro }],
            1, 50, 1);

        HotstringTableFormatter.Write(sw, page, EmptyNames);

        string output = sw.ToString();
        output.Should().Contain("Macro");
        output.Should().Contain(expectedTruncated);
        output.Should().NotContain(macroReplacement);
    }
}
