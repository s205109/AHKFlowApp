using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using NSubstitute;
using Xunit;

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
            "^!n::Run(\"notepad.exe\")\n" +  // 'O' < 'R' so Open Notepad before Reload
            "^F5::Send(\"{F5}\")\n" +
            "; end");
    }
}
