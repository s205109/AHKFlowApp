using AHKFlowApp.UI.Blazor.Helpers;
using FluentAssertions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Helpers;

public sealed class DownloadFileNamesTests
{
    [Fact]
    public void Timestamp_formats_local_moment_as_sortable_stamp() =>
        DownloadFileNames.Timestamp(new DateTimeOffset(2026, 7, 26, 14, 5, 9, TimeSpan.FromHours(2)))
            .Should().Be("20260726_140509");

    [Fact]
    public void Timestamp_pads_single_digit_parts() =>
        DownloadFileNames.Timestamp(new DateTimeOffset(2026, 1, 2, 3, 4, 5, TimeSpan.Zero))
            .Should().Be("20260102_030405");

    [Fact]
    public void Timestamp_reads_the_clock_in_local_time()
    {
        FakeTimeProvider clock = new(new DateTimeOffset(2026, 7, 26, 12, 0, 0, TimeSpan.Zero));
        clock.SetLocalTimeZone(TimeZoneInfo.CreateCustomTimeZone("t", TimeSpan.FromHours(2), "t", "t"));

        DownloadFileNames.Timestamp(clock).Should().Be("20260726_140000");
    }
}
