using System.Globalization;

namespace AHKFlowApp.UI.Blazor.Helpers;

/// <summary>
/// Sortable local-time stamps for generated download file names. Invariant culture keeps the
/// stamp digits identical on every machine — a non-Gregorian calendar culture would otherwise
/// change the year in the file name.
/// </summary>
public static class DownloadFileNames
{
    /// <summary>Stamps the clock's current local moment, e.g. <c>20260726_140509</c>.</summary>
    public static string Timestamp(TimeProvider clock) => Timestamp(clock.GetLocalNow());

    /// <summary>Stamps an explicit local moment, e.g. <c>20260726_140509</c>.</summary>
    public static string Timestamp(DateTimeOffset localNow) =>
        localNow.ToString("yyyyMMdd_HHmmss", CultureInfo.InvariantCulture);
}
