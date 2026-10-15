using AHKFlowApp.Application.Commands.Dev;
using AHKFlowApp.Application.Constants;
using AHKFlowApp.Domain.Constants;

namespace AHKFlowApp.TestUtilities.Fixtures;

/// <summary>
/// The number of rows in each dev seed catalog. A test project that cannot see the internals of
/// AHKFlowApp.Application reads its expected seed counts here, so a catalog change does not break
/// its count assertions.
/// </summary>
public static class SeedCatalogCounts
{
    /// <summary>The default categories in <c>DefaultCategories.Names</c>.</summary>
    public static int Categories => DefaultCategories.Names.Count;

    /// <summary>The sample hotstrings in <c>HotstringSeedSamples.All</c>.</summary>
    public static int Hotstrings => HotstringSeedSamples.All.Length;

    /// <summary>The sample hotkeys in <c>DefaultHotkeyCatalog.All</c>.</summary>
    public static int Hotkeys => DefaultHotkeyCatalog.All.Count;
}
