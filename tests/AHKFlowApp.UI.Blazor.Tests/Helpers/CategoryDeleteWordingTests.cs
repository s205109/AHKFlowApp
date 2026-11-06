using AHKFlowApp.UI.Blazor.Helpers;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Helpers;

// Backlog 205: the confirmation said only "Delete "Code"? This cannot be undone.",
// and gave no sign that items lose the category.
public sealed class CategoryDeleteWordingTests
{
    [Theory]
    [InlineData(5, 2, "Delete \"Code\"? 5 hotstrings and 2 hotkeys use this category. They are not deleted, but they lose this category. This cannot be undone.")]
    [InlineData(1, 0, "Delete \"Code\"? 1 hotstring uses this category. It is not deleted, but it loses this category. This cannot be undone.")]
    [InlineData(0, 1, "Delete \"Code\"? 1 hotkey uses this category. It is not deleted, but it loses this category. This cannot be undone.")]
    [InlineData(1, 1, "Delete \"Code\"? 1 hotstring and 1 hotkey use this category. They are not deleted, but they lose this category. This cannot be undone.")]
    [InlineData(0, 3, "Delete \"Code\"? 3 hotkeys use this category. They are not deleted, but they lose this category. This cannot be undone.")]
    [InlineData(0, 0, "Delete \"Code\"? No hotstrings or hotkeys use this category. This cannot be undone.")]
    public void Message_SaysHowManyItemsLoseTheCategory(int hotstrings, int hotkeys, string expected) =>
        CategoryDeleteWording.Message("Code", hotstrings, hotkeys).Should().Be(expected);
}
