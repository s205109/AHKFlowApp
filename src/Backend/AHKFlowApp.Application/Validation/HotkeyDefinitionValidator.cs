using FluentValidation;

namespace AHKFlowApp.Application.Validation;

/// <summary>
/// The rules a new save applies, bound to a <see cref="HotkeyDefinitionDraft"/>. Mirrors
/// <c>UpdateHotkeyCommandValidator</c> without the profile-association rules, which backlog 162
/// leaves out on purpose — see <see cref="HotstringDefinitionValidator"/> for the reason.
/// </summary>
internal sealed class HotkeyDefinitionValidator : AbstractValidator<HotkeyDefinitionDraft>
{
    public HotkeyDefinitionValidator()
    {
        RuleFor(x => x.Description).ValidDescription();
        RuleFor(x => x.Key).ValidKey();
        this.AddHotkeyActionRules(x => x);
        this.AddWindowContextRules(
            x => x.ContextMatchType,
            x => x.ContextValue);
    }
}
