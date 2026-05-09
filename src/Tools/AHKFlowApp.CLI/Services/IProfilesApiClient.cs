namespace AHKFlowApp.CLI.Services;

public interface IProfilesApiClient
{
    Task<IReadOnlyList<ProfileSummary>> ListAsync(CancellationToken ct);
}

public sealed record ProfileSummary(Guid Id, string Name);
