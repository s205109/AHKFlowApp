using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.History;

public sealed class StoredDefinitionTests
{
    // Backlog 175: a read checks the stored item again. A field that ToDefinition dropped or swapped
    // would be checked at the wrong value, and the read would name other rules than the Restore did.
    // Every value below differs from its default and from its neighbours, so either mistake fails.
    [Fact]
    public void Hotstring_ToDefinition_GivesBackTheDefinitionItWasBuiltFrom()
    {
        HotstringDefinition definition = new(
            Trigger: "he7 ", Replacement: "text", Description: "note", AppliesToAllProfiles: false,
            IsEndingCharacterRequired: false, IsTriggerInsideWord: true, Kind: HotstringKind.Macro,
            IsCaseSensitive: true, OmitEndingCharacter: true, DateTimeFormat: "yyyy",
            DateOffsetAmount: 2, DateOffsetUnit: DateOffsetUnit.Hours,
            ContextMatchType: WindowMatchType.TitleContains, ContextValue: "a \" b",
            Delivery: HotstringDelivery.ClipboardPaste);

        Hotstring.Create(Guid.NewGuid(), definition, TimeProvider.System).ToDefinition()
            .Should().Be(definition);
    }

    [Fact]
    public void Hotkey_ToDefinition_GivesBackTheDefinitionItWasBuiltFrom()
    {
        HotkeyDefinition definition = new(
            Description: "d", Key: "NotAKeyName", Ctrl: true, Alt: false, Shift: true, Win: false,
            ActionKind: HotkeyActionKind.Run, AppliesToAllProfiles: false, Text: "t",
            SendKeysContent: "^c", RunTarget: "notepad.exe", RunTargetKind: RunTargetKind.Url,
            WindowOp: WindowOp.Close, RemapDest: "b", Body: "Send x",
            ContextMatchType: WindowMatchType.Executable, ContextValue: "x.exe");

        Hotkey.Create(Guid.NewGuid(), definition, TimeProvider.System).ToDefinition()
            .Should().Be(definition);
    }
}
