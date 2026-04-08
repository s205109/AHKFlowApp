using System.ComponentModel.DataAnnotations;
using System.Net;
using System.Net.Http;
using System.Net.Http.Json;
using System.Text;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.ApplicationParts;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace AHKFlowApp.API.Tests.Middleware;

[Collection("WebApi")]
public sealed class ValidationProblemDetailsTests(SqlContainerFixture sqlFixture) : IDisposable
{
    private readonly WebApplicationFactory<global::Program> _factory = new TestControllerFactory(sqlFixture);

    [Fact]
    public async Task Post_WhenRequiredFieldMissing_Returns422WithValidationProblemDetails()
    {
        // Arrange
        using HttpClient client = _factory.CreateClient();
        using var content = new StringContent("{}", Encoding.UTF8, "application/json");

        // Act
        HttpResponseMessage response = await client.PostAsync("/test", content);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.UnprocessableEntity);
        response.Content.Headers.ContentType!.MediaType.Should().Be("application/problem+json");

        ValidationProblemDetails? body = await response.Content.ReadFromJsonAsync<ValidationProblemDetails>();
        body!.Title.Should().Be("One or more validation errors occurred.");
        body.Errors.Should().ContainKey("Name");
        body.Extensions.Should().ContainKey("traceId");
        body.Extensions["traceId"].Should().NotBeNull();
    }

    public void Dispose() => _factory.Dispose();
}

internal sealed class TestControllerFactory(SqlContainerFixture sqlFixture) : WebApplicationFactory<global::Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            var descriptors = services
                .Where(d => d.ServiceType == typeof(DbContextOptions<AppDbContext>)
                         || d.ServiceType == typeof(AppDbContext))
                .ToList();

            foreach (ServiceDescriptor d in descriptors)
                services.Remove(d);

            services.AddDbContext<AppDbContext>(options =>
                options.UseSqlServer(sqlFixture.ConnectionString,
                    sql => sql.EnableRetryOnFailure()));

            ApplicationPartManager? partManager = services
                .Where(d => d.ServiceType == typeof(ApplicationPartManager))
                .Select(d => d.ImplementationInstance as ApplicationPartManager)
                .FirstOrDefault();

            partManager?.ApplicationParts.Add(new AssemblyPart(typeof(TestModelController).Assembly));
        });
    }
}

[ApiController]
[Route("test")]
[AllowAnonymous]
public sealed class TestModelController : ControllerBase
{
    [HttpPost]
    public IActionResult Post([FromBody] RequiredModel model) => Ok(model);

    public sealed record RequiredModel([Required] string Name);
}
