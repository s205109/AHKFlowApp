using AHKFlowApp.Application.Constants;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Profiles;
using Ardalis.Result;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Profiles;

public sealed class ListHeaderPresetsQueryHandlerTests
{
    [Fact]
    public async Task ExecuteAsync_ReturnsEveryPresetInCatalogOrder()
    {
        ListHeaderPresetsQueryHandler handler = new();

        Result<HeaderPresetCatalogDto> result =
            await handler.ExecuteAsync(new ListHeaderPresetsQuery(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Presets.Select(p => p.Id)
            .Should().Equal(HeaderPresetCatalog.All.Select(p => p.Id));
    }

    [Fact]
    public async Task ExecuteAsync_CarriesEveryFieldOfAPreset()
    {
        ListHeaderPresetsQueryHandler handler = new();
        HeaderPreset expected = HeaderPresetCatalog.All[0];

        Result<HeaderPresetCatalogDto> result =
            await handler.ExecuteAsync(new ListHeaderPresetsQuery(), CancellationToken.None);

        HeaderPresetDto actual = result.Value.Presets[0];
        actual.Id.Should().Be(expected.Id);
        actual.Name.Should().Be(expected.Name);
        actual.Description.Should().Be(expected.Description);
        actual.Tag.Should().Be(expected.Tag);
        actual.Body.Should().Be(expected.Body);
    }
}
