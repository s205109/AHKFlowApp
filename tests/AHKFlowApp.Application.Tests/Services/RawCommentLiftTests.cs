using AHKFlowApp.Application.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Services;

public sealed class RawCommentLiftTests
{
    [Fact]
    public void Merge_EmptyDescription_UsesLifted()
    {
        RawCommentLift.Merge(null, "moved comment").Should().Be("moved comment");
    }

    [Fact]
    public void Merge_WhitespaceDescription_UsesLifted()
    {
        RawCommentLift.Merge("   ", "moved comment").Should().Be("moved comment");
    }

    [Fact]
    public void Merge_EqualDescription_DropsDuplicate()
    {
        RawCommentLift.Merge("same note", "same note").Should().Be("same note");
    }

    [Fact]
    public void Merge_DifferingDescription_AppendsOnNewLine()
    {
        RawCommentLift.Merge("existing", "lifted").Should().Be("existing\nlifted");
    }

    [Fact]
    public void Merge_NoLifted_ReturnsTrimmedDescription()
    {
        RawCommentLift.Merge("  keep  ", null).Should().Be("keep");
    }

    [Fact]
    public void Merge_BothEmpty_ReturnsNull()
    {
        RawCommentLift.Merge(null, null).Should().BeNull();
    }
}
