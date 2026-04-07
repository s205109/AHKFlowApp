using System.Net;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Serilog.Core;
using Serilog.Events;
using Xunit;
using Xunit.Sdk;

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

    [Fact]
    public async Task FileLogging_WhenRequestReceived_WritesRequestEntryToConfiguredLogFile()
    {
        // Arrange
        string logDirectory = Path.Combine(Path.GetTempPath(), $"ahkflowapp-api-tests-{Guid.NewGuid():N}");
        Directory.CreateDirectory(logDirectory);

        try
        {
            string logFilePath = Path.Combine(logDirectory, "AHKFlowApp.API-.log");

            using (WebApplicationFactory<global::Program> testFactory = _factory.WithWebHostBuilder(builder =>
                   builder.ConfigureAppConfiguration((_, configBuilder) =>
                       configBuilder.AddInMemoryCollection(new Dictionary<string, string?>
                       {
                           ["Serilog:WriteTo:1:Args:path"] = logFilePath
                       }))))
            using (HttpClient client = testFactory.CreateClient())
            {
                // Act
                HttpResponseMessage response = await client.GetAsync("/health");

                // Assert
                response.StatusCode.Should().Be(HttpStatusCode.OK);
            }

            string writtenLogFile = await WaitForLogFileAsync(logDirectory);
            string logContent = await WaitForLogContentAsync(writtenLogFile, "/health");

            logContent.Should().Contain("/health");
            logContent.Should().Contain("200");
        }
        finally
        {
            if (Directory.Exists(logDirectory))
            {
                Directory.Delete(logDirectory, recursive: true);
            }
        }
    }

    public void Dispose() => _factory.Dispose();

    private static async Task<string> WaitForLogFileAsync(string logDirectory)
    {
        const int maxAttempts = 20;

        for (int attempt = 0; attempt < maxAttempts; attempt++)
        {
            string? logFile = Directory
                .EnumerateFiles(logDirectory, "AHKFlowApp.API-*.log")
                .OrderByDescending(File.GetLastWriteTimeUtc)
                .FirstOrDefault();

            if (logFile is not null)
            {
                return logFile;
            }

            await Task.Delay(250);
        }

        throw new XunitException($"Expected Serilog file sink to create a log file in '{logDirectory}'.");
    }

    private static async Task<string> WaitForLogContentAsync(string logFilePath, string expectedContent)
    {
        const int maxAttempts = 20;

        for (int attempt = 0; attempt < maxAttempts; attempt++)
        {
            string content = await File.ReadAllTextAsync(logFilePath);

            if (content.Contains(expectedContent, StringComparison.Ordinal))
            {
                return content;
            }

            await Task.Delay(250);
        }

        throw new XunitException($"Expected log file '{logFilePath}' to contain '{expectedContent}'.");
    }

    private sealed class LogCaptureSink : ILogEventSink
    {
        private readonly object _syncRoot = new();
        private readonly List<LogEvent> _events = [];

        public IReadOnlyList<LogEvent> Events
        {
            get
            {
                lock (_syncRoot)
                {
                    return _events.ToArray();
                }
            }
        }

        public void Emit(LogEvent logEvent)
        {
            lock (_syncRoot)
            {
                _events.Add(logEvent);
            }
        }
    }
}
