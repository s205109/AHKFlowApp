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
        // WindowOp is persisted as an int, so renumbering here silently rewrites stored rows.
        // AHKFlowApp.UI.Blazor.DTOs.WindowOp hand-mirrors it; that the two agree on every name and
        // ordinal is enforced by WindowOpTests.MirrorsDomainEnum_NameAndOrdinal in
        // AHKFlowApp.UI.Blazor.Tests, which can see both enums. This table pins the numbers
        // themselves, which a mirror comparison alone cannot.
        ((int)op).Should().Be(expected);
    }
}
