using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.TestUtilities.Builders;
using FluentAssertions;
using Microsoft.Extensions.Time.Testing;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Services;

public sealed class AhkScriptGeneratorTests
{
    private static AhkScriptGenerator DefaultSut()
    {
        IAppVersionProvider version = Substitute.For<IAppVersionProvider>();
        version.GetVersion().Returns("0.0.0");
        return new AhkScriptGenerator(new HeaderTokenRenderer(), TimeProvider.System, version);
    }

    [Fact]
    public void Generate_EmptyProfile_EmitsHeaderSectionMarkersAndFooter()
    {
        Profile profile = new ProfileBuilder()
            .WithHeader("#Requires AutoHotkey v2.0")
            .WithFooter("; end of file")
            .Build();

        string output = DefaultSut().Generate(profile, [], []);

        output.Should().Be(
            "#Requires AutoHotkey v2.0\n" +
            "; --- Hotstrings ---\n" +
            "; --- Hotkeys ---\n" +
            "; end of file");
    }

    [Fact]
    public void Generate_EmptyHeaderAndFooter_StillEmitsSectionMarkers()
    {
        Profile profile = new ProfileBuilder().WithHeader("").WithFooter("").Build();

        string output = DefaultSut().Generate(profile, [], []);

        output.Should().Be(
            "\n" +
            "; --- Hotstrings ---\n" +
            "; --- Hotkeys ---\n");
    }

    [Theory]
    [InlineData(true, false, false, false, ":T:btw::by the way")]    // defaults — Text always emits T (WYSIWYG, D1)
    [InlineData(false, false, false, false, ":*T:btw::by the way")]  // expand immediately
    [InlineData(true, true, false, false, ":?T:btw::by the way")]    // trigger inside word
    [InlineData(true, false, true, false, ":CT:btw::by the way")]    // case sensitive
    [InlineData(true, false, false, true, ":OT:btw::by the way")]    // omit ending character
    [InlineData(false, false, false, true, ":*T:btw::by the way")]   // O suppressed when *
    [InlineData(false, true, true, true, ":*?CT:btw::by the way")]   // deterministic order * ? C O T
    public void Generate_Hotstring_FormatsOptionsCorrectly(
        bool isEndingCharacterRequired,
        bool isTriggerInsideWord,
        bool isCaseSensitive,
        bool omitEndingCharacter,
        string expectedLine)
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("btw")
            .WithReplacement("by the way")
            .WithEndingCharacterRequired(isEndingCharacterRequired)
            .WithTriggerInsideWord(isTriggerInsideWord)
            .WithCaseSensitive(isCaseSensitive)
            .WithOmitEndingCharacter(omitEndingCharacter)
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Be(
            "H\n" +
            "; --- Hotstrings ---\n" +
            expectedLine + "\n" +
            "; --- Hotkeys ---\n" +
            "F");
    }

    [Theory]
    [InlineData("line one\nline two", ":T:sig::line one`nline two")]
    [InlineData("a\rb", ":T:sig::a`rb")]
    [InlineData("a\tb", ":T:sig::a`tb")]
    [InlineData("a\r\nb", ":T:sig::a`r`nb")]
    [InlineData("back`tick", ":T:sig::back``tick")]
    [InlineData("literal `n stays\n", ":T:sig::literal ``n stays`n")]
    [InlineData("a ; b", ":T:sig::a `; b")]
    public void Generate_HotstringWithSpecialChars_EscapesOntoSinglePhysicalLine(
        string replacement, string expectedLine)
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("sig")
            .WithReplacement(replacement)
            .WithEndingCharacterRequired(true)
            .WithTriggerInsideWord(false)
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Be(
            "H\n" +
            "; --- Hotstrings ---\n" +
            expectedLine + "\n" +
            "; --- Hotkeys ---\n" +
            "F");
    }

    [Theory]
    [InlineData("a ;b", ":T:a `;b::x")]
    [InlineData("back`tick", ":T:back``tick::x")]
    public void Generate_TriggerWithSpecialChars_EscapesTriggerToo(string trigger, string expectedLine)
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger(trigger)
            .WithReplacement("x")
            .WithEndingCharacterRequired(true)
            .WithTriggerInsideWord(false)
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Be(
            "H\n" +
            "; --- Hotstrings ---\n" +
            expectedLine + "\n" +
            "; --- Hotkeys ---\n" +
            "F");
    }

    [Fact]
    public void Generate_MultipleHotstrings_AllAppearUnderHotstringsSection()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs1 = new HotstringBuilder().WithTrigger("a").WithReplacement("alpha")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false).Build();
        Hotstring hs2 = new HotstringBuilder().WithTrigger("b").WithReplacement("beta")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false).Build();

        string output = DefaultSut().Generate(profile, [hs1, hs2], []);

        output.Should().Be(
            "H\n" +
            "; --- Hotstrings ---\n" +
            ":T:a::alpha\n" +
            ":T:b::beta\n" +
            "; --- Hotkeys ---\n" +
            "F");
    }

    [Theory]
    [InlineData(false, false, false, false, "n")]               // no modifiers
    [InlineData(true, false, false, false, "^n")]               // Ctrl
    [InlineData(false, true, false, false, "!n")]               // Alt
    [InlineData(false, false, true, false, "+n")]               // Shift
    [InlineData(false, false, false, true, "#n")]               // Win
    [InlineData(true, true, false, false, "^!n")]               // Ctrl+Alt
    [InlineData(true, true, true, true, "^!+#n")]               // all four, prefix-order locked
    public void Generate_Hotkey_FormatsModifierPrefixesCorrectly(
        bool ctrl, bool alt, bool shift, bool win, string expectedLhs)
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotkey hk = new HotkeyBuilder()
            .WithDescription("d")
            .WithKey("n")
            .WithCtrl(ctrl).WithAlt(alt).WithShift(shift).WithWin(win)
            .WithAction(AHKFlowApp.Domain.Enums.HotkeyAction.Send)
            .WithParameters("hi")
            .Build();

        string output = DefaultSut().Generate(profile, [], [hk]);

        output.Should().Be(
            "H\n" +
            "; --- Hotstrings ---\n" +
            "; --- Hotkeys ---\n" +
            $"{expectedLhs}::Send(\"hi\")\n" +
            "F");
    }

    [Theory]
    [InlineData(AHKFlowApp.Domain.Enums.HotkeyAction.Send, "Send")]
    [InlineData(AHKFlowApp.Domain.Enums.HotkeyAction.Run, "Run")]
    public void Generate_Hotkey_EmitsCorrectActionFunctionName(
        AHKFlowApp.Domain.Enums.HotkeyAction action, string expectedFn)
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotkey hk = new HotkeyBuilder()
            .WithDescription("d")
            .WithKey("F5")
            .WithCtrl(false).WithAlt(false).WithShift(false).WithWin(false)
            .WithAction(action)
            .WithParameters("notepad.exe")
            .Build();

        string output = DefaultSut().Generate(profile, [], [hk]);

        output.Should().Contain($"F5::{expectedFn}(\"notepad.exe\")");
    }

    [Fact]
    public void Generate_Hotkey_EmitsParametersVerbatim_NoEscaping()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotkey hk = new HotkeyBuilder()
            .WithDescription("d")
            .WithKey("a")
            .WithCtrl(true)
            .WithAction(AHKFlowApp.Domain.Enums.HotkeyAction.Send)
            .WithParameters("he said \"hi\"")
            .Build();

        string output = DefaultSut().Generate(profile, [], [hk]);

        output.Should().Contain("^a::Send(\"he said \"hi\"\")");
    }

    [Fact]
    public void Generate_Hotstrings_AreSortedByTriggerOrdinalAscending()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring c = new HotstringBuilder().WithTrigger("c").WithReplacement("c-rep")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false).Build();
        Hotstring a = new HotstringBuilder().WithTrigger("a").WithReplacement("a-rep")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false).Build();
        Hotstring b = new HotstringBuilder().WithTrigger("b").WithReplacement("b-rep")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false).Build();

        string output = DefaultSut().Generate(profile, [c, a, b], []);

        int posA = output.IndexOf(":T:a::a-rep", StringComparison.Ordinal);
        int posB = output.IndexOf(":T:b::b-rep", StringComparison.Ordinal);
        int posC = output.IndexOf(":T:c::c-rep", StringComparison.Ordinal);
        posA.Should().BeLessThan(posB);
        posB.Should().BeLessThan(posC);
    }

    [Fact]
    public void Generate_Hotkeys_AreSortedByDescriptionOrdinalAscending()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotkey z = new HotkeyBuilder().WithDescription("Zeta").WithKey("z")
            .WithAction(AHKFlowApp.Domain.Enums.HotkeyAction.Send).WithParameters("z").Build();
        Hotkey a = new HotkeyBuilder().WithDescription("Alpha").WithKey("a")
            .WithAction(AHKFlowApp.Domain.Enums.HotkeyAction.Send).WithParameters("a").Build();
        Hotkey m = new HotkeyBuilder().WithDescription("Mike").WithKey("m")
            .WithAction(AHKFlowApp.Domain.Enums.HotkeyAction.Send).WithParameters("m").Build();

        string output = DefaultSut().Generate(profile, [], [z, a, m]);

        int posA = output.IndexOf("a::Send(\"a\")", StringComparison.Ordinal);
        int posM = output.IndexOf("m::Send(\"m\")", StringComparison.Ordinal);
        int posZ = output.IndexOf("z::Send(\"z\")", StringComparison.Ordinal);
        posA.Should().BeLessThan(posM);
        posM.Should().BeLessThan(posZ);
    }

    [Fact]
    public void Generate_Ordering_IsCultureIndependent_OrdinalNotInvariant()
    {
        // Ordinal sort: uppercase letters precede lowercase. Lock this in so future
        // refactors don't silently swap to InvariantCultureIgnoreCase.
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring lower = new HotstringBuilder().WithTrigger("aa").WithReplacement("lower")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false).Build();
        Hotstring upper = new HotstringBuilder().WithTrigger("AA").WithReplacement("upper")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false).Build();

        string output = DefaultSut().Generate(profile, [lower, upper], []);

        int posUpper = output.IndexOf(":T:AA::upper", StringComparison.Ordinal);
        int posLower = output.IndexOf(":T:aa::lower", StringComparison.Ordinal);
        posUpper.Should().BeLessThan(posLower);  // 'A' (0x41) < 'a' (0x61) in Ordinal
    }

    private static AhkScriptGenerator TokenSut(string version = "1.2.3")
    {
        IAppVersionProvider ver = Substitute.For<IAppVersionProvider>();
        ver.GetVersion().Returns(version);
        return new AhkScriptGenerator(
            new HeaderTokenRenderer(),
            new FakeTimeProvider(DateTimeOffset.Parse("2026-05-19T12:00:00Z",
                System.Globalization.CultureInfo.InvariantCulture)),
            ver);
    }

    [Fact]
    public void Generate_SubstitutesHeaderTokens()
    {
        AhkScriptGenerator sut = TokenSut();

        Profile p = new ProfileBuilder()
            .WithOwner(Guid.NewGuid())
            .WithName("Work")
            .WithHeader("; {ProfileName} v{AppVersion} — {HotstringCount}h {HotkeyCount}k @ {GeneratedAt:yyyy-MM-dd}\n")
            .WithFooter("")
            .Build();

        Hotstring[] hs =
        [
            new HotstringBuilder().WithOwner(p.OwnerOid).WithTrigger("btw").WithReplacement("by the way").Build(),
        ];

        string output = sut.Generate(p, hs, []);

        output.Should().StartWith("; Work v1.2.3 — 1h 0k @ 2026-05-19");
    }

    [Fact]
    public void Generate_PreservesUnknownTokens_InHeader()
    {
        AhkScriptGenerator sut = TokenSut();
        Profile p = new ProfileBuilder().WithHeader("{Nope} hello\n").WithFooter("").Build();

        string output = sut.Generate(p, [], []);

        output.Should().Contain("{Nope} hello");
    }

    [Fact]
    public void Generate_FooterIsAlsoRendered()
    {
        AhkScriptGenerator sut = TokenSut();
        Profile p = new ProfileBuilder().WithHeader("").WithFooter("; bye v{AppVersion}").Build();

        string output = sut.Generate(p, [], []);

        output.Should().EndWith("; bye v1.2.3");
    }
}
