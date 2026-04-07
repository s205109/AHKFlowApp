using System.Net;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Serilog.Core;
using Serilog.Events;
using Xunit;

namespace AHKFlowApp.API.Tests.Logging;

/// <summary>
/// Verifies Serilog request logging by registering a test ILogEventSink in DI.
/// ReadFrom.Services(services) in Program.cs picks up any registered ILogEventSink,
/// so the capture sink receives all Serilog events including UseSerilogRequestLogging output.
/// </summary>
[Collection("WebApi")]
public sealed class SerilogRequestLoggingTests(SqlContainerFixture sqlFixture) : IDisposable
{
    private readonly CustomWebApplicationFactory _factory = new(sqlFixture);

    [Fact]
    public async Task RequestLogging_WhenRequestReceived_LogsStructuredRequestProperties()
    {
        // Arrange
        var sink = new LogCaptureSink();
        using WebApplicationFactory<global::Program> testFactory = _factory.WithWebHostBuilder(builder =>
            builder.ConfigureServices(services =>
                services.AddSingleton<ILogEventSink>(sink)));
        using HttpClient client = testFactory.CreateClient();

        // Act
        HttpResponseMessage response = await client.GetAsync("/api/v1/health");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);

        // The Serilog request logging event has StatusCode + Elapsed.
        // ASP.NET Core's own Hosting.Diagnostics events also have RequestPath but not StatusCode/Elapsed.
        LogEvent? requestLog = sink.Events.FirstOrDefault(e =>
            e.Properties.ContainsKey("StatusCode") && e.Properties.ContainsKey("Elapsed"));

        requestLog.Should().NotBeNull("UseSerilogRequestLogging must emit a structured log event with StatusCode and Elapsed per HTTP request");
        requestLog!.Properties.Should().ContainKey("RequestPath");
        requestLog.Properties["StatusCode"].ToString().Should().Be("200");
    }

    [Fact]
    public async Task RequestLogging_WhenRequestReceived_DoesNotLogSensitivePropertyNames()
    {
        // Arrange
        var sink = new LogCaptureSink();
        using WebApplicationFactory<global::Program> testFactory = _factory.WithWebHostBuilder(builder =>
            builder.ConfigureServices(services =>
                services.AddSingleton<ILogEventSink>(sink)));
        using HttpClient client = testFactory.CreateClient();

        // Act
        await client.GetAsync("/api/v1/health");

        // Assert
        IEnumerable<string> allPropertyNames = sink.Events.SelectMany(e => e.Properties.Keys);
        allPropertyNames.Should().NotContain(
            p => p.Equals("Password", StringComparison.OrdinalIgnoreCase)
                 || p.Equals("Token", StringComparison.OrdinalIgnoreCase)
                 || p.Equals("Secret", StringComparison.OrdinalIgnoreCase),
            "sensitive property names must not appear in any log event");
    }

    public void Dispose() => _factory.Dispose();

    private sealed class LogCaptureSink : ILogEventSink
    {
        private readonly List<LogEvent> _events = [];

        public IReadOnlyList<LogEvent> Events => _events;

        public void Emit(LogEvent logEvent) => _events.Add(logEvent);
    }
}
