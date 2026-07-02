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
public sealed class UpdateCategoryCommandHandlerTests(CategoryDbFixture fx)
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
    public async Task Update_ReturnsNotFound_WhenIdDoesNotExist()
    {
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new UpdateCategoryCommandHandler(ctx, CurrentUser(), _clock);

        Result<CategoryDto> result = await sut.ExecuteAsync(
            new UpdateCategoryCommand(Guid.NewGuid(), new UpdateCategoryDto("Email")), CancellationToken.None);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Update_ReturnsNotFound_WhenIdBelongsToAnotherUser()
    {
        await using AppDbContext ctx = fx.CreateContext();
        var otherOwner = Guid.NewGuid();
        Category other = new CategoryBuilder().WithOwner(otherOwner).Named("Email").Build();
        ctx.Categories.Add(other);
        await ctx.SaveChangesAsync();

        var sut = new UpdateCategoryCommandHandler(ctx, CurrentUser(), _clock);

        Result<CategoryDto> result = await sut.ExecuteAsync(
            new UpdateCategoryCommand(other.Id, new UpdateCategoryDto("Renamed")), CancellationToken.None);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Update_ReturnsConflict_WhenNameAlreadyExists()
    {
        await using AppDbContext ctx = fx.CreateContext();
        Category email = new CategoryBuilder().WithOwner(_ownerOid).Named("Email").Build();
        Category work = new CategoryBuilder().WithOwner(_ownerOid).Named("Work").Build();
        ctx.Categories.AddRange(email, work);
        await ctx.SaveChangesAsync();

        var sut = new UpdateCategoryCommandHandler(ctx, CurrentUser(), _clock);

        Result<CategoryDto> result = await sut.ExecuteAsync(
            new UpdateCategoryCommand(email.Id, new UpdateCategoryDto("Work")), CancellationToken.None);

        result.Status.Should().Be(ResultStatus.Conflict);
    }

    [Fact]
    public async Task Update_ReturnsConflict_WhenNameDiffersOnlyByCase()
    {
        await using AppDbContext ctx = fx.CreateContext();
        Category email = new CategoryBuilder().WithOwner(_ownerOid).Named("Email").Build();
        Category work = new CategoryBuilder().WithOwner(_ownerOid).Named("work").Build();
        ctx.Categories.AddRange(email, work);
        await ctx.SaveChangesAsync();

        var sut = new UpdateCategoryCommandHandler(ctx, CurrentUser(), _clock);

        Result<CategoryDto> result = await sut.ExecuteAsync(
            new UpdateCategoryCommand(email.Id, new UpdateCategoryDto("WORK")), CancellationToken.None);

        result.Status.Should().Be(ResultStatus.Conflict);
    }

    [Fact]
    public async Task Update_RenameToSameName_ReturnsSuccess()
    {
        await using AppDbContext ctx = fx.CreateContext();
        Category entity = new CategoryBuilder().WithOwner(_ownerOid).Named("Email").Build();
        ctx.Categories.Add(entity);
        await ctx.SaveChangesAsync();

        var sut = new UpdateCategoryCommandHandler(ctx, CurrentUser(), _clock);

        Result<CategoryDto> result = await sut.ExecuteAsync(
            new UpdateCategoryCommand(entity.Id, new UpdateCategoryDto("Email")), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Name.Should().Be("Email");
    }

    [Fact]
    public async Task Update_TrimsName()
    {
        await using AppDbContext ctx = fx.CreateContext();
        Category entity = new CategoryBuilder().WithOwner(_ownerOid).Named("Email").Build();
        ctx.Categories.Add(entity);
        await ctx.SaveChangesAsync();

        var sut = new UpdateCategoryCommandHandler(ctx, CurrentUser(), _clock);

        Result<CategoryDto> result = await sut.ExecuteAsync(
            new UpdateCategoryCommand(entity.Id, new UpdateCategoryDto("  Email  ")), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Name.Should().Be("Email");
        (await ctx.Categories.CountAsync(c => c.OwnerOid == _ownerOid && c.Name == "Email"))
            .Should().Be(1);
    }

    [Fact]
    public async Task Update_ReturnsUnauthorized_WhenNoOid()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns((Guid?)null);
        var sut = new UpdateCategoryCommandHandler(ctx, user, _clock);

        Result<CategoryDto> result = await sut.ExecuteAsync(
            new UpdateCategoryCommand(Guid.NewGuid(), new UpdateCategoryDto("Email")), CancellationToken.None);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }

    [Fact]
    public async Task Update_UpdatesNameAndUpdatedAt()
    {
        await using AppDbContext ctx = fx.CreateContext();
        FakeTimeProvider seedClock = new(DateTimeOffset.Parse("2026-05-19T10:00:00Z"));
        Category entity = new CategoryBuilder().WithOwner(_ownerOid).Named("Email").WithClock(seedClock).Build();
        ctx.Categories.Add(entity);
        await ctx.SaveChangesAsync();

        DateTimeOffset originalUpdatedAt = entity.UpdatedAt;
        _clock.SetUtcNow(DateTimeOffset.Parse("2026-05-19T12:00:00Z"));

        var sut = new UpdateCategoryCommandHandler(ctx, CurrentUser(), _clock);

        Result<CategoryDto> result = await sut.ExecuteAsync(
            new UpdateCategoryCommand(entity.Id, new UpdateCategoryDto("Personal")), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Name.Should().Be("Personal");

        Category? updated = await ctx.Categories.FindAsync(entity.Id);
        updated!.UpdatedAt.Should().BeAfter(originalUpdatedAt);
    }
}
