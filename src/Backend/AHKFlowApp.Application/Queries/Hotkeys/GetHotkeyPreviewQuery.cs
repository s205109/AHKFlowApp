using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Entities;
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
        this.AddHotkeyActionRules(x => x.Input);
        this.AddWindowContextRules(
            x => x.Input.ContextMatchType,
            x => x.Input.ContextValue);
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
        // ToDefinition applies the same key/token canonicalization the create and update handlers
        // do, so the previewed snippet is exactly what a save would persist and emit (spec §8).
        var hk = Hotkey.Create(Guid.Empty, request.Input.ToDefinition(appliesToAllProfiles: true), clock);

        // The same Runtime helpers and the same wrapping AhkScriptGenerator uses, so the live preview
        // matches the downloaded script byte for byte. No hotkey needs a helper today, so the list
        // starts empty.
        List<string> lines = [.. RuntimeHelpers.NeededBy([], [hk])];
        lines.AddRange(DefinitionWrapping.InWindowContext(
            hk.ContextMatchType,
            hk.ContextValue,
            DefinitionWrapping.WithDescription(hk.Description, HotkeyEmitter.Emit(hk))));
        string snippet = string.Join('\n', lines);

        return Task.FromResult(Result.Success(new HotkeyPreviewDto(snippet)));
    }
}
