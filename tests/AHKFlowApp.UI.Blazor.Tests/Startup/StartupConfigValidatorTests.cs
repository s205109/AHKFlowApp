using AHKFlowApp.UI.Blazor.Startup;
using FluentAssertions;
using Microsoft.Extensions.Configuration;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Startup;

public sealed class StartupConfigValidatorTests
{
    private static IConfiguration Config(Dictionary<string, string?> values) =>
        new ConfigurationBuilder().AddInMemoryCollection(values).Build();

    private static Dictionary<string, string?> Valid() => new()
    {
        ["ApiHttpClient:BaseAddress"] = "http://localhost:5600",
        ["AzureAd:Instance"] = "https://login.microsoftonline.com/",
        ["AzureAd:TenantId"] = "11111111-1111-1111-1111-111111111111",
        ["AzureAd:ClientId"] = "22222222-2222-2222-2222-222222222222"
    };

    [Fact]
    public void Check_WhenAllPresent_ReturnsNull()
    {
        StartupConfigValidator.Check(Config(Valid())).Should().BeNull();
    }

    [Theory]
    [InlineData("AzureAd:TenantId")]
    [InlineData("AzureAd:ClientId")]
    [InlineData("AzureAd:Instance")]
    [InlineData("ApiHttpClient:BaseAddress")]
    public void Check_WhenRequiredValueEmpty_ReturnsMissingFrontendConfig(string key)
    {
        Dictionary<string, string?> values = Valid();
        values[key] = "";

        StartupConfigValidator.Check(Config(values))
            .Should().Be(StartupErrorReason.MissingFrontendConfig);
    }

    [Fact]
    public void Check_WhenPlaceholderRemains_ReturnsPlaceholderConfig()
    {
        Dictionary<string, string?> values = Valid();
        values["AzureAd:ClientId"] = "<your-client-id>";

        StartupConfigValidator.Check(Config(values))
            .Should().Be(StartupErrorReason.PlaceholderConfig);
    }
}
