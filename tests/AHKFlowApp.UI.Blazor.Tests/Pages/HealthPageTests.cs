using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Pages;
using AHKFlowApp.UI.Blazor.Services;
using Bunit;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor;
using MudBlazor.Services;
using NSubstitute;
using NSubstitute.ExceptionExtensions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Pages;

public sealed class HealthPageTests : BunitContext
{
    private readonly IAhkFlowAppApiHttpClient _apiClient = Substitute.For<IAhkFlowAppApiHttpClient>();

    public HealthPageTests()
    {
        Services.AddSingleton(_apiClient);
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    [Fact]
    public void Health_WhenApiReturnsData_DisplaysVersion()
    {
        // Arrange
        var response = new HealthResponse("Healthy", "1.2.3", "Test", DateTimeOffset.UtcNow, []);
        _apiClient.GetHealthAsync(Arg.Any<CancellationToken>())
            .Returns(Task.FromResult<HealthResponse?>(response));

        // Act
        IRenderedComponent<Health> cut = Render<Health>();
        cut.WaitForState(() => !cut.Find(".mud-paper").TextContent.Contains("Checking"));

        // Assert
        cut.Markup.Should().Contain("1.2.3");
    }

    [Fact]
    public void Health_WhenApiReturnsData_DisplaysStatus()
    {
        // Arrange
        var response = new HealthResponse("Healthy", string.Empty, "Test", DateTimeOffset.UtcNow, new Dictionary<string, string> { ["database"] = "Healthy" });
        _apiClient.GetHealthAsync(Arg.Any<CancellationToken>())
            .Returns(Task.FromResult<HealthResponse?>(response));

        // Act
        IRenderedComponent<Health> cut = Render<Health>();
        cut.WaitForState(() => !cut.Find(".mud-paper").TextContent.Contains("Checking"));

        // Assert
        cut.Markup.Should().Contain("Healthy");
        cut.Markup.Should().Contain("Test");
        cut.Markup.Should().Contain("database");
    }

    [Fact]
    public void Health_WhenApiThrows_DisplaysErrorAlert()
    {
        // Arrange
        _apiClient.GetHealthAsync(Arg.Any<CancellationToken>())
            .ThrowsAsync(new HttpRequestException("Connection refused"));

        // Act
        IRenderedComponent<Health> cut = Render<Health>();
        cut.WaitForState(() => !cut.Find(".mud-paper").TextContent.Contains("Checking"));

        // Assert
        cut.Markup.Should().Contain("Unable to retrieve health status");
    }

    [Fact]
    public void Health_WhenApiReturnsNull_DisplaysErrorAlert()
    {
        // Arrange
        _apiClient.GetHealthAsync(Arg.Any<CancellationToken>())
            .Returns(Task.FromResult<HealthResponse?>(null));

        // Act
        IRenderedComponent<Health> cut = Render<Health>();
        cut.WaitForState(() => !cut.Find(".mud-paper").TextContent.Contains("Checking"));

        // Assert
        cut.Markup.Should().Contain("Unable to retrieve health status");
    }

    [Fact]
    public Task Health_WhenRefreshClicked_RefetchesData()
    {
        // Arrange
        _apiClient.GetHealthAsync(Arg.Any<CancellationToken>())
            .Returns(Task.FromResult<HealthResponse?>(new HealthResponse("Healthy", string.Empty, "Test", DateTimeOffset.UtcNow, [])));

        IRenderedComponent<Health> cut = Render<Health>();
        cut.WaitForState(() => !cut.Find(".mud-paper").TextContent.Contains("Checking"));

        // Act
        cut.Find("button").Click();
        cut.WaitForState(() => !cut.Find(".mud-paper").TextContent.Contains("Checking"));

        // Assert
        return _apiClient.Received(2).GetHealthAsync(Arg.Any<CancellationToken>());
    }

    [Fact]
    public void Health_WhenApiReturnsUnhealthy_DisplaysUnhealthyStatusAndCheckDetails()
    {
        // Arrange
        var checks = new Dictionary<string, string>
        {
            ["database"] = "Unhealthy: Login failed for user 'ahkflow'."
        };
        var response = new HealthResponse("Unhealthy", "1.0.0", "Production", DateTimeOffset.UtcNow, checks);
        _apiClient.GetHealthAsync(Arg.Any<CancellationToken>())
            .Returns(Task.FromResult<HealthResponse?>(response));

        // Act
        IRenderedComponent<Health> cut = Render<Health>();
        cut.WaitForState(() => !cut.Find(".mud-paper").TextContent.Contains("Checking"));

        // Assert
        cut.Markup.Should().Contain("Unhealthy");
        cut.Markup.Should().Contain("database");
        cut.Markup.Should().Contain("Login failed for user");
    }
}
