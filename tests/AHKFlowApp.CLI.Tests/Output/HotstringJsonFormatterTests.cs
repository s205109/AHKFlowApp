using AHKFlowApp.CLI.Output;
using AHKFlowApp.CLI.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Output;

public sealed class HotstringJsonFormatterTests
{
    [Fact]
    public void WriteSingle_EmitsCamelCaseIndentedJson()
    {
        HotstringDto dto = new(
            Guid.Parse("11111111-1111-1111-1111-111111111111"),
            [],
            true,
            "btw",
            "by the way",
            true,
            true,
            new DateTimeOffset(2026, 5, 8, 12, 0, 0, TimeSpan.Zero),
            new DateTimeOffset(2026, 5, 8, 12, 0, 0, TimeSpan.Zero));

        StringWriter sw = new();
        HotstringJsonFormatter.WriteSingle(sw, dto);

        string output = sw.ToString();
        output.Should().Contain("\"appliesToAllProfiles\": true");
        output.Should().Contain("\"trigger\": \"btw\"");
        output.Should().Contain("\n");
    }

    [Fact]
    public void WritePage_RoundtripsToPagedList()
    {
        PagedList<HotstringDto> page = new(
            [],
            Page: 1,
            PageSize: 50,
            TotalCount: 0);

        StringWriter sw = new();
        HotstringJsonFormatter.WritePage(sw, page);

        PagedList<HotstringDto>? roundtrip = System.Text.Json.JsonSerializer.Deserialize<PagedList<HotstringDto>>(
            sw.ToString(), System.Text.Json.JsonSerializerOptions.Web);
        roundtrip.Should().NotBeNull();
        roundtrip!.TotalCount.Should().Be(0);
    }
}
