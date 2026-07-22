using System.Net;
using System.Net.Http.Json;
using System.Net.Sockets;
using System.Text;
using AHKFlowApp.CLI.Services;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using Polly.Timeout;
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

        Func<Task> act = async () => await sut.ListAsync(null, null, 1, 50, CancellationToken.None);

        ApiException ex = (await act.Should().ThrowAsync<ApiException>()).Which;
        ex.StatusCode.Should().Be(403);
        handler.RequestCount.Should().Be(1);
        retryStatusWriter.Messages.Should().BeEmpty();
    }

    [Fact]
    public async Task ListAsync_UnrelatedHtml403_DoesNotRetry()
    {
        SequenceHandler handler = new(CreateUnrelatedHtml403Response());
        RecordingRetryStatusWriter retryStatusWriter = new();

        using ServiceProvider provider = CreateServices(handler, retryStatusWriter);
        IHotstringsApiClient sut = provider.GetRequiredService<IHotstringsApiClient>();

        Func<Task> act = async () => await sut.ListAsync(null, null, 1, 50, CancellationToken.None);

        ApiException ex = (await act.Should().ThrowAsync<ApiException>()).Which;
        ex.StatusCode.Should().Be(403);
        handler.RequestCount.Should().Be(1);
        retryStatusWriter.Messages.Should().BeEmpty();
    }

    [Fact]
    public async Task CreateAsync_UnrelatedHtml403_DoesNotRetry()
    {
        SequenceHandler handler = new(CreateUnrelatedHtml403Response());
        RecordingRetryStatusWriter retryStatusWriter = new();

        using ServiceProvider provider = CreateServices(handler, retryStatusWriter);
        IHotstringsApiClient sut = provider.GetRequiredService<IHotstringsApiClient>();

        Func<Task> act = async () => await sut.CreateAsync(CreateInput(), CancellationToken.None);

        ApiException ex = (await act.Should().ThrowAsync<ApiException>()).Which;
        ex.StatusCode.Should().Be(403);
        handler.RequestCount.Should().Be(1);
        retryStatusWriter.Messages.Should().BeEmpty();
    }

    [Fact]
    public async Task ListAsync_Timeout_RetriesUntilSuccess()
    {
        SequenceHandler handler = new(
            new TimeoutRejectedException(),
            CreateSuccessfulListResponse());
        RecordingRetryStatusWriter retryStatusWriter = new();

        using ServiceProvider provider = CreateServices(handler, retryStatusWriter);
        IHotstringsApiClient sut = provider.GetRequiredService<IHotstringsApiClient>();

        PagedList<HotstringDto> result = await sut.ListAsync(null, null, 1, 50, CancellationToken.None);

        result.Items.Should().BeEmpty();
        handler.RequestCount.Should().Be(2);
    }

    [Fact]
    public async Task CreateAsync_Timeout_DoesNotRetry()
    {
        SequenceHandler handler = new(
            new TimeoutRejectedException(),
            CreateSuccessfulCreateResponse());
        RecordingRetryStatusWriter retryStatusWriter = new();

        using ServiceProvider provider = CreateServices(handler, retryStatusWriter);
        IHotstringsApiClient sut = provider.GetRequiredService<IHotstringsApiClient>();

        Func<Task> act = async () => await sut.CreateAsync(CreateInput(), CancellationToken.None);

        await act.Should().ThrowAsync<TimeoutRejectedException>();
        handler.RequestCount.Should().Be(1);
        retryStatusWriter.Messages.Should().BeEmpty();
    }

    [Fact]
    public async Task ListAsync_GatewayTimeout_RetriesUntilSuccess()
    {
        SequenceHandler handler = new(
            new HttpResponseMessage(HttpStatusCode.GatewayTimeout),
            CreateSuccessfulListResponse());
        RecordingRetryStatusWriter retryStatusWriter = new();

        using ServiceProvider provider = CreateServices(handler, retryStatusWriter);
        IHotstringsApiClient sut = provider.GetRequiredService<IHotstringsApiClient>();

        PagedList<HotstringDto> result = await sut.ListAsync(null, null, 1, 50, CancellationToken.None);

        result.Items.Should().BeEmpty();
        handler.RequestCount.Should().Be(2);
    }

    // No response means the method can only come from the resilience context; if that lookup broke,
    // the request would be treated as unsafe and this read would stop retrying.
    [Fact]
    public async Task ListAsync_ConnectionDroppedAfterSend_RetriesUntilSuccess()
    {
        SequenceHandler handler = new(
            new HttpRequestException(
                HttpRequestError.ConnectionError,
                "connection reset",
                new SocketException((int)SocketError.ConnectionReset)),
            CreateSuccessfulListResponse());
        RecordingRetryStatusWriter retryStatusWriter = new();

        using ServiceProvider provider = CreateServices(handler, retryStatusWriter);
        IHotstringsApiClient sut = provider.GetRequiredService<IHotstringsApiClient>();

        PagedList<HotstringDto> result = await sut.ListAsync(null, null, 1, 50, CancellationToken.None);

        result.Items.Should().BeEmpty();
        handler.RequestCount.Should().Be(2);
    }

    [Fact]
    public async Task CreateAsync_GatewayTimeout_DoesNotRetry()
    {
        SequenceHandler handler = new(
            new HttpResponseMessage(HttpStatusCode.GatewayTimeout),
            CreateSuccessfulCreateResponse());
        RecordingRetryStatusWriter retryStatusWriter = new();

        using ServiceProvider provider = CreateServices(handler, retryStatusWriter);
        IHotstringsApiClient sut = provider.GetRequiredService<IHotstringsApiClient>();

        Func<Task> act = async () => await sut.CreateAsync(CreateInput(), CancellationToken.None);

        ApiException ex = (await act.Should().ThrowAsync<ApiException>()).Which;
        ex.StatusCode.Should().Be(504);
        handler.RequestCount.Should().Be(1);
        retryStatusWriter.Messages.Should().BeEmpty();
    }

    [Fact]
    public async Task CreateAsync_ConnectionDroppedAfterSend_DoesNotRetry()
    {
        SequenceHandler handler = new(
            new HttpRequestException(
                HttpRequestError.ConnectionError,
                "connection reset",
                new SocketException((int)SocketError.ConnectionReset)),
            CreateSuccessfulCreateResponse());
        RecordingRetryStatusWriter retryStatusWriter = new();

        using ServiceProvider provider = CreateServices(handler, retryStatusWriter);
        IHotstringsApiClient sut = provider.GetRequiredService<IHotstringsApiClient>();

        Func<Task> act = async () => await sut.CreateAsync(CreateInput(), CancellationToken.None);

        await act.Should().ThrowAsync<HttpRequestException>();
        handler.RequestCount.Should().Be(1);
        retryStatusWriter.Messages.Should().BeEmpty();
    }

    [Fact]
    public async Task CreateAsync_StoppedWebAppHtml_RetriesUntilSuccess()
    {
        SequenceHandler handler = new(
            CreateStoppedWebAppResponse(),
            CreateSuccessfulCreateResponse());
        RecordingRetryStatusWriter retryStatusWriter = new();

        using ServiceProvider provider = CreateServices(handler, retryStatusWriter);
        IHotstringsApiClient sut = provider.GetRequiredService<IHotstringsApiClient>();

        HotstringDto result = await sut.CreateAsync(CreateInput(), CancellationToken.None);

        result.Trigger.Should().Be("btw");
        handler.RequestCount.Should().Be(2);
        retryStatusWriter.Messages.Should().HaveCount(1);
    }

    [Fact]
    public async Task CreateAsync_ConnectionRefused_RetriesUntilSuccess()
    {
        SequenceHandler handler = new(
            new HttpRequestException(
                HttpRequestError.ConnectionError,
                "connection refused",
                new SocketException((int)SocketError.ConnectionRefused)),
            CreateSuccessfulCreateResponse());
        RecordingRetryStatusWriter retryStatusWriter = new();

        using ServiceProvider provider = CreateServices(handler, retryStatusWriter);
        IHotstringsApiClient sut = provider.GetRequiredService<IHotstringsApiClient>();

        HotstringDto result = await sut.CreateAsync(CreateInput(), CancellationToken.None);

        result.Trigger.Should().Be("btw");
        handler.RequestCount.Should().Be(2);
        retryStatusWriter.Messages.Should().HaveCount(1);
    }

    private static CreateHotstringDto CreateInput() => new("btw", "by the way");

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

    // A 403 with an HTML body that is NOT the App Service stopped-app page — e.g. a WAF or
    // gateway auth block. Must not be mistaken for a cold origin and retried.
    private static HttpResponseMessage CreateUnrelatedHtml403Response() =>
        new(HttpStatusCode.Forbidden)
        {
            Content = new StringContent(
                """
                <!DOCTYPE html>
                <html>
                <head><title>403 Forbidden</title></head>
                <body><h1>Access denied by web application firewall.</h1></body>
                </html>
                """,
                Encoding.UTF8,
                "text/html"),
        };

    private static HttpResponseMessage CreateSuccessfulCreateResponse() =>
        new(HttpStatusCode.Created)
        {
            Content = JsonContent.Create(new HotstringDto(
                Guid.NewGuid(),
                [],
                true,
                "btw",
                "by the way",
                true,
                true,
                DateTimeOffset.UnixEpoch,
                DateTimeOffset.UnixEpoch)),
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

    // Each outcome is either an HttpResponseMessage to return or an Exception to throw, replayed
    // in order so a test can script transport failures alongside responses.
    private sealed class SequenceHandler(params object[] outcomes) : HttpMessageHandler
    {
        private readonly Queue<object> _outcomes = new(outcomes);

        public int RequestCount { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            RequestCount++;
            return _outcomes.Dequeue() switch
            {
                HttpResponseMessage response => Task.FromResult(response),
                Exception exception => Task.FromException<HttpResponseMessage>(exception),
                var outcome => throw new InvalidOperationException($"Unsupported outcome: {outcome}"),
            };
        }
    }
}
