using AHKFlowApp.E2E.Tests.Fixtures;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

// The four groups are balance buckets. They carry no meaning beyond keeping the four roughly
// equal, which is why they are lettered and not named after a feature. The whole run takes as
// long as the slowest group, so put a new test class in the smallest group. The rule is in
// docs/development/testing-workflow.md, and nothing enforces it.
//
// Seconds measured on 2026-09-09, one warm run, before the split.

/// <summary>Group A — 64.03 s. ShortcutWarningFlowTests 60.07, ProfileHeaderPresetFlowTests 3.96.</summary>
public sealed class StackFixtureA() : StackFixture("AHKFlowApp.E2E.Tests.A") { }

/// <summary>Group B — 61.36 s. HotkeysCrudFlowTests 31.39, HotkeysMobileFlowTests 18.90, ClipboardDeliveryFlowTests 11.06, PublishFreshnessTests 0.01.</summary>
public sealed class StackFixtureB() : StackFixture("AHKFlowApp.E2E.Tests.B") { }

/// <summary>Group C — 64.28 s. RawHotstringFlowTests 21.67, VersionHistoryFlowTests 20.14, HotstringsMobileFlowTests 17.04, HotstringsCrudFlowTests 5.43.</summary>
public sealed class StackFixtureC() : StackFixture("AHKFlowApp.E2E.Tests.C") { }

/// <summary>Group D — 70.51 s. WindowSnapFlowTests 16.16, BootFailureFlowTests 15.29, KnownShortcutsMobileFlowTests 12.91, ProfileScriptDownloadFlowTests 6.55, DownloadsSaveFailureFlowTests 6.18, MacroHotstringFlowTests 5.40, FirstPageLoadDiagnosticsTests 5.06, LocalAuthModeFlowTests 2.96.</summary>
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
