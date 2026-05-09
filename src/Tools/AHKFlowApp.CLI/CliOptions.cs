namespace AHKFlowApp.CLI;

public sealed record CliOptions
{
    public string ApiBaseUrl { get; init; } = "";
    public string ClientId { get; init; } = "";
    public string TenantId { get; init; } = "";
}
