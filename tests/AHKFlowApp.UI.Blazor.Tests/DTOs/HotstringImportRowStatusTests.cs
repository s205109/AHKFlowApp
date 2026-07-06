using AHKFlowApp.UI.Blazor.DTOs;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.DTOs;

public sealed class HotstringImportRowStatusTests
{
    [Theory]
    [InlineData(HotstringImportRowStatus.Ready, 0)]
    [InlineData(HotstringImportRowStatus.Warning, 1)]
    [InlineData(HotstringImportRowStatus.Duplicate, 2)]
    [InlineData(HotstringImportRowStatus.Invalid, 3)]
    public void OrdinalValue_MatchesBackendMirror(HotstringImportRowStatus status, int expected)
    {
        // HotstringImportRowStatus is deserialized from an int and hand-mirrors
        // AHKFlowApp.Application.DTOs.HotstringImportRowStatus — these ordinals must
        // stay in lockstep with that file's HotstringImportRowStatusTests.
        ((int)status).Should().Be(expected);
    }
}
