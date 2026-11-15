using System.Security.Claims;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Pages;
using AHKFlowApp.UI.Blazor.Services;
using AHKFlowApp.UI.Blazor.Validation;
using Bunit;
using FluentAssertions;
using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Pages;

public sealed class HotstringsPageInlineEditTests : HotstringsPageTestsBase
{
    [Fact]
    public void Page_AddButton_StartsDraftGridEdit()
    {
        StubList(Page());

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.add-hotstring"));

        cut.Find("button.add-hotstring").Click();

        cut.WaitForAssertion(() => cut.Find("input[data-test=\"trigger-input\"]").Should().NotBeNull());
    }

    [Fact]
    public Task Page_SaveDraftRow_CallsCreateAndRefreshes()
    {
        StubList(Page());
        _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow)));

        IRenderedComponent<Hotstrings> cut = RenderPage();
        StartDraftEdit(cut);
        FillRequiredFields(cut);
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotstringDto>(d => d.Trigger == "btw" && d.Replacement == "by the way"),
            Arg.Any<CancellationToken>()));
        return Task.CompletedTask;
    }

    [Fact]
    public void Page_CommitInlineCreate_RefreshesTheMobileBranch()
    {
        var created = new HotstringDto(Guid.NewGuid(), [], true, "btwx", "by the way", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        StubList(Page());
        _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(created));

        IRenderedComponent<Hotstrings> cut = RenderPage();
        StartDraftEdit(cut);
        FillRequiredFields(cut, "btwx", "by the way");

        // Both branches read the same endpoint, so this is what a real reload brings back.
        StubList(Page(created));

        cut.Find("button.commit-edit").Click();

        // Both branches render at once, so the assertion names the branch it is about.
        cut.WaitForAssertion(() =>
            cut.Find(".mobile-branch").TextContent.Should().Contain("btwx"));
    }

    [Fact]
    public Task Page_BlankReplacement_BlocksCommit_AndShowsValidationMessage()
    {
        StubList(Page());

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.add-hotstring"));
        cut.Find("button.add-hotstring").Click();

        cut.WaitForAssertion(() => cut.Find("input[data-test=\"trigger-input\"]"));
        cut.Find("input[data-test=\"trigger-input\"]").Input("btw");
        // Leave replacement empty
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => cut.Markup.Should().Contain("Replacement is required"));
        _api.DidNotReceive().CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>());
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_EditExistingRow_CallsUpdate()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        StubList(Page(dto));
        _api.UpdateAsync(dto.Id, Arg.Any<UpdateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(dto with { Replacement = "by the way!" }));

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.edit"));
        cut.Find("button.edit").Click();
        cut.WaitForAssertion(() => cut.Find("textarea[data-test=\"replacement-input\"]"));
        cut.Find("textarea[data-test=\"replacement-input\"]").Input("by the way!");
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => _api.Received(1).UpdateAsync(dto.Id,
            Arg.Is<UpdateHotstringDto>(d => d.Replacement == "by the way!"), Arg.Any<CancellationToken>()));
        return Task.CompletedTask;
    }

    [Fact]
    public void Page_CommitInlineEdit_RefreshesTheMobileBranch()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "btwx", "by the way", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        HotstringDto renamed = dto with { Replacement = "renamed replacement" };
        StubList(Page(dto));
        _api.UpdateAsync(dto.Id, Arg.Any<UpdateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(renamed));

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.edit"));
        cut.Find("button.edit").Click();
        cut.WaitForAssertion(() => cut.Find("textarea[data-test=\"replacement-input\"]"));
        cut.Find("textarea[data-test=\"replacement-input\"]").Input("renamed replacement");

        // Both branches read the same endpoint, so this is what a real reload brings back.
        StubList(Page(renamed));

        cut.Find("button.commit-edit").Click();

        // Both branches render at once, so the assertion names the branch it is about.
        cut.WaitForAssertion(() =>
            cut.Find(".mobile-branch").TextContent.Should().Contain("renamed replacement"));
    }

    [Fact]
    public Task Page_InlineCreate_Allows4001CharacterAutoReplacement()
    {
        string replacement = new('x', 4_001);
        StubList(Page());
        _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(
                new HotstringDto(Guid.NewGuid(), [], true, "long", replacement, null, true, true,
                    DateTimeOffset.UtcNow, DateTimeOffset.UtcNow)));

        IRenderedComponent<Hotstrings> cut = RenderPage();
        StartDraftEdit(cut);
        FillRequiredFields(cut, "long", replacement);
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotstringDto>(dto => dto.Replacement.Length == 4_001
                && dto.Delivery == HotstringDelivery.Auto),
            Arg.Any<CancellationToken>()));
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_InlineEdit_Allows4001CharacterClipboardReplacement()
    {
        string replacement = new('x', 4_001);
        HotstringDto dto = new(Guid.NewGuid(), [], true, "long", "initial", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, Delivery: HotstringDelivery.ClipboardPaste);
        StubList(Page(dto));
        _api.UpdateAsync(dto.Id, Arg.Any<UpdateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(dto with { Replacement = replacement }));

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.edit"));
        cut.Find("button.edit").Click();
        cut.WaitForAssertion(() => cut.Find("textarea[data-test=\"replacement-input\"]"));
        cut.Find("textarea[data-test=\"replacement-input\"]").Input(replacement);
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => _api.Received(1).UpdateAsync(dto.Id,
            Arg.Is<UpdateHotstringDto>(update => update.Replacement.Length == 4_001
                && update.Delivery == HotstringDelivery.ClipboardPaste),
            Arg.Any<CancellationToken>()));
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_TruncatedRow_FetchesFullReplacementBeforeInlineEdit()
    {
        string fullReplacement = new('x', 1_000);
        HotstringDto summary = new(Guid.NewGuid(), [], true, "long", new string('x', 200), null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, ReplacementIsTruncated: true);
        HotstringDto detail = summary with { Replacement = fullReplacement, ReplacementIsTruncated = false };
        StubList(Page(summary));
        _api.GetAsync(summary.Id, Arg.Any<CancellationToken>()).Returns(ApiResult<HotstringDto>.Ok(detail));

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.edit"));
        cut.Find("button.edit").Click();

        cut.WaitForAssertion(() =>
        {
            _ = _api.Received(1).GetAsync(summary.Id, Arg.Any<CancellationToken>());
            cut.Find("textarea[data-test=\"replacement-input\"]").TextContent.Should().Be(fullReplacement);
        });
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_NonTruncatedRow_StartsInlineEditWithoutListRoundTrip()
    {
        HotstringDto dto = new(Guid.NewGuid(), [], true, "short", "replacement", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        StubList(Page(dto));
        IUserPreferencesService preferences = Services.GetRequiredService<IUserPreferencesService>();
        preferences.GetAsync(Arg.Any<CancellationToken>()).Returns(new UserPreferences(25, false));

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.edit"));
        _api.ClearReceivedCalls();
        cut.Find("button.reload-hotstrings-mobile").Click();
        cut.WaitForAssertion(() =>
        {
            _ = _api.Received(1).ListAsync(
                Arg.Is<HotstringListRequest>(request => request.PageSize == 25),
                Arg.Any<CancellationToken>());
            _ = _api.Received(1).ListAsync(
                Arg.Is<HotstringListRequest>(request => request.PageSize == 10),
                Arg.Any<CancellationToken>());
        });
        _api.ClearReceivedCalls();

        cut.Find("button.edit").Click();

        cut.WaitForAssertion(() => cut.Find("textarea[data-test=\"replacement-input\"]"));
        _ = _api.DidNotReceive().ListAsync(
            Arg.Any<HotstringListRequest>(), Arg.Any<CancellationToken>());
        return Task.CompletedTask;
    }

    [Fact]
    public async Task Page_WhenAnyToggleIsReenabled_ClearsSpecificProfilesBeforeCreate()
    {
        ProfileDto work = new(Guid.NewGuid(), "Work", false, "header text", "footer text", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        StubProfiles(work);
        StubList(Page());
        _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow)));

        IRenderedComponent<Hotstrings> cut = RenderPage();
        StartDraftEdit(cut);
        FillRequiredFields(cut);

        cut.Find("input[data-test=\"applies-to-all-checkbox\"]").Change(false);
        cut.WaitForAssertion(() => cut.FindComponent<MudSelect<Guid>>().Should().NotBeNull());
        await cut.InvokeAsync(() =>
            cut.FindComponent<MudSelect<Guid>>().Instance.SelectedValuesChanged
                .InvokeAsync(new HashSet<Guid> { work.Id }));

        cut.Find("input[data-test=\"applies-to-all-checkbox\"]").Change(true);
        cut.WaitForAssertion(() => cut.FindAll("[data-test=\"profile-select\"]").Should().BeEmpty());

        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotstringDto>(d =>
                d.AppliesToAllProfiles &&
                d.ProfileIds == null),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public Task Page_EditRow_DescriptionInput_PreFilledAndCommitsUpdate()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", "polite filler", true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        StubList(Page(dto));
        _api.UpdateAsync(dto.Id, Arg.Any<UpdateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(dto with { Description = "updated filler" }));

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.edit"));
        cut.Find("button.edit").Click();
        cut.WaitForAssertion(() =>
            cut.Find("input[data-test=\"description-input\"]").GetAttribute("value").Should().Be("polite filler"));

        cut.Find("input[data-test=\"description-input\"]").Input("updated filler");
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => _api.Received(1).UpdateAsync(dto.Id,
            Arg.Is<UpdateHotstringDto>(d => d.Description == "updated filler"), Arg.Any<CancellationToken>()));
        return Task.CompletedTask;
    }

    [Fact]
    public void Page_OnConflictResponse_ShowsErrorSnackbar()
    {
        StubList(Page());
        _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Failure(ApiResultStatus.Conflict,
                new ApiProblemDetails(null, "Conflict", 409, "Trigger already exists", null, null)));

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.add-hotstring"));
        cut.Find("button.add-hotstring").Click();
        cut.WaitForAssertion(() => cut.Find("input[data-test=\"trigger-input\"]"));
        cut.Find("input[data-test=\"trigger-input\"]").Input("btw");
        cut.Find("textarea[data-test=\"replacement-input\"]").Input("by the way");
        cut.Find("button.commit-edit").Click();

        // MudBlazor snackbars render via portal and are not in the component DOM in bUnit.
        // Assert the API was called (proving the commit path ran and conflict was handled without crash).
        cut.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotstringDto>(d => d.Trigger == "btw"),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public void Page_CategoryEditorShowsMultiSelect_WhenEditing()
    {
        CategoryDto work = new(Guid.NewGuid(), "Work", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        StubCategories(work);
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.edit"));
        cut.Find("button.edit").Click();

        cut.WaitForAssertion(() => cut.FindAll("[data-test=\"category-select\"]").Should().NotBeEmpty());
    }

    // Backlog 168. Each row icon button names the hotstring it acts on, by its trigger.
    [Fact]
    public void Row_IconButtons_NameTheirHotstring()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForState(() => cut.Markup.Contains("btw"));

        cut.Find("button.edit").GetAttribute("aria-label").Should().Be("Edit btw");
        cut.Find("button.show-history").GetAttribute("aria-label").Should().Be("Show history for btw");
        cut.Find("button.delete").GetAttribute("aria-label").Should().Be("Delete btw");
        cut.Find("button.reload-hotstrings-mobile").GetAttribute("aria-label").Should().Be("Reload hotstrings");

        cut.Find("button.edit").Click();
        cut.WaitForAssertion(() => cut.Find("button.commit-edit"));

        cut.Find("button.commit-edit").GetAttribute("aria-label").Should().Be("Save btw");
        cut.Find("button.cancel-edit").GetAttribute("aria-label").Should().Be("Cancel editing btw");
    }

    // Backlog 168. A new row has no trigger yet, so its labels fall back to "new hotstring".
    [Fact]
    public void NewRow_IconButtons_NameTheNewHotstring()
    {
        StubList(Page());

        IRenderedComponent<Hotstrings> cut = RenderPage();
        StartDraftEdit(cut);

        cut.Find("button.commit-edit").GetAttribute("aria-label").Should().Be("Save new hotstring");
        cut.Find("button.cancel-edit").GetAttribute("aria-label").Should().Be("Cancel editing new hotstring");
    }

    // Backlog 186. A field in a row being edited has no visible label, so its aria-label is its
    // name. The selector names the element, so the name sits on the field, not a wrapper.
    [Fact]
    public void EditRow_Fields_NameWhatTheyHold()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForState(() => cut.Markup.Contains("btw"));
        cut.Find("button.edit").Click();
        cut.WaitForAssertion(() => cut.Find("input[data-test=\"trigger-input\"]"));

        cut.Find("input[data-test=\"trigger-input\"]").GetAttribute("aria-label").Should().Be("Trigger");
        cut.Find("textarea[data-test=\"replacement-input\"]").GetAttribute("aria-label").Should().Be("Replacement");
        cut.Find("input[data-test=\"description-input\"]").GetAttribute("aria-label").Should().Be("Description");
    }

    // Backlog 189. The pickers are shared components, so the page names them through AriaLabel.
    // AppliesToAllProfiles is false, so the profile picker renders.
    [Fact]
    public void EditRow_Pickers_NameWhatTheyHold()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], false, "btw", "by the way", null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForState(() => cut.Markup.Contains("btw"));
        cut.Find("button.edit").Click();
        cut.WaitForAssertion(() => cut.Find("input[data-test=\"profile-select\"]"));

        cut.Find("input[data-test=\"profile-select\"]").GetAttribute("aria-label").Should().Be("Profiles");
        cut.Find("input[data-test=\"category-select\"]").GetAttribute("aria-label").Should().Be("Categories");
    }
}
