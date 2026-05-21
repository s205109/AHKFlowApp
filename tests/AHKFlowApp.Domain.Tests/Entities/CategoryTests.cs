using AHKFlowApp.Domain.Entities;
using FluentAssertions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace AHKFlowApp.Domain.Tests.Entities;

public sealed class CategoryTests
{
    [Fact]
    public void Create_SetsAllFields()
    {
        FakeTimeProvider clock = new(new DateTimeOffset(2026, 5, 19, 12, 0, 0, TimeSpan.Zero));
        var owner = Guid.NewGuid();

        var category = Category.Create(owner, "Email", clock);

        category.Id.Should().NotBeEmpty();
        category.OwnerOid.Should().Be(owner);
        category.Name.Should().Be("Email");
        category.CreatedAt.Should().Be(clock.GetUtcNow());
        category.UpdatedAt.Should().Be(clock.GetUtcNow());
    }

    [Fact]
    public void Update_ChangesNameAndUpdatedAt()
    {
        FakeTimeProvider clock = new(new DateTimeOffset(2026, 5, 19, 12, 0, 0, TimeSpan.Zero));
        var category = Category.Create(Guid.NewGuid(), "Email", clock);
        DateTimeOffset originalCreated = category.CreatedAt;

        clock.Advance(TimeSpan.FromHours(1));
        category.Update("Work Email", clock);

        category.Name.Should().Be("Work Email");
        category.CreatedAt.Should().Be(originalCreated);
        category.UpdatedAt.Should().Be(clock.GetUtcNow());
    }
}
