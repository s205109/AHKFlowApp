using AHKFlowApp.Application.Constants;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Constants;

public sealed class HotkeyKeysTests
{
    [Theory]
    [InlineData("a", "a")]
    [InlineData("A", "a")]
    [InlineData("F5", "F5")]
    [InlineData("f5", "F5")]
    [InlineData("Numpad0", "Numpad0")]
    [InlineData("Volume_Up", "Volume_Up")]
    public void TryCanonicalize_KnownKey_ReturnsCanonicalCasing(string input, string expected)
    {
        bool ok = HotkeyKeys.TryCanonicalize(input, out string canonical);

        ok.Should().BeTrue();
        canonical.Should().Be(expected);
    }

    [Theory]
    [InlineData("Esc", "Escape")]
    [InlineData("Return", "Enter")]
    [InlineData("Del", "Delete")]
    [InlineData("Ins", "Insert")]
    [InlineData("BS", "Backspace")]
    public void TryCanonicalize_Alias_ResolvesToCanonicalName(string alias, string expected)
    {
        bool ok = HotkeyKeys.TryCanonicalize(alias, out string canonical);

        ok.Should().BeTrue();
        canonical.Should().Be(expected);
    }

    [Theory]
    [InlineData("vk1B", "vk1b")]
    [InlineData("VK1B", "vk1b")]
    [InlineData("vk1", "vk01")]
    [InlineData("sc001", "sc001")]
    [InlineData("SC01F", "sc01f")]
    [InlineData("sc1", "sc001")]
    [InlineData("sc1F", "sc01f")]
    [InlineData("vkFF", "vkff")]
    [InlineData("sc1FF", "sc1ff")]
    [InlineData("scFFF", "scfff")]
    public void TryCanonicalize_VkOrScCode_LowercasesAndPadsTheCode(string input, string expected)
    {
        bool ok = HotkeyKeys.TryCanonicalize(input, out string canonical);

        ok.Should().BeTrue();
        canonical.Should().Be(expected);
    }

    // AHK rejects "vk00::" / "sc000::" with "Invalid hotkey" — a zero code names no key.
    [Theory]
    [InlineData("vk0")]
    [InlineData("vk00")]
    [InlineData("VK00")]
    [InlineData("sc0")]
    [InlineData("sc00")]
    [InlineData("sc000")]
    public void TryCanonicalize_ZeroCode_IsRejected(string input)
    {
        bool ok = HotkeyKeys.TryCanonicalize(input, out _);

        ok.Should().BeFalse();
    }

    // .NET's $ also matches before a trailing newline; \z does not. A code that kept its LF
    // would split the emitted left-hand side across two script lines.
    [Theory]
    [InlineData("vk1\n")]
    [InlineData("sc1\n")]
    [InlineData("a\n")]
    [InlineData("F5\n")]
    public void TryCanonicalize_TrailingNewline_IsRejected(string input)
    {
        bool ok = HotkeyKeys.TryCanonicalize(input, out _);

        ok.Should().BeFalse();
    }

    [Fact]
    public void TryCanonicalize_CombinedVkAndSc_IsRejected()
    {
        bool ok = HotkeyKeys.TryCanonicalize("vk1Bsc001", out _);

        ok.Should().BeFalse();
    }

    [Theory]
    [InlineData("")]
    [InlineData(null)]
    [InlineData("NotAKey")]
    [InlineData("vk")]
    [InlineData("vkZZ")]
    [InlineData("sc12345")]
    [InlineData("Joy1")]
    [InlineData(" a")]
    [InlineData("a ")]
    public void TryCanonicalize_UnknownOrMalformed_IsRejected(string? input)
    {
        bool ok = HotkeyKeys.TryCanonicalize(input, out _);

        ok.Should().BeFalse();
    }

    [Fact]
    public void All_HasNoDuplicateCanonicalNames()
    {
        HotkeyKeys.All.Select(e => e.Canonical)
            .Should().OnlyHaveUniqueItems();
    }

    [Fact]
    public void All_EveryEntryIsUsableAsAHotkeyKey()
    {
        HotkeyKeys.All.Should().OnlyContain(e => e.Roles.HasFlag(HotkeyKeyRoles.HotkeyKey));
    }

    [Fact]
    public void All_NamedKeysRequireBracesInSend_LettersDoNot()
    {
        HotkeyKeys.All.Single(e => e.Canonical == "Volume_Up")
            .RequiresBracesInSend.Should().BeTrue();

        HotkeyKeys.All.Single(e => e.Canonical == "a")
            .RequiresBracesInSend.Should().BeFalse();
    }
}
