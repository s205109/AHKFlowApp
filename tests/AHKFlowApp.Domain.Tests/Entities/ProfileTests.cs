using AHKFlowApp.Domain.Entities;
using FluentAssertions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace AHKFlowApp.Domain.Tests.Entities;

public sealed class ProfileTests
{
    private readonly FakeTimeProvider _clock = new(DateTimeOffset.Parse("2026-01-01T00:00:00Z"));
    private readonly Guid _ownerOid = Guid.Parse("11111111-1111-1111-1111-111111111111");

    [Fact]
    public void Create_WithAllArgs_SetsAllProperties()
    {
        var profile = Profile.Create(
            ownerOid: _ownerOid,
            name: "Work",
            isDefault: true,
            headerTemplate: "; header",
            footerTemplate: "; footer",
            clock: _clock);

        profile.Id.Should().NotBeEmpty();
        profile.OwnerOid.Should().Be(_ownerOid);
        profile.Name.Should().Be("Work");
        profile.IsDefault.Should().BeTrue();
        profile.HeaderTemplate.Should().Be("; header");
        profile.FooterTemplate.Should().Be("; footer");
        profile.CreatedAt.Should().Be(_clock.GetUtcNow());
        profile.UpdatedAt.Should().Be(_clock.GetUtcNow());
    }

    [Fact]
    public void Update_WithNewValues_ChangesNameTemplatesAndBumpsUpdatedAt()
    {
        var profile = Profile.Create(_ownerOid, "Work", true, "h", "f", _clock);
        DateTimeOffset originalCreated = profile.CreatedAt;

        _clock.Advance(TimeSpan.FromHours(1));
        profile.Update("Personal", "h2", "f2", _clock);

        profile.Name.Should().Be("Personal");
        profile.HeaderTemplate.Should().Be("h2");
        profile.FooterTemplate.Should().Be("f2");
        profile.CreatedAt.Should().Be(originalCreated);
        profile.UpdatedAt.Should().Be(_clock.GetUtcNow());
    }

    [Fact]
    public void MarkDefault_WhenSetToTrue_SetsFlag()
    {
        var profile = Profile.Create(_ownerOid, "Work", false, "", "", _clock);
        profile.MarkDefault(true, _clock);
        profile.IsDefault.Should().BeTrue();
    }

    [Fact]
    public void MarkDefault_Always_BumpsUpdatedAt()
    {
        var profile = Profile.Create(_ownerOid, "Work", false, "", "", _clock);
        _clock.Advance(TimeSpan.FromMinutes(5));
        profile.MarkDefault(true, _clock);
        profile.UpdatedAt.Should().Be(_clock.GetUtcNow());
    }
}
