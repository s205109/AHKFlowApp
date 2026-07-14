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
[Trait("Category", "Integration")]
public sealed class GenerateAllProfileScriptsQueryTests(ScriptGeneratorDbFixture fx)
{
    private readonly Guid _ownerOid = Guid.NewGuid();
    private readonly AhkScriptGenerator _generator = CreateGenerator();

    private static AhkScriptGenerator CreateGenerator()
    {
        IAppVersionProvider version = Substitute.For<IAppVersionProvider>();
        version.GetVersion().Returns("0.0.0");
        return new AhkScriptGenerator(new HeaderTokenRenderer(), TimeProvider.System, version);
    }

    private GenerateAllProfileScriptsQueryHandler CreateSut(AppDbContext ctx, Guid? oid = null)
    {
        ICurrentUser cu = Substitute.For<ICurrentUser>();
        cu.Oid.Returns(oid ?? _ownerOid);
        return new GenerateAllProfileScriptsQueryHandler(ctx, cu, _generator);
    }

    [Fact]
    public async Task Handle_AnonymousUser_ReturnsUnauthorized()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ICurrentUser cu = Substitute.For<ICurrentUser>();
        cu.Oid.Returns((Guid?)null);
        GenerateAllProfileScriptsQueryHandler sut = new(ctx, cu, _generator);

        Result<IReadOnlyList<ProfileScript>> result = await sut.ExecuteAsync(
            new GenerateAllProfileScriptsQuery(), CancellationToken.None);

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ResultStatus.Unauthorized);
    }

    [Fact]
    public async Task Handle_NoProfiles_ReturnsEmptyList()
    {
        await using AppDbContext ctx = fx.CreateContext();
        var lonelyUser = Guid.NewGuid();
        GenerateAllProfileScriptsQueryHandler sut = CreateSut(ctx, lonelyUser);

        Result<IReadOnlyList<ProfileScript>> result = await sut.ExecuteAsync(
            new GenerateAllProfileScriptsQuery(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Should().BeEmpty();
    }

    [Fact]
    public async Task Handle_TwoProfilesMixedAnyAndSpecific_PartitionsCorrectly()
    {
        await using AppDbContext ctx = fx.CreateContext();
        Profile work = new ProfileBuilder().WithOwner(_ownerOid).WithName($"Work-{Guid.NewGuid():N}")
            .WithHeader("HW").WithFooter("FW").Build();
        Profile personal = new ProfileBuilder().WithOwner(_ownerOid).WithName($"Personal-{Guid.NewGuid():N}")
            .AsDefault(false).WithHeader("HP").WithFooter("FP").Build();
        Hotstring hsAny = new HotstringBuilder().WithOwner(_ownerOid)
            .WithTrigger("btw").WithReplacement("by the way")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false)
            .AppliesToAllProfiles().Build();
        Hotstring hsWork = new HotstringBuilder().WithOwner(_ownerOid)
            .WithTrigger("addr").WithReplacement("123 Main St")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false)
            .InProfile(work.Id).Build();
        Hotkey hkPersonal = new HotkeyBuilder().WithOwner(_ownerOid)
            .WithDescription("Open Notepad").WithKey("n").WithCtrl()
            .WithAction(HotkeyAction.Run).WithParameters("notepad.exe")
            .InProfile(personal.Id).Build();
        ctx.Profiles.AddRange(work, personal);
        ctx.Hotstrings.AddRange(hsAny, hsWork);
        ctx.Hotkeys.Add(hkPersonal);
        await ctx.SaveChangesAsync();

        GenerateAllProfileScriptsQueryHandler sut = CreateSut(ctx);
        Result<IReadOnlyList<ProfileScript>> result = await sut.ExecuteAsync(
            new GenerateAllProfileScriptsQuery(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Should().HaveCount(2);

        ProfileScript workScript = result.Value.Single(s => s.FileName.StartsWith("ahkflow_Work-"));
        workScript.Content.Should().Be(
            "HW\n" +
            "; --- Hotstrings ---\n" +
            ":T:addr::123 Main St\n" +
            ":T:btw::by the way\n" +
            "; --- Hotkeys ---\n" +
            "FW");

        ProfileScript personalScript = result.Value.Single(s => s.FileName.StartsWith("ahkflow_Personal-"));
        personalScript.Content.Should().Be(
            "HP\n" +
            "; --- Hotstrings ---\n" +
            ":T:btw::by the way\n" +
            "; --- Hotkeys ---\n" +
            "; Open Notepad\n" +
            "^n::Run(\"notepad.exe\")\n" +
            "FP");
    }

    [Fact]
    public async Task Handle_OnlyIncludesCallingUsersProfiles()
    {
        await using AppDbContext ctx = fx.CreateContext();
        var otherOwner = Guid.NewGuid();
        Profile mine = new ProfileBuilder().WithOwner(_ownerOid).WithName($"Mine-{Guid.NewGuid():N}").Build();
        Profile theirs = new ProfileBuilder().WithOwner(otherOwner).WithName($"Theirs-{Guid.NewGuid():N}").Build();
        ctx.Profiles.AddRange(mine, theirs);
        await ctx.SaveChangesAsync();

        GenerateAllProfileScriptsQueryHandler sut = CreateSut(ctx);
        Result<IReadOnlyList<ProfileScript>> result = await sut.ExecuteAsync(
            new GenerateAllProfileScriptsQuery(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Should().ContainSingle()
            .Which.FileName.Should().StartWith("ahkflow_Mine-");
    }

    [Fact]
    public async Task Handle_SanitizationCollision_DisambiguatesWithNumericSuffix()
    {
        await using AppDbContext ctx = fx.CreateContext();
        var uniqueOwner = Guid.NewGuid();
        Profile a = new ProfileBuilder().WithOwner(uniqueOwner).WithName("Work/Home").Build();
        Profile b = new ProfileBuilder().WithOwner(uniqueOwner).WithName("Work-Home").AsDefault(false).Build();
        Profile c = new ProfileBuilder().WithOwner(uniqueOwner).WithName("Work\\Home").AsDefault(false).Build();
        ctx.Profiles.AddRange(a, b, c);
        await ctx.SaveChangesAsync();

        GenerateAllProfileScriptsQueryHandler sut = CreateSut(ctx, uniqueOwner);
        Result<IReadOnlyList<ProfileScript>> result = await sut.ExecuteAsync(
            new GenerateAllProfileScriptsQuery(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Should().HaveCount(3);
        result.Value.Select(s => s.FileName).Distinct().Should().HaveCount(3);
        result.Value.Select(s => s.FileName).Should().BeEquivalentTo(
        [
            "ahkflow_Work_Home.ahk",
            "ahkflow_Work-Home.ahk",
            "ahkflow_Work_Home_2.ahk"
        ]);
    }
}
