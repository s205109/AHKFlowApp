using AHKFlowApp.Domain.Enums;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Domain.Tests.Enums;

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
    public void OrdinalValue_MatchesUiMirror(WindowOp op, int expected)
    {
        // WindowOp is persisted as an int and hand-mirrored in
        // AHKFlowApp.UI.Blazor.DTOs.WindowOp — these ordinals must stay in lockstep with
        // that file's WindowOpTests. Renumbering here silently rewrites stored rows.
        ((int)op).Should().Be(expected);
    }
}
