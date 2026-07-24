using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Constants;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using NSubstitute;
using Xunit;
using HotkeyAction = AHKFlowApp.Application.Services.LegacyHotkeyDefinitionConverter.HotkeyAction;

namespace AHKFlowApp.Application.Tests.Services;

[Collection("ScriptGeneratorDb")]
[Trait("Category", "Integration")]
public sealed class AhkScriptGeneratorIntegrationTests(ScriptGeneratorDbFixture fx)
{
    private readonly Guid _ownerOid = Guid.NewGuid();
    private readonly AhkScriptGenerator _sut = CreateSut();

    private static AhkScriptGenerator CreateSut()
    {
        IAppVersionProvider version = Substitute.For<IAppVersionProvider>();
        version.GetVersion().Returns("0.0.0");
        return new AhkScriptGenerator(new HeaderTokenRenderer(), TimeProvider.System, version);
    }

    [Fact]
    public async Task Generate_FromSeededDb_ProducesExactExpectedText()
    {
        await using AppDbContext ctx = fx.CreateContext();

        Profile work = new ProfileBuilder()
            .WithOwner(_ownerOid)
            .WithName("Work")
            .AsDefault()
            .WithHeader("#Requires AutoHotkey v2.0\n#SingleInstance Force")
            .WithFooter("; end")
            .Build();
        Profile personal = new ProfileBuilder()
            .WithOwner(_ownerOid)
            .WithName("Personal")
            .AsDefault(false)
            .WithHeader("#Requires AutoHotkey v2.0")
            .WithFooter("")
            .Build();

        Hotstring hsAny = new HotstringBuilder().WithOwner(_ownerOid)
            .WithTrigger("btw").WithReplacement("by the way")
            .WithEndingCharacterRequired(false).WithTriggerInsideWord(true)
            .AppliesToAllProfiles().Build();
        Hotstring hsWorkOnly = new HotstringBuilder().WithOwner(_ownerOid)
            .WithTrigger("addr").WithReplacement("123 Main St")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false)
            .InProfile(work.Id).Build();
        Hotstring hsPersonalOnly = new HotstringBuilder().WithOwner(_ownerOid)
            .WithTrigger("zzz").WithReplacement("good night")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false)
            .InProfile(personal.Id).Build();

        Hotkey hkAny = new HotkeyBuilder().WithOwner(_ownerOid)
            .WithDescription("Open Notepad").WithKey("n").WithCtrl().WithAlt()
            .WithAction(HotkeyAction.Run).WithParameters("notepad.exe")
            .AppliesToAll().Build();
        Hotkey hkWorkOnly = new HotkeyBuilder().WithOwner(_ownerOid)
            .WithDescription("Reload").WithKey("F5").WithCtrl()
            .WithAction(HotkeyAction.Send).WithParameters("{F5}")
            .InProfile(work.Id).Build();

        ctx.Profiles.AddRange(work, personal);
        ctx.Hotstrings.AddRange(hsAny, hsWorkOnly, hsPersonalOnly);
        ctx.Hotkeys.AddRange(hkAny, hkWorkOnly);
        await ctx.SaveChangesAsync();

        // Mirror the EF query Phase 5 will own: rows in this profile's junction
        // OR rows where AppliesToAllProfiles=true.
        Guid pid = work.Id;
        List<Hotstring> hotstringsForWork = await ctx.Hotstrings.AsNoTracking()
            .Where(h => h.OwnerOid == _ownerOid &&
                        (h.AppliesToAllProfiles || h.Profiles.Any(p => p.ProfileId == pid)))
            .ToListAsync();
        List<Hotkey> hotkeysForWork = await ctx.Hotkeys.AsNoTracking()
            .Where(h => h.OwnerOid == _ownerOid &&
                        (h.AppliesToAllProfiles || h.Profiles.Any(p => p.ProfileId == pid)))
            .ToListAsync();
        Profile workReloaded = await ctx.Profiles.AsNoTracking().FirstAsync(p => p.Id == pid);

        string output = _sut.Generate(workReloaded, hotstringsForWork, hotkeysForWork);

        output.Should().Be(
            "#Requires AutoHotkey v2.0\n" +
            "#SingleInstance Force\n" +
            "; --- Hotstrings ---\n" +
            ":T:addr::123 Main St\n" +       // Ordinal: 'a' < 'b' so addr before btw
            ":*?T:btw::by the way\n" +
            "; --- Hotkeys ---\n" +
            "; Open Notepad\n" +             // Description emitted as a comment above the hotkey
            "^!n::Run(\"notepad.exe\")\n" +  // 'O' < 'R' so Open Notepad before Reload
            "; Reload\n" +
            // The legacy Send "{F5}" converts to ActionKind.SendKeys, which auto-emits the
            // leading $ so the binding's own Send cannot retrigger it (spec §5).
            "$^F5::Send(\"{F5}\")\n" +
            "; end");
    }

    [Fact]
    public async Task Generate_FromSeededCatalog_EmitsCorrectedAndNewLines()
    {
        await using AppDbContext ctx = fx.CreateContext();

        Profile profile = new ProfileBuilder()
            .WithOwner(_ownerOid).WithName("Work").AsDefault()
            .WithHeader("#Requires AutoHotkey v2.0").WithFooter("")
            .Build();

        // Seed the catalog directly (every sample is AppliesToAllProfiles) and emit against it.
        var hotkeys = DefaultHotkeyCatalog.All
            .Select(s => Hotkey.Create(_ownerOid, s.Definition, TimeProvider.System))
            .ToList();
        ctx.Profiles.Add(profile);
        ctx.Hotkeys.AddRange(hotkeys);
        await ctx.SaveChangesAsync();

        Profile reloaded = await ctx.Profiles.AsNoTracking().FirstAsync(p => p.Id == profile.Id);
        List<Hotkey> forProfile = await ctx.Hotkeys.AsNoTracking()
            .Where(h => h.OwnerOid == _ownerOid).ToListAsync();

        string output = _sut.Generate(reloaded, [], forProfile);

        // Corrected samples.
        output.Should().Contain("^!r::Reload()");
        output.Should().Contain("^!d::SendText(FormatTime(A_Now, \"yyyy-MM-dd\"))");
        output.Should().Contain("^!Up::WinMaximize(\"A\")");
        output.Should().Contain("^!Down::WinMinimize(\"A\")");
        output.Should().Contain("^!Left::{\n    WinRestore(\"A\")");
        output.Should().Contain("    WinMove(l, t, (r - l) // 2, b - t, \"A\")");
        output.Should().Contain("^!Right::{\n    WinRestore(\"A\")");
        output.Should().Contain("    WinMove(l + (r - l) // 2, t, (r - l) // 2, b - t, \"A\")");
        // Paste-as-plain-text Raw block: keeps its own braces, save/strip/paste/restore.
        output.Should().Contain("^+v::{\n    saved := ClipboardAll()");
        output.Should().Contain("    A_Clipboard := saved         ; restore the original formatting");
        // New typed kinds.
        output.Should().Contain("F1::return");
        output.Should().Contain("F10::Volume_Mute");
        output.Should().Contain("F9::Volume_Up");
        output.Should().Contain("^!a::WinSetAlwaysOnTop(-1, \"A\")");
        output.Should().Contain("^!m::WinRestore(\"A\")");
    }
}
