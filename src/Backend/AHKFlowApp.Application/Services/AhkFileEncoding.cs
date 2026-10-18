using System.Text;

namespace AHKFlowApp.Application.Services;

public static class AhkFileEncoding
{
    /// <summary>
    /// The bytes of a downloaded <c>.ahk</c> file: a UTF-8 byte-order mark, then the script as
    /// UTF-8. The section "The bytes of a downloaded file" in
    /// <c>docs/development/ahk-v2-syntax.md</c> says why.
    /// </summary>
    public static byte[] GetBytes(string script) =>
        [.. Encoding.UTF8.GetPreamble(), .. Encoding.UTF8.GetBytes(script)];
}
