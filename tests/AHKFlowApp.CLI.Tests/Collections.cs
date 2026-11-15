using AHKFlowApp.TestUtilities.Fixtures;
using Xunit;

namespace AHKFlowApp.CLI.Tests;

// One API host for every CLI integration test. Each test sends its own identity per request,
// through TestIdentityHandler, so the tests share the host but never a user.
[CollectionDefinition("CliWebApi")]
public sealed class CliWebApiCollection : ICollectionFixture<ApiTestFixture>;
