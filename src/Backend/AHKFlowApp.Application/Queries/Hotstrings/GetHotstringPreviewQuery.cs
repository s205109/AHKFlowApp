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
                input.ContextValue),
            clock);

        // Prepend the Description comment lines above the definition, via the same shared formatter
        // AhkScriptGenerator uses, so the live preview matches the downloaded script byte-for-byte.
        string snippet = HotstringEmitter.Emit(hs);
        string commentBlock = string.Join('\n', HotstringEmitter.DescriptionCommentLines(hs.Description));
        if (commentBlock.Length > 0)
            snippet = $"{commentBlock}\n{snippet}";

        // Mirrors AhkScriptGenerator's context-group wrapping (D9) so the live preview matches
        // exactly what the downloaded script would contain for this hotstring.
        if (hs.ContextMatchType is WindowMatchType matchType)
            snippet = $"{HotstringEmitter.EmitHotIfOpen(matchType, hs.ContextValue!)}\n{snippet}\n{HotstringEmitter.HotIfClose}";

        return Task.FromResult(Result.Success(new HotstringPreviewDto(snippet, rawSummary)));
    }
}
