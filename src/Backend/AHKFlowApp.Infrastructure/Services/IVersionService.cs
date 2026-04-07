namespace AHKFlowApp.Infrastructure.Services;

public interface IVersionService
{
    Task<string> GetVersionAsync(CancellationToken cancellationToken = default);
}
