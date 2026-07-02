namespace AHKFlowApp.Application.Abstractions;

public interface IUseCase<in TRequest, TResult>
{
    Task<TResult> ExecuteAsync(TRequest request, CancellationToken ct);
}
