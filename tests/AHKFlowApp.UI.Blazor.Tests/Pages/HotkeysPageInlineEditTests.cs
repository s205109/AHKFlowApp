using System.Security.Claims;
using AHKFlowApp.UI.Blazor.Components.Common;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Pages;
using AHKFlowApp.UI.Blazor.Services;
using AHKFlowApp.UI.Blazor.Validation;
using AngleSharp.Dom;
using Bunit;
using FluentAssertions;
using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor;
using MudBlazor.Extensions;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Pages;

public sealed class HotkeysPageInlineEditTests : HotkeysPageTestsBase
{
    [Fact]
    public async Task Page_BlankKey_BlocksCommit_AndShowsValidationMessage()
    {
        IRenderedComponent<Hotkeys> cut = StartInlineEdit(MakeHotkey("Open terminal", "T"));

        await SetKeyAsync(cut, "");
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => cut.Markup.Should().Contain("Key is required"));
        _ = _api.DidNotReceive().UpdateAsync(Arg.Any<Guid>(), Arg.Any<UpdateHotkeyDto>(), Arg.Any<CancellationToken>());
    }

    [Fact]
    public Task Page_BlankDescription_BlocksCommit_AndShowsValidationMessage()
    {
        IRenderedComponent<Hotkeys> cut = StartInlineEdit(MakeHotkey("Open terminal", "T"));

        cut.Find("input[data-test=\"description-input\"]").Input("");
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => cut.Markup.Should().Contain("Description is required"));
        _api.DidNotReceive().UpdateAsync(Arg.Any<Guid>(), Arg.Any<UpdateHotkeyDto>(), Arg.Any<CancellationToken>());
        return Task.CompletedTask;
    }

    [Fact]
    public async Task Page_EditExistingRow_CallsUpdate()
    {
        HotkeyDto dto = MakeHotkey("Open terminal", "T");
        _api.UpdateAsync(dto.Id, Arg.Any<UpdateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Ok(dto with { Key = "F1" }));

        IRenderedComponent<Hotkeys> cut = StartInlineEdit(dto);

        await SetKeyAsync(cut, "F1");
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => _api.Received(1).UpdateAsync(dto.Id,
            Arg.Is<UpdateHotkeyDto>(d => d.Key == "F1"), Arg.Any<CancellationToken>()));
    }

    [Fact]
    public void Page_CommitInlineEdit_RefreshesTheMobileBranch()
    {
        HotkeyDto dto = MakeHotkey("Open terminal", "T");
        _api.UpdateAsync(dto.Id, Arg.Any<UpdateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Ok(dto with { Description = "Renamed" }));

        IRenderedComponent<Hotkeys> cut = StartInlineEdit(dto);

        cut.Find("input[data-test=\"description-input\"]").Input("Renamed");

        // Both branches read the same endpoint, so this is what a real reload brings back.
        StubList(Page(dto with { Description = "Renamed" }));

        cut.Find("button.commit-edit").Click();

        // Both branches render at once, so the assertion names the branch it is about.
        cut.WaitForAssertion(() =>
            cut.Find(".mobile-branch").TextContent.Should().Contain("Renamed"));
    }

    [Fact]
    public void Page_EditRow_WithModifiers_CallsUpdate_AndKeepsActionChipVisible()
    {
        HotkeyDto dto = MakeHotkey("Open terminal", "T");
        _api.UpdateAsync(dto.Id, Arg.Any<UpdateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Ok(dto));

        IRenderedComponent<Hotkeys> cut = StartInlineEdit(dto);

        // The kind is not inline-changeable, so the chip stays on as context for the one
        // payload field beside it — it replaces the old inline Action dropdown.
        cut.Find("[data-test=\"action-chip\"]").TextContent.Should().Contain("Run");
        cut.FindAll("[data-test=\"run-target-input\"]").Should().NotBeEmpty();

        // Ctrl starts on in the fixture, so clearing it is what proves the binding is two-way.
        cut.Find("input[data-test=\"ctrl-checkbox\"]").Change(false);
        cut.Find("input[data-test=\"shift-checkbox\"]").Change(true);
        cut.Find("input[data-test=\"win-checkbox\"]").Change(true);
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => _api.Received(1).UpdateAsync(dto.Id,
            Arg.Is<UpdateHotkeyDto>(d =>
                d.Description == "Open terminal" &&
                d.Key == "T" &&
                !d.Ctrl &&
                !d.Alt &&
                d.Shift &&
                d.Win),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public void Page_EditSendTextRow_CommitsTextAndNotRunTarget()
    {
        HotkeyDto dto = OneHotkeyOfKind(HotkeyActionKind.SendText);
        _api.UpdateAsync(dto.Id, Arg.Any<UpdateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Ok(dto));

        IRenderedComponent<Hotkeys> cut = StartInlineEdit(dto);

        // The other inline-editable kind: one field, bound to Text rather than RunTarget.
        cut.FindAll("[data-test=\"run-target-input\"]").Should().BeEmpty();
        cut.Find("input[data-test=\"text-input\"]").Input("Jane Smith");
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => _api.Received(1).UpdateAsync(dto.Id,
            Arg.Is<UpdateHotkeyDto>(d =>
                d.ActionKind == HotkeyActionKind.SendText &&
                d.Text == "Jane Smith" &&
                d.RunTarget == null),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task Page_EditRow_WithSpecificProfiles_CallsUpdate()
    {
        ProfileDto work = MakeProfile("Work");
        ProfileDto personal = MakeProfile("Personal");
        StubProfiles(work, personal);
        HotkeyDto dto = MakeHotkey("Open terminal", "T");
        _api.UpdateAsync(dto.Id, Arg.Any<UpdateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Ok(dto));

        IRenderedComponent<Hotkeys> cut = StartInlineEdit(dto);

        cut.Find("input[data-test=\"applies-to-all-checkbox\"]").Change(false);
        cut.WaitForAssertion(() => cut.FindComponent<MudSelect<Guid>>().Should().NotBeNull(), TimeSpan.FromSeconds(5));

        await cut.InvokeAsync(() =>
            cut.FindComponent<MudSelect<Guid>>().Instance.SelectedValuesChanged
                .InvokeAsync(new HashSet<Guid> { work.Id, personal.Id }));

        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => _api.Received(1).UpdateAsync(dto.Id,
            Arg.Is<UpdateHotkeyDto>(d =>
                d.AppliesToAllProfiles == false &&
                d.ProfileIds != null &&
                d.ProfileIds.Length == 2 &&
                d.ProfileIds.Contains(work.Id) &&
                d.ProfileIds.Contains(personal.Id)),
            Arg.Any<CancellationToken>()), TimeSpan.FromSeconds(5));
    }

    [Fact]
    public async Task Page_WhenAnyToggleIsReenabled_ClearsSpecificProfilesBeforeUpdate()
    {
        ProfileDto work = MakeProfile("Work");
        StubProfiles(work);
        HotkeyDto dto = MakeHotkey("Open terminal", "T");
        _api.UpdateAsync(dto.Id, Arg.Any<UpdateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Ok(dto));

        IRenderedComponent<Hotkeys> cut = StartInlineEdit(dto);

        cut.Find("input[data-test=\"applies-to-all-checkbox\"]").Change(false);
        cut.WaitForAssertion(() => cut.FindComponent<MudSelect<Guid>>().Should().NotBeNull());
        await cut.InvokeAsync(() =>
            cut.FindComponent<MudSelect<Guid>>().Instance.SelectedValuesChanged
                .InvokeAsync(new HashSet<Guid> { work.Id }));

        cut.Find("input[data-test=\"applies-to-all-checkbox\"]").Change(true);
        cut.WaitForAssertion(() => cut.FindAll("[data-test=\"profile-select\"]").Should().BeEmpty());

        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => _api.Received(1).UpdateAsync(dto.Id,
            Arg.Is<UpdateHotkeyDto>(d =>
                d.AppliesToAllProfiles &&
                d.ProfileIds == null),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public void Page_OnConflictResponse_ApiCalledAndNoException()
    {
        HotkeyDto dto = MakeHotkey("Open terminal", "T");
        _api.UpdateAsync(dto.Id, Arg.Any<UpdateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Failure(ApiResultStatus.Conflict,
                new ApiProblemDetails(null, "Conflict", 409, "Hotkey already exists", null, null)));

        IRenderedComponent<Hotkeys> cut = StartInlineEdit(dto);
        cut.Find("button.commit-edit").Click();

        // MudBlazor snackbars render via portal and are not in the component DOM in bUnit.
        // Assert the API was called (proving the commit path ran and conflict was handled without crash).
        cut.WaitForAssertion(() => _api.Received(1).UpdateAsync(dto.Id,
            Arg.Is<UpdateHotkeyDto>(d => d.Description == "Open terminal"),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public void Page_CategoryEditorShowsMultiSelect_WhenEditing()
    {
        CategoryDto work = new(Guid.NewGuid(), "Work", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        StubCategories(work);

        IRenderedComponent<Hotkeys> cut = StartInlineEdit(MakeHotkey("Open terminal", "T"));

        cut.WaitForAssertion(() => cut.FindAll("[data-test=\"category-select\"]").Should().NotBeEmpty());
    }

    [Fact]
    public void InlineRow_ShowsTheTemplateNoticeForAKeyTheProfileHeaderUses()
    {
        // A profile whose header carries the shipped Caps Lock layer.
        ProfileDto work = new(
            Guid.NewGuid(), "Work", false,
            "#Requires AutoHotkey v2.0\n\n*CapsLock::\n{\n    Send \"{Blind}{LCtrl DownR}\"\n}",
            "", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);

        StubProfiles(work);

        // Run is one of the two inline-editable kinds (HotkeyEditModel.IsInlineEditable).
        HotkeyDto row = new(
            Guid.NewGuid(), [work.Id], false, "Open notepad", "CapsLock", false, false, false, false,
            HotkeyActionKind.Run, null, null, "notepad.exe", RunTargetKind.Application,
            null, null, null, null, null, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);

        IRenderedComponent<Hotkeys> cut = StartInlineEdit(row);

        cut.WaitForAssertion(() =>
            cut.Find("[data-test=\"template-warning\"]").TextContent
                .Should().Be("The header template in Work also uses CapsLock. Your hotkey may not fire."));
    }

    // Backlog 186. The action field is named by the chip beside it, so it says what it holds.
    [Theory]
    [InlineData(HotkeyActionKind.Run, "run-target-input", "Run")]
    [InlineData(HotkeyActionKind.SendText, "text-input", "Send text")]
    public void EditRow_Fields_NameWhatTheyHold(HotkeyActionKind kind, string actionField, string actionName)
    {
        IRenderedComponent<Hotkeys> cut = StartInlineEdit(OneHotkeyOfKind(kind));

        cut.Find("input[data-test=\"description-input\"]").GetAttribute("aria-label").Should().Be("Description");
        cut.Find($"input[data-test=\"{actionField}\"]").GetAttribute("aria-label").Should().Be(actionName);
    }

    // Backlog 189. The key field is named Key, as in the hotkey dialog: its Hotkey column also
    // holds the modifier checkboxes, so the column title would name the whole binding.
    [Fact]
    public void EditRow_Pickers_NameWhatTheyHold()
    {
        IRenderedComponent<Hotkeys> cut = StartInlineEdit(MakeHotkey() with { AppliesToAllProfiles = false });

        cut.Find("input[data-test=\"key-input\"]").GetAttribute("aria-label").Should().Be("Key");
        cut.Find("input[data-test=\"profile-select\"]").GetAttribute("aria-label").Should().Be("Profiles");
        cut.Find("input[data-test=\"category-select\"]").GetAttribute("aria-label").Should().Be("Categories");
    }
}
