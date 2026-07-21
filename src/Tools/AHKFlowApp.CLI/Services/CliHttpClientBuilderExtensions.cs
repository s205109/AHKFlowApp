using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Http.Resilience;
using Polly;
using Polly.Retry;

namespace AHKFlowApp.CLI.Services;

public static class CliHttpClientBuilderExtensions
{
    private const int MaxRetryAttempts = 10;
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
                        CliApiFailureDetector.ShouldRetry(
                            args.Outcome.Exception,
                            args.Outcome.Result,
                            GetRequestMethod(args))),
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

    // The response carries the request on a failed status; on a transport exception there is no
    // response, so fall back to the request the resilience handler stashed in the context.
    private static HttpMethod? GetRequestMethod(RetryPredicateArguments<HttpResponseMessage> args) =>
        args.Outcome.Result?.RequestMessage?.Method
        ?? args.Context.GetRequestMessage()?.Method;
}
