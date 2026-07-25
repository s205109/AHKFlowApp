using AHKFlowApp.Application.Constants;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Constants;

public sealed class HotkeyKeysRemapRolesTests
{
    [Theory]
    [InlineData("CapsLock")]   // golden 13 source
    [InlineData("RAlt")]       // golden 14 source
    [InlineData("a")]
    [InlineData("vk1B")]
    public void IsValidRemapSource_RemappableKeyOrCode_IsTrue(string key)
    {
        HotkeyKeys.IsValidRemapSource(key).Should().BeTrue();
    }

    [Theory]
    [InlineData("Ctrl")]       // golden 13 dest
    [InlineData("a")]
    [InlineData("Escape")]
    [InlineData("vk1B")]
    public void IsValidRemapDest_RemappableKeyOrCode_IsTrue(string key)
    {
        HotkeyKeys.IsValidRemapDest(key).Should().BeTrue();
    }

    [Fact]
    public void IsValidRemapDest_Pause_IsFalse()
    {
        // Pause collides with the built-in Pause function name; a remap must target vk13 instead.
        HotkeyKeys.IsValidRemapDest("Pause").Should().BeFalse();
        HotkeyKeys.IsValidRemapDest("vk13").Should().BeTrue();
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("NotAKey")]
    [InlineData("{Ctrl}")]     // braces are not a remap dest
    public void IsValidRemapDest_UnknownOrBraced_IsFalse(string? key)
    {
        HotkeyKeys.IsValidRemapDest(key).Should().BeFalse();
    }

    [Fact]
    public void All_ModifierKeysCanBeRemapSourceAndDest()
    {
        HotkeyKeys.HotkeyKeyEntryByCanonical("RAlt").Roles.Should().HaveFlag(HotkeyKeyRoles.RemapSource);
        HotkeyKeys.HotkeyKeyEntryByCanonical("Ctrl").Roles.Should().HaveFlag(HotkeyKeyRoles.RemapDest);
    }

    [Fact]
    public void TryCanonicalize_ModifierAlias_Resolves()
    {
        HotkeyKeys.TryCanonicalize("Control", out string c).Should().BeTrue();
        c.Should().Be("Ctrl");
    }
}
