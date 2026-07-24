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

        string snippet = HotkeyEmitter.Emit(hk);
        string commentBlock = string.Join('\n', HotstringEmitter.DescriptionCommentLines(hk.Description));
        if (commentBlock.Length > 0)
            snippet = $"{commentBlock}\n{snippet}";

        return Task.FromResult(Result.Success(new HotkeyPreviewDto(snippet)));
    }
}
