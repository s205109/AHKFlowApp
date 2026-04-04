using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.API.Middleware;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using FluentValidation;
using FluentValidation.Results;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace AHKFlowApp.API.Tests.Middleware;

[Collection("WebApi")]
public sealed class GlobalExceptionMiddlewareTests(SqlContainerFixture sqlFixture) : IDisposable
{
    private readonly CustomWebApplicationFactory _factory = new(sqlFixture);

    [Fact]
    public async Task Middleware_WhenValidationExceptionThrown_Returns400ProblemDetails()
    {
        // Arrange
        using HttpClient client = _factory.WithWebHostBuilder(builder =>
        {
            builder.ConfigureServices(services =>
            {
                services.AddRouting();
                services.AddLogging();
            });
            builder.Configure(app =>
            {
                app.UseMiddleware<GlobalExceptionMiddleware>();
                app.UseRouting();
                app.UseEndpoints(endpoints =>
                {
                    endpoints.MapGet("/test/validation-error", _ =>
                    {
                        var failures = new List<ValidationFailure>
                        {
                            new("Name", "Name is required"),
                            new("Name", "Name must be at least 3 characters"),
                            new("Email", "Email is invalid")
                        };
                        throw new ValidationException(failures);
                    });
                });
            });
        }).CreateClient();

        // Act
        HttpResponseMessage response = await client.GetAsync("/test/validation-error");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        response.Content.Headers.ContentType!.MediaType.Should().Be("application/problem+json");

        ProblemDetails? problem = await response.Content.ReadFromJsonAsync<ProblemDetails>();
        problem.Should().NotBeNull();
        problem!.Status.Should().Be(400);
        problem.Title.Should().Be("Validation failed");
    }

    [Fact]
    public async Task Middleware_WhenUnhandledExceptionThrown_Returns500ProblemDetails()
    {
        // Arrange
        using HttpClient client = _factory.WithWebHostBuilder(builder =>
        {
            builder.ConfigureServices(services =>
            {
                services.AddRouting();
                services.AddLogging();
            });
            builder.Configure(app =>
            {
                app.UseMiddleware<GlobalExceptionMiddleware>();
                app.UseRouting();
                app.UseEndpoints(endpoints =>
                {
                    endpoints.MapGet("/test/unhandled-error", _ =>
                        throw new InvalidOperationException("Something broke"));
                });
            });
        }).CreateClient();

        // Act
        HttpResponseMessage response = await client.GetAsync("/test/unhandled-error");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.InternalServerError);
        response.Content.Headers.ContentType!.MediaType.Should().Be("application/problem+json");

        ProblemDetails? problem = await response.Content.ReadFromJsonAsync<ProblemDetails>();
        problem.Should().NotBeNull();
        problem!.Status.Should().Be(500);
        problem.Title.Should().Be("An unexpected error occurred");
    }

    public void Dispose() => _factory.Dispose();
}
