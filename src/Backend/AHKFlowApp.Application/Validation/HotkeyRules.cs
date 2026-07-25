using AHKFlowApp.Application.Constants;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Enums;
using FluentValidation;

namespace AHKFlowApp.Application.Validation;

internal static class HotkeyRules
{
    public const int DescriptionMaxLength = 200;
    public const int KeyMaxLength = 20;

    /// <summary>
    /// The <c>nvarchar(4000)</c> ceiling shared by the legacy <c>Parameters</c> column and the
    /// typed <c>RunTarget</c> column. Applied to every free-text payload field so the retired
    /// <c>ValidParameters</c> cap survives the move onto the typed columns.
    /// </summary>
    public const int PayloadMaxLength = 4000;

    public static IRuleBuilderOptions<T, string> ValidDescription<T>(this IRuleBuilderInitial<T, string> rb) =>
        rb.Cascade(CascadeMode.Stop)
          .NotEmpty().WithMessage("Description is required.")
          .MaximumLength(DescriptionMaxLength).WithMessage($"Description must be {DescriptionMaxLength} characters or fewer.");

    // Key is validated against the canonical registry (or a vkNN / scNNN code) rather than
    // by rejecting known-bad characters. This is the whitelist half of issue #195: an
    // accepted Key is a real AHK key name, so the emitted left-hand side cannot break the
    // script. Escaping of the right-hand side lives in HotkeyEmitter.
    public static IRuleBuilderOptions<T, string> ValidKey<T>(this IRuleBuilderInitial<T, string> rb) =>
        rb.Cascade(CascadeMode.Stop)
          .NotEmpty().WithMessage("Key is required.")
          .MaximumLength(KeyMaxLength).WithMessage($"Key must be {KeyMaxLength} characters or fewer.")
          .Must(HotkeyKeys.IsValidHotkeyKey)
              .WithMessage("Key must be a known key name (for example a, F5, Escape, Numpad0) "
                         + "or a vkNN / scNNN code. Combined vkNNscNNN is not valid in a hotkey.");

    /// <summary>
    /// Kind-conditional action rules (spec §8): each <see cref="HotkeyActionKind"/> requires its own
    /// field(s) and forbids the others'. SendKeys/Remap fields are additionally token-validated; Raw
    /// is brace-balanced with no <c>#</c> directive.
    /// </summary>
    public static void AddHotkeyActionRules<T>(this AbstractValidator<T> v, Func<T, IHotkeyDraft> draft)
    {
        v.RuleFor(x => x).Custom((x, ctx) =>
        {
            IHotkeyDraft d = draft(x);
            HotkeyActionKind k = d.ActionKind;

            // System.Text.Json deserializes any int into an enum field, so a payload can carry
            // ActionKind: 99. Without this the switch below matches nothing, ForbidExcept sees no
            // owner, the DTO validates, and the *emitter* is left to throw — a 500 on bad input.
            // Same for the two nested enums: `is null` alone accepts (WindowOp)99.
            if (!Enum.IsDefined(k))
            {
                ctx.AddFailure("ActionKind", "ActionKind must be a valid HotkeyActionKind value.");
                return;
            }

            // Required field present + valid, per kind.
            switch (k)
            {
                case HotkeyActionKind.SendText:
                    if (string.IsNullOrEmpty(d.Text))
                        ctx.AddFailure("Text", "SendText requires Text.");
                    else
                        ValidateFreeText(d.Text, "Text", ctx);
                    break;

                case HotkeyActionKind.SendKeys:
                    if (!Tokens.IsValidSendKeysContent(d.SendKeysContent))
                        ctx.AddFailure("SendKeysContent", "SendKeys requires a valid key token (for example {Volume_Up} or ^c).");
                    break;

                // Two failures, two fields: a bad RunTargetKind must not be reported against
                // RunTarget, or the UI highlights the wrong control and the ProblemDetails names a
                // field the client never sent wrong.
                case HotkeyActionKind.Run:
                    if (string.IsNullOrEmpty(d.RunTarget))
                        ctx.AddFailure("RunTarget", "Run requires a run target.");
                    else
                        ValidateFreeText(d.RunTarget, "RunTarget", ctx);

                    if (d.RunTargetKind is not RunTargetKind rtk || !Enum.IsDefined(rtk))
                        ctx.AddFailure("RunTargetKind", "Run requires a valid run target kind.");
                    break;

                case HotkeyActionKind.Window:
                    if (d.WindowOp is not WindowOp op || !Enum.IsDefined(op))
                        ctx.AddFailure("WindowOp", "Window requires a valid window operation.");
                    break;

                case HotkeyActionKind.Remap:
                    if (!Tokens.IsValidRemapDest(d.RemapDest))
                        ctx.AddFailure("RemapDest", "Remap requires a valid destination key.");
                    break;

                // The emitter writes Body verbatim (2026-07-22 decision), so a block body carries
                // its own outer braces. Counting braces holds either way; it does not assume an
                // emitter-supplied wrapper.
                case HotkeyActionKind.Raw:
                    if (string.IsNullOrEmpty(d.Body))
                        ctx.AddFailure("Body", "Raw requires an action body.");
                    else if (!BracesBalanced(d.Body))
                        ctx.AddFailure("Body", "Raw body braces are unbalanced.");
                    else if (HasDirectiveLine(d.Body))
                        ctx.AddFailure("Body", "Raw body must not contain a # directive.");
                    else
                        ValidateFreeText(d.Body, "Body", ctx);
                    break;

                case HotkeyActionKind.Disable:
                    break;   // takes no payload field at all
            }

            // Foreign fields forbidden: only the kind's own field(s) may be set. RunTargetKind is
            // listed too — it is Run's second field, and omitting it let a SendText payload smuggle
            // one through.
            ForbidExcept(k, ctx,
                (HotkeyActionKind.SendText, "Text", !string.IsNullOrEmpty(d.Text)),
                (HotkeyActionKind.SendKeys, "SendKeysContent", !string.IsNullOrEmpty(d.SendKeysContent)),
                (HotkeyActionKind.Run, "RunTarget", !string.IsNullOrEmpty(d.RunTarget)),
                (HotkeyActionKind.Run, "RunTargetKind", d.RunTargetKind is not null),
                (HotkeyActionKind.Window, "WindowOp", d.WindowOp is not null),
                (HotkeyActionKind.Remap, "RemapDest", !string.IsNullOrEmpty(d.RemapDest)),
                (HotkeyActionKind.Raw, "Body", !string.IsNullOrEmpty(d.Body)));
        });
    }

    /// <summary>
    /// The two limits the retired <c>ValidParameters</c> rule enforced, carried onto the free-text
    /// successors of <c>Parameters</c>. Length still matters (<c>RunTarget</c> is nvarchar(4000)),
    /// and so do control characters: <c>AhkEscaping</c> represents only <c>\n</c>, <c>\r</c> and
    /// <c>\t</c>, so any other one would reach the emitted script verbatim.
    /// </summary>
    private static void ValidateFreeText<T>(string value, string field, ValidationContext<T> ctx)
    {
        if (value.Length > PayloadMaxLength)
            ctx.AddFailure(field, $"{field} must be {PayloadMaxLength} characters or fewer.");
        else if (value.Any(c => char.IsControl(c) && c is not '\n' and not '\r' and not '\t'))
            ctx.AddFailure(field, $"{field} must not contain control characters.");
    }

    /// <summary>
    /// Equal counts of <c>{</c> and <c>}</c> — deliberately not nesting order, which a verbatim
    /// body may legitimately open and close across the lines the emitter writes untouched.
    /// </summary>
    private static bool BracesBalanced(string body)
    {
        int open = 0, close = 0;
        foreach (char c in body)
        {
            if (c == '{')
                open++;
            else if (c == '}')
                close++;
        }

        return open == close;
    }

    // Split on '\n' only, matching what the emitted script treats as a line: a lone '\r' does not
    // start a new directive line, so neither does it here.
    private static bool HasDirectiveLine(string body)
    {
        ReadOnlySpan<char> rest = body;
        while (!rest.IsEmpty)
        {
            int nl = rest.IndexOf('\n');
            ReadOnlySpan<char> line = nl < 0 ? rest : rest[..nl];
            if (line.TrimStart().StartsWith('#'))
                return true;

            if (nl < 0)
                break;

            rest = rest[(nl + 1)..];
        }

        return false;
    }

    private static void ForbidExcept<T>(
        HotkeyActionKind kind, ValidationContext<T> ctx,
        params (HotkeyActionKind Owner, string Field, bool IsSet)[] fields)
    {
        foreach ((HotkeyActionKind owner, string field, bool isSet) in fields)
        {
            if (owner != kind && isSet)
                ctx.AddFailure(field, $"{field} is only valid for the {owner} action.");
        }
    }

    /// <summary>
    /// Pure token grammars for the two validated-token action kinds (spec §8). Public so validators
    /// and unit tests share exactly one implementation of each rule.
    /// </summary>
    public static class Tokens
    {
        /// <summary>
        /// A <c>SendKeys</c> token: optional <c>^ ! + #</c> modifiers (each at most once, any order;
        /// <c>*</c> is NOT a Send modifier) then exactly one key — a single printable character bare
        /// (<c>c</c>), or a registry key with the <c>SendToken</c> role braced (<c>{Volume_Up}</c>).
        /// A named key unbraced, a double-brace macro leak, and multiple keys are all rejected.
        /// </summary>
        public static bool IsValidSendKeysContent(string? content)
        {
            if (string.IsNullOrEmpty(content))
                return false;

            (string mods, string key) = SplitSendKeysToken(content);

            // Each modifier at most once. The prefix is four symbols at most, so a linear
            // look-back is cheaper than any set.
            for (int i = 1; i < mods.Length; i++)
            {
                if (mods.IndexOf(mods[i]) < i)
                    return false;
            }

            if (key.Length == 0)
                return false; // modifiers but no key

            if (key[0] == '{')
            {
                if (key.Length < 3 || key[^1] != '}')
                    return false;
                string inner = key[1..^1];
                // Exactly one braced token: no nested/second brace (rejects {{date...}} and {a}{b}).
                if (inner.Length == 0 || inner.Contains('{') || inner.Contains('}'))
                    return false;

                // vk/sc codes are valid Send tokens; named keys must carry the SendToken role.
                return HotkeyKeys.IsValidSendToken(inner);
            }

            // Bare: exactly one printable, non-brace, non-modifier character. Quote and backtick
            // stay valid here — Send can type them. They are hostile to the *string literal*, not
            // to Send, so the emitter escapes them (Task 5); this validator owns Send semantics only.
            return key.Length == 1 && !char.IsControl(key[0]) && key[0] is not '{' and not '}';
        }

        /// <summary>
        /// A <c>RemapDest</c> token: a single registry key with the <c>RemapDest</c> role, or a
        /// <c>vk</c>/<c>sc</c> code. No modifiers, no braces (spec §8).
        /// </summary>
        public static bool IsValidRemapDest(string? dest) => HotkeyKeys.IsValidRemapDest(dest);

        /// <summary>
        /// Canonical spelling of a token already accepted by <see cref="IsValidSendKeysContent"/>
        /// (spec §8 storage invariant). The modifier prefix is preserved verbatim — its order and
        /// the four symbols carry meaning — and a braced named/code key is resolved to its registry
        /// spelling (<c>{Esc}</c> → <c>{Escape}</c>, <c>{vk1}</c> → <c>{vk01}</c>). A bare printable
        /// character is returned unchanged: Send reads it case-sensitively (<c>^C</c> ≠ <c>^c</c>),
        /// so folding it would change what is typed.
        /// </summary>
        public static string? NormalizeSendKeysContent(string? content)
        {
            if (string.IsNullOrEmpty(content))
                return content;

            (string mods, string key) = SplitSendKeysToken(content);
            if (key.Length == 0 || key[0] != '{')
                return content;

            string inner = key[1..^1];
            return HotkeyKeys.TryCanonicalize(inner, out string canonical)
                ? $"{mods}{{{canonical}}}"
                : content;
        }

        /// <summary>
        /// Canonical spelling of a token already accepted by <see cref="IsValidRemapDest"/>
        /// (<c>Esc</c> → <c>Escape</c>, <c>vk1</c> → <c>vk01</c>).
        /// </summary>
        public static string? NormalizeRemapDest(string? dest) =>
            HotkeyKeys.TryCanonicalize(dest, out string canonical) ? canonical : dest;

        /// <summary>
        /// Splits a Send token into its modifier prefix and the key part that follows. Shared by
        /// the validator and the normalizer so the two cannot disagree on where the modifiers end
        /// — a disagreement would persist an accepted token unnormalized and break the §8 storage
        /// invariant duplicate detection depends on.
        /// </summary>
        private static (string Mods, string Key) SplitSendKeysToken(string content)
        {
            int i = 0;
            while (i < content.Length && content[i] is '^' or '!' or '+' or '#')
                i++;

            return (content[..i], content[i..]);
        }
    }
}
