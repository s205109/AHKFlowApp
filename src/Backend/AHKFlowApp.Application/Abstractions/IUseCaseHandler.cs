namespace AHKFlowApp.Application.Abstractions;

internal interface IUseCaseHandler<in TRequest, TResult>
{
    Task<TResult> ExecuteAsync(TRequest request, CancellationToken ct);
}
