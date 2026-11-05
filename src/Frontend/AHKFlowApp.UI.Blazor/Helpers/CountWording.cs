namespace AHKFlowApp.UI.Blazor.Helpers;

/// <summary>
/// A count with its noun, such as "1 hotstring" or "3 hotstrings". Only one takes the singular.
/// The caller passes both forms, because English plurals such as "categories" are not regular.
/// </summary>
internal static class CountWording
{
    public static string Of(int count, string singular, string plural) =>
        $"{count} {(count == 1 ? singular : plural)}";
}
