using AHKFlowApp.TestUtilities.Fixtures;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotkeys;

public sealed class HotkeyDbFixture : MigratedDbFixture;

[CollectionDefinition("HotkeyDb")]
public sealed class HotkeyDbCollection : ICollectionFixture<HotkeyDbFixture>;
