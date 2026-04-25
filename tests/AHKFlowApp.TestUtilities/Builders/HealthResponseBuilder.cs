using AHKFlowApp.API.Models;

namespace AHKFlowApp.TestUtilities.Builders;

public sealed class HealthResponseBuilder
{
    private string _status = "Healthy";
    private string _version = "0.0.0-dev";
    private string _environment = "Test";
    private DateTimeOffset _timestamp = DateTimeOffset.UtcNow;
    private readonly Dictionary<string, string> _checks = new() { ["database"] = "Healthy" };
    private string? _tier;

    public HealthResponseBuilder WithStatus(string status)
    {
        _status = status;
        return this;
    }

    public HealthResponseBuilder WithVersion(string version)
    {
        _version = version;
        return this;
    }

    public HealthResponseBuilder WithEnvironment(string environment)
    {
        _environment = environment;
        return this;
    }

    public HealthResponseBuilder WithTimestamp(DateTimeOffset timestamp)
    {
        _timestamp = timestamp;
        return this;
    }

    public HealthResponseBuilder WithCheck(string name, string status)
    {
        _checks[name] = status;
        return this;
    }

    public HealthResponseBuilder WithoutChecks()
    {
        _checks.Clear();
        return this;
    }

    public HealthResponseBuilder WithTier(string? tier)
    {
        _tier = tier;
        return this;
    }

#pragma warning disable IDE0028 // Simplify collection initialization
    public HealthResponse Build() => new(_status, _version, _environment, _timestamp, new(_checks), _tier);
#pragma warning restore IDE0028 // Simplify collection initialization
}
