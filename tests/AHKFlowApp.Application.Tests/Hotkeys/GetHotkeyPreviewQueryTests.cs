using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Behaviors;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Hotkeys;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using FluentValidation;
using Microsoft.Extensions.Time.Testing;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotkeys;

public sealed class GetHotkeyPreviewQueryTests
{
    private static async Task<string> Preview(HotkeyPreviewRequestDto dto)
    {
        var handler = new GetHotkeyPreviewQueryHandler(new FakeTimeProvider());
        Result<HotkeyPreviewDto> r = await handler.ExecuteAsync(new GetHotkeyPreviewQuery(dto), CancellationToken.None);
        r.IsSuccess.Should().BeTrue();
        return r.Value.Snippet;
    }

    [Fact]
    public async Task Run_EmitsRunLineWithDescriptionComment()
    {
        string snippet = await Preview(new HotkeyPreviewRequestDto(
            "Open Notepad", "n", HotkeyActionKind.Run, Win: true,
            RunTarget: "notepad", RunTargetKind: RunTargetKind.Application));

        snippet.Should().Contain("#n::Run(\"notepad\")");
        snippet.Should().StartWith("; Open Notepad\n");
    }

    [Fact]
    public async Task SendKeys_EmitsDollarPrefix()
    {
        string snippet = await Preview(new HotkeyPreviewRequestDto(
            "Volume", "p", HotkeyActionKind.SendKeys, Win: true, SendKeysContent: "{Media_Play_Pause}"));

        snippet.Should().Contain("$#p::Send(\"{Media_Play_Pause}\")");
    }

    [Fact]
    public async Task SendText_EmitsSendTextCall()
    {
        string snippet = await Preview(new HotkeyPreviewRequestDto(
            "Greeting", "F5", HotkeyActionKind.SendText, Text: "hello"));

        snippet.Should().Contain("F5::SendText(\"hello\")");
    }

    [Fact]
    public async Task Window_EmitsWindowCall()
    {
        string snippet = await Preview(new HotkeyPreviewRequestDto(
            "Minimize", "F6", HotkeyActionKind.Window, WindowOp: WindowOp.Minimize));

        snippet.Should().Contain("F6::WinMinimize(\"A\")");
    }

    [Fact]
    public async Task Remap_EmitsBareDestinationKey()
    {
        string snippet = await Preview(new HotkeyPreviewRequestDto(
            "CapsLock to Ctrl", "CapsLock", HotkeyActionKind.Remap, RemapDest: "Ctrl"));

        snippet.Should().Contain("CapsLock::Ctrl");
    }

    [Fact]
    public async Task Disable_EmitsReturn()
    {
        string snippet = await Preview(new HotkeyPreviewRequestDto(
            "Disable F13", "F13", HotkeyActionKind.Disable));

        snippet.Should().Contain("F13::return");
    }

    [Fact]
    public async Task Raw_EmitsBodyVerbatim()
    {
        string snippet = await Preview(new HotkeyPreviewRequestDto(
            "Raw body", "F7", HotkeyActionKind.Raw, Body: "MsgBox(\"hi\")"));

        snippet.Should().Contain("F7::MsgBox(\"hi\")");
    }

    [Fact]
    public async Task NoDescription_OmitsCommentLine()
    {
        string snippet = await Preview(new HotkeyPreviewRequestDto(
            "", "F8", HotkeyActionKind.Disable));

        // ValidDescription requires non-empty Description at the boundary, but the handler
        // itself has no such guard — this pins that an empty comment block is simply omitted,
        // matching HotstringEmitter.DescriptionCommentLines' yield-break on blank input.
        snippet.Should().Be("F8::return");
    }

    // --- Parity: preview must equal what AhkScriptGenerator would emit for the same row ---

    private static AhkScriptGenerator NewGenerator()
    {
        IAppVersionProvider version = Substitute.For<IAppVersionProvider>();
        version.GetVersion().Returns("0.0.0");
        return new AhkScriptGenerator(new HeaderTokenRenderer(), TimeProvider.System, version);
    }

    /// <summary>
    /// Builds the persisted <see cref="Hotkey"/> and the equivalent preview request from the same
    /// field values, runs both independently (the real <see cref="AhkScriptGenerator"/> vs. the
    /// preview handler), and asserts they agree — proof the preview is not a hand-maintained
    /// second copy of the emission logic.
    /// </summary>
    private static async Task AssertPreviewMatchesGeneratedScript(Hotkey persisted, HotkeyPreviewRequestDto draft)
    {
        Domain.Entities.Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        string script = NewGenerator().Generate(profile, [], [persisted]);

        const string marker = "; --- Hotkeys ---\n";
        int idx = script.IndexOf(marker, StringComparison.Ordinal);
        idx.Should().BeGreaterThan(-1);
        string afterMarker = script[(idx + marker.Length)..];
        afterMarker.Should().EndWith("\nF");
        string expectedBlock = afterMarker[..^"\nF".Length];

        string previewSnippet = await Preview(draft);

        previewSnippet.Should().Be(expectedBlock);
    }

    [Fact]
    public Task Parity_SendText_MatchesGeneratedScript() =>
        AssertPreviewMatchesGeneratedScript(
            new HotkeyBuilder().WithDescription("d").WithKey("a").WithCtrl().WithSendText("he said \"hi\"").Build(),
            new HotkeyPreviewRequestDto("d", "a", HotkeyActionKind.SendText, Ctrl: true, Text: "he said \"hi\""));

    [Fact]
    public Task Parity_SendKeys_MatchesGeneratedScript() =>
        AssertPreviewMatchesGeneratedScript(
            new HotkeyBuilder().WithDescription("Volume").WithKey("p").WithWin().WithSendKeys("{Media_Play_Pause}").Build(),
            new HotkeyPreviewRequestDto("Volume", "p", HotkeyActionKind.SendKeys, Win: true, SendKeysContent: "{Media_Play_Pause}"));

    [Fact]
    public Task Parity_Run_MatchesGeneratedScript() =>
        AssertPreviewMatchesGeneratedScript(
            new HotkeyBuilder().WithDescription("Open Notepad").WithKey("n").WithWin().WithRun("notepad", RunTargetKind.Application).Build(),
            new HotkeyPreviewRequestDto("Open Notepad", "n", HotkeyActionKind.Run, Win: true, RunTarget: "notepad", RunTargetKind: RunTargetKind.Application));

    [Fact]
    public Task Parity_Window_MatchesGeneratedScript() =>
        AssertPreviewMatchesGeneratedScript(
            new HotkeyBuilder().WithDescription("Minimize").WithKey("F6").WithWindow(WindowOp.Minimize).Build(),
            new HotkeyPreviewRequestDto("Minimize", "F6", HotkeyActionKind.Window, WindowOp: WindowOp.Minimize));

    [Fact]
    public Task Parity_Remap_MatchesGeneratedScript() =>
        AssertPreviewMatchesGeneratedScript(
            new HotkeyBuilder().WithDescription("CapsLock to Ctrl").WithKey("CapsLock").WithRemap("Ctrl").Build(),
            new HotkeyPreviewRequestDto("CapsLock to Ctrl", "CapsLock", HotkeyActionKind.Remap, RemapDest: "Ctrl"));

    [Fact]
    public Task Parity_Disable_MatchesGeneratedScript() =>
        AssertPreviewMatchesGeneratedScript(
            new HotkeyBuilder().WithDescription("Disable F13").WithKey("F13").WithDisable().Build(),
            new HotkeyPreviewRequestDto("Disable F13", "F13", HotkeyActionKind.Disable));

    [Fact]
    public Task Parity_Raw_MatchesGeneratedScript() =>
        AssertPreviewMatchesGeneratedScript(
            new HotkeyBuilder().WithDescription("Raw body").WithKey("F7").WithRawBody("MsgBox(\"hi\")").Build(),
            new HotkeyPreviewRequestDto("Raw body", "F7", HotkeyActionKind.Raw, Body: "MsgBox(\"hi\")"));

    // --- 400, not 500: kind-conditional validation must reject a malformed draft before the
    // emitter — which throws on a null RemapDest or WindowOp — ever runs. ---

    private static ValidatingUseCase<GetHotkeyPreviewQuery, Result<HotkeyPreviewDto>> RealPipeline() =>
        new([new GetHotkeyPreviewQueryValidator()], new GetHotkeyPreviewQueryHandler(TimeProvider.System));

    [Fact]
    public async Task Preview_RemapWithoutDest_ThrowsValidationExceptionNotEmitterException()
    {
        var dto = new HotkeyPreviewRequestDto("Bad remap", "CapsLock", HotkeyActionKind.Remap);

        Func<Task> act = async () => await RealPipeline().ExecuteAsync(new GetHotkeyPreviewQuery(dto), CancellationToken.None);

        (await act.Should().ThrowAsync<ValidationException>())
            .Which.Errors.Should().Contain(e => e.PropertyName == "RemapDest");
    }

    [Fact]
    public async Task Preview_WindowWithoutOp_ThrowsValidationExceptionNotEmitterException()
    {
        var dto = new HotkeyPreviewRequestDto("Bad window", "F6", HotkeyActionKind.Window);

        Func<Task> act = async () => await RealPipeline().ExecuteAsync(new GetHotkeyPreviewQuery(dto), CancellationToken.None);

        (await act.Should().ThrowAsync<ValidationException>())
            .Which.Errors.Should().Contain(e => e.PropertyName == "WindowOp");
    }
}
