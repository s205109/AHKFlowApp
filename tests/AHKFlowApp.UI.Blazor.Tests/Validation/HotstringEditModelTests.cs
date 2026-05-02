using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Validation;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Validation;

public sealed class HotstringEditModelTests
{
    private static HotstringDto MakeDto(
        string trigger = "btw",
        string replacement = "by the way",
        Guid[]? profileIds = null,
        bool appliesToAllProfiles = true,
        bool endingChar = true,
        bool insideWord = false)
        => new(Guid.NewGuid(), profileIds ?? [], appliesToAllProfiles, trigger, replacement, endingChar, insideWord,
               DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);

    [Fact]
    public void FromDto_MapsAllFields()
    {
        var profileId = Guid.NewGuid();
        HotstringDto dto = MakeDto(profileIds: [profileId], appliesToAllProfiles: false, endingChar: false, insideWord: true);

        var model = HotstringEditModel.FromDto(dto);

        model.Id.Should().Be(dto.Id);
        model.Trigger.Should().Be(dto.Trigger);
        model.Replacement.Should().Be(dto.Replacement);
        model.AppliesToAllProfiles.Should().BeFalse();
        model.ProfileIds.Should().HaveCount(1).And.Contain(profileId);
        model.IsEndingCharacterRequired.Should().BeFalse();
        model.IsTriggerInsideWord.Should().BeTrue();
    }

    [Fact]
    public void ToCreateDto_MapsAllFields()
    {
        var profileId = Guid.NewGuid();
        var model = new HotstringEditModel
        {
            Trigger = "btw",
            Replacement = "by the way",
            AppliesToAllProfiles = false,
            ProfileIds = [profileId],
            IsEndingCharacterRequired = true,
            IsTriggerInsideWord = false
        };

        CreateHotstringDto dto = model.ToCreateDto();

        dto.Trigger.Should().Be("btw");
        dto.Replacement.Should().Be("by the way");
        dto.AppliesToAllProfiles.Should().BeFalse();
        dto.ProfileIds.Should().HaveCount(1).And.Contain(profileId);
        dto.IsEndingCharacterRequired.Should().BeTrue();
        dto.IsTriggerInsideWord.Should().BeFalse();
    }

    [Fact]
    public void ToUpdateDto_MapsAllFields()
    {
        var model = new HotstringEditModel
        {
            Trigger = "omw",
            Replacement = "on my way",
            AppliesToAllProfiles = true,
            ProfileIds = [],
            IsEndingCharacterRequired = false,
            IsTriggerInsideWord = true
        };

        UpdateHotstringDto dto = model.ToUpdateDto();

        dto.Trigger.Should().Be("omw");
        dto.Replacement.Should().Be("on my way");
        dto.AppliesToAllProfiles.Should().BeTrue();
        dto.ProfileIds.Should().BeNull();
        dto.IsEndingCharacterRequired.Should().BeFalse();
        dto.IsTriggerInsideWord.Should().BeTrue();
    }
}
