using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Downloads;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Application.Tests.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Queries.Downloads;

[Collection("ScriptGeneratorDb")]
public sealed class GenerateProfileScriptQueryTests(ScriptGeneratorDbFixture fx)
{
    private readonly Guid _ownerOid = Guid.NewGuid();
    private readonly AhkScriptGenerator _generator = CreateGenerator();

    private static AhkScriptGenerator CreateGenerator()
    {
        IAppVersionProvider version = Substitute.For<IAppVersionProvider>();
        version.GetVersion().Returns("0.0.0");
        return new AhkScriptGenerator(new HeaderTokenRenderer(), TimeProvider.System, version);
    }

    private GenerateProfileScriptQueryHandler CreateSut(AppDbContext ctx, Guid? oid = null)
    {
        ICurrentUser cu = Substitute.For<ICurrentUser>();
        cu.Oid.Returns(oid ?? _ownerOid);
        return new GenerateProfileScriptQueryHandler(new ProfileScriptLoader(ctx), cu, _generator);
    }

    [Fact]
    public async Task Handle_UnknownProfileId_ReturnsNotFound()
    {
        await using AppDbContext ctx = fx.CreateContext();
        GenerateProfileScriptQueryHandler sut = CreateSut(ctx);

        Result<ProfileScript> result = await sut.Handle(
            new GenerateProfileScriptQuery(Guid.NewGuid()), CancellationToken.None);

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Handle_ProfileOwnedByOtherUser_ReturnsNotFound()
    {
        await using AppDbContext ctx = fx.CreateContext();
        var otherOwner = Guid.NewGuid();
        Profile theirs = new ProfileBuilder().WithOwner(otherOwner).WithName($"Theirs-{Guid.NewGuid():N}").Build();
        ctx.Profiles.Add(theirs);
        await ctx.SaveChangesAsync();

        GenerateProfileScriptQueryHandler sut = CreateSut(ctx);
        Result<ProfileScript> result = await sut.Handle(
            new GenerateProfileScriptQuery(theirs.Id), CancellationToken.None);

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Handle_OwnedProfile_ReturnsGeneratedScript()
    {
        await using AppDbContext ctx = fx.CreateContext();
        Profile work = new ProfileBuilder().WithOwner(_ownerOid).WithName($"Work-{Guid.NewGuid():N}")
            .WithHeader("#Requires AutoHotkey v2.0").WithFooter("; end").Build();
        Hotstring hsAny = new HotstringBuilder().WithOwner(_ownerOid)
            .WithTrigger("btw").WithReplacement("by the way")
            .WithEndingCharacterRequired(false).WithTriggerInsideWord(true)
            .AppliesToAllProfiles().Build();
        Hotstring hsWork = new HotstringBuilder().WithOwner(_ownerOid)
            .WithTrigger("addr").WithReplacement("123 Main St")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false)
            .InProfile(work.Id).Build();
        Hotkey hkAny = new HotkeyBuilder().WithOwner(_ownerOid)
            .WithDescription("Open Notepad").WithKey("n").WithCtrl().WithAlt()
            .WithAction(HotkeyAction.Run).WithParameters("notepad.exe")
            .AppliesToAll().Build();
        ctx.Profiles.Add(work);
        ctx.Hotstrings.AddRange(hsAny, hsWork);
        ctx.Hotkeys.Add(hkAny);
        await ctx.SaveChangesAsync();

        GenerateProfileScriptQueryHandler sut = CreateSut(ctx);
        Result<ProfileScript> result = await sut.Handle(
            new GenerateProfileScriptQuery(work.Id), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.FileName.Should().StartWith("ahkflow_Work-").And.EndWith(".ahk");
        result.Value.Content.Should().Be(
            "#Requires AutoHotkey v2.0\n" +
            "; --- Hotstrings ---\n" +
            "::addr::123 Main St\n" +
            ":*?:btw::by the way\n" +
            "; --- Hotkeys ---\n" +
            "^!n::Run(\"notepad.exe\")\n" +
            "; end");
    }

    [Fact]
    public async Task Handle_AnonymousUser_ReturnsUnauthorized()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ICurrentUser cu = Substitute.For<ICurrentUser>();
        cu.Oid.Returns((Guid?)null);
        GenerateProfileScriptQueryHandler sut = new(new ProfileScriptLoader(ctx), cu, _generator);

        Result<ProfileScript> result = await sut.Handle(
            new GenerateProfileScriptQuery(Guid.NewGuid()), CancellationToken.None);

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ResultStatus.Unauthorized);
    }
}
