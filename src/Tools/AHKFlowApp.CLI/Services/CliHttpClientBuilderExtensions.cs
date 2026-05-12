using System.Net;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Http.Resilience;
using Polly;
using Polly.Timeout;

namespace AHKFlowApp.CLI.Services;

public static class CliHttpClientBuilderExtensions
{
    private const int MaxRetryAttempts = 5;
    private static readonly TimeSpan RetryDelay = TimeSpan.FromSeconds(2);
    private static readonly TimeSpan AttemptTimeout = TimeSpan.FromSeconds(20);
    private static readonly TimeSpan TotalTimeout = TimeSpan.FromMinutes(2);

    public static IHttpClientBuilder AddCliApiResilience(
        this IHttpClientBuilder httpClientBuilder,
        string operationName)
    {
        httpClientBuilder.AddResilienceHandler(
            $"{operationName}-cli",
            (pipeline, context) =>
            {
                IHttpRetryStatusWriter retryStatusWriter =
                    context.ServiceProvider.GetRequiredService<IHttpRetryStatusWriter>();

                pipeline.AddTimeout(TotalTimeout);
                pipeline.AddRetry(new HttpRetryStrategyOptions
                {
                    MaxRetryAttempts = MaxRetryAttempts,
                    BackoffType = DelayBackoffType.Constant,
                    Delay = RetryDelay,
                    UseJitter = false,
                    ShouldHandle = static args => ValueTask.FromResult(
                        args.Outcome.Exception is HttpRequestException or TimeoutRejectedException
                        || args.Outcome.Result?.StatusCode is HttpStatusCode.RequestTimeout
                            or HttpStatusCode.TooManyRequests
                            or HttpStatusCode.BadGateway
                            or HttpStatusCode.ServiceUnavailable
                            or HttpStatusCode.GatewayTimeout),
                    OnRetry = args =>
                    {
                        retryStatusWriter.WriteRetrying(
                            operationName,
                            args.AttemptNumber + 1,
                            MaxRetryAttempts,
                            args.RetryDelay);
                        return default;
                    },
                });
                pipeline.AddTimeout(AttemptTimeout);
            });

        return httpClientBuilder;
    }
}
