using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Validation;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Validation;

public sealed class HotkeyEditModelTests
{
    [Fact]
    public void Clone_CopiesEditableFields_WithoutSharingCollections()
    {
        var profileId = Guid.NewGuid();
        var categoryId = Guid.NewGuid();
        var model = new HotkeyEditModel
        {
            Id = Guid.NewGuid(),
            Description = "Open palette",
            Key = "K",
            Ctrl = true,
            Alt = true,
            Shift = true,
            Win = false,
            Action = HotkeyAction.Run,
            Parameters = "shell:AppsFolder",
            AppliesToAllProfiles = false,
            ProfileIds = [profileId],
            CategoryIds = [categoryId],
        };

        HotkeyEditModel clone = model.Clone();

        clone.Should().BeEquivalentTo(model);
        clone.ProfileIds.Should().NotBeSameAs(model.ProfileIds);
        clone.CategoryIds.Should().NotBeSameAs(model.CategoryIds);
    }
}
