using System.Text.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;
using HotkeyAction = AHKFlowApp.Application.Services.LegacyHotkeyDefinitionConverter.HotkeyAction;

namespace AHKFlowApp.Application.Tests.Services;

public sealed class LegacyHotkeySnapshotConverterTests
{
    // Takes the fixture's name, not the fixture — see the note on the converter test. A record
    // does not serialize, so every case shared one test id.
    [Theory]
    [MemberData(nameof(Legacy))]
    public void ToDefinition_LegacySnapshot_ConvertsViaSameRules(string fixtureName)
    {
        LegacyHotkeyFixture f = LegacyHotkeyFixtures.ByName(fixtureName);

        HotkeySnapshot legacy = Snapshot() with { Action = f.Action, Parameters = f.Parameters };

        HotkeyDefinition def = LegacyHotkeySnapshotConverter.ToDefinition(legacy);

        LegacyHotkeyDefinitionConverter.TypedAction expected =
            LegacyHotkeyDefinitionConverter.ToTyped(f.Action, f.Parameters);
        def.ActionKind.Should().Be(expected.ActionKind, "fixture '{0}'", f.Name);
        def.Text.Should().Be(expected.Text, "fixture '{0}'", f.Name);
        def.SendKeysContent.Should().Be(expected.SendKeysContent, "fixture '{0}'", f.Name);
        def.RunTarget.Should().Be(expected.RunTarget, "fixture '{0}'", f.Name);
        def.RunTargetKind.Should().Be(expected.RunTargetKind, "fixture '{0}'", f.Name);
        def.WindowOp.Should().Be(expected.WindowOp, "fixture '{0}'", f.Name);
        def.RemapDest.Should().Be(expected.RemapDest, "fixture '{0}'", f.Name);
        def.Body.Should().Be(expected.Body, "fixture '{0}'", f.Name);
    }

    [Theory]
    [MemberData(nameof(TypedSnapshotKinds))]
    public void ToDefinition_TypedSnapshot_PassesEveryKindThrough(HotkeyActionKind kind)
    {
        HotkeySnapshot typed = TypedSnapshot(kind);

        HotkeyDefinition def = LegacyHotkeySnapshotConverter.ToDefinition(typed);

        def.ActionKind.Should().Be(typed.ActionKind);
        def.Text.Should().Be(typed.Text);
        def.SendKeysContent.Should().Be(typed.SendKeysContent);
        def.RunTarget.Should().Be(typed.RunTarget);
        def.RunTargetKind.Should().Be(typed.RunTargetKind);
        def.WindowOp.Should().Be(typed.WindowOp);
        def.RemapDest.Should().Be(typed.RemapDest);
        def.Body.Should().Be(typed.Body);
    }

    [Fact]
    public void ToDefinition_TypedSnapshot_CarriesWindowContextThrough()
    {
        HotkeySnapshot typed = Snapshot() with
        {
            ContextMatchType = WindowMatchType.Executable,
            ContextValue = "notepad.exe",
        };

        HotkeyDefinition def = LegacyHotkeySnapshotConverter.ToDefinition(typed);

        def.ContextMatchType.Should().Be(WindowMatchType.Executable);
        def.ContextValue.Should().Be("notepad.exe");
    }

    [Fact]
    public void ToDefinition_LegacySnapshot_YieldsNullContext()
    {
        HotkeySnapshot legacy = Snapshot() with
        {
            Action = HotkeyAction.Run,
            Parameters = "notepad.exe",
        };

        HotkeyDefinition def = LegacyHotkeySnapshotConverter.ToDefinition(legacy);

        def.ContextMatchType.Should().BeNull();
        def.ContextValue.Should().BeNull();
    }

    [Fact]
    public void ToDefinition_TypedSnapshot_CarriesIdentityFieldsThrough()
    {
        HotkeySnapshot typed = Snapshot() with
        {
            Description = "close the window",
            Key = "f4",
            Alt = true,
            AppliesToAllProfiles = false,
            ActionKind = HotkeyActionKind.Window,
            WindowOp = WindowOp.Close,
        };

        HotkeyDefinition def = LegacyHotkeySnapshotConverter.ToDefinition(typed);

        def.Description.Should().Be("close the window");
        def.Key.Should().Be("f4");
        def.Alt.Should().BeTrue();
        def.Ctrl.Should().BeFalse();
        def.AppliesToAllProfiles.Should().BeFalse();
    }

    [Fact]
    public void ToDefinition_MixedSnapshot_PrefersLegacyPair()
    {
        // A snapshot carrying both shapes must restore the way it did before the typed members
        // existed, so the legacy pair wins.
        HotkeySnapshot mixed = Snapshot() with
        {
            ActionKind = HotkeyActionKind.SendText,
            Text = "typed text",
            Action = HotkeyAction.Run,
            Parameters = "notepad.exe",
        };

        HotkeyDefinition def = LegacyHotkeySnapshotConverter.ToDefinition(mixed);

        def.ActionKind.Should().Be(HotkeyActionKind.Run);
        def.RunTarget.Should().Be("notepad.exe");
        def.RunTargetKind.Should().Be(RunTargetKind.Application);
        def.Text.Should().BeNull();
    }

    [Fact]
    public void Deserialize_LegacyShapedJson_LeavesTypedMembersAbsent()
    {
        // Verbatim shape of a pre-W1 history row: no typed members at all.
        const string json = """
            {
              "Description": "open notepad",
              "Key": "n",
              "Ctrl": true,
              "Alt": false,
              "Shift": false,
              "Win": false,
              "Action": 1,
              "Parameters": "notepad.exe",
              "AppliesToAllProfiles": true,
              "ProfileIds": [],
              "CategoryIds": [],
              "CreatedAt": "1970-01-01T00:00:00+00:00",
              "UpdatedAt": "1970-01-01T00:00:00+00:00"
            }
            """;

        HotkeySnapshot? snapshot = JsonSerializer.Deserialize<HotkeySnapshot>(json);

        snapshot.Should().NotBeNull();
        snapshot!.Action.Should().Be(HotkeyAction.Run);
        snapshot.Parameters.Should().Be("notepad.exe");
        snapshot.Text.Should().BeNull();
        snapshot.RunTarget.Should().BeNull();
        snapshot.Body.Should().BeNull();

        HotkeyDefinition def = LegacyHotkeySnapshotConverter.ToDefinition(snapshot);
        def.ActionKind.Should().Be(HotkeyActionKind.Run);
        def.RunTarget.Should().Be("notepad.exe");
        def.Description.Should().Be("open notepad");
        def.Ctrl.Should().BeTrue();
    }

    [Theory]
    [MemberData(nameof(TypedSnapshotKinds))]
    public void Serialize_TypedSnapshot_RoundTripsLosslessly(HotkeyActionKind kind)
    {
        HotkeySnapshot typed = TypedSnapshot(kind);

        string json = JsonSerializer.Serialize(typed);

        HotkeySnapshot? roundTripped = JsonSerializer.Deserialize<HotkeySnapshot>(json);

        roundTripped.Should().NotBeNull();
        roundTripped!.Action.Should().BeNull();
        roundTripped.Parameters.Should().BeNull();
        LegacyHotkeySnapshotConverter.ToDefinition(roundTripped)
            .Should().Be(LegacyHotkeySnapshotConverter.ToDefinition(typed));
    }

    public static TheoryData<string> Legacy() => new(LegacyHotkeyFixtures.AllNames);

    /// <summary>
    /// The action kind is the theory argument, because a <c>HotkeySnapshot</c> is a record and does
    /// not serialize — passing one put all seven cases under a single test id. Enumerating the enum
    /// rather than listing kinds means a kind added later cannot quietly miss this coverage:
    /// <see cref="TypedSnapshot"/> has no arm for it and the case fails loudly.
    /// </summary>
    public static TheoryData<HotkeyActionKind> TypedSnapshotKinds() =>
        new(Enum.GetValues<HotkeyActionKind>());

    /// <summary>One typed snapshot per action kind — all seven must survive the round trip.</summary>
    private static HotkeySnapshot TypedSnapshot(HotkeyActionKind kind) => kind switch
    {
        HotkeyActionKind.SendText =>
            Snapshot() with { ActionKind = HotkeyActionKind.SendText, Text = "hello world" },
        HotkeyActionKind.SendKeys =>
            Snapshot() with { ActionKind = HotkeyActionKind.SendKeys, SendKeysContent = "^v" },
        HotkeyActionKind.Run => Snapshot() with
        {
            ActionKind = HotkeyActionKind.Run,
            RunTarget = "https://github.com",
            RunTargetKind = RunTargetKind.Url,
        },
        HotkeyActionKind.Window =>
            Snapshot() with { ActionKind = HotkeyActionKind.Window, WindowOp = WindowOp.Close },
        HotkeyActionKind.Remap =>
            Snapshot() with { ActionKind = HotkeyActionKind.Remap, RemapDest = "b" },
        HotkeyActionKind.Disable =>
            Snapshot() with { ActionKind = HotkeyActionKind.Disable },
        HotkeyActionKind.Raw =>
            Snapshot() with { ActionKind = HotkeyActionKind.Raw, Body = "MsgBox \"hi\"" },
        _ => throw new ArgumentOutOfRangeException(nameof(kind), kind, "No typed snapshot for this kind."),
    };

    private static HotkeySnapshot Snapshot() => new(
        "d", "a", false, false, false, false, true, [], [],
        DateTimeOffset.UnixEpoch, DateTimeOffset.UnixEpoch);
}
