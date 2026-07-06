using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.TestUtilities.Builders;
using FluentAssertions;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

[Trait("Category", "Unit")]
public sealed class AhkHotstringRoundTripTests
{
    private static AhkScriptGenerator Generator()
    {
        IAppVersionProvider version = Substitute.For<IAppVersionProvider>();
        version.GetVersion().Returns("0.0.0");
        return new AhkScriptGenerator(new HeaderTokenRenderer(), TimeProvider.System, version);
    }

    [Fact]
    public void GenerateParseGenerate_BacktickNewlineTabReplacement_IsUnchanged()
    {
        string replacement = "a `b ; c\n\td\r\ne";
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring original = new HotstringBuilder()
            .WithTrigger("sig")
            .WithReplacement(replacement)
            .WithEndingCharacterRequired(true)
            .WithTriggerInsideWord(false)
            .Build();

        string firstScript = Generator().Generate(profile, [original], []);
        HotstringImportRowDto row = AhkHotstringParser.Parse(firstScript).Single();
        Hotstring reimported = new HotstringBuilder()
            .WithTrigger(row.Trigger)
            .WithReplacement(row.Replacement)
            .WithEndingCharacterRequired(row.IsEndingCharacterRequired)
            .WithTriggerInsideWord(row.IsTriggerInsideWord)
            .Build();
        string secondScript = Generator().Generate(profile, [reimported], []);

        firstScript.Should().Contain("::sig::a ``b `; c`n`td`r`ne");
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
        row.Replacement.Should().Be(replacement);
        secondScript.Should().Be(firstScript);
    }

    [Fact]
    public void GenerateParseGenerate_TriggerWithBacktickAndSemicolon_IsUnchanged()
    {
        string trigger = "a `b ;c";
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring original = new HotstringBuilder()
            .WithTrigger(trigger)
            .WithReplacement("x")
            .WithEndingCharacterRequired(true)
            .WithTriggerInsideWord(false)
            .Build();

        string firstScript = Generator().Generate(profile, [original], []);
        HotstringImportRowDto row = AhkHotstringParser.Parse(firstScript).Single();
        Hotstring reimported = new HotstringBuilder()
            .WithTrigger(row.Trigger)
            .WithReplacement(row.Replacement)
            .WithEndingCharacterRequired(row.IsEndingCharacterRequired)
            .WithTriggerInsideWord(row.IsTriggerInsideWord)
            .Build();
        string secondScript = Generator().Generate(profile, [reimported], []);

        row.Status.Should().Be(HotstringImportRowStatus.Ready);
        row.Trigger.Should().Be(trigger);
        secondScript.Should().Be(firstScript);
    }
}
