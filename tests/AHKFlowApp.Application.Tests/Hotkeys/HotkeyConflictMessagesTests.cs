using AHKFlowApp.Application.Commands.Hotkeys;
using AHKFlowApp.Domain.Enums;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotkeys;

public sealed class HotkeyConflictMessagesTests
{
    [Fact]
    public void Duplicate_NoContext_SaysAllWindows()
    {
        string message = HotkeyConflictMessages.Duplicate(null, null);

        message.Should().Be("A hotkey with this key + modifier combination already exists for all windows.");
    }

    [Fact]
    public void Duplicate_Executable_NamesTheProgram()
    {
        string message = HotkeyConflictMessages.Duplicate(WindowMatchType.Executable, "notepad.exe");

        message.Should().Be("A hotkey with this key + modifier combination already exists for \"notepad.exe\".");
    }

    [Fact]
    public void Duplicate_WindowClass_NamesTheWindowClass()
    {
        string message = HotkeyConflictMessages.Duplicate(WindowMatchType.WindowClass, "Notepad");

        message.Should().Be(
            "A hotkey with this key + modifier combination already exists for the window class \"Notepad\".");
    }

    [Fact]
    public void Duplicate_TitleContains_NamesTheTitleText()
    {
        string message = HotkeyConflictMessages.Duplicate(WindowMatchType.TitleContains, "Untitled");

        message.Should().Be(
            "A hotkey with this key + modifier combination already exists for windows with \"Untitled\" in the title.");
    }

    [Fact]
    public void Duplicate_UnknownMatchType_FallsBackToAGenericMessage()
    {
        string message = HotkeyConflictMessages.Duplicate((WindowMatchType)99, "whatever");

        message.Should().Be(
            "A hotkey with this key + modifier combination already exists in the same window context.");
    }
}
