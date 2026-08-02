using AHKFlowApp.Application.Constants;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Constants;

/// <summary>
/// Pins the seven rows that used to be authored as legacy (action, parameters) pairs. The only
/// other suite that reads the catalog is Integration-only, and it asserts emitted text — which
/// cannot catch a wrong <see cref="RunTargetKind"/>, because the emitter never reads it.
/// </summary>
public sealed class DefaultHotkeyCatalogTests
{
    private static readonly Guid OwnerOid = Guid.Parse("11111111-1111-1111-1111-111111111111");

    private static HotkeyDefinition Definition(string description) =>
        DefaultHotkeyCatalog.All
            .Select(s => s.Definition)
            .Single(d => d.Description == description);

    private static string Emit(HotkeyDefinition definition) =>
        HotkeyEmitter.Emit(Hotkey.Create(OwnerOid, definition, TimeProvider.System));

    [Theory]
    [InlineData("Launch Windows Terminal", "T", "wt.exe", RunTargetKind.Application, "^!T::Run(\"wt.exe\")")]
    [InlineData("Launch Notepad", "N", "notepad.exe", RunTargetKind.Application, "^!N::Run(\"notepad.exe\")")]
    [InlineData("Launch File Explorer", "E", "explorer.exe", RunTargetKind.Application, "^!E::Run(\"explorer.exe\")")]
    [InlineData("Open default browser", "B", "https://", RunTargetKind.Url, "^!B::Run(\"https://\")")]
    [InlineData("Lock workstation", "L", "rundll32.exe user32.dll,LockWorkStation",
        RunTargetKind.Application, "^!L::Run(\"rundll32.exe user32.dll,LockWorkStation\")")]
    public void RunRow_HasTypedColumnsAndEmitsUnchanged(
        string description, string key, string target, RunTargetKind targetKind, string expectedLine)
    {
        HotkeyDefinition definition = Definition(description);

        definition.ActionKind.Should().Be(HotkeyActionKind.Run);
        definition.Key.Should().Be(key);
        definition.RunTarget.Should().Be(target);
        // The emitter never reads RunTargetKind, so only this assertion can catch a wrong kind.
        definition.RunTargetKind.Should().Be(targetKind);
        definition.SendKeysContent.Should().BeNull();
        definition.Body.Should().BeNull();
        definition.Ctrl.Should().BeTrue();
        definition.Alt.Should().BeTrue();
        definition.Shift.Should().BeFalse();
        definition.Win.Should().BeFalse();
        definition.AppliesToAllProfiles.Should().BeTrue();

        Emit(definition).Should().Be(expectedLine);
    }

    [Theory]
    [InlineData("Play / pause media", "p", "{Media_Play_Pause}", "$^!p::Send(\"{Media_Play_Pause}\")")]
    [InlineData("Select to end of line", "k", "+{End}", "$^!k::Send(\"+{End}\")")]
    public void SendKeysRow_HasTypedColumnsAndEmitsUnchanged(
        string description, string key, string content, string expectedLine)
    {
        HotkeyDefinition definition = Definition(description);

        definition.ActionKind.Should().Be(HotkeyActionKind.SendKeys);
        definition.Key.Should().Be(key);
        definition.SendKeysContent.Should().Be(content);
        definition.RunTarget.Should().BeNull();
        definition.RunTargetKind.Should().BeNull();
        definition.Body.Should().BeNull();
        definition.Ctrl.Should().BeTrue();
        definition.Alt.Should().BeTrue();
        definition.Shift.Should().BeFalse();
        definition.Win.Should().BeFalse();
        definition.AppliesToAllProfiles.Should().BeTrue();

        Emit(definition).Should().Be(expectedLine);
    }

    [Fact]
    public void EverySample_AppliesToAllProfiles()
    {
        // Derived from the source rather than a hard-coded count, so adding a sample later does
        // not break this suite for the wrong reason.
        DefaultHotkeyCatalog.All.Should().OnlyContain(s => s.Definition.AppliesToAllProfiles);
    }

    [Fact]
    public void EverySample_HasAUniqueDescription()
    {
        // Definition(...) above uses Single on the description, so a duplicate would turn every
        // other failure in this file into a confusing exception.
        DefaultHotkeyCatalog.All.Select(s => s.Definition.Description)
            .Should().OnlyHaveUniqueItems();
    }
}
