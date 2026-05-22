using AHKFlowApp.TestUtilities.Fixtures;
using Xunit;

namespace AHKFlowApp.Application.Tests.Services;

public sealed class ScriptGeneratorDbFixture : MigratedDbFixture;

[CollectionDefinition("ScriptGeneratorDb")]
public sealed class ScriptGeneratorDbCollection : ICollectionFixture<ScriptGeneratorDbFixture>;
