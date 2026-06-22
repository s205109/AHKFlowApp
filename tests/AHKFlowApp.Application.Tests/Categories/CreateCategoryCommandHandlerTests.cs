using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Commands.Categories;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Time.Testing;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Categories;

[Collection("CategoryDb")]
[Trait("Category", "Integration")]
public sealed class CreateCategoryCommandHandlerTests(CategoryDbFixture fx)
{
    private readonly Guid _ownerOid = Guid.NewGuid();
    private readonly FakeTimeProvider _clock = new(DateTimeOffset.Parse("2026-05-19T12:00:00Z"));

    private ICurrentUser CurrentUser()
    {
        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns(_ownerOid);
        return user;
    }

    [Fact]
    public async Task Create_PersistsCategoryAndReturnsDto()
    {
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new CreateCategoryCommandHandler(ctx, CurrentUser(), _clock);

        Result<CategoryDto> result = await sut.Handle(
            new CreateCategoryCommand(new CreateCategoryDto("Email")), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Name.Should().Be("Email");
        (await ctx.Categories.CountAsync(c => c.OwnerOid == _ownerOid && c.Name == "Email"))
            .Should().Be(1);
    }

    [Fact]
    public async Task Create_ReturnsUnauthorized_WhenNoOid()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns((Guid?)null);
        var sut = new CreateCategoryCommandHandler(ctx, user, _clock);

        Result<CategoryDto> result = await sut.Handle(
            new CreateCategoryCommand(new CreateCategoryDto("Email")), CancellationToken.None);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }

    [Fact]
    public async Task Create_ReturnsConflict_WhenNameAlreadyExists()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ctx.Categories.Add(new CategoryBuilder().WithOwner(_ownerOid).Named("Email").Build());
        await ctx.SaveChangesAsync();

        var sut = new CreateCategoryCommandHandler(ctx, CurrentUser(), _clock);

        Result<CategoryDto> result = await sut.Handle(
            new CreateCategoryCommand(new CreateCategoryDto("Email")), CancellationToken.None);

        result.Status.Should().Be(ResultStatus.Conflict);
    }

    [Fact]
    public async Task Create_ReturnsConflict_WhenNameDiffersOnlyByCase()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ctx.Categories.Add(new CategoryBuilder().WithOwner(_ownerOid).Named("email").Build());
        await ctx.SaveChangesAsync();

        var sut = new CreateCategoryCommandHandler(ctx, CurrentUser(), _clock);

        Result<CategoryDto> result = await sut.Handle(
            new CreateCategoryCommand(new CreateCategoryDto("Email")), CancellationToken.None);

        result.Status.Should().Be(ResultStatus.Conflict);
    }

    [Fact]
    public async Task Create_TrimsName()
    {
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new CreateCategoryCommandHandler(ctx, CurrentUser(), _clock);

        Result<CategoryDto> result = await sut.Handle(
            new CreateCategoryCommand(new CreateCategoryDto("  Email  ")), CancellationToken.None);

        result.Value.Name.Should().Be("Email");
        (await ctx.Categories.CountAsync(c => c.OwnerOid == _ownerOid && c.Name == "Email"))
            .Should().Be(1);
    }
}
