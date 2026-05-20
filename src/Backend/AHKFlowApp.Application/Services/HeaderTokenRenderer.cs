using System.Globalization;
using System.Text;

namespace AHKFlowApp.Application.Services;

/// <summary>
/// Substitutes recognized tokens in a header/footer template, then collapses
/// doubled braces (<c>{{</c> / <c>}}</c>) to literal single braces.
/// All formatting uses <see cref="CultureInfo.InvariantCulture"/> so generated
/// scripts are culture-independent.
/// </summary>
public sealed class HeaderTokenRenderer
{
    public readonly record struct Context(
        string ProfileName,
        string AppVersion,
        int HotstringCount,
        int HotkeyCount,
        DateTimeOffset GeneratedAt);

    public string Render(string template, Context ctx)
    {
        if (string.IsNullOrEmpty(template))
            return template;

        StringBuilder sb = new(template.Length + 64);
        int i = 0;
        while (i < template.Length)
        {
            char c = template[i];
            // Skip past escapes — they're handled in pass 2.
            if (c == '{' && i + 1 < template.Length && template[i + 1] == '{')
            {
                sb.Append('{').Append('{');
                i += 2;
                continue;
            }
            if (c == '}' && i + 1 < template.Length && template[i + 1] == '}')
            {
                sb.Append('}').Append('}');
                i += 2;
                continue;
            }
            if (c == '{')
            {
                int close = template.IndexOf('}', i + 1);
                if (close < 0)
                {
                    sb.Append(template, i, template.Length - i);
                    break;
                }
                string raw = template.Substring(i + 1, close - i - 1);
                int colon = raw.IndexOf(':');
                string name = colon < 0 ? raw : raw[..colon];
                string? format = colon < 0 ? null : raw[(colon + 1)..];

                if (TryRender(name, format, ctx, out string replacement))
                {
                    sb.Append(replacement);
                }
                else
                {
                    sb.Append(template, i, close - i + 1);
                }
                i = close + 1;
                continue;
            }

            sb.Append(c);
            i++;
        }

        // Pass 2: collapse {{ → { and }} → }
        string afterPass1 = sb.ToString();
        if (!afterPass1.Contains("{{", StringComparison.Ordinal)
            && !afterPass1.Contains("}}", StringComparison.Ordinal))
            return afterPass1;

        return afterPass1.Replace("{{", "{", StringComparison.Ordinal)
                         .Replace("}}", "}", StringComparison.Ordinal);
    }

    private static bool TryRender(string name, string? format, Context ctx, out string replacement)
    {
        switch (name)
        {
            case "ProfileName":
                replacement = ctx.ProfileName;
                return true;
            case "AppVersion":
                replacement = ctx.AppVersion;
                return true;
            case "HotstringCount":
                replacement = ctx.HotstringCount.ToString(CultureInfo.InvariantCulture);
                return true;
            case "HotkeyCount":
                replacement = ctx.HotkeyCount.ToString(CultureInfo.InvariantCulture);
                return true;
            case "GeneratedAt":
                replacement = ctx.GeneratedAt.ToString(format ?? "o", CultureInfo.InvariantCulture);
                return true;
            default:
                replacement = string.Empty;
                return false;
        }
    }
}
