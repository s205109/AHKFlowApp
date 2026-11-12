using AHKFlowApp.Application.Common;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.Profiles;

[Collection("ProfileDb")]
[Trait("Category", "Integration")]
public sealed class ProfileIndexViolationTests(ProfileDbFixture fx)
{
    // Backlog 166: one catch block turned every duplicate key into the name message,
    // because nothing told the two Profile indexes apart.
    [Theory]
    [InlineData("A", true, "B", true, ProfileIndexNames.OwnerDefault, ProfileIndexNames.OwnerName)]
    [InlineData("Same", false, "Same", false, ProfileIndexNames.OwnerName, ProfileIndexNames.OwnerDefault)]
    // Review of 166: SQL Server puts the duplicate profile name in the message after the index name.
    // A name that quotes the other index must not make the name collision read as a default collision.
    [InlineData("'IX_Profile_Owner_DefaultOnly'", false, "'IX_Profile_Owner_DefaultOnly'", false, ProfileIndexNames.OwnerName, ProfileIndexNames.OwnerDefault)]
    public async Task IsUniqueIndexViolation_names_the_index_that_refused_the_save(
        string firstName, bool firstDefault, string secondName, bool secondDefault,
        string refusingIndex, string otherIndex)
    {
        var ownerOid = Guid.NewGuid();
        await using AppDbContext ctx = fx.CreateContext();
        ctx.Profiles.Add(new ProfileBuilder().WithOwner(ownerOid).WithName(firstName).AsDefault(firstDefault).Build());
        await ctx.SaveChangesAsync();
        ctx.Profiles.Add(new ProfileBuilder().WithOwner(ownerOid).WithName(secondName).AsDefault(secondDefault).Build());

        Func<Task> act = async () => await ctx.SaveChangesAsync();
        DbUpdateException ex = (await act.Should().ThrowAsync<DbUpdateException>()).Which;

        ex.IsUniqueIndexViolation(refusingIndex).Should().BeTrue();
        ex.IsUniqueIndexViolation(otherIndex).Should().BeFalse();
    }
}
