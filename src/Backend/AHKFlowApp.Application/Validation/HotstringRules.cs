using System.Linq;
using System.Linq.Expressions;
using System.Text.RegularExpressions;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Enums;
using FluentValidation;

namespace AHKFlowApp.Application.Validation;

internal static partial class HotstringRules
{
    public const int TriggerMaxLength = 50;
    public const int ReplacementMaxLength = 4000;
    public const int DescriptionMaxLength = 200;
    public const int DateTimeFormatMaxLength = 50;
    public const int DateOffsetAmountMax = 3650;
    public const int ContextValueMaxLength = 200;

    // Raw-specific limits. RawDefinitionMaxLength = 4000 body + trigger/options/brace
    // overhead, so migrated near-limit Script rows stay editable. RawTriggerMaxLength is
    // AHK's own documented abbreviation limit ("no more than 40 characters"), so Raw never
    // accepts a definition AHK itself would reject. Structured kinds keep TriggerMaxLength (50).
    public const int RawDefinitionMaxLength = 4200;
    public const int RawTriggerMaxLength = 40;

    public static IRuleBuilderOptions<T, string> ValidTrigger<T>(this IRuleBuilderInitial<T, string> rb) =>
        rb.Cascade(CascadeMode.Stop)
          .Must(t => !string.IsNullOrEmpty(t)).WithMessage("Trigger is required.")
          .MaximumLength(TriggerMaxLength).WithMessage($"Trigger must be {TriggerMaxLength} characters or fewer.")
          .Must(t => t is not null && t.Length == t.Trim().Length)
              .WithMessage("Trigger must not have leading or trailing whitespace.")
          .Must(t => t is not null && t.IndexOfAny(['\n', '\r', '\t']) < 0)
              .WithMessage("Trigger must not contain line breaks or tabs.");

    public static IRuleBuilderOptions<T, string> ValidReplacement<T>(this IRuleBuilderInitial<T, string> rb) =>
        rb.Cascade(CascadeMode.Stop)
          .NotEmpty().WithMessage("Replacement is required.")
          .MaximumLength(ReplacementMaxLength).WithMessage($"Replacement must be {ReplacementMaxLength} characters or fewer.");

    /// <summary>
    /// Adds validation for a nullable date/time format string: required, max length, and a
    /// whitelist of AHK/.NET-shared date/time tokens plus a small set of separator characters.
    /// </summary>
    public static IRuleBuilderOptions<T, string?> ValidDateTimeFormat<T>(this IRuleBuilderInitial<T, string?> rb) =>
        rb.Cascade(CascadeMode.Stop)
          .NotEmpty().WithMessage("DateTimeFormat is required.")
          .MaximumLength(DateTimeFormatMaxLength)
              .WithMessage($"DateTimeFormat must be {DateTimeFormatMaxLength} characters or fewer.")
          .Must(f => f is not null && DateTimeFormatWhitelistRegex().IsMatch(f))
              .WithMessage("DateTimeFormat contains unsupported characters or tokens.");

    /// <summary>
    /// Adds profile-association validation rules to a validator.
    /// When <paramref name="appliesToAll"/> is true, <paramref name="profileIds"/> must be null/empty.
    /// When false, at least one non-empty, non-duplicated GUID must be provided.
    /// Failures key off the <paramref name="profileIds"/> expression so PropertyName matches the DTO path (e.g. "Input.ProfileIds").
    /// </summary>
    public static void AddProfileAssociationRules<T>(
        this AbstractValidator<T> validator,
        Expression<Func<T, bool>> appliesToAll,
        Expression<Func<T, Guid[]?>> profileIds)
    {
        Func<T, bool> appliesToAllFn = appliesToAll.Compile();

        // When AppliesToAllProfiles = true, ProfileIds must be empty
        validator.RuleFor(profileIds)
            .Must(ids => ids is null || ids.Length == 0)
            .When(x => appliesToAllFn(x))
            .WithMessage("ProfileIds must be empty when AppliesToAllProfiles is true.");

        // When AppliesToAllProfiles = false, at least one profile required
        validator.RuleFor(profileIds)
            .Must(ids => ids is { Length: > 0 })
            .When(x => !appliesToAllFn(x))
            .WithMessage("At least one profile must be specified when AppliesToAllProfiles is false.");

        // No empty GUIDs in the array
        validator.RuleFor(profileIds)
            .Must(ids => ids is null || ids.All(id => id != Guid.Empty))
            .When(x => !appliesToAllFn(x))
            .WithMessage("ProfileIds must not contain empty GUIDs.");

        // No duplicate GUIDs in the array
        validator.RuleFor(profileIds)
            .Must(ids => ids is null || ids.Length == ids.Distinct().Count())
            .When(x => !appliesToAllFn(x))
            .WithMessage("ProfileIds must not contain duplicates.");
    }

    /// <summary>
    /// Adds kind-conditional rules for Date &amp; time hotstrings.
    /// When <paramref name="kind"/> is <see cref="HotstringKind.DateTime"/>: <paramref name="replacement"/> must be
    /// empty, <paramref name="dateTimeFormat"/> is required and whitelisted, and <paramref name="dateOffsetAmount"/> /
    /// <paramref name="dateOffsetUnit"/> must be both-set-or-both-null (amount bound to +/-<see cref="DateOffsetAmountMax"/>,
    /// 0 explicitly allowed).
    /// Otherwise: <paramref name="replacement"/> follows the normal <see cref="ValidReplacement{T}"/> rule, and the
    /// three Date &amp; time-only fields must all be null.
    /// </summary>
    public static void AddDateTimeKindRules<T>(
        this AbstractValidator<T> validator,
        Expression<Func<T, HotstringKind>> kind,
        Expression<Func<T, string>> replacement,
        Expression<Func<T, string?>> dateTimeFormat,
        Expression<Func<T, int?>> dateOffsetAmount,
        Expression<Func<T, DateOffsetUnit?>> dateOffsetUnit)
    {
        Func<T, HotstringKind> kindFn = kind.Compile();
        Func<T, int?> amountFn = dateOffsetAmount.Compile();
        Func<T, DateOffsetUnit?> unitFn = dateOffsetUnit.Compile();

        bool IsDateTime(T x) => kindFn(x) == HotstringKind.DateTime;
        bool BothOffsetsSet(T x) => amountFn(x) is not null && unitFn(x) is not null;

        // Replacement: normal rules for structured non-DateTime kinds, must be empty for DateTime.
        // Raw is excluded — its own length limit (RawDefinitionMaxLength, 4200) and structural
        // rules live in AddRawKindRules; ValidReplacement's 4000 cap would otherwise shadow it.
        validator.RuleFor(replacement)
            .ValidReplacement()
            .When(x => !IsDateTime(x) && kindFn(x) != HotstringKind.Raw);

        validator.RuleFor(replacement)
            .Must(r => r == string.Empty)
            .When(IsDateTime)
            .WithMessage("Replacement must be empty when Kind is Date & time.");

        // DateTimeFormat: required + whitelisted for DateTime, must be null otherwise
        validator.RuleFor(dateTimeFormat)
            .ValidDateTimeFormat()
            .When(IsDateTime);

        validator.RuleFor(dateTimeFormat)
            .Must(f => f is null)
            .When(x => !IsDateTime(x))
            .WithMessage("DateTimeFormat must be null unless Kind is Date & time.");

        // DateOffsetAmount / DateOffsetUnit: must be null unless DateTime
        validator.RuleFor(dateOffsetAmount)
            .Must(a => a is null)
            .When(x => !IsDateTime(x))
            .WithMessage("DateOffsetAmount must be null unless Kind is Date & time.");

        validator.RuleFor(dateOffsetUnit)
            .Must(u => u is null)
            .When(x => !IsDateTime(x))
            .WithMessage("DateOffsetUnit must be null unless Kind is Date & time.");

        // For DateTime: both-or-neither, range + enum checks when both are set (0 is a valid amount)
        validator.RuleFor(dateOffsetAmount)
            .Must((x, a) => (a is null) == (unitFn(x) is null))
            .When(IsDateTime)
            .WithMessage("DateOffsetAmount and DateOffsetUnit must both be set or both be null.");

        validator.RuleFor(dateOffsetAmount)
            .InclusiveBetween(-DateOffsetAmountMax, DateOffsetAmountMax)
            .When(x => IsDateTime(x) && BothOffsetsSet(x))
            .WithMessage($"DateOffsetAmount must be between -{DateOffsetAmountMax} and {DateOffsetAmountMax}.");

        validator.RuleFor(dateOffsetUnit)
            .IsInEnum()
            .When(x => IsDateTime(x) && BothOffsetsSet(x));
    }

    /// <summary>
    /// Adds kind-conditional validation for Macro hotstrings.
    /// When <paramref name="kind"/> is <see cref="HotstringKind.Macro"/>, <paramref name="replacement"/> must:
    /// (1) parse cleanly via <see cref="MacroTokenParser"/> — the first parser error is surfaced verbatim,
    /// (2) contain at most one <c>{{cursor}}</c> token, and (3) contain no <c>{{key:...}}</c> tokens after the
    /// cursor. Rules 2 and 3 only run when the replacement parsed without errors — a malformed replacement's
    /// token stream isn't meaningful to evaluate further.
    /// The Replacement-required and date-field-null rules for Macro are already covered by
    /// <see cref="AddDateTimeKindRules{T}"/> (Macro is not DateTime, so it falls into that method's "otherwise"
    /// branches) and are not duplicated here.
    /// </summary>
    public static void AddMacroKindRules<T>(
        this AbstractValidator<T> validator,
        Expression<Func<T, HotstringKind>> kind,
        Expression<Func<T, string>> replacement)
    {
        Func<T, HotstringKind> kindFn = kind.Compile();

        bool IsMacro(T x) => kindFn(x) == HotstringKind.Macro;

        validator.RuleFor(replacement)
            .Custom((value, context) =>
            {
                MacroParseResult parsed = MacroTokenParser.Parse(value);

                if (parsed.Errors.Count > 0)
                {
                    context.AddFailure(parsed.Errors[0]);
                    return;
                }

                int cursorCount = 0;
                bool keyAfterCursor = false;

                foreach (MacroToken token in parsed.Tokens)
                {
                    if (token is MacroToken.Cursor)
                        cursorCount++;
                    else if (token is MacroToken.Key && cursorCount > 0)
                        keyAfterCursor = true;
                }

                if (cursorCount > 1)
                {
                    context.AddFailure("Macro replacement must contain at most one {{cursor}} token.");
                    return;
                }

                if (keyAfterCursor)
                    context.AddFailure("Macro replacement must not contain {{key:...}} tokens after {{cursor}}.");
            })
            .When(IsMacro);
    }

    /// <summary>
    /// Adds kind-conditional validation for Raw hotstrings.
    /// When <paramref name="kind"/> is <see cref="HotstringKind.Raw"/>, <paramref name="replacement"/> (the
    /// verbatim AHK v2 definition) is run through <see cref="RawHotstringDefinitionParser.Prepare"/> — one
    /// authoritative pass that lifts leading <c>;</c> comments, body-aware-normalizes, and parses — and the
    /// resulting structural facts are mapped to per-rule failures: length (rule 8), first-line shape (1),
    /// single definition (2), derived trigger (3), known option flags (4), no directive lines outside a
    /// literal continuation body (5), and structural body completeness (6/7). Brace balance is checked via
    /// naive <c>{</c>/<c>}</c> counting with no string-literal or comment awareness (D12) — a <c>{</c> inside
    /// a quoted string (e.g. <c>SendText "{"</c>) counts toward the balance and can false-positive reject an
    /// otherwise valid definition. This is a deliberate limitation, not a bug: a string/comment-aware scanner
    /// would cross the "not a script IDE" boundary (D8). When a comment is lifted, its merge into
    /// <paramref name="description"/> (via <see cref="RawCommentLift.Merge"/>) is length-checked here; the
    /// base Description length rule for the typed value lives on the Create/Update/preview validators.
    /// </summary>
    public static void AddRawKindRules<T>(
        this AbstractValidator<T> validator,
        Expression<Func<T, HotstringKind>> kind,
        Expression<Func<T, string>> replacement,
        Expression<Func<T, string?>> description)
    {
        Func<T, HotstringKind> kindFn = kind.Compile();
        Func<T, string?> descriptionFn = description.Compile();

        bool IsRaw(T x) => kindFn(x) == HotstringKind.Raw;

        validator.RuleFor(replacement)
            .Custom((value, context) =>
            {
                value ??= string.Empty;

                // One authoritative preparation: lift leading comments, normalize, parse. Validating
                // the persisted form (normalized, comment-stripped) keeps validation and save in
                // lockstep (e.g. a whitespace-only inline replacement normalized to a bare trigger).
                RawPrepared prepared = RawHotstringDefinitionParser.Prepare(value);
                RawParseResult parsed = prepared.Parsed;

                // Rule 8 — length. Lifted comment lines leave the definition, so they don't count.
                if (prepared.NormalizedDefinition.Length > RawDefinitionMaxLength)
                {
                    context.AddFailure($"Raw definition must be {RawDefinitionMaxLength} characters or fewer.");
                    return;
                }

                // Rule 1 — first line must be a valid hotstring definition.
                if (!parsed.FirstLineValid)
                {
                    context.AddFailure(parsed.Error);
                    return;
                }

                // Rule 2 — exactly one definition.
                if (parsed.DefinitionCount > 1)
                {
                    context.AddFailure("Multiple hotstrings detected — paste one definition at a time.");
                    return;
                }

                // Rule 3 — derived trigger (Raw-specific 40-char limit; AHK's own abbreviation cap).
                if (parsed.Trigger.Length == 0)
                {
                    context.AddFailure("Trigger is required.");
                    return;
                }

                if (parsed.Trigger.Length > RawTriggerMaxLength)
                {
                    context.AddFailure($"Trigger must be {RawTriggerMaxLength} characters or fewer.");
                    return;
                }

                if (parsed.Trigger.IndexOfAny(['\n', '\r', '\t']) >= 0)
                {
                    context.AddFailure("Trigger must not contain line breaks or tabs.");
                    return;
                }

                // Rule 4 — every option flag in the known AHK v2 set.
                if (parsed.UnknownOptionTokens.Length > 0)
                {
                    context.AddFailure($"Unknown hotstring option '{parsed.UnknownOptionTokens[0]}'.");
                    return;
                }

                // Rule 5 — no directive lines outside a literal continuation body (would corrupt
                // #HotIf grouping). Body-awareness lives in the parser; the validator keeps the message.
                if (parsed.HasDirectiveOutsideLiteralBody)
                {
                    context.AddFailure("Raw definition must not contain directive lines starting with '#'.");
                    return;
                }

                // Rules 6 & 7 — structural body completeness (balanced brace body / inline shape).
                if (!parsed.IsValid)
                {
                    context.AddFailure(parsed.Error);
                    return;
                }

                // A lifted comment merges into Description — reject when it no longer fits. Only the
                // lifted case is checked here; the standalone Description rule covers the rest.
                if (prepared.LiftedComment is not null)
                {
                    string? merged = RawCommentLift.Merge(descriptionFn(context.InstanceToValidate), prepared.LiftedComment);
                    if (merged is not null && merged.Length > DescriptionMaxLength)
                        context.AddFailure("Pasted comment does not fit in Description (200-char max) — shorten it or remove the comment lines.");
                }
            })
            .When(IsRaw);
    }

    /// <summary>
    /// Adds validation for a hotstring's optional window-context match, kind-agnostic (applies
    /// regardless of <see cref="HotstringKind"/>): <paramref name="contextMatchType"/> and
    /// <paramref name="contextValue"/> must both be null or both be set, the match type must be a
    /// valid <see cref="WindowMatchType"/>, and the value must not be blank/whitespace-only, is
    /// capped at <see cref="ContextValueMaxLength"/> characters, and must not contain a
    /// double-quote, backtick, or any control character &#8212; it is embedded raw into a
    /// generated <c>WinActive(...)</c> AHK expression, so these characters would break or escape
    /// that syntax.
    /// </summary>
    public static void AddWindowContextRules<T>(
        this AbstractValidator<T> validator,
        Expression<Func<T, WindowMatchType?>> contextMatchType,
        Expression<Func<T, string?>> contextValue)
    {
        Func<T, string?> valueFn = contextValue.Compile();

        // Both-or-neither
        validator.RuleFor(contextMatchType)
            .Must((x, matchType) => (matchType is null) == (valueFn(x) is null))
            .WithMessage("ContextMatchType and ContextValue must both be set or both be null.");

        validator.RuleFor(contextMatchType)
            .IsInEnum();

        validator.RuleFor(contextValue)
            .Must(v => v is null || !string.IsNullOrWhiteSpace(v))
                .WithMessage("ContextValue must not be blank or whitespace.")
            .MaximumLength(ContextValueMaxLength)
                .WithMessage($"ContextValue must be {ContextValueMaxLength} characters or fewer.")
            .Must(v => v is null || !v.Contains('"'))
                .WithMessage("ContextValue must not contain double-quote characters.")
            .Must(v => v is null || !v.Contains('`'))
                .WithMessage("ContextValue must not contain backtick characters.")
            .Must(v => v is null || !v.Any(char.IsControl))
                .WithMessage("ContextValue must not contain control characters.");
    }

    [GeneratedRegex(@"^(?=.*[yMdHhmst])[yMdHhmst0-9 \-./:,()]+$")]
    private static partial Regex DateTimeFormatWhitelistRegex();
}
