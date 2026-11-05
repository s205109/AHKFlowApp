using AHKFlowApp.UI.Blazor.Helpers;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Helpers;

// Backlog 169: a bulk delete of one row read "Delete 1 hotstring(s)? You can restore them",
// and "1 were already gone". Each method picks the singular for one item.
public sealed class BulkDeleteWordingTests
{
    [Theory]
    [InlineData(1, "Delete hotstring?")]
    [InlineData(3, "Delete hotstrings?")]
    public void Title_UsesTheSingularOnlyForOne(int count, string expected) =>
        BulkDeleteWording.Title(count, "hotstring", "hotstrings").Should().Be(expected);

    [Theory]
    [InlineData(1, "Delete 1 hotstring? You can restore it from the Recycle Bin.")]
    [InlineData(3, "Delete 3 hotstrings? You can restore them from the Recycle Bin.")]
    public void Message_UsesTheSingularOnlyForOne(int count, string expected) =>
        BulkDeleteWording.Message(count, "hotstring", "hotstrings").Should().Be(expected);

    [Theory]
    [InlineData(1, 0, "Deleted 1 hotstring.")]
    [InlineData(2, 0, "Deleted 2 hotstrings.")]
    [InlineData(2, 1, "Deleted 2 hotstrings. 1 was already gone.")]
    [InlineData(1, 2, "Deleted 1 hotstring. 2 were already gone.")]
    [InlineData(0, 1, "Deleted 0 hotstrings. 1 was already gone.")]
    public void ResultMessage_UsesTheSingularOnlyForOne(int deleted, int missing, string expected) =>
        BulkDeleteWording.ResultMessage(deleted, missing, "hotstring", "hotstrings").Should().Be(expected);
}
