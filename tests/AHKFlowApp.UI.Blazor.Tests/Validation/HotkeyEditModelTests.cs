using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using AHKFlowApp.UI.Blazor.Validation;
using FluentAssertions;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Validation;

public sealed class HotkeyEditModelTests
{
    private static IHotkeyKeyCatalog CatalogSaying(bool valid)
    {
        IHotkeyKeyCatalog catalog = Substitute.For<IHotkeyKeyCatalog>();
        catalog.IsValidKey(Arg.Any<string?>()).Returns(valid);
        return catalog;
    }

    [Fact]
    public void ToCreateDto_NullsFieldsBelongingToOtherKinds()
    {
        var model = new HotkeyEditModel
        {
            Description = "Open Notepad",
            Key = "n",
            Win = true,
            ActionKind = HotkeyActionKind.Run,
            RunTarget = "notepad",
            RunTargetKind = RunTargetKind.Application,
            Text = "stale text from a previous kind",
            Body = "stale body",
        };

        CreateHotkeyDto dto = model.ToCreateDto();

        dto.ActionKind.Should().Be(HotkeyActionKind.Run);
        dto.RunTarget.Should().Be("notepad");
        dto.Text.Should().BeNull();
        dto.Body.Should().BeNull();
    }

    [Fact]
    public void ToCreateDto_RetainsOtherKindFieldsOnTheModel()
    {
        var model = new HotkeyEditModel
        {
            Description = "Open Notepad",
            Key = "n",
            ActionKind = HotkeyActionKind.Run,
            RunTarget = "notepad",
            Text = "typed earlier",
        };

        _ = model.ToCreateDto();

        model.Text.Should().Be("typed earlier");
    }

    [Fact]
    public void ToCreateDto_DisableKindSendsNoActionFields()
    {
        var model = new HotkeyEditModel { Description = "Kill F1", Key = "F1", ActionKind = HotkeyActionKind.Disable };

        CreateHotkeyDto dto = model.ToCreateDto();

        dto.Text.Should().BeNull();
        dto.SendKeysContent.Should().BeNull();
        dto.RunTarget.Should().BeNull();
        dto.RunTargetKind.Should().BeNull();
        dto.WindowOp.Should().BeNull();
        dto.RemapDest.Should().BeNull();
        dto.Body.Should().BeNull();
    }

    [Theory]
    [InlineData(HotkeyActionKind.SendText, true)]
    [InlineData(HotkeyActionKind.Run, true)]
    [InlineData(HotkeyActionKind.SendKeys, false)]
    [InlineData(HotkeyActionKind.Window, false)]
    [InlineData(HotkeyActionKind.Remap, false)]
    [InlineData(HotkeyActionKind.Disable, false)]
    [InlineData(HotkeyActionKind.Raw, false)]
    public void IsInlineEditable_OnlySendTextAndRun(HotkeyActionKind kind, bool expected)
    {
        var model = new HotkeyEditModel { Key = "n", ActionKind = kind };

        model.IsInlineEditable(CatalogSaying(valid: true)).Should().Be(expected);
    }

    [Fact]
    public void IsInlineEditable_FalseWhenKeyFailsValidation()
    {
        var model = new HotkeyEditModel { Key = "!!legacy!!", ActionKind = HotkeyActionKind.Run };

        model.IsInlineEditable(CatalogSaying(valid: false)).Should().BeFalse();
    }

    [Fact]
    public void ToPreviewRequest_CarriesActiveKindFieldsOnly()
    {
        var model = new HotkeyEditModel
        {
            Description = "Volume",
            Key = "p",
            Win = true,
            ActionKind = HotkeyActionKind.SendKeys,
            SendKeysContent = "{Media_Play_Pause}",
            RunTarget = "stale",
        };

        HotkeyPreviewRequestDto request = model.ToPreviewRequest();

        request.SendKeysContent.Should().Be("{Media_Play_Pause}");
        request.RunTarget.Should().BeNull();
    }

    [Fact]
    public void Clone_CopiesAllFields_WithoutSharingCollections()
    {
        var profileId = Guid.NewGuid();
        var categoryId = Guid.NewGuid();
        var model = new HotkeyEditModel
        {
            Id = Guid.NewGuid(),
            Description = "Open Notepad",
            Key = "n",
            Ctrl = true,
            Alt = true,
            Shift = true,
            Win = true,
            ActionKind = HotkeyActionKind.Run,
            Text = "text",
            SendKeysContent = "{Media_Play_Pause}",
            RunTarget = "notepad",
            RunTargetKind = RunTargetKind.Application,
            WindowOp = WindowOp.ToggleAlwaysOnTop,
            RemapDest = "F13",
            Body = "raw body",
            AppliesToAllProfiles = false,
            ProfileIds = [profileId],
            CategoryIds = [categoryId],
        };

        HotkeyEditModel clone = model.Clone();

        clone.Should().BeEquivalentTo(model);

        clone.ProfileIds.Add(Guid.NewGuid());
        clone.CategoryIds.Add(Guid.NewGuid());

        model.ProfileIds.Should().Equal(profileId);
        model.CategoryIds.Should().Equal(categoryId);
    }

    [Fact]
    public void ToUpdateDto_NullsFieldsBelongingToOtherKinds()
    {
        var model = new HotkeyEditModel
        {
            Description = "Open Notepad",
            Key = "n",
            Win = true,
            ActionKind = HotkeyActionKind.Run,
            RunTarget = "notepad",
            RunTargetKind = RunTargetKind.Application,
            Text = "stale text from a previous kind",
            Body = "stale body",
        };

        UpdateHotkeyDto dto = model.ToUpdateDto();

        dto.ActionKind.Should().Be(HotkeyActionKind.Run);
        dto.RunTarget.Should().Be("notepad");
        dto.Text.Should().BeNull();
        dto.Body.Should().BeNull();
    }

    [Fact]
    public void FromDto_RoundTripsTypedFields()
    {
        var dto = new HotkeyDto(
            Guid.NewGuid(), [], true, "Always on top", "Space",
            Ctrl: true, Alt: false, Shift: false, Win: false,
            HotkeyActionKind.Window, null, null, null, null, WindowOp.ToggleAlwaysOnTop, null, null,
            DateTimeOffset.UnixEpoch, DateTimeOffset.UnixEpoch);

        var model = HotkeyEditModel.FromDto(dto);

        model.ActionKind.Should().Be(HotkeyActionKind.Window);
        model.WindowOp.Should().Be(WindowOp.ToggleAlwaysOnTop);
        model.Ctrl.Should().BeTrue();
    }
}
