using AHKFlowApp.TestUtilities.Fixtures;
using Xunit;

namespace AHKFlowApp.Application.Tests.Profiles;

public sealed class ProfileDbFixture : MigratedDbFixture;

[CollectionDefinition("ProfileDb")]
public sealed class ProfileDbCollection : ICollectionFixture<ProfileDbFixture>;
