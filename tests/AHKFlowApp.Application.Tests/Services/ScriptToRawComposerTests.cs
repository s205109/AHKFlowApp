using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Services;

public sealed class ScriptToRawComposerTests
{
    public static TheoryData<string> FixtureNames()
    {
        TheoryData<string> data = [];
        foreach (ScriptToRawFixture f in ScriptToRawFixtures.All)
            data.Add(f.Name);
        return data;
    }

    [Theory]
    [MemberData(nameof(FixtureNames))]
    public void Compose_MatchesGolden(string fixtureName)
    {
        ScriptToRawFixture f = ScriptToRawFixtures.All.Single(x => x.Name == fixtureName);

        string composed = ScriptToRawComposer.Compose(
            f.Trigger, f.Body,
            f.IsEndingCharacterRequired, f.IsTriggerInsideWord,
            f.IsCaseSensitive, f.OmitEndingCharacter);

        composed.Should().Be(f.ExpectedRawDefinition);
    }

    [Fact]
    public void ToDefinition_LegacyScriptSnapshot_ConvertsToRaw()
    {
#pragma warning disable CS0618 // Simulating a stored legacy snapshot.
        HotstringSnapshot snapshot = Snapshot("rng", "Send foo", HotstringKind.Script);
#pragma warning restore CS0618

        HotstringDefinition def = ScriptToRawComposer.ToDefinition(snapshot);

        def.Kind.Should().Be(HotstringKind.Raw);
        def.Trigger.Should().Be("rng");
        def.Replacement.Should().Be("::rng::\n{\nSend foo\n}");
    }

    [Fact]
    public void ToDefinition_NonScriptSnapshot_PassesThroughUnchanged()
    {
        HotstringSnapshot snapshot = Snapshot("btw", "by the way", HotstringKind.Text);

        HotstringDefinition def = ScriptToRawComposer.ToDefinition(snapshot);

        def.Kind.Should().Be(HotstringKind.Text);
        def.Trigger.Should().Be("btw");
        def.Replacement.Should().Be("by the way");
    }

    private static HotstringSnapshot Snapshot(string trigger, string replacement, HotstringKind kind) =>
        new(trigger, replacement, Description: null, AppliesToAllProfiles: true,
            IsEndingCharacterRequired: true, IsTriggerInsideWord: false,
            ProfileIds: [], CategoryIds: [],
            CreatedAt: DateTimeOffset.UnixEpoch, UpdatedAt: DateTimeOffset.UnixEpoch,
            Kind: kind);
}
