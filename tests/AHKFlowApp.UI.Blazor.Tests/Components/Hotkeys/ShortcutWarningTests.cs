using AHKFlowApp.UI.Blazor.Components.Hotkeys;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using Bunit;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Components.Hotkeys;

// The Hotkeys page fills its Profile list from its own request, and the grid can render an
// editable row before that request returns. The row hands this component the list it holds right
// then, so the component has to notice a later list instead of keeping its first answer.
public sealed class ShortcutWarningTests : BunitContext
{
    private readonly IHotkeyKeyCatalog _catalog = Substitute.For<IHotkeyKeyCatalog>();
    private readonly IKnownShortcutCatalog _knownShortcuts = Substitute.For<IKnownShortcutCatalog>();

    private const string CapsLockLayerHeader = """
        #Requires AutoHotkey v2.0

        *CapsLock::
        {
            Send "{Blind}{LCtrl DownR}"
        }
        """;

    public ShortcutWarningTests()
    {
        _catalog.CanonicalizeAsync(Arg.Any<string>(), Arg.Any<CancellationToken>())
            .Returns(call => ValueTask.FromResult(call.Arg<string>() ?? ""));
        Services.AddSingleton(_catalog);

        // An empty catalog: this file is about the template notice, which reads no known shortcut.
        _knownShortcuts.GetAsync(Arg.Any<CancellationToken>())
            .Returns(ValueTask.FromResult<KnownShortcutCatalogDto?>(new([])));
        Services.AddSingleton(_knownShortcuts);

        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    private static ProfileDto Profile(string name, string header) =>
        new(Guid.NewGuid(), name, false, header, "", DateTimeOffset.UnixEpoch, DateTimeOffset.UnixEpoch);

    [Fact]
    public void TemplateNotice_AppearsWhenTheProfileListArrivesAfterTheFirstRender()
    {
        IRenderedComponent<ShortcutWarning> warning = Render<ShortcutWarning>(parameters => parameters
            .Add(p => p.Key, "CapsLock")
            .Add(p => p.AppliesToAllProfiles, true)
            .Add(p => p.Profiles, (IReadOnlyList<ProfileDto>)[]));

        // Nothing to warn about yet: an empty list holds no template.
        warning.WaitForAssertion(() =>
            warning.Find("[data-test=\"shortcut-warning-checked\"]").GetAttribute("data-combination")
                .Should().Be("CapsLock"));
        warning.FindAll("[data-test=\"template-warning\"]").Should().BeEmpty();

        warning.Render(parameters => parameters
            .Add(p => p.Key, "CapsLock")
            .Add(p => p.AppliesToAllProfiles, true)
            .Add(p => p.Profiles, (IReadOnlyList<ProfileDto>)[Profile("Work", CapsLockLayerHeader)]));

        warning.WaitForAssertion(() =>
            warning.Find("[data-test=\"template-warning\"]").TextContent
                .Should().Be("The header template in Work also uses CapsLock. Your hotkey may not fire."));
    }

    [Fact]
    public void TemplateNotice_FollowsAnEditToTheTemplateItAlreadyRead()
    {
        ProfileDto work = Profile("Work", CapsLockLayerHeader);

        IRenderedComponent<ShortcutWarning> warning = Render<ShortcutWarning>(parameters => parameters
            .Add(p => p.Key, "CapsLock")
            .Add(p => p.AppliesToAllProfiles, true)
            .Add(p => p.Profiles, (IReadOnlyList<ProfileDto>)[work]));

        warning.WaitForAssertion(() =>
            warning.FindAll("[data-test=\"template-warning\"]").Should().NotBeEmpty());

        // Same Profile, same id, no CapsLock line any more. The notice has to go.
        warning.Render(parameters => parameters
            .Add(p => p.Key, "CapsLock")
            .Add(p => p.AppliesToAllProfiles, true)
            .Add(p => p.Profiles, (IReadOnlyList<ProfileDto>)[work with { HeaderTemplate = "#Requires AutoHotkey v2.0" }]));

        warning.WaitForAssertion(() =>
            warning.FindAll("[data-test=\"template-warning\"]").Should().BeEmpty());
    }
}
