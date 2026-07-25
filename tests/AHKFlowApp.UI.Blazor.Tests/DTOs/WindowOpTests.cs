using AHKFlowApp.UI.Blazor.DTOs;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.DTOs;

public sealed class WindowOpTests
{
    [Theory]
    [InlineData(WindowOp.Minimize, 0)]
    [InlineData(WindowOp.Maximize, 1)]
    [InlineData(WindowOp.Restore, 2)]
    [InlineData(WindowOp.Close, 3)]
    [InlineData(WindowOp.ToggleAlwaysOnTop, 4)]
    [InlineData(WindowOp.SnapLeft, 5)]
    [InlineData(WindowOp.SnapRight, 6)]
    public void OrdinalValue_MatchesBackendMirror(WindowOp op, int expected)
    {
        // WindowOp is deserialized from an int and hand-mirrors
        // AHKFlowApp.Domain.Enums.WindowOp — these ordinals must stay in lockstep with that file.
        ((int)op).Should().Be(expected);
    }
}
