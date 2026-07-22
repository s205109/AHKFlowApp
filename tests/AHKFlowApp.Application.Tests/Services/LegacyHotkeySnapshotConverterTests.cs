using System.Text.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Services;

public sealed class LegacyHotkeySnapshotConverterTests
{
    [Theory]
    [MemberData(nameof(Legacy))]
    public void ToDefinition_LegacySnapshot_ConvertsViaSameRules(LegacyHotkeyFixture f)
    {
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
    [MemberData(nameof(TypedSnapshots))]
    public void ToDefinition_TypedSnapshot_PassesEveryKindThrough(HotkeySnapshot typed)
    {
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
    [MemberData(nameof(TypedSnapshots))]
    public void Serialize_TypedSnapshot_RoundTripsLosslessly(HotkeySnapshot typed)
    {
        string json = JsonSerializer.Serialize(typed);

        HotkeySnapshot? roundTripped = JsonSerializer.Deserialize<HotkeySnapshot>(json);

        roundTripped.Should().NotBeNull();
        roundTripped!.Action.Should().BeNull();
        roundTripped.Parameters.Should().BeNull();
        LegacyHotkeySnapshotConverter.ToDefinition(roundTripped)
            .Should().Be(LegacyHotkeySnapshotConverter.ToDefinition(typed));
    }

    public static TheoryData<LegacyHotkeyFixture> Legacy()
    {
        TheoryData<LegacyHotkeyFixture> d = [];
        foreach (LegacyHotkeyFixture f in LegacyHotkeyFixtures.All)
            d.Add(f);
        return d;
    }

    /// <summary>One typed snapshot per action kind — all seven must survive the round trip.</summary>
    public static TheoryData<HotkeySnapshot> TypedSnapshots() =>
    [
        Snapshot() with { ActionKind = HotkeyActionKind.SendText, Text = "hello world" },
        Snapshot() with { ActionKind = HotkeyActionKind.SendKeys, SendKeysContent = "^v" },
        Snapshot() with
        {
            ActionKind = HotkeyActionKind.Run,
            RunTarget = "https://github.com",
            RunTargetKind = RunTargetKind.Url,
        },
        Snapshot() with { ActionKind = HotkeyActionKind.Window, WindowOp = WindowOp.Close },
        Snapshot() with { ActionKind = HotkeyActionKind.Remap, RemapDest = "b" },
        Snapshot() with { ActionKind = HotkeyActionKind.Disable },
        Snapshot() with { ActionKind = HotkeyActionKind.Raw, Body = "MsgBox \"hi\"" },
    ];

    private static HotkeySnapshot Snapshot() => new(
        "d", "a", false, false, false, false, true, [], [],
        DateTimeOffset.UnixEpoch, DateTimeOffset.UnixEpoch);
}
