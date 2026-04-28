using AHKFlowApp.UI.Blazor.Auth;
using FluentAssertions;
using Microsoft.Extensions.Configuration;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Auth;

public sealed class AuthConfigurationValidatorTests
{
    [Fact]
    public void ValidateForMsal_WhenRequiredValueMissing_ThrowsHelpfulError()
    {
        // Arrange
        IConfiguration configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["AzureAd:Authority"] = "https://login.microsoftonline.com/tenant-id",
                ["AzureAd:ClientId"] = "11111111-1111-1111-1111-111111111111",
                ["AzureAd:DefaultScope"] = "api://11111111-1111-1111-1111-111111111111/access_as_user"
            })
            .Build();

        // Act
        Action act = () => AuthConfigurationValidator.ValidateForMsal(configuration);

        // Assert
        act.Should()
            .Throw<InvalidOperationException>()
            .WithMessage("Configuration value 'ApiHttpClient:BaseAddress' is missing or empty.");
    }

    [Fact]
    public void ValidateForMsal_WhenPlaceholderValuesRemain_ThrowsSetupGuidance()
    {
        // Arrange
        IConfiguration configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ApiHttpClient:BaseAddress"] = "http://localhost:5600",
                ["AzureAd:Authority"] = "https://login.microsoftonline.com/<your-tenant-id>",
                ["AzureAd:ClientId"] = "<your-client-id>",
                ["AzureAd:DefaultScope"] = "api://<your-client-id>/access_as_user"
            })
            .Build();

        // Act
        Action act = () => AuthConfigurationValidator.ValidateForMsal(configuration);

        // Assert
        act.Should()
            .Throw<InvalidOperationException>()
            .WithMessage("*setup-dev-entra.ps1*");
    }

    [Fact]
    public void ValidateForMsal_WhenValuesArePresent_DoesNotThrow()
    {
        // Arrange
        IConfiguration configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ApiHttpClient:BaseAddress"] = "http://localhost:5600",
                ["AzureAd:Authority"] = "https://login.microsoftonline.com/tenant-id",
                ["AzureAd:ClientId"] = "11111111-1111-1111-1111-111111111111",
                ["AzureAd:DefaultScope"] = "api://11111111-1111-1111-1111-111111111111/access_as_user"
            })
            .Build();

        // Act
        Action act = () => AuthConfigurationValidator.ValidateForMsal(configuration);

        // Assert
        act.Should().NotThrow();
    }
}
