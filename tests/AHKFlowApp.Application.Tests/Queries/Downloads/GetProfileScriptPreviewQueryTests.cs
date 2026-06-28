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
using Microsoft.Extensions.Time.Testing;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Queries.Downloads;

[Collection("ScriptGeneratorDb")]
[Trait("Category", "Integration")]
public sealed class GetProfileScriptPreviewQueryTests(ScriptGeneratorDbFixture fx)
{
    private readonly Guid _ownerOid = Guid.NewGuid();
    private readonly FakeTimeProvider _clock = new();

    private static AhkScriptGenerator CreateGenerator(TimeProvider clock)
    {
        IAppVersionProvider version = Substitute.For<IAppVersionProvider>();
        version.GetVersion().Returns("0.0.0");
        return new AhkScriptGenerator(new HeaderTokenRenderer(), clock, version);
    }

    private GetProfileScriptPreviewQueryHandler CreateSut(AppDbContext ctx, Guid? oid = null)
    {
        ICurrentUser cu = Substitute.For<ICurrentUser>();
        cu.Oid.Returns(oid ?? _ownerOid);
        return new GetProfileScriptPreviewQueryHandler(
            new ProfileScriptLoader(ctx), cu, CreateGenerator(_clock), _clock);
    }

    [Fact]
    public async Task Handle_AnonymousUser_ReturnsUnauthorized()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ICurrentUser cu = Substitute.For<ICurrentUser>();
        cu.Oid.Returns((Guid?)null);
        GetProfileScriptPreviewQueryHandler sut = new(
            new ProfileScriptLoader(ctx), cu, CreateGenerator(_clock), _clock);

        Result<ProfileScriptPreviewDto> result = await sut.Handle(
            new GetProfileScriptPreviewQuery(Guid.NewGuid()), CancellationToken.None);

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ResultStatus.Unauthorized);
    }

    [Fact]
    public async Task Handle_UnknownProfileId_ReturnsNotFound()
    {
        await using AppDbContext ctx = fx.CreateContext();
        GetProfileScriptPreviewQueryHandler sut = CreateSut(ctx);

        Result<ProfileScriptPreviewDto> result = await sut.Handle(
            new GetProfileScriptPreviewQuery(Guid.NewGuid()), CancellationToken.None);

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Handle_OwnedProfile_ReturnsGeneratedScriptCountsAndTimestamp()
    {
        DateTimeOffset now = new(2026, 5, 19, 12, 0, 0, TimeSpan.Zero);
        _clock.SetUtcNow(now);

        await using AppDbContext ctx = fx.CreateContext();
        Profile work = new ProfileBuilder().WithOwner(_ownerOid).WithName($"Work-{Guid.NewGuid():N}")
            .WithHeader("#Requires AutoHotkey v2.0").WithFooter("; end").Build();
        Hotstring hs = new HotstringBuilder().WithOwner(_ownerOid)
            .WithTrigger("btw").WithReplacement("by the way")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false)
            .AppliesToAllProfiles().Build();
        Hotkey hk = new HotkeyBuilder().WithOwner(_ownerOid)
            .WithDescription("Open Notepad").WithKey("n").WithCtrl()
            .WithAction(HotkeyAction.Run).WithParameters("notepad.exe")
            .InProfile(work.Id).Build();
        ctx.Profiles.Add(work);
        ctx.Hotstrings.Add(hs);
        ctx.Hotkeys.Add(hk);
        await ctx.SaveChangesAsync();

        GetProfileScriptPreviewQueryHandler sut = CreateSut(ctx);
        Result<ProfileScriptPreviewDto> result = await sut.Handle(
            new GetProfileScriptPreviewQuery(work.Id), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.HotstringCount.Should().Be(1);
        result.Value.HotkeyCount.Should().Be(1);
        result.Value.GeneratedAt.Should().Be(now);
        result.Value.Script.Should().Be(
            "#Requires AutoHotkey v2.0\n" +
            "; --- Hotstrings ---\n" +
            "::btw::by the way\n" +
            "; --- Hotkeys ---\n" +
            "^n::Run(\"notepad.exe\")\n" +
            "; end");
    }
}
