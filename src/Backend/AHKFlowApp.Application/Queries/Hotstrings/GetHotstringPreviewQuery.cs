using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using FluentValidation;

namespace AHKFlowApp.Application.Queries.Hotstrings;

public sealed record GetHotstringPreviewQuery(HotstringPreviewRequestDto Input);

public sealed class GetHotstringPreviewQueryValidator : AbstractValidator<GetHotstringPreviewQuery>
{
    public GetHotstringPreviewQueryValidator()
    {
        // Raw derives its trigger server-side; the client-trigger rules are gated off for Raw.
        RuleFor(x => x.Input.Trigger).ValidTrigger()
            .When(x => x.Input.Kind != HotstringKind.Raw);
        RuleFor(x => x.Input.Kind)
            .Must(k => k is HotstringKind.Text or HotstringKind.DateTime or HotstringKind.Macro or HotstringKind.Raw)
            .WithMessage("Only Text, Date & time, Macro and Raw hotstrings are supported.");
        // Base Description length applies to every kind (matching the Create/Update save rule), so an
        // over-long typed Description fails preview the same way it fails save. Raw additionally checks
        // the base+lifted-comment merged length in AddRawKindRules.
        RuleFor(x => x.Input.Description)
            .MaximumLength(HotstringRules.DescriptionMaxLength)
            .WithMessage($"Description must be {HotstringRules.DescriptionMaxLength} characters or fewer.");
        this.AddDateTimeKindRules(
            x => x.Input.Kind,
            x => x.Input.Replacement,
            x => x.Input.DateTimeFormat,
            x => x.Input.DateOffsetAmount,
            x => x.Input.DateOffsetUnit);
        this.AddDeliveryRules(
            x => x.Input.Kind,
            x => x.Input.Delivery,
            x => x.Input.Replacement);
        this.AddMacroKindRules(
            x => x.Input.Kind,
            x => x.Input.Replacement);
        this.AddRawKindRules(
            x => x.Input.Kind,
            x => x.Input.Replacement,
            x => x.Input.Description);
        this.AddWindowContextRules(
            x => x.Input.ContextMatchType,
            x => x.Input.ContextValue);
    }
}

/// <summary>
/// Computes the exact AutoHotkey snippet a hotstring definition would generate, without
/// persisting anything. Builds a transient (never-saved) <see cref="Hotstring"/> via
/// <see cref="Hotstring.Create"/> purely to reuse <see cref="HotstringEmitter"/> — no
/// <c>IAppDbContext</c> dependency, no side effects.
/// </summary>
internal sealed class GetHotstringPreviewQueryHandler(TimeProvider clock)
    : IUseCaseHandler<GetHotstringPreviewQuery, Result<HotstringPreviewDto>>
{
    public Task<Result<HotstringPreviewDto>> ExecuteAsync(GetHotstringPreviewQuery request, CancellationToken ct)
    {
        HotstringPreviewRequestDto input = request.Input;

        // Raw derives its trigger + option summary server-side from the verbatim definition. One
        // Prepare pass (lift comments, normalize, parse) so the preview matches exactly what a save
        // would persist and emit — including the Description merged from any lifted comment.
        string trigger = input.Trigger;
        string replacement = input.Replacement;
        string? description = string.IsNullOrWhiteSpace(input.Description) ? null : input.Description.Trim();
        RawSummaryDto? rawSummary = null;
        if (input.Kind == HotstringKind.Raw)
        {
            RawPrepared prepared = RawHotstringDefinitionParser.Prepare(input.Replacement);
            RawParseResult parsed = prepared.Parsed;
            replacement = prepared.NormalizedDefinition;
            trigger = parsed.Trigger;
            description = RawCommentLift.Merge(input.Description, prepared.LiftedComment);
            rawSummary = new RawSummaryDto(
                parsed.Trigger, parsed.OptionTokens, parsed.BodyKind, parsed.BodyLineCount, prepared.LiftedComment);
        }

        var hs = Hotstring.Create(
            Guid.Empty,
            new HotstringDefinition(
                trigger,
                replacement,
                description,
                AppliesToAllProfiles: true,
                input.IsEndingCharacterRequired,
                input.IsTriggerInsideWord,
                input.Kind,
                input.IsCaseSensitive,
                input.OmitEndingCharacter,
                input.DateTimeFormat,
                input.DateOffsetAmount,
                input.DateOffsetUnit,
                input.ContextMatchType,
                input.ContextValue,
                input.Delivery),
            clock);

        HotstringDelivery effectiveDelivery = HotstringEmitter.ResolveEffectiveDelivery(hs);

        // The same Runtime helpers and the same wrapping AhkScriptGenerator uses, so the live preview
        // matches the downloaded script byte for byte. A needed helper comes first, above the #HotIf
        // block, so the snippet is complete on its own.
        List<string> lines = [.. RuntimeHelpers.NeededBy([hs], [])];
        lines.AddRange(DefinitionWrapping.InWindowContext(
            hs.ContextMatchType,
            hs.ContextValue,
            DefinitionWrapping.WithDescription(hs.Description, HotstringEmitter.Emit(hs))));
        string snippet = string.Join('\n', lines);

        return Task.FromResult(Result.Success(
            new HotstringPreviewDto(snippet, rawSummary, effectiveDelivery)));
    }
}
