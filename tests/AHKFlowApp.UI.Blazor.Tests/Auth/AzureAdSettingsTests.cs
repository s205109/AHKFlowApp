using AHKFlowApp.UI.Blazor.Auth;
using FluentAssertions;
using Microsoft.Extensions.Configuration;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Auth;

public sealed class AzureAdSettingsTests
{
    private static IConfiguration Config(Dictionary<string, string?> values) =>
        new ConfigurationBuilder().AddInMemoryCollection(values).Build();

    [Fact]
    public void Resolve_WhenInstanceTenantClientSet_DerivesAuthorityAndScope()
    {
        IConfiguration config = Config(new()
        {
            ["AzureAd:Instance"] = "https://login.microsoftonline.com/",
            ["AzureAd:TenantId"] = "tenant-123",
            ["AzureAd:ClientId"] = "client-abc"
        });

        var settings = AzureAdSettings.Resolve(config);

        settings.Authority.Should().Be("https://login.microsoftonline.com/tenant-123");
        settings.ClientId.Should().Be("client-abc");
        settings.Scope.Should().Be("api://client-abc/access_as_user");
        settings.ValidateAuthority.Should().BeTrue();
    }

    [Fact]
    public void Resolve_WhenInstanceHasNoTrailingSlash_DoesNotDoubleSlashAuthority()
    {
        IConfiguration config = Config(new()
        {
            ["AzureAd:Instance"] = "https://login.microsoftonline.com",
            ["AzureAd:TenantId"] = "t",
            ["AzureAd:ClientId"] = "c"
        });

        var settings = AzureAdSettings.Resolve(config);

        settings.Authority.Should().Be("https://login.microsoftonline.com/t");
    }

    [Fact]
    public void Resolve_WhenScopesOverrideSet_UsesOverride()
    {
        IConfiguration config = Config(new()
        {
            ["AzureAd:Instance"] = "https://login.microsoftonline.com/",
            ["AzureAd:TenantId"] = "t",
            ["AzureAd:ClientId"] = "c",
            ["AzureAd:Scopes"] = "api://other/custom.scope"
        });

        var settings = AzureAdSettings.Resolve(config);

        settings.Scope.Should().Be("api://other/custom.scope");
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void Resolve_WhenScopesBlank_FallsBackToDerivedScope(string blankScope)
    {
        IConfiguration config = Config(new()
        {
            ["AzureAd:Instance"] = "https://login.microsoftonline.com/",
            ["AzureAd:TenantId"] = "t",
            ["AzureAd:ClientId"] = "c",
            ["AzureAd:Scopes"] = blankScope
        });

        var settings = AzureAdSettings.Resolve(config);

        settings.Scope.Should().Be("api://c/access_as_user");
    }

    [Fact]
    public void Resolve_WhenValidateAuthorityFalse_RespectsConfig()
    {
        IConfiguration config = Config(new()
        {
            ["AzureAd:Instance"] = "https://login.microsoftonline.com/",
            ["AzureAd:TenantId"] = "t",
            ["AzureAd:ClientId"] = "c",
            ["AzureAd:ValidateAuthority"] = "false"
        });

        var settings = AzureAdSettings.Resolve(config);

        settings.ValidateAuthority.Should().BeFalse();
    }
}
