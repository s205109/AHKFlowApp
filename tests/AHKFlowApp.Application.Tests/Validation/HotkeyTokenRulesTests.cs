using AHKFlowApp.Application.Validation;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Validation;

public sealed class HotkeyTokenRulesTests
{
    [Theory]
    [InlineData("^v")]                 // ctrl + printable, bare
    [InlineData("c")]                  // bare printable
    [InlineData("{Up}")]               // named key braced
    [InlineData("{Volume_Up}")]        // named key braced
    [InlineData("^!{Delete}")]         // modifiers + braced named
    [InlineData("+{Left}")]
    public void IsValidSendKeysContent_ValidToken_IsTrue(string token)
    {
        HotkeyRules.Tokens.IsValidSendKeysContent(token).Should().BeTrue();
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("Volume_Up")]          // named key MUST be braced
    [InlineData("*c")]                 // * is not a Send modifier
    [InlineData("^ab")]                // more than one key
    [InlineData("{{date:yyyy-MM-dd}}")]// macro leak — double brace
    [InlineData("{Up")]                // unbalanced brace
    [InlineData("^")]                  // modifiers with no key
    [InlineData("{NotAKey}")]          // braced unknown name
    public void IsValidSendKeysContent_InvalidToken_IsFalse(string? token)
    {
        HotkeyRules.Tokens.IsValidSendKeysContent(token).Should().BeFalse();
    }

    [Theory]
    [InlineData("Ctrl")]
    [InlineData("a")]
    [InlineData("vk1B")]
    public void IsValidRemapDest_Valid_IsTrue(string dest)
    {
        HotkeyRules.Tokens.IsValidRemapDest(dest).Should().BeTrue();
    }

    [Theory]
    [InlineData(null)]
    [InlineData("Pause")]              // built-in function name collision
    [InlineData("{Ctrl}")]             // no braces on a remap dest
    [InlineData("^a")]                 // no modifiers on a remap dest
    public void IsValidRemapDest_Invalid_IsFalse(string? dest)
    {
        HotkeyRules.Tokens.IsValidRemapDest(dest).Should().BeFalse();
    }
}
