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

    // The literal table above only catches renumbering of a value both enums already have; a value
    // added to one side alone leaves every hand-written table green while the wire silently
    // mismatches. This compares the two enums directly — the domain assembly is a transitive
    // reference here — so neither side can grow, shrink, or rename without the other.
    [Fact]
    public void MirrorsDomainEnum_NameAndOrdinal() =>
        Enum.GetValues<WindowOp>().Select(op => (op.ToString(), (int)op))
            .Should().BeEquivalentTo(
                Enum.GetValues<AHKFlowApp.Domain.Enums.WindowOp>().Select(op => (op.ToString(), (int)op)));
}
