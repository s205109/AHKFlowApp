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
    [GeneratedRegex(@"^:([^:\r\n]*):(.*?)::(.*)$")]
    private static partial Regex HotstringLine();

    public static IReadOnlyList<HotstringImportRowDto> Parse(string script)
    {
        ArgumentNullException.ThrowIfNull(script);

        string[] lines = script.Replace("\r\n", "\n").Split('\n');
        List<HotstringImportRowDto> rows = [];

        for (int i = 0; i < lines.Length; i++)
        {
            string line = lines[i];
            string trimmed = line.Trim();

            if (trimmed.Length == 0 || trimmed.StartsWith(';'))
                continue;

            Match match = HotstringLine().Match(line);
            if (!match.Success)
                continue; // hotkey, directive, or plain code — not a hotstring candidate

            int lineNumber = i + 1;
            string trigger = match.Groups[2].Value.Trim();
            string replacement = DecodeEscapes(match.Groups[3].Value);
            (bool endingRequired, bool insideWord, string[] ignoredFlags) = ParseOptions(match.Groups[1].Value);

            // "::trigger::" immediately followed by a "(" opens a continuation section.
            if (replacement.Length == 0 && i + 1 < lines.Length && lines[i + 1].Trim() == "(")
            {
                rows.Add(new HotstringImportRowDto(
                    lineNumber, trigger, replacement, endingRequired, insideWord, ignoredFlags,
                    HotstringImportRowStatus.Invalid, "Multi-line replacements are not supported."));

                i++; // consume "("
                while (i + 1 < lines.Length && lines[i + 1].Trim() != ")")
                    i++;
                if (i + 1 < lines.Length)
                    i++; // consume ")"
                continue;
            }

            string? reason = ValidateTrigger(trigger) ?? ValidateReplacement(replacement);
            HotstringImportRowStatus status = reason is not null
                ? HotstringImportRowStatus.Invalid
                : ignoredFlags.Length > 0
                    ? HotstringImportRowStatus.Warning
                    : HotstringImportRowStatus.Ready;

            rows.Add(new HotstringImportRowDto(
                lineNumber, trigger, replacement, endingRequired, insideWord, ignoredFlags, status, reason));
        }

        return rows;
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

            char next = value[++i];
            sb.Append(next switch
            {
                '`' => '`',
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                's' => ' ',
                ';' => ';',
                _ => next,
            });
        }

        return sb.ToString();
    }

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
