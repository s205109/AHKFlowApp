using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Fixtures;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Testcontainers.MsSql;

namespace AHKFlowApp.E2E.Tests.Fixtures;

public sealed class ApiFactory : WebApplicationFactory<Program>, IAsyncDisposable
{
    private const string E2ETestAssemblyName = "AHKFlowApp.E2E.Tests";
    private const string SqlServerImage = "mcr.microsoft.com/mssql/server:2022-CU14-ubuntu-22.04";

    private readonly MsSqlContainer? _sql;
    private string? _connectionString;

    public ApiFactory()
    {
        string? sharedSqlConnectionString = Environment.GetEnvironmentVariable(
            SqlContainerFixture.SharedSqlConnectionStringEnvironmentVariable);
        if (string.IsNullOrWhiteSpace(sharedSqlConnectionString))
        {
            _sql = new MsSqlBuilder(SqlServerImage).Build();
            return;
        }

        _connectionString = CreateTestDatabaseConnectionString(sharedSqlConnectionString);
    }

    internal string ConnectionString => _connectionString
        ?? throw new InvalidOperationException("E2E API SQL connection has not been initialized.");

    public async Task StartAsync()
    {
        if (_sql is not null)
        {
            await _sql.StartAsync();
            _connectionString = CreateTestDatabaseConnectionString(_sql.GetConnectionString());
        }

        // Force the factory to build the host (triggers ConfigureWebHost).
        _ = Services;
        using AsyncServiceScope scope = Services.CreateAsyncScope();
        await scope.ServiceProvider.GetRequiredService<AppDbContext>().Database.MigrateAsync();
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Test");
        builder.ConfigureAppConfiguration((_, config) =>
        {
            config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:DefaultConnection"] = ConnectionString,
                // Microsoft.Identity.Web validates these on first request — provide placeholders
                ["AzureAd:TenantId"] = "00000000-0000-0000-0000-000000000001",
                ["AzureAd:ClientId"] = "00000000-0000-0000-0000-000000000002",
            });
        });
        builder.ConfigureTestServices(services =>
        {
            services.AddAuthentication(TestAuthHandler.SchemeName)
                .AddScheme<AuthenticationSchemeOptions, TestAuthHandler>(TestAuthHandler.SchemeName, _ => { });
            services.PostConfigure<AuthorizationOptions>(opts =>
            {
                opts.DefaultPolicy = new AuthorizationPolicyBuilder(TestAuthHandler.SchemeName)
                    .RequireAuthenticatedUser().Build();
            });
        });
    }

    public override async ValueTask DisposeAsync()
    {
        await base.DisposeAsync();
        if (_sql is not null)
        {
            await _sql.DisposeAsync();
        }
    }

    private static string CreateTestDatabaseConnectionString(string baseConnectionString) =>
        SqlTestDatabase.CreateConnectionString(baseConnectionString, E2ETestAssemblyName);

    ValueTask IAsyncDisposable.DisposeAsync() => DisposeAsync();
}
