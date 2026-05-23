using AHKFlowApp.TestUtilities.Fixtures;
using Xunit;

namespace AHKFlowApp.Application.Tests.Categories;

public sealed class CategoryDbFixture : MigratedDbFixture;

[CollectionDefinition("CategoryDb")]
public sealed class CategoryDbCollection : ICollectionFixture<CategoryDbFixture>;
