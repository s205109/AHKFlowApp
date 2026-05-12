using System.Net;
using System.Net.Http.Json;
using System.Text;
using AHKFlowApp.CLI.Services;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Services;

public sealed class CliHttpClientBuilderExtensionsTests
{
    [Fact]
    public async Task ListAsync_StoppedWebAppHtml_RetriesUntilSuccess()
    {
        SequenceHandler handler = new(
            CreateStoppedWebAppResponse(),
            CreateStoppedWebAppResponse(),
            CreateSuccessfulListResponse());
        RecordingRetryStatusWriter retryStatusWriter = new();

        using ServiceProvider provider = CreateServices(handler, retryStatusWriter);
        IHotstringsApiClient sut = provider.GetRequiredService<IHotstringsApiClient>();

        PagedList<HotstringDto> result = await sut.ListAsync(null, null, 1, 50, CancellationToken.None);

        result.Items.Should().BeEmpty();
        handler.RequestCount.Should().Be(3);
        retryStatusWriter.Messages.Should().HaveCount(2);
        retryStatusWriter.Messages.Should().OnlyContain(message => message.Contains("/10)"));
    }

    [Fact]
    public async Task ListAsync_ProblemJson403_DoesNotRetry()
    {
        SequenceHandler handler = new(
            new HttpResponseMessage(HttpStatusCode.Forbidden)
            {
                Content = JsonContent.Create(new { title = "Forbidden", detail = "missing scope" }),
            });
        RecordingRetryStatusWriter retryStatusWriter = new();

        using ServiceProvider provider = CreateServices(handler, retryStatusWriter);
        IHotstringsApiClient sut = provider.GetRequiredService<IHotstringsApiClient>();

        Func<Task> act = () => sut.ListAsync(null, null, 1, 50, CancellationToken.None);

        ApiException ex = (await act.Should().ThrowAsync<ApiException>()).Which;
        ex.StatusCode.Should().Be(403);
        handler.RequestCount.Should().Be(1);
        retryStatusWriter.Messages.Should().BeEmpty();
    }

    private static ServiceProvider CreateServices(
        HttpMessageHandler handler,
        IHttpRetryStatusWriter retryStatusWriter)
    {
        ServiceCollection services = new();
        services.AddSingleton(retryStatusWriter);
        services.AddHttpClient<IHotstringsApiClient, HotstringsApiClient>(client =>
            client.BaseAddress = new Uri("http://localhost/"))
            .ConfigurePrimaryHttpMessageHandler(() => handler)
            .AddCliApiResilience("hotstrings");

        return services.BuildServiceProvider();
    }

    private static HttpResponseMessage CreateStoppedWebAppResponse() =>
        new(HttpStatusCode.Forbidden)
        {
            Content = new StringContent(
                """
                <!DOCTYPE html>
                <html>
                <head><title>Web App - Unavailable</title></head>
                <body><h1>Error 403 - This web app is stopped.</h1></body>
                </html>
                """,
                Encoding.UTF8,
                "text/html"),
        };

    private static HttpResponseMessage CreateSuccessfulListResponse() =>
        new(HttpStatusCode.OK)
        {
            Content = JsonContent.Create(new PagedList<HotstringDto>([], 1, 50, 0)),
        };

    private sealed class RecordingRetryStatusWriter : IHttpRetryStatusWriter
    {
        public List<string> Messages { get; } = [];

        public void WriteRetrying(
            string operationName,
            int retryAttempt,
            int maxRetryAttempts,
            TimeSpan delay)
        {
            Messages.Add(HttpRetryStatusMessages.FormatRetrying(
                operationName,
                retryAttempt,
                maxRetryAttempts,
                delay));
        }
    }

    private sealed class SequenceHandler(params HttpResponseMessage[] responses) : HttpMessageHandler
    {
        private readonly Queue<HttpResponseMessage> _responses = new(responses);

        public int RequestCount { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            RequestCount++;
            return Task.FromResult(_responses.Dequeue());
        }
    }
}
