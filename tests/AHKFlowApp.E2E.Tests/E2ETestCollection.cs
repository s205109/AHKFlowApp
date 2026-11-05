using AHKFlowApp.E2E.Tests.Fixtures;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

// The four groups are balance buckets. They carry no meaning beyond keeping the four roughly
// equal, which is why they are lettered and not named after a feature. The whole run takes as
// long as the slowest group, so put a new test class in the smallest group. The rule is in
// docs/development/testing-workflow.md, and nothing enforces it.
//
// Seconds measured on 2026-11-05: each class's median over five warm runs (backlog 194).

/// <summary>Group A — 58.54 s. ShortcutWarningFlowTests 38.44, ProfileScriptDownloadFlowTests 9.22, ProductAndPageNamesFlowTests 4.74, HotstringImportPasteFlowTests 4.44, DashboardFirstViewFlowTests 1.69.</summary>
public sealed class StackFixtureA() : StackFixture("AHKFlowApp.E2E.Tests.A") { }

/// <summary>Group B — 56.99 s. HotkeysCrudFlowTests 23.90, HotstringsMobileFlowTests 11.08, KnownShortcutsMobileFlowTests 10.19, BootFailureFlowTests 7.96, MacroHotstringFlowTests 3.85, PublishFreshnessTests 0.01.</summary>
public sealed class StackFixtureB() : StackFixture("AHKFlowApp.E2E.Tests.B") { }

/// <summary>Group C — 57.47 s. RawHotstringFlowTests 21.80, KeyboardAccessFlowTests 12.44, WindowSnapFlowTests 10.35, FirstPageLoadDiagnosticsTests 9.08, ProfileHeaderPresetFlowTests 3.81.</summary>
public sealed class StackFixtureC() : StackFixture("AHKFlowApp.E2E.Tests.C") { }

/// <summary>Group D — 57.70 s. VersionHistoryFlowTests 18.98, HotkeysMobileFlowTests 17.18, HotstringsCrudFlowTests 9.31, ProfileCreateDefaultHeaderFlowTests 6.03, DownloadsSaveFailureFlowTests 4.45, ChangelogFlowTests 1.75.</summary>
public sealed class StackFixtureD() : StackFixture("AHKFlowApp.E2E.Tests.D") { }

[CollectionDefinition(Name)]
public sealed class E2ECollectionA : ICollectionFixture<StackFixtureA>
{
    public const string Name = "E2E-A";
}

[CollectionDefinition(Name)]
public sealed class E2ECollectionB : ICollectionFixture<StackFixtureB>
{
    public const string Name = "E2E-B";
}

[CollectionDefinition(Name)]
public sealed class E2ECollectionC : ICollectionFixture<StackFixtureC>
{
    public const string Name = "E2E-C";
}

[CollectionDefinition(Name)]
public sealed class E2ECollectionD : ICollectionFixture<StackFixtureD>
{
    public const string Name = "E2E-D";
}
