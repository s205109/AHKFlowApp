namespace AHKFlowApp.Infrastructure.Services;

public interface IVersionService
{
    ValueTask<string> GetVersionAsync(CancellationToken cancellationToken = default);
}
