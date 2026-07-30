using System.Security.Claims;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Pages;
using AHKFlowApp.UI.Blazor.Services;
using AngleSharp.Dom;
using Bunit;
using FluentAssertions;
using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Pages;

public sealed class KnownShortcutsPageTests : BunitContext, IAsyncLifetime
{
    private readonly IKnownShortcutsApiClient _api = Substitute.For<IKnownShortcutsApiClient>();
    private readonly IKnownShortcutCatalog _catalog = Substitute.For<IKnownShortcutCatalog>();

    // The add form holds a KeyPicker, which reads the key registry through this.
    private readonly IHotkeyKeyCatalog _keys = Substitute.For<IHotkeyKeyCatalog>();

    public KnownShortcutsPageTests()
    {
        Services.AddSingleton(_api);
        Services.AddSingleton(_catalog);
        Services.AddSingleton(_keys);
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;

    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    private static ManagedShortcutUseDto BuiltInUse(string usedBy = "Windows", bool ignored = false) =>
        new(usedBy, ShortcutProtection.Normal, ShortcutScope.Global, "open File Explorer",
            ShortcutRecordOrigin.BuiltIn, OwnerRecordId: null, IsIgnored: ignored);

    private static ManagedShortcutUseDto OwnerUse(Guid recordId, string usedBy = "My notes tool") =>
        new(usedBy, ShortcutProtection.Unknown, ShortcutScope.Foreground, "open my notes",
            ShortcutRecordOrigin.Owner, OwnerRecordId: recordId, IsIgnored: false);

    private static ManagedKnownShortcutDto Shortcut(
        string id, string key, params ManagedShortcutUseDto[] uses) =>
        new(id, key, Ctrl: false, Alt: false, Shift: false, Win: true, uses, WarningText: null);

    private static ManagedKnownShortcutDto BrowserShortcut() =>
        new("browser.new-window", "n", Ctrl: true, Alt: false, Shift: false, Win: false,
            [
                new("Chrome", ShortcutProtection.Normal, ShortcutScope.Foreground, "open a new window",
                    ShortcutRecordOrigin.BuiltIn, null, false),
                new("Edge", ShortcutProtection.Normal, ShortcutScope.Foreground, "open a new window",
                    ShortcutRecordOrigin.BuiltIn, null, false),
            ],
            WarningText: null);

    private void StubList(params ManagedKnownShortcutDto[] shortcuts) =>
        _api.ListManagedAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<ManagedKnownShortcutCatalogDto>.Ok(new ManagedKnownShortcutCatalogDto(shortcuts)));

    private void StubListFailure() =>
        _api.ListManagedAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<ManagedKnownShortcutCatalogDto>.Failure(ApiResultStatus.ServerError, null));

    private static readonly Task<AuthenticationState> AuthenticatedState =
        Task.FromResult(new AuthenticationState(
            new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.Name, "testuser")], "test"))));

    private static readonly Task<AuthenticationState> AnonymousState =
        Task.FromResult(new AuthenticationState(new ClaimsPrincipal(new ClaimsIdentity())));

    private IRenderedComponent<KnownShortcuts> RenderPage()
    {
        Render<MudPopoverProvider>();
        return Render<KnownShortcuts>(p => p.AddCascadingValue(AuthenticatedState));
    }

    private IRenderedComponent<KnownShortcuts> RenderSignedOutPage()
    {
        Render<MudPopoverProvider>();
        return Render<KnownShortcuts>(p => p.AddCascadingValue(AnonymousState));
    }

    // Confirms or cancels the delete message box. Registered before the page renders, because the
    // page resolves IDialogService once.
    private void StubDeleteConfirmation(bool confirmed)
    {
        IDialogService dialogService = Substitute.For<IDialogService>();
        dialogService.ShowMessageBoxAsync(
            Arg.Any<string>(), Arg.Any<string>(), Arg.Any<string>(), Arg.Any<string>(), Arg.Any<string>(),
            Arg.Any<DialogOptions>())
            .Returns(Task.FromResult<bool?>(confirmed ? true : null));
        Services.AddSingleton(dialogService);
    }

    private static IElement Button(IRenderedComponent<KnownShortcuts> page, string css, string shortcutId, string usedBy) =>
        page.Find($"button.{css}[data-shortcut-id=\"{shortcutId}\"][data-used-by=\"{usedBy}\"]");

    [Fact]
    public void Page_RendersOneRowPerUse()
    {
        StubList(BrowserShortcut());

        IRenderedComponent<KnownShortcuts> page = RenderPage();

        page.FindAll("[data-test=\"known-shortcut-row\"]").Should().HaveCount(2);
        page.FindAll("[data-test=\"known-shortcut-row\"]").Should()
            .OnlyContain(r => r.TextContent == "Ctrl+N");
        page.FindAll("button.ignore-use").Should().HaveCount(2);
    }

    [Fact]
    public void BuiltInUse_OffersIgnore_AndCallsItWithThatUse()
    {
        StubList(BrowserShortcut());
        _api.IgnoreAsync(Arg.Any<string>(), Arg.Any<string>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult.Ok());

        IRenderedComponent<KnownShortcuts> page = RenderPage();
        Button(page, "ignore-use", "browser.new-window", "Chrome").Click();

        _api.Received(1).IgnoreAsync("browser.new-window", "Chrome", Arg.Any<CancellationToken>());
    }

    [Fact]
    public void IgnoredUse_OffersRestore_AndCallsIt()
    {
        StubList(Shortcut("windows.file-explorer", "e", BuiltInUse(ignored: true)));
        _api.RestoreAsync(Arg.Any<string>(), Arg.Any<string>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult.Ok());

        IRenderedComponent<KnownShortcuts> page = RenderPage();
        page.FindAll("button.ignore-use").Should().BeEmpty();
        Button(page, "restore-use", "windows.file-explorer", "Windows").Click();

        _api.Received(1).RestoreAsync("windows.file-explorer", "Windows", Arg.Any<CancellationToken>());
    }

    [Fact]
    public void OwnerUse_OffersDelete_AndCallsItWithTheRecordId()
    {
        var recordId = Guid.NewGuid();
        StubDeleteConfirmation(confirmed: true);
        StubList(Shortcut("owner.1", "F7", OwnerUse(recordId)));
        _api.DeleteAsync(Arg.Any<Guid>(), Arg.Any<CancellationToken>()).Returns(ApiResult.Ok());

        IRenderedComponent<KnownShortcuts> page = RenderPage();
        page.Find("button.delete-use").Click();

        page.WaitForAssertion(() =>
            _api.Received(1).DeleteAsync(recordId, Arg.Any<CancellationToken>()));
    }

    [Fact]
    public void OwnerUse_DoesNotOfferIgnore_AndBuiltInDoesNotOfferDelete()
    {
        StubList(
            Shortcut("owner.1", "F7", OwnerUse(Guid.NewGuid())),
            Shortcut("windows.file-explorer", "e", BuiltInUse()));

        IRenderedComponent<KnownShortcuts> page = RenderPage();

        page.FindAll("button.ignore-use").Should().ContainSingle()
            .Which.GetAttribute("data-shortcut-id").Should().Be("windows.file-explorer");
        page.FindAll("button.delete-use").Should().ContainSingle()
            .Which.GetAttribute("data-shortcut-id").Should().Be("owner.1");
    }

    [Fact]
    public void CombinationWithABuiltInAndAnOwnerUse_RendersBothActions()
    {
        StubList(Shortcut("windows.file-explorer", "e", BuiltInUse(), OwnerUse(Guid.NewGuid())));

        IRenderedComponent<KnownShortcuts> page = RenderPage();

        page.FindAll("[data-test=\"known-shortcut-row\"]").Should().HaveCount(2);
        page.FindAll("button.ignore-use").Should().ContainSingle();
        page.FindAll("button.delete-use").Should().ContainSingle();
    }

    [Fact]
    public void IgnoringOneUse_LeavesTheOtherUseActive()
    {
        StubList(BrowserShortcut());
        _api.IgnoreAsync(Arg.Any<string>(), Arg.Any<string>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult.Ok());

        IRenderedComponent<KnownShortcuts> page = RenderPage();

        // The reload after the mutation returns Chrome silenced and Edge untouched.
        _api.ListManagedAsync(Arg.Any<CancellationToken>()).Returns(
            ApiResult<ManagedKnownShortcutCatalogDto>.Ok(new ManagedKnownShortcutCatalogDto(
            [
                new("browser.new-window", "n", false, false, false, false,
                    [
                        new("Chrome", ShortcutProtection.Normal, ShortcutScope.Foreground, "open a new window",
                            ShortcutRecordOrigin.BuiltIn, null, true),
                        new("Edge", ShortcutProtection.Normal, ShortcutScope.Foreground, "open a new window",
                            ShortcutRecordOrigin.BuiltIn, null, false),
                    ],
                    null),
            ])));

        Button(page, "ignore-use", "browser.new-window", "Chrome").Click();

        Button(page, "restore-use", "browser.new-window", "Chrome").Should().NotBeNull();
        Button(page, "ignore-use", "browser.new-window", "Edge").Should().NotBeNull();
    }

    [Fact]
    public void AfterASuccessfulIgnore_TheListIsReloadedAndTheRowOffersRestore()
    {
        StubList(Shortcut("windows.file-explorer", "e", BuiltInUse()));
        _api.IgnoreAsync(Arg.Any<string>(), Arg.Any<string>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult.Ok());

        IRenderedComponent<KnownShortcuts> page = RenderPage();
        StubList(Shortcut("windows.file-explorer", "e", BuiltInUse(ignored: true)));

        Button(page, "ignore-use", "windows.file-explorer", "Windows").Click();

        _api.Received(2).ListManagedAsync(Arg.Any<CancellationToken>());
        page.FindAll("button.restore-use").Should().ContainSingle();
    }

    [Fact]
    public void Add_SavesThroughCreate_AndShowsTheReturnedList()
    {
        StubList();
        _api.CreateAsync(Arg.Any<CreateCustomKnownShortcutDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<ManagedKnownShortcutCatalogDto>.Ok(new ManagedKnownShortcutCatalogDto(
                [Shortcut("owner.1", "F7", OwnerUse(Guid.NewGuid()))])));

        IRenderedComponent<KnownShortcuts> page = RenderPage();
        page.Find("button.add-known-shortcut").Click();
        page.Find("[data-test=\"known-shortcut-usedby-input\"]").Input("My notes tool");
        page.Find("[data-test=\"known-shortcut-does-input\"]").Input("open my notes");
        page.Find("button.commit-edit").Click();

        _api.Received(1).CreateAsync(
            Arg.Is<CreateCustomKnownShortcutDto>(d => d.UsedBy == "My notes tool" && d.Does == "open my notes"),
            Arg.Any<CancellationToken>());
        page.FindAll("[data-test=\"known-shortcut-row\"]").Should().ContainSingle();
    }

    [Fact]
    public void Add_WhenTheServerConflicts_ShowsTheMessageAndKeepsTheFormOpen()
    {
        StubList();
        _api.CreateAsync(Arg.Any<CreateCustomKnownShortcutDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<ManagedKnownShortcutCatalogDto>.Failure(
                ApiResultStatus.Conflict,
                new ApiProblemDetails(null, "Conflict", 409, "You have already recorded this one.", null, null)));

        IRenderedComponent<KnownShortcuts> page = RenderPage();
        page.Find("button.add-known-shortcut").Click();
        page.Find("button.commit-edit").Click();

        page.Markup.Should().Contain("You have already recorded this one.");
        page.FindAll("button.commit-edit").Should().ContainSingle("the form stays open");
    }

    [Fact]
    public void FailedLoad_ShowsAnErrorAndAnEmptyTable()
    {
        StubListFailure();

        IRenderedComponent<KnownShortcuts> page = RenderPage();

        page.FindAll("[data-test=\"known-shortcut-row\"]").Should().BeEmpty();
        page.FindAll("div.mud-alert").Should().NotBeEmpty();
    }

    [Fact]
    public void SignedOut_SaysSo_AndReadsNothing()
    {
        // Same shape as the categories page: no request goes out, and the two toolbar buttons are
        // dead until there is someone to act as.
        StubList(Shortcut("windows.file-explorer", "e", BuiltInUse()));

        IRenderedComponent<KnownShortcuts> page = RenderSignedOutPage();

        _api.DidNotReceive().ListManagedAsync(Arg.Any<CancellationToken>());
        page.Markup.Should().Contain("You are not signed in.");
        page.Find("button.add-known-shortcut").HasAttribute("disabled").Should().BeTrue();
        page.Find("button.reload-known-shortcuts").HasAttribute("disabled").Should().BeTrue();
    }

    [Fact]
    public void Delete_WhenTheConfirmationIsCancelled_RemovesNothing()
    {
        StubDeleteConfirmation(confirmed: false);
        StubList(Shortcut("owner.1", "F7", OwnerUse(Guid.NewGuid())));
        _api.DeleteAsync(Arg.Any<Guid>(), Arg.Any<CancellationToken>()).Returns(ApiResult.Ok());

        IRenderedComponent<KnownShortcuts> page = RenderPage();
        page.Find("button.delete-use").Click();

        _api.DidNotReceive().DeleteAsync(Arg.Any<Guid>(), Arg.Any<CancellationToken>());
        page.FindAll("[data-test=\"known-shortcut-row\"]").Should().ContainSingle();
    }

    [Fact]
    public void Delete_WhenConfirmed_RemovesTheRecord()
    {
        var recordId = Guid.NewGuid();
        StubDeleteConfirmation(confirmed: true);
        StubList(Shortcut("owner.1", "F7", OwnerUse(recordId)));
        _api.DeleteAsync(Arg.Any<Guid>(), Arg.Any<CancellationToken>()).Returns(ApiResult.Ok());

        IRenderedComponent<KnownShortcuts> page = RenderPage();
        page.Find("button.delete-use").Click();

        page.WaitForAssertion(() =>
            _api.Received(1).DeleteAsync(recordId, Arg.Any<CancellationToken>()));
    }

    [Fact]
    public void WhileAMutationIsInFlight_TheRowActionsAreDisabled()
    {
        // Two clicks on one row used to send two requests, and their two reloads then raced.
        TaskCompletionSource<ApiResult> pending = new();
        StubList(Shortcut("windows.file-explorer", "e", BuiltInUse()));
        _api.IgnoreAsync(Arg.Any<string>(), Arg.Any<string>(), Arg.Any<CancellationToken>())
            .Returns(pending.Task);

        IRenderedComponent<KnownShortcuts> page = RenderPage();
        page.Find("button.ignore-use").Click();

        page.Find("button.ignore-use").HasAttribute("disabled").Should().BeTrue();
        page.Find("button.reload-known-shortcuts").HasAttribute("disabled").Should().BeTrue();

        pending.SetResult(ApiResult.Ok());
        page.WaitForAssertion(() =>
            page.Find("button.reload-known-shortcuts").HasAttribute("disabled").Should().BeFalse());
    }

    [Fact]
    public void WhileAReadIsInFlight_ReloadIsDisabled()
    {
        // The other half of "one at a time": a second read cannot start while the first is out,
        // so two answers can never arrive in the wrong order.
        TaskCompletionSource<ApiResult<ManagedKnownShortcutCatalogDto>> pending = new();
        _api.ListManagedAsync(Arg.Any<CancellationToken>()).Returns(pending.Task);

        IRenderedComponent<KnownShortcuts> page = RenderPage();

        page.Find("button.reload-known-shortcuts").HasAttribute("disabled").Should().BeTrue();

        pending.SetResult(ApiResult<ManagedKnownShortcutCatalogDto>.Ok(
            new ManagedKnownShortcutCatalogDto([BrowserShortcut()])));

        page.WaitForAssertion(() =>
            page.Find("button.reload-known-shortcuts").HasAttribute("disabled").Should().BeFalse());
    }

    [Fact]
    public void AMutationLostToTheNetwork_ReconcilesWithTheServer()
    {
        // No response came back, so the write may or may not have landed. The page and the dialog
        // cache both have to be re-read, or a silenced use keeps warning until a hard reload.
        StubList(Shortcut("windows.file-explorer", "e", BuiltInUse()));
        _api.IgnoreAsync(Arg.Any<string>(), Arg.Any<string>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult.Failure(ApiResultStatus.NetworkError, null));

        IRenderedComponent<KnownShortcuts> page = RenderPage();
        page.Find("button.ignore-use").Click();

        page.WaitForAssertion(() => _catalog.Received(1).Invalidate());
        _api.Received(2).ListManagedAsync(Arg.Any<CancellationToken>());
    }

    [Theory]
    [InlineData("ignore")]
    [InlineData("restore")]
    [InlineData("delete")]
    [InlineData("create")]
    public void EverySuccessfulMutation_InvalidatesTheDialogCache(string mutation)
    {
        ArrangeMutation(mutation, succeeds: true);

        IRenderedComponent<KnownShortcuts> page = RenderPage();
        PerformMutation(page, mutation);

        page.WaitForAssertion(() => _catalog.Received(1).Invalidate());
    }

    [Theory]
    [InlineData("ignore")]
    [InlineData("restore")]
    [InlineData("delete")]
    [InlineData("create")]
    public void AFailedMutation_DoesNotInvalidateTheDialogCache(string mutation)
    {
        // A failure the server answered — 500 here — changed nothing the page is showing, so
        // throwing the cache away costs a refetch for no reason and hides the failure behind a
        // slow dialog. A lost response is the other case, and
        // AMutationLostToTheNetwork_ReconcilesWithTheServer covers it.
        ArrangeMutation(mutation, succeeds: false);

        IRenderedComponent<KnownShortcuts> page = RenderPage();
        PerformMutation(page, mutation);

        _catalog.DidNotReceive().Invalidate();
    }

    private void ArrangeMutation(string mutation, bool succeeds)
    {
        ApiResult result = succeeds ? ApiResult.Ok() : ApiResult.Failure(ApiResultStatus.ServerError, null);

        // Delete asks first. Both theories drive the confirmed path.
        StubDeleteConfirmation(confirmed: true);

        switch (mutation)
        {
            case "ignore":
                StubList(Shortcut("windows.file-explorer", "e", BuiltInUse()));
                _api.IgnoreAsync(Arg.Any<string>(), Arg.Any<string>(), Arg.Any<CancellationToken>())
                    .Returns(result);
                break;
            case "restore":
                StubList(Shortcut("windows.file-explorer", "e", BuiltInUse(ignored: true)));
                _api.RestoreAsync(Arg.Any<string>(), Arg.Any<string>(), Arg.Any<CancellationToken>())
                    .Returns(result);
                break;
            case "delete":
                StubList(Shortcut("owner.1", "F7", OwnerUse(Guid.NewGuid())));
                _api.DeleteAsync(Arg.Any<Guid>(), Arg.Any<CancellationToken>()).Returns(result);
                break;
            default:
                StubList();
                _api.CreateAsync(Arg.Any<CreateCustomKnownShortcutDto>(), Arg.Any<CancellationToken>())
                    .Returns(succeeds
                        ? ApiResult<ManagedKnownShortcutCatalogDto>.Ok(new ManagedKnownShortcutCatalogDto([]))
                        : ApiResult<ManagedKnownShortcutCatalogDto>.Failure(ApiResultStatus.ServerError, null));
                break;
        }
    }

    private static void PerformMutation(IRenderedComponent<KnownShortcuts> page, string mutation)
    {
        switch (mutation)
        {
            case "ignore":
                page.Find("button.ignore-use").Click();
                break;
            case "restore":
                page.Find("button.restore-use").Click();
                break;
            case "delete":
                page.Find("button.delete-use").Click();
                break;
            default:
                page.Find("button.add-known-shortcut").Click();
                page.Find("button.commit-edit").Click();
                break;
        }
    }
}
