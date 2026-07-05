namespace AHKFlowApp.Application.Validation;

internal static class HotstringImportRules
{
    /// <summary>Max raw script payload, in characters (~1 MB sanity bound).</summary>
    public const int MaxScriptLength = 1_048_576;

    /// <summary>Max parsed hotstring rows accepted per import.</summary>
    public const int MaxRows = 1000;
}
