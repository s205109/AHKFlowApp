using AHKFlowApp.CLI.Exceptions;
using AHKFlowApp.CLI.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Services;

public sealed class EnvVarAuthTokenProviderTests
{
    private const string Var = "AHKFLOW_TOKEN";

    [Fact]
    public async Task GetTokenAsync_EnvVarSet_ReturnsToken()
    {
        using var _ = new EnvVarScope(Var, "abc.def.ghi");
        EnvVarAuthTokenProvider sut = new();

        string token = await sut.GetTokenAsync(CancellationToken.None);

        token.Should().Be("abc.def.ghi");
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public async Task GetTokenAsync_EnvVarUnsetOrBlank_ThrowsNotAuthenticated(string? value)
    {
        using var _ = new EnvVarScope(Var, value);
        EnvVarAuthTokenProvider sut = new();

        Func<Task> act = () => sut.GetTokenAsync(CancellationToken.None);

        (await act.Should().ThrowAsync<NotAuthenticatedException>())
            .WithMessage("Not signed in. Set AHKFLOW_TOKEN environment variable to a bearer token.");
    }

    [Fact]
    public async Task LoginAsync_Throws_NotImplementedForItem029()
    {
        EnvVarAuthTokenProvider sut = new();

        Func<Task> act = () => sut.LoginAsync(CancellationToken.None);

        await act.Should().ThrowAsync<NotImplementedException>();
    }

    private sealed class EnvVarScope : IDisposable
    {
        private readonly string _name;
        private readonly string? _previous;
        public EnvVarScope(string name, string? value)
        {
            _name = name;
            _previous = Environment.GetEnvironmentVariable(name);
            Environment.SetEnvironmentVariable(name, value);
        }
        public void Dispose() => Environment.SetEnvironmentVariable(_name, _previous);
    }
}
