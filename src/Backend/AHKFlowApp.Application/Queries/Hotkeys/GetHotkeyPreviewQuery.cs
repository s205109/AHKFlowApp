using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Constants;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using FluentValidation;

namespace AHKFlowApp.Application.Queries.Hotkeys;

public sealed record GetHotkeyPreviewQuery(HotkeyPreviewRequestDto Input);

public sealed class GetHotkeyPreviewQueryValidator : AbstractValidator<GetHotkeyPreviewQuery>
{
    public GetHotkeyPreviewQueryValidator()
    {
        RuleFor(x => x.Input.Description).ValidDescription();
        RuleFor(x => x.Input.Key).ValidKey();
        this.AddHotkeyActionRules(
            x => x.Input.ActionKind,
            x => x.Input.Text,
            x => x.Input.SendKeysContent,
            x => x.Input.RunTarget,
            x => x.Input.RunTargetKind,
            x => x.Input.WindowOp,
            x => x.Input.RemapDest,
            x => x.Input.Body);
    }
}

/// <summary>
/// Computes the exact AutoHotkey snippet a hotkey draft would generate, without persisting. Builds a
/// transient (never-saved) <see cref="Hotkey"/> to reuse <see cref="HotkeyEmitter"/> — no
/// <c>IAppDbContext</c>, no side effects. Clone of <c>GetHotstringPreviewQueryHandler</c>.
/// </summary>
internal sealed class GetHotkeyPreviewQueryHandler(TimeProvider clock)
    : IUseCaseHandler<GetHotkeyPreviewQuery, Result<HotkeyPreviewDto>>
{
    public Task<Result<HotkeyPreviewDto>> ExecuteAsync(GetHotkeyPreviewQuery request, CancellationToken ct)
    {
        HotkeyPreviewRequestDto i = request.Input;

        // Canonicalize the key so the preview matches what a save would persist and emit.
        HotkeyKeys.TryCanonicalize(i.Key, out string canonicalKey);

        var hk = Hotkey.Create(
            Guid.Empty,
            new HotkeyDefinition(
                Description: i.Description, Key: canonicalKey,
                Ctrl: i.Ctrl, Alt: i.Alt, Shift: i.Shift, Win: i.Win,
                ActionKind: i.ActionKind, AppliesToAllProfiles: true,
                Text: i.Text, SendKeysContent: i.SendKeysContent,
                RunTarget: i.RunTarget, RunTargetKind: i.RunTargetKind, WindowOp: i.WindowOp,
                RemapDest: i.RemapDest, Body: i.Body),
            clock);

        string snippet = HotkeyEmitter.Emit(hk);
        string commentBlock = string.Join('\n', HotstringEmitter.DescriptionCommentLines(hk.Description));
        if (commentBlock.Length > 0)
            snippet = $"{commentBlock}\n{snippet}";

        return Task.FromResult(Result.Success(new HotkeyPreviewDto(snippet)));
    }
}
