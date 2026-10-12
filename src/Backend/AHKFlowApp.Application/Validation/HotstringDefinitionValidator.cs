using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using FluentValidation;

namespace AHKFlowApp.Application.Validation;

/// <summary>
/// The rules a new save applies, bound to a <see cref="HotstringDefinition"/> rather than to a
/// create or update command. Restore and Revert build a definition out of a stored Snapshot, so
/// the definition is the only shape available to check — the request carries just an id.
/// Mirrors <c>CreateHotstringCommandValidator</c> without the profile-association rules, which
/// backlog 162 leaves out on purpose: they guard a UI invariant, not the emitted script, and the
/// restore handlers already repair association state by filtering to live rows.
/// </summary>
internal sealed class HotstringDefinitionValidator : AbstractValidator<HotstringDefinition>
{
    public HotstringDefinitionValidator()
    {
        // Raw derives its trigger from the definition text, so AddRawKindRules owns that check
        // and applies AHK's own 40-character abbreviation cap instead of the structured 50.
        RuleFor(x => x.Trigger).ValidTrigger()
            .When(x => x.Kind != HotstringKind.Raw);
        RuleFor(x => x.Description)
            .MaximumLength(HotstringRules.DescriptionMaxLength)
            .WithMessage($"Description must be {HotstringRules.DescriptionMaxLength} characters or fewer.");
        RuleFor(x => x.Kind)
            .Must(k => k is HotstringKind.Text or HotstringKind.DateTime or HotstringKind.Macro or HotstringKind.Raw)
            .WithMessage("Only Text, Date & time, Macro and Raw hotstrings are supported.");
        this.AddDateTimeKindRules(
            x => x.Kind,
            x => x.Replacement,
            x => x.DateTimeFormat,
            x => x.DateOffsetAmount,
            x => x.DateOffsetUnit);
        this.AddDeliveryRules(
            x => x.Kind,
            x => x.Delivery,
            x => x.Replacement);
        this.AddMacroKindRules(
            x => x.Kind,
            x => x.Replacement);
        this.AddRawKindRules(
            x => x.Kind,
            x => x.Replacement,
            x => x.Description);
        this.AddWindowContextRules(
            x => x.ContextMatchType,
            x => x.ContextValue);
    }
}
