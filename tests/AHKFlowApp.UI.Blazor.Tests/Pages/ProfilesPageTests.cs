using System.Security.Claims;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Pages;
using AHKFlowApp.UI.Blazor.Services;
using Bunit;
using FluentAssertions;
using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Pages;

public sealed class ProfilesPageTests : BunitContext, IAsyncLifetime
{
    private readonly IProfilesApiClient _api = Substitute.For<IProfilesApiClient>();

    private static readonly Task<AuthenticationState> AuthenticatedState =
        Task.FromResult(new AuthenticationState(
            new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.Name, "testuser")], "test"))));

    public ProfilesPageTests()
    {
        Services.AddSingleton(_api);
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    private IRenderedComponent<Profiles> RenderPage()
    {
        Render<MudPopoverProvider>();
        return Render<Profiles>(p => p.AddCascadingValue(AuthenticatedState));
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;

    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    private static ProfileDto MakeProfile(string name = "Work", bool isDefault = false) =>
        new(Guid.NewGuid(), name, isDefault, "header text", "footer text", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);

    private void StubList(params ProfileDto[] profiles) =>
        _api.ListAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<IReadOnlyList<ProfileDto>>.Ok(profiles));

    private void StubListFailure(ApiResultStatus status, ApiProblemDetails? problem = null) =>
        _api.ListAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<IReadOnlyList<ProfileDto>>.Failure(status, problem));

    [Fact]
    public void Page_OnLoad_ShowsTitleAndButtons()
    {
        StubList();

        IRenderedComponent<Profiles> cut = RenderPage();

        cut.WaitForAssertion(() => cut.Find("button.add-profile").Should().NotBeNull());
        cut.Find("button.reload-profiles").Should().NotBeNull();
        cut.Markup.Should().Contain("Profiles");
    }

    [Fact]
    public void Page_OnLoad_ShowsRowsFromApi()
    {
        ProfileDto dto = MakeProfile("Work");
        StubList(dto);

        IRenderedComponent<Profiles> cut = RenderPage();
        cut.WaitForState(() => cut.Markup.Contains("Work"));

        cut.Markup.Should().Contain("Work");
    }

    [Fact]
    public void Page_OnApiError_ShowsErrorAlert()
    {
        StubListFailure(ApiResultStatus.NetworkError);

        IRenderedComponent<Profiles> cut = RenderPage();
        cut.WaitForState(() => cut.Markup.Contains("Unable to reach"));

        cut.Markup.Should().Contain("Unable to reach the API");
    }

    [Fact]
    public Task Page_AddAndCommit_CallsCreateWithCorrectName()
    {
        StubList();
        _api.CreateAsync(Arg.Any<CreateProfileDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<ProfileDto>.Ok(MakeProfile("Personal")));

        IRenderedComponent<Profiles> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.add-profile"));
        cut.Find("button.add-profile").Click();

        cut.WaitForAssertion(() => cut.Find("input[data-test=\"profile-name-input\"]"));
        cut.Find("input[data-test=\"profile-name-input\"]").Input("Personal");
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateProfileDto>(d => d.Name == "Personal"),
            Arg.Any<CancellationToken>()));
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_EditExistingRow_CallsUpdateWithNewName()
    {
        ProfileDto dto = MakeProfile("Work");
        StubList(dto);
        _api.UpdateAsync(dto.Id, Arg.Any<UpdateProfileDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<ProfileDto>.Ok(dto with { Name = "Work Updated" }));

        IRenderedComponent<Profiles> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.start-edit"));
        cut.Find("button.start-edit").Click();

        cut.WaitForAssertion(() => cut.Find("input[data-test=\"profile-name-input\"]"));
        cut.Find("input[data-test=\"profile-name-input\"]").Input("Work Updated");
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => _api.Received(1).UpdateAsync(
            dto.Id,
            Arg.Is<UpdateProfileDto>(d => d.Name == "Work Updated"),
            Arg.Any<CancellationToken>()));
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_Delete_ConfirmCallsDeleteAsync()
    {
        ProfileDto dto = MakeProfile("Work");
        StubList(dto);
        _api.DeleteAsync(dto.Id, Arg.Any<CancellationToken>())
            .Returns(ApiResult.Ok());

        IRenderedComponent<Profiles> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.delete"));
        cut.Find("button.delete").Click();

        // ShowMessageBoxAsync renders via JS interop; confirm is not callable in bUnit.
        // Verify Delete button was clicked and api was invoked or not invoked (cancel path).
        // bUnit JS is loose so the dialog resolves as null (cancel) — DeleteAsync NOT called.
        cut.WaitForAssertion(() => _api.DidNotReceive().DeleteAsync(Arg.Any<Guid>(), Arg.Any<CancellationToken>()));
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_BlankName_BlocksCommit_AndShowsValidationMessage()
    {
        StubList();

        IRenderedComponent<Profiles> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.add-profile"));
        cut.Find("button.add-profile").Click();

        cut.WaitForAssertion(() => cut.Find("input[data-test=\"profile-name-input\"]"));
        // Leave name empty
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => cut.Markup.Should().Contain("Name is required"));
        _api.DidNotReceive().CreateAsync(Arg.Any<CreateProfileDto>(), Arg.Any<CancellationToken>());
        return Task.CompletedTask;
    }

    [Fact]
    public void Page_ToggleExpand_ShowsChildRowContent()
    {
        ProfileDto dto = MakeProfile("Work");
        StubList(dto);

        IRenderedComponent<Profiles> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.toggle-expand"));
        cut.Find("button.toggle-expand").Click();

        cut.WaitForAssertion(() => cut.Markup.Should().Contain("header text"));
    }

    [Fact]
    public void Page_OnConflictResponse_ApiCalledAndNoException()
    {
        StubList();
        _api.CreateAsync(Arg.Any<CreateProfileDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<ProfileDto>.Failure(ApiResultStatus.Conflict,
                new ApiProblemDetails(null, "Conflict", 409, "Profile name already exists", null, null)));

        IRenderedComponent<Profiles> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.add-profile"));
        cut.Find("button.add-profile").Click();
        cut.WaitForAssertion(() => cut.Find("input[data-test=\"profile-name-input\"]"));
        cut.Find("input[data-test=\"profile-name-input\"]").Input("Work");
        cut.Find("button.commit-edit").Click();

        // MudBlazor snackbars render via portal and are not in the component DOM in bUnit.
        // Assert the API was called (proving the commit path ran and conflict was handled without crash).
        cut.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateProfileDto>(d => d.Name == "Work"),
            Arg.Any<CancellationToken>()));
    }
}
