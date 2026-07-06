using AHKFlowApp.Application.DTOs;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

[Trait("Category", "Unit")]
public sealed class HotstringImportRowStatusTests
{
    [Theory]
    [InlineData(HotstringImportRowStatus.Ready, 0)]
    [InlineData(HotstringImportRowStatus.Warning, 1)]
    [InlineData(HotstringImportRowStatus.Duplicate, 2)]
    [InlineData(HotstringImportRowStatus.Invalid, 3)]
    public void OrdinalValue_MatchesUiMirror(HotstringImportRowStatus status, int expected)
    {
        // HotstringImportRowStatus is serialized as an int and hand-mirrored in
        // AHKFlowApp.UI.Blazor.DTOs.HotstringImportRowStatus — these ordinals must
        // stay in lockstep with that file's HotstringImportRowStatusTests.
        ((int)status).Should().Be(expected);
    }
}
