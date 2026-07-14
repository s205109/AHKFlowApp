using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Application.Tests.Hotstrings;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Services;

[Collection("HotstringDb")]
[Trait("Category", "Integration")]
public sealed class RawContinuationRoundTripTests(HotstringDbFixture fx)
{
    [Fact]
    public async Task PasteColorsContinuation_SaveThenGenerate_ContainsSectionByteIdentical()
    {
        // Paste a :*:col:: continuation section holding literal multi-line text, save it through the
        // real Create handler, then regenerate the profile script — the section must survive verbatim.
        const string definition = ":*:col::\n(\nred\ngreen\nblue\n)";
        var owner = Guid.NewGuid();

        await using AppDbContext db = fx.CreateContext();
        CreateHotstringCommandHandler handler = new(db, CurrentUserHelper.For(owner), TimeProvider.System);
        Result<HotstringDto> created = await handler.ExecuteAsync(
            new CreateHotstringCommand(new CreateHotstringDto("ignored", definition, Kind: HotstringKind.Raw)),
            default);

        created.IsSuccess.Should().BeTrue();
        created.Value.Trigger.Should().Be("col");

        await using AppDbContext verify = fx.CreateContext();
        List<Hotstring> hotstrings = await verify.Hotstrings.AsNoTracking()
            .Where(h => h.OwnerOid == owner).ToListAsync();

        Profile profile = new ProfileBuilder().WithOwner(owner).WithHeader("H").WithFooter("F").Build();
        string script = CreateGenerator().Generate(profile, hotstrings, []);

        script.Should().Contain(definition);
    }

    private static AhkScriptGenerator CreateGenerator()
    {
        IAppVersionProvider version = Substitute.For<IAppVersionProvider>();
        version.GetVersion().Returns("0.0.0");
        return new AhkScriptGenerator(new HeaderTokenRenderer(), TimeProvider.System, version);
    }
}
