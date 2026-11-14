using AHKFlowApp.UI.Blazor.Helpers;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Helpers;

public sealed class ProfileDeleteWordingTests
{
    // Backlog 210: the confirmation said only "Delete "Work"? This cannot be undone.",
    // and gave no sign that items would reach no script.
    [Theory]
    [InlineData(3, 1, "Delete \"Work\"? 3 hotstrings and 1 hotkey apply only to this profile. After the delete they apply to no profile, so no script contains them until you choose their profiles again. This cannot be undone.")]
    [InlineData(1, 0, "Delete \"Work\"? 1 hotstring applies only to this profile. After the delete it applies to no profile, so no script contains it until you choose its profiles again. This cannot be undone.")]
    [InlineData(0, 1, "Delete \"Work\"? 1 hotkey applies only to this profile. After the delete it applies to no profile, so no script contains it until you choose its profiles again. This cannot be undone.")]
    [InlineData(0, 2, "Delete \"Work\"? 2 hotkeys apply only to this profile. After the delete they apply to no profile, so no script contains them until you choose their profiles again. This cannot be undone.")]
    [InlineData(0, 0, "Delete \"Work\"? No hotstrings or hotkeys apply only to this profile. This cannot be undone.")]
    public void Confirmation_SaysHowManyItemsReachNoScript(int hotstrings, int hotkeys, string expected) =>
        ProfileDeleteWording.Confirmation("Work", hotstrings, hotkeys).Should().Be(expected);

    // Backlog 210: the snackbar said only "Profile deleted." after items lost their last profile.
    [Theory]
    [InlineData(3, 1, "Profile deleted. 3 hotstrings and 1 hotkey now apply to no profile.")]
    [InlineData(1, 0, "Profile deleted. 1 hotstring now applies to no profile.")]
    [InlineData(0, 0, "Profile deleted.")]
    public void Deleted_RepeatsTheCount(int hotstrings, int hotkeys, string expected) =>
        ProfileDeleteWording.Deleted(hotstrings, hotkeys).Should().Be(expected);
}
