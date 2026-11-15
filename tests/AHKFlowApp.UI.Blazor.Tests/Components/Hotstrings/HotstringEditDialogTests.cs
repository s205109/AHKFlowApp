using AHKFlowApp.UI.Blazor.Components.Common;
using AHKFlowApp.UI.Blazor.Components.Hotstrings;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Helpers;
using AHKFlowApp.UI.Blazor.Services;
using AHKFlowApp.UI.Blazor.Validation;
using Bunit;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Time.Testing;
using MudBlazor;
using MudBlazor.Extensions;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Components.Hotstrings;

public sealed class HotstringEditDialogTests : HotstringEditDialogTestsBase
{
    [Fact]
    public async Task CreateMode_RendersEmptyFields()
    {
        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            await dialogService.ShowAsync<HotstringEditDialog>("New",
                new DialogParameters
                {
                    [nameof(HotstringEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                    [nameof(HotstringEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
                },
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        provider.WaitForAssertion(() => provider.Find("input[data-test=\"trigger-input\"]").GetAttribute("value").Should().Be(""));
        provider.Find("textarea[data-test=\"replacement-input\"]").TextContent.Should().Be("");
    }

    [Fact]
    public async Task CreateMode_TriggerInsideWordsCheckbox_StartsUnticked()
    {
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(new HotstringEditModel());

        provider.WaitForAssertion(() => IsInsideWordsChecked(provider).Should().BeFalse());
    }

    // Fails if the checkbox is hardcoded to unticked instead of bound to the model.
    [Fact]
    public async Task EditMode_SavedWithTriggerInsideWords_StartsTicked()
    {
        HotstringEditModel saved = new()
        {
            Id = Guid.NewGuid(),
            Trigger = "btw",
            Replacement = "by the way",
            IsTriggerInsideWord = true,
        };

        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(saved);

        provider.WaitForAssertion(() => IsInsideWordsChecked(provider).Should().BeTrue());
    }

    [Fact]
    public async Task EditMode_PrefillsFieldsFromItem()
    {
        HotstringEditModel item = new()
        {
            Id = Guid.NewGuid(),
            Trigger = "btw",
            Replacement = "by the way",
            Description = "polite filler",
        };

        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            await dialogService.ShowAsync<HotstringEditDialog>("Edit",
                new DialogParameters
                {
                    [nameof(HotstringEditDialog.Item)] = item,
                    [nameof(HotstringEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                    [nameof(HotstringEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
                },
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        provider.WaitForAssertion(() => provider.Find("input[data-test=\"trigger-input\"]").GetAttribute("value").Should().Be("btw"));
        provider.Find("textarea[data-test=\"replacement-input\"]").TextContent.Should().Contain("by the way");
    }

    [Fact]
    public async Task SaveInCreateMode_CallsCreateAsync()
    {
        HotstringDto created = new(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(created));

        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            await dialogService.ShowAsync<HotstringEditDialog>("New",
                new DialogParameters
                {
                    [nameof(HotstringEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                    [nameof(HotstringEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
                },
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        provider.WaitForAssertion(() => provider.Find("input[data-test=\"trigger-input\"]"));
        await provider.InvokeAsync(() => provider.Find("input[data-test=\"trigger-input\"]").Input("btw"));
        await provider.InvokeAsync(() => provider.Find("textarea[data-test=\"replacement-input\"]").Input("by the way"));
        await provider.InvokeAsync(() => provider.Find("button.commit-edit").Click());

        provider.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotstringDto>(d => d.Trigger == "btw" && d.Replacement == "by the way"),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task SaveInEditMode_CallsUpdateAsync()
    {
        HotstringEditModel item = new()
        {
            Id = Guid.NewGuid(),
            Trigger = "btw",
            Replacement = "by the way",
        };
        _api.UpdateAsync(item.Id!.Value, Arg.Any<UpdateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(
                new HotstringDto(item.Id.Value, [], true, "btw", "by the way!", null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow)));

        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            await dialogService.ShowAsync<HotstringEditDialog>("Edit",
                new DialogParameters
                {
                    [nameof(HotstringEditDialog.Item)] = item,
                    [nameof(HotstringEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                    [nameof(HotstringEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
                },
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        provider.WaitForAssertion(() => provider.Find("textarea[data-test=\"replacement-input\"]"));
        await provider.InvokeAsync(() => provider.Find("textarea[data-test=\"replacement-input\"]").Input("by the way!"));
        await provider.InvokeAsync(() => provider.Find("button.commit-edit").Click());

        provider.WaitForAssertion(() => _api.Received(1).UpdateAsync(
            item.Id.Value,
            Arg.Is<UpdateHotstringDto>(d => d.Replacement == "by the way!"),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task SaveConflict_ShowsTriggerErrorInline()
    {
        _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Failure(ApiResultStatus.Conflict,
                new ApiProblemDetails(null, "Conflict", 409, "Trigger already exists", null, null)));

        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            await dialogService.ShowAsync<HotstringEditDialog>("New",
                new DialogParameters
                {
                    [nameof(HotstringEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                    [nameof(HotstringEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
                },
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        provider.WaitForAssertion(() => provider.Find("input[data-test=\"trigger-input\"]"));
        await provider.InvokeAsync(() => provider.Find("input[data-test=\"trigger-input\"]").Input("btw"));
        await provider.InvokeAsync(() => provider.Find("textarea[data-test=\"replacement-input\"]").Input("by the way"));
        await provider.InvokeAsync(() => provider.Find("button.commit-edit").Click());

        provider.WaitForAssertion(() => provider.Markup.Should().Contain("Trigger already exists"));
        provider.FindAll(".mud-alert").Should().BeEmpty();
    }

    [Fact]
    public async Task SaveInCreateMode_WithCaseSensitiveChecked_SendsNewFlags()
    {
        HotstringDto created = new(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(created));

        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            await dialogService.ShowAsync<HotstringEditDialog>("New",
                new DialogParameters
                {
                    [nameof(HotstringEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                    [nameof(HotstringEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
                },
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        provider.WaitForAssertion(() => provider.Find("input[data-test=\"trigger-input\"]"));
        await provider.InvokeAsync(() => provider.Find("input[data-test=\"trigger-input\"]").Input("btw"));
        await provider.InvokeAsync(() => provider.Find("textarea[data-test=\"replacement-input\"]").Input("by the way"));
        await provider.InvokeAsync(() => provider.Find("input[data-test=\"case-sensitive-checkbox\"]").Change(true));
        await provider.InvokeAsync(() => provider.Find("input[data-test=\"omit-ending-checkbox\"]").Change(true));
        await provider.InvokeAsync(() => provider.Find("button.commit-edit").Click());

        provider.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotstringDto>(d => d.IsCaseSensitive && d.OmitEndingCharacter),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task Save_WithDateTimeKind_PostsDtoWithEmptyReplacement()
    {
        HotstringDto created = new(Guid.NewGuid(), [], true, "date", "", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(created));

        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]"));

        await provider.InvokeAsync(() => provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Contains("Date & time")).Click());
        provider.WaitForAssertion(() => provider.Find("[data-test=\"datetime-format-select\"]"));
        await SelectFormatAsync(provider, "yyyy-MM-dd");

        await provider.InvokeAsync(() => provider.Find("input[data-test=\"trigger-input\"]").Input("date"));
        await provider.InvokeAsync(() => provider.Find("button.commit-edit").Click());

        provider.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotstringDto>(d => d.Kind == HotstringKind.DateTime && d.Replacement == ""),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task ContextSwitch_TurnedOn_ShowsMatchTypeAndValueFields()
    {
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"context-switch\"]"));

        provider.FindAll("[data-test=\"context-match-type-select\"]").Should().BeEmpty();
        provider.FindAll("[data-test=\"context-value-input\"]").Should().BeEmpty();

        await provider.InvokeAsync(() => provider.Find("input[data-test=\"context-switch\"]").Change(true));

        provider.WaitForAssertion(() =>
        {
            provider.Find("[data-test=\"context-match-type-select\"]").Should().NotBeNull();
            provider.Find("[data-test=\"context-value-input\"]").Should().NotBeNull();
        });
    }

    [Fact]
    public async Task ContextSwitch_TurnedOff_ClearsContextFields()
    {
        HotstringEditModel item = new() { Trigger = "btw", Replacement = "by the way" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"context-switch\"]"));

        await provider.InvokeAsync(() => provider.Find("input[data-test=\"context-switch\"]").Change(true));
        provider.WaitForAssertion(() => provider.Find("[data-test=\"context-value-input\"]"));
        await provider.InvokeAsync(() => provider.Find("input[data-test=\"context-value-input\"]").Input("notepad.exe"));

        provider.WaitForAssertion(() => item.ContextValue.Should().Be("notepad.exe"));

        await provider.InvokeAsync(() => provider.Find("input[data-test=\"context-switch\"]").Change(false));

        provider.WaitForAssertion(() =>
        {
            item.ContextMatchType.Should().BeNull();
            item.ContextValue.Should().BeNull();
            provider.FindAll("[data-test=\"context-value-input\"]").Should().BeEmpty();
        });
    }

    [Fact]
    public async Task ContextValueField_ExecutableSelected_ShowsExePlaceholder()
    {
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"context-switch\"]"));

        await provider.InvokeAsync(() => provider.Find("input[data-test=\"context-switch\"]").Change(true));

        provider.WaitForAssertion(() =>
            provider.Find("input[data-test=\"context-value-input\"]").GetAttribute("placeholder").Should().Be("notepad.exe"));
    }

    [Fact]
    public async Task Save_WithContext_SendsContextInCreateDto()
    {
        HotstringDto created = new(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(created));

        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"context-switch\"]"));

        await provider.InvokeAsync(() => provider.Find("input[data-test=\"trigger-input\"]").Input("btw"));
        await provider.InvokeAsync(() => provider.Find("textarea[data-test=\"replacement-input\"]").Input("by the way"));
        await provider.InvokeAsync(() => provider.Find("input[data-test=\"context-switch\"]").Change(true));
        provider.WaitForAssertion(() => provider.Find("input[data-test=\"context-value-input\"]"));
        await provider.InvokeAsync(() => provider.Find("input[data-test=\"context-value-input\"]").Input("notepad.exe"));
        await provider.InvokeAsync(() => provider.Find("button.commit-edit").Click());

        provider.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotstringDto>(d => d.ContextMatchType == WindowMatchType.Executable && d.ContextValue == "notepad.exe"),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task Save_ContextOnEmptyValue_BlockedByValidation()
    {
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"context-switch\"]"));

        await provider.InvokeAsync(() => provider.Find("input[data-test=\"trigger-input\"]").Input("btw"));
        await provider.InvokeAsync(() => provider.Find("textarea[data-test=\"replacement-input\"]").Input("by the way"));
        await provider.InvokeAsync(() => provider.Find("input[data-test=\"context-switch\"]").Change(true));
        provider.WaitForAssertion(() => provider.Find("input[data-test=\"context-value-input\"]"));
        // Value field left empty while context is on.
        await provider.InvokeAsync(() => provider.Find("button.commit-edit").Click());

        // The rendered required message is the signal that the blocked save finished.
        provider.WaitForAssertion(() => provider.Markup.Should().Contain("Value is required"));

        _ = _api.DidNotReceive().CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task ScriptSuggestion_TextLooksLikeCode_ShowsDismissibleAlert()
    {
        HotstringEditModel item = new() { Trigger = "sig", Kind = HotstringKind.Text, Replacement = "Send \"{Enter}\"" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);

        provider.WaitForAssertion(() => provider.Find("[data-test=\"script-suggestion\"]").Should().NotBeNull());

        await provider.InvokeAsync(() => provider.Find("[data-test=\"script-suggestion\"] button.mud-icon-button").Click());

        provider.WaitForAssertion(() => provider.FindAll("[data-test=\"script-suggestion\"]").Should().BeEmpty());
    }

    [Fact]
    public async Task Suggestions_ReplacementHasMacroToken_ShowsMacroSuggestionOnly()
    {
        // A recognized macro token contains braces, so LooksLikeAhkCode alone would also flag it
        // as Script-like. Macro tokens must take precedence: only the Macro suggestion shows.
        HotstringEditModel item = new() { Trigger = "hi", Kind = HotstringKind.Text, Replacement = "Hi {{cursor}}" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);

        provider.WaitForAssertion(() => provider.Find("[data-test=\"macro-suggestion\"]").Should().NotBeNull());
        provider.FindAll("[data-test=\"script-suggestion\"]").Should().BeEmpty();
    }

    [Fact]
    public async Task Save_RawKind_SendsDefinitionVerbatimInCreateDto()
    {
        HotstringDto created = new(Guid.NewGuid(), [], true, "ftw", ":K1000 SE*:ftw::for the win", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, [], HotstringKind.Raw);
        _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(created));

        HotstringEditModel item = new() { Kind = HotstringKind.Raw, Replacement = ":K1000 SE*:ftw::for the win" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("button.commit-edit"));

        await provider.InvokeAsync(() => provider.Find("button.commit-edit").Click());

        provider.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotstringDto>(d => d.Kind == HotstringKind.Raw && d.Replacement == ":K1000 SE*:ftw::for the win"),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task Save_RawBraceImbalance_WithPreviewCollapsed_ShowsInlineRawDefinitionError()
    {
        const string braceMessage = "Raw definition must have balanced braces.";
        _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Failure(ApiResultStatus.Validation,
                new ApiProblemDetails(null, "Bad Request", 400, null, null,
                    new Dictionary<string, string[]> { ["Input.Replacement"] = [braceMessage] })));

        HotstringEditModel item = new() { Kind = HotstringKind.Raw, Replacement = ":*:m::\n{\nSend foo" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("button.commit-edit"));

        // Preview panel is never expanded — this exercises SaveAsync's own field-error mapping,
        // not ApplyPreviewResult's.
        await provider.InvokeAsync(() => provider.Find("button.commit-edit").Click());

        provider.WaitForAssertion(() =>
        {
            MudTextField<string> replacementField = provider.FindComponents<MudTextField<string>>()
                .Single(f => f.Instance.Label == "Raw definition").Instance;
            replacementField.GetState(x => x.ErrorText).Should().Be(braceMessage);

            provider.FindAll(".mud-alert").Should().NotContain(e => e.TextContent.Contains(braceMessage),
                "a field-mapped save error shows inline only, never duplicated in an alert");
        });
    }

    [Theory]
    [InlineData(HotstringDelivery.Auto)]
    [InlineData(HotstringDelivery.ClipboardPaste)]
    public async Task Save_LongTextReplacement_AllowsAutoAndClipboardDelivery(HotstringDelivery delivery)
    {
        string replacement = new('x', 4_001);
        HotstringEditModel item = new()
        {
            Trigger = "long",
            Replacement = "initial",
            Delivery = delivery,
        };
        _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(
                new HotstringDto(Guid.NewGuid(), [], true, "long", replacement, null, true, true,
                    DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, Delivery: delivery)));

        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("textarea[data-test=\"replacement-input\"]"));
        await provider.InvokeAsync(() => provider.Find("textarea[data-test=\"replacement-input\"]").Input(replacement));
        await provider.InvokeAsync(() => provider.Find("button.commit-edit").Click());

        provider.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotstringDto>(dto => dto.Replacement.Length == 4_001 && dto.Delivery == delivery),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task DeliverySelector_TextOnly_ShowsHintAndResetsWhenKindChanges()
    {
        HotstringEditModel item = new()
        {
            Trigger = "long",
            Replacement = "",
            Delivery = HotstringDelivery.ClipboardPaste,
        };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);

        provider.WaitForAssertion(() => provider.Find("[data-test=\"delivery-select\"]"));
        provider.Markup.Should().Contain("Auto types a replacement shorter than 200 characters.");
        provider.Markup.Should().NotContain("case-conforming");

        IRenderedComponent<MudToggleGroup<HotstringKind>> kindSelector = provider.FindComponent<MudToggleGroup<HotstringKind>>();
        await provider.InvokeAsync(() => kindSelector.Instance.ValueChanged.InvokeAsync(HotstringKind.Macro));

        provider.WaitForAssertion(() =>
        {
            item.Delivery.Should().Be(HotstringDelivery.Auto);
            provider.FindAll("[data-test=\"delivery-select\"]").Should().BeEmpty();
        });
    }

    [Theory]
    [InlineData(HotstringDelivery.Auto, "Auto")]
    [InlineData(HotstringDelivery.Type, "Typed")]
    [InlineData(HotstringDelivery.ClipboardPaste, "Clipboard")]
    public void DeliveryOptionLabel_UsesGlossaryWording(HotstringDelivery delivery, string expected)
    {
        // The delivery picker renders these three labels (HotstringEditDialog.razor). CONTEXT.md
        // lists "Hotstring" under Avoid for Delivery — it overloaded the name of the whole entity.
        DeliveryDisplay.OptionLabel(delivery).Should().Be(expected);
    }

    [Fact]
    public async Task DeliverySelector_OpenMenu_RendersGlossaryOptions()
    {
        HotstringEditModel item = new() { Trigger = "btw", Replacement = "by the way" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"delivery-select\"]"));

        // The theory above covers the helper. This covers the dialog markup actually calling it —
        // swapping the literals back to "Hotstring" must fail here.
        IRenderedComponent<MudSelect<HotstringDelivery>> select =
            provider.FindComponent<MudSelect<HotstringDelivery>>();
        await provider.InvokeAsync(select.Instance.OpenMenu);

        IRenderedComponent<MudPopoverProvider> popover = _popoverProvider!;
        popover.WaitForAssertion(() =>
        {
            string menu = popover.Markup;
            menu.Should().Contain("Typed");
            menu.Should().Contain("Auto");
            menu.Should().Contain("Clipboard");
            menu.Should().NotContain("Hotstring");
        });
    }

    // Backlog 211: an item with no profile opened with an empty Profiles field and no reason.
    [Fact]
    public async Task EditMode_ItemWithNoProfile_ShowsTheNoticeUntilAProfileIsChosen()
    {
        ProfileDto work = new(Guid.NewGuid(), "Work", false, "", "", DateTimeOffset.UnixEpoch, DateTimeOffset.UnixEpoch);
        // Built the way the grid opens the dialog: from the stored DTO, then cloned.
        HotstringEditModel item = HotstringEditModel.FromDto(new HotstringDto(Guid.NewGuid(), [], false, "orphan", "x",
            null, true, false, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow)).Clone();

        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item, work);

        provider.WaitForAssertion(() => provider.Find("[data-test=\"no-profile-notice\"]").TextContent
            .Should().Contain("This item applies to no profile, so no script contains it. Choose its profiles, or turn on Apply to all profiles."));

        await provider.InvokeAsync(() => provider
            .FindComponents<EntityMultiSelect>()
            .Single(s => s.Instance.DataTest == "profile-select")
            .Instance.SelectedIdsChanged.InvokeAsync([work.Id]));

        provider.WaitForAssertion(() => provider.FindAll("[data-test=\"no-profile-notice\"]").Should().BeEmpty());
    }

    // Backlog 211: an unsaved item applies to nothing yet, so it gets no notice.
    [Fact]
    public async Task CreateMode_NoProfileChosen_ShowsNoNotice()
    {
        IRenderedComponent<MudDialogProvider> provider =
            await RenderDialogAsync(new HotstringEditModel { AppliesToAllProfiles = false });

        provider.WaitForAssertion(() => provider.Find("[data-test=\"profile-select\"]"));
        provider.FindAll("[data-test=\"no-profile-notice\"]").Should().BeEmpty();
    }

    // Backlog 175: the dialog showed no broken rule until Save. Every rule must show at open on its
    // visible input, and a preview at open must not replace them (Review Focus 4).
    [Fact]
    public async Task EditMode_BrokenRulesOnVisibleInputs_ShowInlineAndOutlastThePreview()
    {
        const string quotes = "Value under Window context must not contain double quotes.";
        const string backticks = "Value under Window context must not contain backticks.";
        const string description = "Description must be 200 characters or fewer.";
        _api.PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringPreviewDto>.Failure(ApiResultStatus.Validation,
                new ApiProblemDetails(null, "Bad Request", 400, null, null,
                    new Dictionary<string, string[]> { ["Input.ContextValue"] = ["A preview message."] })));
        HotstringEditModel item = HotstringEditModel.FromDto(new HotstringDto(
            Guid.NewGuid(), [], false, "btw", "by the way", new string('d', 201), true, false,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow,
            ContextMatchType: WindowMatchType.TitleContains, ContextValue: "a \" ` b",
            BrokenRules: [new("ContextValue", quotes), new("ContextValue", backticks), new("Description", description)])).Clone();

        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        DisablePreviewDebounce(provider);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"ahk-preview\"]"));
        await provider.InvokeAsync(() => provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click());
        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>()));
        await PreviewRun(provider);

        provider.WaitForAssertion(() =>
            provider.FindComponents<MudTextField<string>>().Single(f => f.Instance.Label == "Value").Instance
                .GetState(x => x.ErrorText).Should().Be($"{quotes} {backticks}"));
        provider.FindComponents<MudTextField<string>>().Single(f => f.Instance.Label == "Description").Instance
            .GetState(x => x.ErrorText).Should().Be(description);
        provider.Find("[data-test=\"broken-rules-notice\"]").TextContent.Should()
            .Contain("This item breaks rules that every save must pass. Fix the values marked below before you save.")
            .And.NotContain("These rules belong to fields that are not shown:");
    }

    // Backlog 175 (Review Focus 5): pressing Save must still reach the API, and its own result
    // then replaces the broken rules, as Save's result did before.
    [Fact]
    public async Task EditMode_SavePressed_SaveResultReplacesTheBrokenRules()
    {
        _api.UpdateAsync(Arg.Any<Guid>(), Arg.Any<UpdateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Failure(ApiResultStatus.Validation,
                new ApiProblemDetails(null, "Bad Request", 400, null, null,
                    new Dictionary<string, string[]> { ["ContextValue"] = ["Save says this."] })));
        HotstringEditModel item = HotstringEditModel.FromDto(new HotstringDto(
            Guid.NewGuid(), [], false, "btw", "by the way", null, true, false,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow,
            ContextMatchType: WindowMatchType.TitleContains, ContextValue: "a \" b",
            BrokenRules: [new("ContextValue", "Value under Window context must not contain double quotes.")])).Clone();

        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"broken-rules-notice\"]"));
        await provider.InvokeAsync(() => provider.Find("button.commit-edit").Click());

        provider.WaitForAssertion(() =>
            provider.FindComponents<MudTextField<string>>().Single(f => f.Instance.Label == "Value").Instance
                .GetState(x => x.ErrorText).Should().Be("Save says this."));
        await _api.Received(1).UpdateAsync(Arg.Any<Guid>(), Arg.Any<UpdateHotstringDto>(), Arg.Any<CancellationToken>());
        provider.FindAll("[data-test=\"broken-rules-notice\"]").Should().BeEmpty();
    }

    // Backlog 175: MudBlazor validates some inputs once the dialog opens, and that clears an Error
    // set from outside. Every kind of input must still show its broken rule at open.
    [Theory]
    [InlineData(HotstringKind.Text, "Trigger")]
    [InlineData(HotstringKind.Text, "Replacement")]
    [InlineData(HotstringKind.Text, "Description")]
    [InlineData(HotstringKind.Text, "Kind")]
    [InlineData(HotstringKind.Text, "Delivery")]
    [InlineData(HotstringKind.Text, "ContextMatchType")]
    [InlineData(HotstringKind.Text, "ContextValue")]
    [InlineData(HotstringKind.DateTime, "DateTimeFormat")]
    [InlineData(HotstringKind.DateTime, "DateOffsetAmount")]
    [InlineData(HotstringKind.DateTime, "DateOffsetUnit")]
    [InlineData(HotstringKind.Macro, "Replacement")]
    public async Task EditMode_BrokenRule_ShowsOnItsOwnInputAtOpen(HotstringKind kind, string field)
    {
        string message = $"Broken {field}.";
        HotstringEditModel item = HotstringEditModel.FromDto(new HotstringDto(
            Guid.NewGuid(), [], true, "btw", "by the way", "A note", true, false,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow,
            Kind: kind, DateTimeFormat: "yyyy-MM-dd", DateOffsetAmount: 1, DateOffsetUnit: DateOffsetUnit.Days,
            ContextMatchType: WindowMatchType.TitleContains, ContextValue: "x", Delivery: HotstringDelivery.Auto,
            BrokenRules: [new(field, message)])).Clone();

        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);

        provider.WaitForAssertion(() => provider.Markup.Should().Contain(message));
        provider.Find("[data-test=\"broken-rules-notice\"]").TextContent.Should()
            .NotContain(message, "the input shows it, so the notice does not list it again");
    }

    // Backlog 175 (final review): MudBlazor validates a text field when it loses focus, and that
    // cleared an Error set from outside. An Owner who tabs through the form must still see the marks.
    [Theory]
    [InlineData("trigger-input", "Trigger")]
    [InlineData("description-input", "Description")]
    [InlineData("context-value-input", "ContextValue")]
    [InlineData("replacement-input", "Replacement")]
    public async Task EditMode_BrokenRule_StaysMarkedWhenTheFieldLosesFocusUnchanged(string dataTest, string field)
    {
        string message = $"Broken {field}.";
        HotstringEditModel item = HotstringEditModel.FromDto(new HotstringDto(
            Guid.NewGuid(), [], true, "btw", "by the way", "A note", true, false,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow,
            ContextMatchType: WindowMatchType.TitleContains, ContextValue: "x",
            BrokenRules: [new(field, message)])).Clone();
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Markup.Should().Contain(message));

        await provider.InvokeAsync(() => provider.Find($"[data-test=\"{dataTest}\"]").Blur());

        provider.Markup.Should().Contain(message);
    }
}
