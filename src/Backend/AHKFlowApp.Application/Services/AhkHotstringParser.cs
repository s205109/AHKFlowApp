using System.Text;
using System.Text.RegularExpressions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Validation;

namespace AHKFlowApp.Application.Services;

/// <summary>
/// Parses AutoHotkey v2 hotstring lines into typed rows — the syntax inverse of
/// <see cref="AhkScriptGenerator"/>'s <c>:{options}:{trigger}::{replacement}</c> format.
/// Pure and stateless; emits only Ready/Warning/Invalid (never Duplicate).
/// </summary>
internal static partial class AhkHotstringParser
{
    // :options:trigger::replacement — options and trigger contain no ':'; the trigger is
    // non-greedy so the FIRST '::' delimits, leaving any later '::' inside the replacement.
    // Leading whitespace is tolerated so indented hotstring definitions still match, both
    // at the top level and as the hard boundary inside a scanned code body.
    [GeneratedRegex(@"^\s*:([^:\r\n]*):(.*?)::(.*)$")]
    private static partial Regex HotstringLine();

    [GeneratedRegex(@"^\s*(SendInput|SendText|SendRaw|SendEvent|SendPlay|Send)\b\s*,?\s*(.*)$", RegexOptions.IgnoreCase)]
    private static partial Regex SendCommand();

    // A bare "return" that terminates a v1 code body may carry a trailing comment
    // (e.g. "return ; end hotstring") — still a valid terminator, not body content.
    [GeneratedRegex(@"^return(?:[ \t]+;.*)?$", RegexOptions.IgnoreCase)]
    private static partial Regex ReturnStatement();

    public static IReadOnlyList<HotstringImportRowDto> Parse(string script)
    {
        ArgumentNullException.ThrowIfNull(script);

        // Normalize every line ending variant (CRLF, lone CR, LF) to LF before splitting —
        // a lone-CR script would otherwise collapse into a single unparseable line.
        string[] lines = script.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n');
        List<HotstringImportRowDto> rows = [];

        for (int i = 0; i < lines.Length; i++)
        {
            string line = lines[i];
            string trimmed = line.Trim();

            if (IsBlankOrComment(trimmed))
                continue;

            Match match = HotstringLine().Match(line);
            if (!match.Success)
                continue; // hotkey, directive, or plain code — not a hotstring candidate

            int lineNumber = i + 1;
            string trigger = DecodeEscapes(match.Groups[2].Value).Trim();
            string rawReplacement = match.Groups[3].Value;
            string replacement = DecodeEscapes(StripInlineComment(rawReplacement));
            (bool endingRequired, bool insideWord, string[] ignoredFlags) = ParseOptions(match.Groups[1].Value);

            // Route on the RAW (pre-decode) replacement text — deciding on the decoded value
            // would misroute a raw replacement that decodes to empty (e.g. a lone trailing
            // backtick) into the continuation/code-body scanners below.
            // "::trigger::" immediately followed by a "(" opens a continuation section.
            if (rawReplacement.Length == 0 && i + 1 < lines.Length && lines[i + 1].Trim().StartsWith('('))
            {
                rows.Add(ParseContinuationSection(
                    lines, ref i, lineNumber, trigger, endingRequired, insideWord, ignoredFlags));
                continue;
            }

            // "::trigger::" followed by non-hotstring code is a v1 code-body hotstring.
            if (rawReplacement.Length == 0 && HasCodeBody(lines, i))
            {
                rows.Add(ParseCodeBody(
                    lines, ref i, lineNumber, trigger, endingRequired, insideWord, ignoredFlags));
                continue;
            }

            rows.Add(BuildRow(lineNumber, trigger, replacement, endingRequired, insideWord, ignoredFlags));
        }

        return rows;
    }

    private static bool IsBlankOrComment(string trimmed) =>
        trimmed.Length == 0 || trimmed.StartsWith(';');

    private static HotstringImportRowDto BuildRow(
        int lineNumber,
        string trigger,
        string replacement,
        bool endingRequired,
        bool insideWord,
        string[] ignoredFlags)
    {
        string? reason = ValidateTrigger(trigger) ?? ValidateReplacement(replacement);
        HotstringImportRowStatus status = reason is not null
            ? HotstringImportRowStatus.Invalid
            : ignoredFlags.Length > 0
                ? HotstringImportRowStatus.Warning
                : HotstringImportRowStatus.Ready;

        return new HotstringImportRowDto(
            lineNumber, trigger, replacement, endingRequired, insideWord, ignoredFlags, status, reason);
    }

    private static HotstringImportRowDto ParseContinuationSection(
        string[] lines,
        ref int i,
        int lineNumber,
        string trigger,
        bool endingRequired,
        bool insideWord,
        string[] ignoredFlags)
    {
        i++; // consume "("
        List<string> inner = [];

        while (i + 1 < lines.Length)
        {
            i++;
            // AHK closes a continuation section on any line whose first non-whitespace
            // character is ')' — trailing content (e.g. "') ; comment") is legal.
            if (lines[i].Trim().StartsWith(')'))
                return BuildRow(
                    lineNumber, trigger, string.Join('\n', inner),
                    endingRequired, insideWord, ignoredFlags);

            inner.Add(lines[i].TrimStart());
        }

        return InvalidRow(
            lineNumber, trigger, endingRequired, insideWord, ignoredFlags,
            "Unterminated continuation section.");
    }

    private static bool HasCodeBody(string[] lines, int index)
    {
        for (int j = index + 1; j < lines.Length; j++)
        {
            string trimmed = lines[j].Trim();
            if (IsBlankOrComment(trimmed))
                continue;

            return !HotstringLine().IsMatch(lines[j]);
        }

        return false;
    }

    private static HotstringImportRowDto ParseCodeBody(
        string[] lines,
        ref int i,
        int lineNumber,
        string trigger,
        bool endingRequired,
        bool insideWord,
        string[] ignoredFlags)
    {
        List<string> body = [];
        int nestedDepth = 0;
        bool terminated = false;

        while (i + 1 < lines.Length)
        {
            string next = lines[i + 1];
            string trimmed = next.Trim();

            if (nestedDepth == 0)
            {
                if (HotstringLine().IsMatch(next))
                    return InvalidRow(
                        lineNumber, trigger, endingRequired, insideWord, ignoredFlags,
                        "Unterminated code body (no `return` before next hotstring).");

                i++;

                if (IsBlankOrComment(trimmed))
                    continue;

                if (ReturnStatement().IsMatch(trimmed))
                {
                    terminated = true;
                    break;
                }

                // A continuation opener may carry options ("( LTrim", "( Join`n") — any line
                // starting with '(' opens a nested block.
                if (trimmed.StartsWith('('))
                    nestedDepth++;

                body.Add(next);
            }
            else
            {
                i++;
                if (trimmed.StartsWith('('))
                    nestedDepth++;
                else if (trimmed.StartsWith(')'))
                    nestedDepth--;

                body.Add(next);
            }
        }

        if (!terminated)
            return InvalidRow(
                lineNumber, trigger, endingRequired, insideWord, ignoredFlags,
                "Unterminated code body (no `return`).");

        return TryConvertSendBody(body, out string converted, out string reason)
            ? BuildRow(lineNumber, trigger, converted, endingRequired, insideWord, ignoredFlags)
            : InvalidRow(lineNumber, trigger, endingRequired, insideWord, ignoredFlags, reason);
    }

    private static HotstringImportRowDto InvalidRow(
        int lineNumber,
        string trigger,
        bool endingRequired,
        bool insideWord,
        string[] ignoredFlags,
        string reason) =>
        new(lineNumber, trigger, "", endingRequired, insideWord, ignoredFlags,
            HotstringImportRowStatus.Invalid, reason);

    private static bool TryConvertSendBody(
        IReadOnlyList<string> bodyLines,
        out string replacement,
        out string reason)
    {
        replacement = "";
        reason = "Code-body hotstrings that run logic aren't supported.";

        StringBuilder text = new();
        foreach (string line in bodyLines)
        {
            Match match = SendCommand().Match(line);
            if (!match.Success)
            {
                string token = FirstToken(line);
                if (token.Length > 0)
                    reason = $"Code-body hotstrings that run logic aren't supported (found: {token}).";

                return false;
            }

            string command = match.Groups[1].Value;
            bool literalMode = command.Equals("SendText", StringComparison.OrdinalIgnoreCase)
                || command.Equals("SendRaw", StringComparison.OrdinalIgnoreCase);

            if (!TryConvertSendArg(match.Groups[2].Value, literalMode, out string converted, out reason))
                return false;

            text.Append(converted);
        }

        replacement = text.ToString();
        return true;
    }

    private static bool TryConvertSendArg(
        string arg,
        bool literalMode,
        out string converted,
        out string reason)
    {
        converted = "";
        reason = "";

        if (arg.Trim() == "(")
        {
            reason = "Code-body hotstrings that run logic aren't supported (found: continuation section in Send).";
            return false;
        }

        StringBuilder sb = new(arg.Length);
        for (int i = 0; i < arg.Length; i++)
        {
            char c = arg[i];

            if (c == '`')
            {
                if (i + 1 >= arg.Length)
                    break;

                sb.Append(DecodeEscapeChar(arg[++i]));
                continue;
            }

            if (c == ';' && (i == 0 || arg[i - 1] is ' ' or '\t'))
            {
                reason = "Inline comment in Send — not imported.";
                return false;
            }

            if (c == '%')
            {
                reason = "Code-body hotstrings that run logic aren't supported (found: % character).";
                return false;
            }

            if (!literalMode && c is '^' or '!' or '+' or '#')
            {
                reason = $"Code-body hotstrings that run logic aren't supported (found: modifier {c}).";
                return false;
            }

            if (!literalMode && c == '{')
            {
                int close = arg.IndexOf('}', i + 1);
                if (close < 0)
                {
                    reason = "Code-body hotstrings that run logic aren't supported (found: unclosed { token).";
                    return false;
                }

                string token = arg[(i + 1)..close];
                if (token.Equals("Enter", StringComparison.OrdinalIgnoreCase)
                    || token.Equals("Return", StringComparison.OrdinalIgnoreCase))
                {
                    sb.Append('\n');
                }
                else if (token.Equals("Tab", StringComparison.OrdinalIgnoreCase))
                {
                    sb.Append('\t');
                }
                else
                {
                    reason = $"Code-body hotstrings that run logic aren't supported (found: {{{token}}}).";
                    return false;
                }

                i = close;
                continue;
            }

            if (!literalMode && c == '}')
            {
                reason = "Code-body hotstrings that run logic aren't supported (found: stray }).";
                return false;
            }

            sb.Append(c);
        }

        converted = sb.ToString();
        return true;
    }

    private static string FirstToken(string line)
    {
        string trimmed = line.Trim();
        int end = trimmed.IndexOfAny([' ', '\t', ',']);
        return end < 0 ? trimmed : trimmed[..end];
    }

    // Mirrors AhkScriptGenerator's Escape(): a ';' preceded by whitespace starts a real
    // AHK comment unless it was backtick-escaped, so the importer must stop decoding
    // there instead of treating the comment text as part of the replacement.
    private static string StripInlineComment(string raw)
    {
        for (int i = 0; i < raw.Length; i++)
        {
            char c = raw[i];
            if (c == '`')
            {
                i++;
                continue;
            }

            if (c == ';' && i > 0 && raw[i - 1] is ' ' or '\t')
                return raw[..i].TrimEnd(' ', '\t');
        }

        return raw;
    }

    private static string DecodeEscapes(string value)
    {
        if (!value.Contains('`'))
            return value;

        StringBuilder sb = new(value.Length);
        for (int i = 0; i < value.Length; i++)
        {
            char c = value[i];
            if (c != '`')
            {
                sb.Append(c);
                continue;
            }

            if (i + 1 >= value.Length)
                break;

            sb.Append(DecodeEscapeChar(value[++i]));
        }

        return sb.ToString();
    }

    // Shared by DecodeEscapes (single-line replacements) and TryConvertSendArg (v1 Send
    // bodies) so the two decoding paths cannot silently diverge.
    private static char DecodeEscapeChar(char next) =>
        next switch
        {
            '`' => '`',
            'n' => '\n',
            'r' => '\r',
            't' => '\t',
            's' => ' ',
            ';' => ';',
            _ => next,
        };

    private static (bool EndingRequired, bool InsideWord, string[] Ignored) ParseOptions(string options)
    {
        bool endingRequired = true;
        bool insideWord = false;
        List<string> ignored = [];

        for (int i = 0; i < options.Length; i++)
        {
            char c = options[i];
            switch (c)
            {
                case '*':
                    endingRequired = false;
                    break;
                case '?':
                    insideWord = true;
                    break;
                case ' ' or '\t':
                    break;
                case 'S' or 's' when i + 1 < options.Length && options[i + 1] is 'I' or 'P' or 'E' or 'i' or 'p' or 'e':
                    // Send-mode flags (SI/SP/SE) are two-letter tokens.
                    ignored.Add(options.Substring(i, 2));
                    i++;
                    break;
                default:
                    // A flag plus its trailing digits is one token (B0, C1, K5, P9, Z0, …),
                    // preserved verbatim so the preview reports exactly what was dropped.
                    int start = i;
                    while (i + 1 < options.Length && char.IsDigit(options[i + 1]))
                        i++;
                    ignored.Add(options[start..(i + 1)]);
                    break;
            }
        }

        return (endingRequired, insideWord, [.. ignored]);
    }

    private static string? ValidateTrigger(string trigger) =>
        trigger.Length == 0
            ? "Trigger is required."
            : trigger.Length > HotstringRules.TriggerMaxLength
                ? $"Trigger must be {HotstringRules.TriggerMaxLength} characters or fewer."
                : trigger.IndexOfAny(['\n', '\r', '\t']) >= 0
                    ? "Trigger must not contain line breaks or tabs."
                    : null;

    private static string? ValidateReplacement(string replacement) =>
        replacement.Length == 0
            ? "Replacement is required."
            : replacement.Length > HotstringRules.ReplacementMaxLength
                ? $"Replacement must be {HotstringRules.ReplacementMaxLength} characters or fewer."
                : null;
}
