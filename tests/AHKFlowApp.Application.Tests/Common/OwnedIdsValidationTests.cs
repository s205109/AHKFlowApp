using AHKFlowApp.Application.Common;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Common;

[Collection("ProfileDb")]
[Trait("Category", "Integration")]
public sealed class OwnedIdsValidationTests(Profiles.ProfileDbFixture fx)
{
    [Fact]
    public async Task CheckOwnedIdsAsync_WhenAllIdsExistForOwner_ReturnsNull()
    {
        var owner = Guid.NewGuid();
        Profile prof1 = new ProfileBuilder().WithOwner(owner).WithName("One").Build();
        Profile prof2 = new ProfileBuilder().WithOwner(owner).WithName("Two").AsDefault(false).Build();

        await using AppDbContext db = fx.CreateContext();
        db.Profiles.AddRange(prof1, prof2);
        await db.SaveChangesAsync();
        Guid[] ids = [prof1.Id, prof2.Id];

        ValidationError? error = await OwnedIdsValidation.CheckOwnedIdsAsync(
            db.Profiles, p => p.OwnerOid == owner && ids.Contains(p.Id), ids, "ProfileIds", default);

        error.Should().BeNull();
    }

    [Fact]
    public async Task CheckOwnedIdsAsync_WhenIdMissing_ReturnsErrorWithFieldIdentifier()
    {
        var owner = Guid.NewGuid();
        Profile prof = new ProfileBuilder().WithOwner(owner).WithName("Only").Build();

        await using AppDbContext db = fx.CreateContext();
        db.Profiles.Add(prof);
        await db.SaveChangesAsync();
        Guid[] ids = [prof.Id, Guid.NewGuid()];

        ValidationError? error = await OwnedIdsValidation.CheckOwnedIdsAsync(
            db.Profiles, p => p.OwnerOid == owner && ids.Contains(p.Id), ids, "ProfileIds", default);

        error.Should().NotBeNull();
        error.Identifier.Should().Be("Input.ProfileIds");
        // Backlog 169: the message named the property, "One or more ProfileIds do not exist for
        // this user.", and an owner reaches it by deleting a chosen profile in another tab.
        error.ErrorMessage.Should().Be("One or more of the chosen profiles do not exist.");
    }

    [Fact]
    public async Task CheckOwnedIdsAsync_WhenCategoryIdMissing_NamesCategoriesNotTheProperty()
    {
        await using AppDbContext db = fx.CreateContext();
        Guid[] ids = [Guid.NewGuid()];

        ValidationError? error = await OwnedIdsValidation.CheckOwnedIdsAsync(
            db.Categories, c => ids.Contains(c.Id), ids, "CategoryIds", default);

        error.Should().NotBeNull();
        error.Identifier.Should().Be("Input.CategoryIds");
        error.ErrorMessage.Should().Be("One or more of the chosen categories do not exist.");
    }

    [Fact]
    public async Task CheckOwnedIdsAsync_WhenIdBelongsToOtherOwner_ReturnsError()
    {
        var owner = Guid.NewGuid();
        Profile foreign = new ProfileBuilder().WithOwner(Guid.NewGuid()).WithName("Foreign").Build();

        await using AppDbContext db = fx.CreateContext();
        db.Profiles.Add(foreign);
        await db.SaveChangesAsync();
        Guid[] ids = [foreign.Id];

        ValidationError? error = await OwnedIdsValidation.CheckOwnedIdsAsync(
            db.Profiles, p => p.OwnerOid == owner && ids.Contains(p.Id), ids, "ProfileIds", default);

        error.Should().NotBeNull();
        error.Identifier.Should().Be("Input.ProfileIds");
    }

    [Fact]
    public async Task CheckOwnedIdsAsync_WhenEmptyIds_ReturnsNull()
    {
        await using AppDbContext db = fx.CreateContext();

        ValidationError? error = await OwnedIdsValidation.CheckOwnedIdsAsync(
            db.Categories, c => false, [], "CategoryIds", default);

        error.Should().BeNull();
    }
}
